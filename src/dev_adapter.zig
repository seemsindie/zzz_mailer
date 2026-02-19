const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const SendResult = email_mod.SendResult;

const c_time = @cImport({
    @cInclude("time.h");
});

/// Development adapter: stores emails in memory for the dev mailbox web UI.
pub const DevAdapter = struct {
    const max_emails = 256;
    const max_field_len = 512;
    const max_body_len = 8192;

    pub const Config = struct {};

    /// A stored email record for the web UI.
    pub const StoredEmail = struct {
        from: [max_field_len]u8 = undefined,
        from_len: usize = 0,
        to: [max_field_len]u8 = undefined,
        to_len: usize = 0,
        cc: [max_field_len]u8 = undefined,
        cc_len: usize = 0,
        bcc: [max_field_len]u8 = undefined,
        bcc_len: usize = 0,
        subject: [max_field_len]u8 = undefined,
        subject_len: usize = 0,
        text_body: [max_body_len]u8 = undefined,
        text_body_len: usize = 0,
        html_body: [max_body_len]u8 = undefined,
        html_body_len: usize = 0,
        timestamp: i64 = 0,

        pub fn getFrom(self: *const StoredEmail) []const u8 {
            return self.from[0..self.from_len];
        }

        pub fn getTo(self: *const StoredEmail) []const u8 {
            return self.to[0..self.to_len];
        }

        pub fn getCc(self: *const StoredEmail) []const u8 {
            return self.cc[0..self.cc_len];
        }

        pub fn getBcc(self: *const StoredEmail) []const u8 {
            return self.bcc[0..self.bcc_len];
        }

        pub fn getSubject(self: *const StoredEmail) []const u8 {
            return self.subject[0..self.subject_len];
        }

        pub fn getTextBody(self: *const StoredEmail) []const u8 {
            return self.text_body[0..self.text_body_len];
        }

        pub fn getHtmlBody(self: *const StoredEmail) []const u8 {
            return self.html_body[0..self.html_body_len];
        }
    };

    emails: [max_emails]StoredEmail = [_]StoredEmail{.{}} ** max_emails,
    count: usize = 0,
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(_: Config) DevAdapter {
        return .{};
    }

    pub fn deinit(_: *DevAdapter) void {}

    pub fn send(self: *DevAdapter, email: Email, _: std.mem.Allocator) SendResult {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();

        const idx = self.count % max_emails;
        var stored = &self.emails[idx];
        stored.* = .{};

        // Store from
        copyField(&stored.from, &stored.from_len, email.from.email);

        // Store to (join addresses)
        if (email.to.len > 0) {
            var to_buf: [max_field_len]u8 = undefined;
            var to_pos: usize = 0;
            for (email.to, 0..) |addr, i| {
                if (i > 0) {
                    if (to_pos + 2 < max_field_len) {
                        to_buf[to_pos] = ',';
                        to_buf[to_pos + 1] = ' ';
                        to_pos += 2;
                    }
                }
                const len = @min(addr.email.len, max_field_len - to_pos);
                @memcpy(to_buf[to_pos..][0..len], addr.email[0..len]);
                to_pos += len;
            }
            copyField(&stored.to, &stored.to_len, to_buf[0..to_pos]);
        }

        // Store cc
        if (email.cc.len > 0) {
            var cc_buf: [max_field_len]u8 = undefined;
            var cc_pos: usize = 0;
            for (email.cc, 0..) |addr, i| {
                if (i > 0) {
                    if (cc_pos + 2 < max_field_len) {
                        cc_buf[cc_pos] = ',';
                        cc_buf[cc_pos + 1] = ' ';
                        cc_pos += 2;
                    }
                }
                const len = @min(addr.email.len, max_field_len - cc_pos);
                @memcpy(cc_buf[cc_pos..][0..len], addr.email[0..len]);
                cc_pos += len;
            }
            copyField(&stored.cc, &stored.cc_len, cc_buf[0..cc_pos]);
        }

        // Store bcc
        if (email.bcc.len > 0) {
            var bcc_buf: [max_field_len]u8 = undefined;
            var bcc_pos: usize = 0;
            for (email.bcc, 0..) |addr, i| {
                if (i > 0) {
                    if (bcc_pos + 2 < max_field_len) {
                        bcc_buf[bcc_pos] = ',';
                        bcc_buf[bcc_pos + 1] = ' ';
                        bcc_pos += 2;
                    }
                }
                const len = @min(addr.email.len, max_field_len - bcc_pos);
                @memcpy(bcc_buf[bcc_pos..][0..len], addr.email[0..len]);
                bcc_pos += len;
            }
            copyField(&stored.bcc, &stored.bcc_len, bcc_buf[0..bcc_pos]);
        }

        // Store subject
        copyField(&stored.subject, &stored.subject_len, email.subject);

        // Store text body
        if (email.text_body) |text| {
            const len = @min(text.len, max_body_len);
            @memcpy(stored.text_body[0..len], text[0..len]);
            stored.text_body_len = len;
        }

        // Store html body
        if (email.html_body) |html| {
            const len = @min(html.len, max_body_len);
            @memcpy(stored.html_body[0..len], html[0..len]);
            stored.html_body_len = len;
        }

        stored.timestamp = c_time.time(null);

        self.count += 1;

        return .{ .success = true, .message_id = "dev-msg-id" };
    }

    fn copyField(dest: []u8, dest_len: *usize, src: []const u8) void {
        const len = @min(src.len, dest.len);
        @memcpy(dest[0..len], src[0..len]);
        dest_len.* = len;
    }

    // ── Query methods for web UI ──

    /// Returns the total number of stored emails.
    pub fn sentCount(self: *DevAdapter) usize {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        return self.count;
    }

    /// Get a single email by index (0 = oldest in buffer).
    pub fn getEmail(self: *DevAdapter, index: usize) ?*const StoredEmail {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        if (index >= self.count or index >= max_emails) return null;
        return &self.emails[index];
    }

    /// Returns the number of emails available in the buffer.
    pub fn availableCount(self: *DevAdapter) usize {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        return @min(self.count, max_emails);
    }

    /// Clear all stored emails.
    pub fn clear(self: *DevAdapter) void {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();
        self.count = 0;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "DevAdapter stores full email data" {
    var adapter = DevAdapter.init(.{});
    defer adapter.deinit();

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "recipient@example.com" }},
        .cc = &.{.{ .email = "cc@example.com" }},
        .subject = "Test Subject",
        .text_body = "Hello World",
        .html_body = "<h1>Hello</h1>",
    };

    const result = adapter.send(email, std.testing.allocator);
    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(usize, 1), adapter.sentCount());

    const stored = adapter.getEmail(0).?;
    try std.testing.expectEqualStrings("sender@example.com", stored.getFrom());
    try std.testing.expectEqualStrings("recipient@example.com", stored.getTo());
    try std.testing.expectEqualStrings("cc@example.com", stored.getCc());
    try std.testing.expectEqualStrings("Test Subject", stored.getSubject());
    try std.testing.expectEqualStrings("Hello World", stored.getTextBody());
    try std.testing.expectEqualStrings("<h1>Hello</h1>", stored.getHtmlBody());
}

test "DevAdapter clear resets" {
    var adapter = DevAdapter.init(.{});
    defer adapter.deinit();

    const email = Email{
        .from = .{ .email = "test@example.com" },
        .subject = "Test",
    };

    _ = adapter.send(email, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), adapter.sentCount());

    adapter.clear();
    try std.testing.expectEqual(@as(usize, 0), adapter.sentCount());
}

test "DevAdapter multiple recipients" {
    var adapter = DevAdapter.init(.{});
    defer adapter.deinit();

    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{
            .{ .email = "a@example.com" },
            .{ .email = "b@example.com" },
        },
        .subject = "Multi",
    };

    _ = adapter.send(email, std.testing.allocator);
    const stored = adapter.getEmail(0).?;
    try std.testing.expectEqualStrings("a@example.com, b@example.com", stored.getTo());
}
