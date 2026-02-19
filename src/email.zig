const std = @import("std");

/// An email address with optional display name.
pub const Address = struct {
    email: []const u8,
    name: ?[]const u8 = null,

    /// Format as "Name <email>" or just "email".
    pub fn format(self: Address, buf: []u8) ?[]const u8 {
        if (self.name) |n| {
            return std.fmt.bufPrint(buf, "{s} <{s}>", .{ n, self.email }) catch null;
        } else {
            return std.fmt.bufPrint(buf, "{s}", .{self.email}) catch null;
        }
    }
};

/// Content disposition for attachments.
pub const Disposition = enum {
    attachment,
    @"inline",
};

/// An email attachment.
pub const Attachment = struct {
    filename: []const u8,
    content: []const u8,
    content_type: []const u8 = "application/octet-stream",
    disposition: Disposition = .attachment,
    content_id: ?[]const u8 = null,
};

/// A custom email header.
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Represents an email message.
pub const Email = struct {
    from: Address,
    to: []const Address = &.{},
    cc: []const Address = &.{},
    bcc: []const Address = &.{},
    reply_to: ?Address = null,
    subject: []const u8 = "",
    text_body: ?[]const u8 = null,
    html_body: ?[]const u8 = null,
    attachments: []const Attachment = &.{},
    headers: []const Header = &.{},
};

/// Result of sending an email.
pub const SendResult = struct {
    success: bool,
    message_id: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
};

// ── Tests ──────────────────────────────────────────────────────────────

test "Address format with name" {
    const addr = Address{ .email = "test@example.com", .name = "Test User" };
    var buf: [256]u8 = undefined;
    const formatted = addr.format(&buf).?;
    try std.testing.expectEqualStrings("Test User <test@example.com>", formatted);
}

test "Address format without name" {
    const addr = Address{ .email = "test@example.com" };
    var buf: [256]u8 = undefined;
    const formatted = addr.format(&buf).?;
    try std.testing.expectEqualStrings("test@example.com", formatted);
}

test "Email default fields" {
    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .subject = "Hello",
    };
    try std.testing.expectEqual(@as(usize, 0), email.to.len);
    try std.testing.expectEqual(@as(usize, 0), email.cc.len);
    try std.testing.expectEqual(@as(usize, 0), email.bcc.len);
    try std.testing.expect(email.reply_to == null);
    try std.testing.expect(email.text_body == null);
    try std.testing.expect(email.html_body == null);
    try std.testing.expectEqual(@as(usize, 0), email.attachments.len);
}
