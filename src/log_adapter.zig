const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const SendResult = email_mod.SendResult;

/// Adapter that logs emails to stderr. Always returns success.
pub const LogAdapter = struct {
    pub const Config = struct {
        prefix: []const u8 = "[zzz_mailer]",
    };

    prefix: []const u8,

    pub fn init(config: Config) LogAdapter {
        return .{ .prefix = config.prefix };
    }

    pub fn deinit(_: *LogAdapter) void {}

    pub fn send(self: *LogAdapter, email: Email, _: std.mem.Allocator) SendResult {
        var buf: [2048]u8 = undefined;
        var pos: usize = 0;

        // Build log line
        const hdr = std.fmt.bufPrint(buf[pos..], "{s} Sending email\n  From: {s}\n  Subject: {s}\n", .{
            self.prefix,
            email.from.email,
            email.subject,
        }) catch {
            return .{ .success = true, .message_id = "log-msg-id" };
        };
        pos += hdr.len;

        // Log recipients
        for (email.to) |addr| {
            const line = std.fmt.bufPrint(buf[pos..], "  To: {s}\n", .{addr.email}) catch break;
            pos += line.len;
        }
        for (email.cc) |addr| {
            const line = std.fmt.bufPrint(buf[pos..], "  Cc: {s}\n", .{addr.email}) catch break;
            pos += line.len;
        }

        if (email.text_body) |text| {
            const preview_len = @min(text.len, 100);
            const line = std.fmt.bufPrint(buf[pos..], "  Body: {s}...\n", .{text[0..preview_len]}) catch "";
            pos += line.len;
        }

        // Write to stderr via debug.print
        std.debug.print("{s}", .{buf[0..pos]});

        return .{ .success = true, .message_id = "log-msg-id" };
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "LogAdapter always returns success" {
    var adapter = LogAdapter.init(.{});
    defer adapter.deinit();

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "recipient@example.com" }},
        .subject = "Test Subject",
        .text_body = "Hello World",
    };

    const result = adapter.send(email, std.testing.allocator);
    try std.testing.expect(result.success);
}

test "LogAdapter with custom prefix" {
    var adapter = LogAdapter.init(.{ .prefix = "[MAIL]" });
    defer adapter.deinit();

    const email = Email{
        .from = .{ .email = "test@example.com" },
        .subject = "Test",
    };

    const result = adapter.send(email, std.testing.allocator);
    try std.testing.expect(result.success);
}
