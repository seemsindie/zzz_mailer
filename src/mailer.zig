const std = @import("std");
const email_mod = @import("email.zig");
const adapter_mod = @import("adapter.zig");
const rate_limiter_mod = @import("rate_limiter.zig");
const telemetry_mod = @import("telemetry.zig");
const Email = email_mod.Email;
const SendResult = email_mod.SendResult;
const RateLimiter = rate_limiter_mod.RateLimiter;
const Telemetry = telemetry_mod.Telemetry;

const c_time = @cImport({
    @cInclude("time.h");
});

fn timestampMs() i64 {
    var ts: c_time.struct_timespec = undefined;
    _ = c_time.clock_gettime(c_time.CLOCK_MONOTONIC, &ts);
    return @as(i64, @intCast(ts.tv_sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.tv_nsec)), 1_000_000);
}

/// Generic mailer that wraps any adapter conforming to the adapter interface.
pub fn Mailer(comptime Adapter: type) type {
    adapter_mod.validate(Adapter);

    return struct {
        const Self = @This();

        adapter: Adapter,
        rate_limiter: ?RateLimiter = null,
        telemetry: ?*Telemetry = null,

        pub const Config = struct {
            adapter: Adapter.Config = .{},
            rate_limit: ?RateLimiter.Config = null,
        };

        pub fn init(config: Config) Self {
            return .{
                .adapter = Adapter.init(config.adapter),
                .rate_limiter = if (config.rate_limit) |rl| RateLimiter.init(rl) else null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.adapter.deinit();
        }

        /// Send an email through the adapter.
        pub fn send(self: *Self, email: Email, allocator: std.mem.Allocator) SendResult {
            // Emit sending event
            if (self.telemetry) |t| {
                t.emit(.{ .email_sending = email });
            }

            // Rate limiting
            if (self.rate_limiter) |*rl| {
                if (!rl.acquire()) {
                    if (self.telemetry) |t| {
                        t.emit(.{ .rate_limited = email });
                    }
                    // Block until token available
                    rl.acquireBlocking();
                }
            }

            const start = timestampMs();
            const result = self.adapter.send(email, allocator);
            const duration = timestampMs() - start;

            // Emit result event
            if (self.telemetry) |t| {
                if (result.success) {
                    t.emit(.{ .email_sent = .{
                        .email = email,
                        .duration_ms = duration,
                        .error_msg = null,
                        .message_id = result.message_id,
                    } });
                } else {
                    t.emit(.{ .email_failed = .{
                        .email = email,
                        .duration_ms = duration,
                        .error_msg = result.error_message,
                        .message_id = null,
                    } });
                }
            }

            return result;
        }
    };
}

// ── Tests ──────────────────────────────────────────────────────────────

test "Mailer with TestAdapter" {
    const TestAdapter = @import("test_adapter.zig").TestAdapter;
    var mailer = Mailer(TestAdapter).init(.{});
    defer mailer.deinit();

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "to@example.com" }},
        .subject = "Hello from Mailer",
        .text_body = "Test body",
    };

    const result = mailer.send(email, std.testing.allocator);
    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 1), mailer.adapter.allSentCount());
}

test "Mailer with telemetry" {
    const TestAdapter = @import("test_adapter.zig").TestAdapter;

    var t = Telemetry{};
    var mailer = Mailer(TestAdapter).init(.{});
    mailer.telemetry = &t;
    defer mailer.deinit();

    const handler = struct {
        fn handle(_: telemetry_mod.Event) void {
            // Tests that telemetry handlers are invoked without crashing
        }
    }.handle;
    t.attach(&handler);

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .subject = "Telemetry test",
    };

    _ = mailer.send(email, std.testing.allocator);
}

test "Mailer with rate limiting" {
    const TestAdapter = @import("test_adapter.zig").TestAdapter;
    var mailer = Mailer(TestAdapter).init(.{
        .rate_limit = .{ .max_per_second = 100.0 },
    });
    defer mailer.deinit();

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .subject = "Rate limited",
    };

    // Should succeed (we have tokens)
    const result = mailer.send(email, std.testing.allocator);
    try std.testing.expect(result.success);
}
