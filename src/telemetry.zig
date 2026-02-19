const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;

pub const Event = union(enum) {
    email_sending: Email,
    email_sent: EmailResult,
    email_failed: EmailResult,
    email_enqueued: Email,
    rate_limited: Email,
};

pub const EmailResult = struct {
    email: Email,
    duration_ms: i64,
    error_msg: ?[]const u8,
    message_id: ?[]const u8,
};

pub const HandlerFn = *const fn (Event) void;

pub const Telemetry = struct {
    const max_handlers = 8;

    handlers: [max_handlers]HandlerFn = undefined,
    handler_count: usize = 0,
    mutex: std.atomic.Mutex = .unlocked,

    pub fn attach(self: *Telemetry, handler: HandlerFn) void {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();

        if (self.handler_count < max_handlers) {
            self.handlers[self.handler_count] = handler;
            self.handler_count += 1;
        }
    }

    pub fn emit(self: *Telemetry, event: Event) void {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();

        for (0..self.handler_count) |i| {
            self.handlers[i](event);
        }
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

var test_event_count: usize = 0;
var test_last_event_tag: ?std.meta.Tag(Event) = null;

fn testHandler(event: Event) void {
    test_event_count += 1;
    test_last_event_tag = event;
}

test "telemetry handler receives events" {
    test_event_count = 0;
    test_last_event_tag = null;

    var telemetry = Telemetry{};
    telemetry.attach(&testHandler);

    const dummy_email = Email{
        .from = .{ .email = "test@example.com" },
        .subject = "Test",
    };

    telemetry.emit(.{ .email_sending = dummy_email });
    try std.testing.expectEqual(@as(usize, 1), test_event_count);
    try std.testing.expectEqual(std.meta.Tag(Event).email_sending, test_last_event_tag.?);

    telemetry.emit(.{ .email_sent = .{
        .email = dummy_email,
        .duration_ms = 100,
        .error_msg = null,
        .message_id = "msg-001",
    } });
    try std.testing.expectEqual(@as(usize, 2), test_event_count);
    try std.testing.expectEqual(std.meta.Tag(Event).email_sent, test_last_event_tag.?);
}

test "multiple telemetry handlers" {
    test_event_count = 0;

    var telemetry = Telemetry{};
    telemetry.attach(&testHandler);
    telemetry.attach(&testHandler);

    const dummy_email = Email{
        .from = .{ .email = "test@example.com" },
        .subject = "Test",
    };

    telemetry.emit(.{ .email_sending = dummy_email });
    try std.testing.expectEqual(@as(usize, 2), test_event_count);
}
