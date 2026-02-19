const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const SendResult = email_mod.SendResult;

/// In-memory test adapter for test assertions.
/// Stores sent emails in a fixed-size ring buffer.
pub const TestAdapter = struct {
    const max_emails = 256;

    pub const Config = struct {};

    subjects: [max_emails][256]u8 = undefined,
    subject_lens: [max_emails]usize = [_]usize{0} ** max_emails,
    from_emails: [max_emails][256]u8 = undefined,
    from_email_lens: [max_emails]usize = [_]usize{0} ** max_emails,
    to_emails: [max_emails][256]u8 = undefined,
    to_email_lens: [max_emails]usize = [_]usize{0} ** max_emails,
    count: usize = 0,
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(_: Config) TestAdapter {
        return .{};
    }

    pub fn deinit(_: *TestAdapter) void {}

    pub fn send(self: *TestAdapter, email: Email, _: std.mem.Allocator) SendResult {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();

        const idx = self.count % max_emails;

        // Store subject
        const subj_len = @min(email.subject.len, 256);
        @memcpy(self.subjects[idx][0..subj_len], email.subject[0..subj_len]);
        self.subject_lens[idx] = subj_len;

        // Store from email
        const from_len = @min(email.from.email.len, 256);
        @memcpy(self.from_emails[idx][0..from_len], email.from.email[0..from_len]);
        self.from_email_lens[idx] = from_len;

        // Store first "to" address
        if (email.to.len > 0) {
            const to_len = @min(email.to[0].email.len, 256);
            @memcpy(self.to_emails[idx][0..to_len], email.to[0].email[0..to_len]);
            self.to_email_lens[idx] = to_len;
        } else {
            self.to_email_lens[idx] = 0;
        }

        self.count += 1;

        return .{ .success = true, .message_id = "test-msg-id" };
    }

    // ── Query methods for assertions ──

    pub fn allSentCount(self: *TestAdapter) usize {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        return self.count;
    }

    pub fn lastSentSubject(self: *TestAdapter) ?[]const u8 {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        if (self.count == 0) return null;
        const idx = (self.count - 1) % max_emails;
        return self.subjects[idx][0..self.subject_lens[idx]];
    }

    pub fn sentToAddress(self: *TestAdapter, target: []const u8) bool {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        const total = @min(self.count, max_emails);
        for (0..total) |i| {
            const len = self.to_email_lens[i];
            if (len > 0 and std.mem.eql(u8, self.to_emails[i][0..len], target)) {
                return true;
            }
        }
        return false;
    }

    pub fn clear(self: *TestAdapter) void {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        self.count = 0;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "TestAdapter stores sent emails" {
    var adapter = TestAdapter.init(.{});
    defer adapter.deinit();

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "recipient@example.com" }},
        .subject = "Test Subject",
        .text_body = "Hello",
    };

    const result = adapter.send(email, std.testing.allocator);
    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 1), adapter.allSentCount());
    try std.testing.expectEqualStrings("Test Subject", adapter.lastSentSubject().?);
    try std.testing.expect(adapter.sentToAddress("recipient@example.com"));
    try std.testing.expect(!adapter.sentToAddress("other@example.com"));
}

test "TestAdapter clear resets count" {
    var adapter = TestAdapter.init(.{});
    defer adapter.deinit();

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .subject = "Test",
    };

    _ = adapter.send(email, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), adapter.allSentCount());

    adapter.clear();
    try std.testing.expectEqual(@as(usize, 0), adapter.allSentCount());
    try std.testing.expect(adapter.lastSentSubject() == null);
}
