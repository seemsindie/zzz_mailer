const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const Address = email_mod.Address;

/// Serialize an Email to a JSON string for async job queues.
/// Note: Attachments are not serialized (not supported in async mode).
pub fn serialize(email: Email, buf: []u8) ?[]const u8 {
    var pos: usize = 0;

    pos += appendStr(buf[pos..], "{") orelse return null;

    // from
    const from = std.fmt.bufPrint(buf[pos..], "\"from\":\"{s}\"", .{email.from.email}) catch return null;
    pos += from.len;

    // to
    pos += appendStr(buf[pos..], ",\"to\":[") orelse return null;
    for (email.to, 0..) |addr, i| {
        if (i > 0) {
            pos += appendStr(buf[pos..], ",") orelse return null;
        }
        const entry = std.fmt.bufPrint(buf[pos..], "\"{s}\"", .{addr.email}) catch return null;
        pos += entry.len;
    }
    pos += appendStr(buf[pos..], "]") orelse return null;

    // cc
    pos += appendStr(buf[pos..], ",\"cc\":[") orelse return null;
    for (email.cc, 0..) |addr, i| {
        if (i > 0) {
            pos += appendStr(buf[pos..], ",") orelse return null;
        }
        const entry = std.fmt.bufPrint(buf[pos..], "\"{s}\"", .{addr.email}) catch return null;
        pos += entry.len;
    }
    pos += appendStr(buf[pos..], "]") orelse return null;

    // bcc
    pos += appendStr(buf[pos..], ",\"bcc\":[") orelse return null;
    for (email.bcc, 0..) |addr, i| {
        if (i > 0) {
            pos += appendStr(buf[pos..], ",") orelse return null;
        }
        const entry = std.fmt.bufPrint(buf[pos..], "\"{s}\"", .{addr.email}) catch return null;
        pos += entry.len;
    }
    pos += appendStr(buf[pos..], "]") orelse return null;

    // subject
    const subj = std.fmt.bufPrint(buf[pos..], ",\"subject\":\"{s}\"", .{email.subject}) catch return null;
    pos += subj.len;

    // text_body
    if (email.text_body) |text| {
        const tb = std.fmt.bufPrint(buf[pos..], ",\"text_body\":\"{s}\"", .{text}) catch return null;
        pos += tb.len;
    }

    // html_body
    if (email.html_body) |html| {
        const hb = std.fmt.bufPrint(buf[pos..], ",\"html_body\":\"{s}\"", .{html}) catch return null;
        pos += hb.len;
    }

    pos += appendStr(buf[pos..], "}") orelse return null;

    return buf[0..pos];
}

/// Deserialize a JSON string back to an Email struct.
/// Note: This returns an Email with string slices pointing into the json buffer.
/// The caller must ensure the json buffer outlives the returned Email.
pub fn deserialize(json: []const u8) ?Email {
    var email = Email{
        .from = .{ .email = "" },
    };

    // Parse from
    if (extractStringValue(json, "\"from\":\"")) |val| {
        email.from = .{ .email = val };
    }

    // Parse subject
    if (extractStringValue(json, "\"subject\":\"")) |val| {
        email.subject = val;
    }

    // Parse text_body
    if (extractStringValue(json, "\"text_body\":\"")) |val| {
        email.text_body = val;
    }

    // Parse html_body
    if (extractStringValue(json, "\"html_body\":\"")) |val| {
        email.html_body = val;
    }

    return email;
}

fn extractStringValue(json: []const u8, key: []const u8) ?[]const u8 {
    const start_idx = std.mem.indexOf(u8, json, key) orelse return null;
    const value_start = start_idx + key.len;
    const value_end = std.mem.indexOfScalarPos(u8, json, value_start, '"') orelse return null;
    return json[value_start..value_end];
}

fn appendStr(buf: []u8, s: []const u8) ?usize {
    if (s.len > buf.len) return null;
    @memcpy(buf[0..s.len], s);
    return s.len;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "serialize basic email" {
    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "to@example.com" }},
        .subject = "Hello",
        .text_body = "World",
    };

    var buf: [4096]u8 = undefined;
    const json = serialize(email, &buf).?;
    try std.testing.expect(std.mem.indexOf(u8, json, "sender@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "to@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "World") != null);
}

test "deserialize basic email" {
    const json = "{\"from\":\"sender@example.com\",\"to\":[\"to@example.com\"],\"cc\":[],\"bcc\":[],\"subject\":\"Hello\",\"text_body\":\"World\"}";
    const email = deserialize(json).?;
    try std.testing.expectEqualStrings("sender@example.com", email.from.email);
    try std.testing.expectEqualStrings("Hello", email.subject);
    try std.testing.expectEqualStrings("World", email.text_body.?);
}

test "serialize and deserialize roundtrip" {
    const original = Email{
        .from = .{ .email = "test@example.com" },
        .subject = "Roundtrip",
        .text_body = "Content",
        .html_body = "<b>Content</b>",
    };

    var buf: [4096]u8 = undefined;
    const json = serialize(original, &buf).?;
    const restored = deserialize(json).?;

    try std.testing.expectEqualStrings("test@example.com", restored.from.email);
    try std.testing.expectEqualStrings("Roundtrip", restored.subject);
    try std.testing.expectEqualStrings("Content", restored.text_body.?);
    try std.testing.expectEqualStrings("<b>Content</b>", restored.html_body.?);
}
