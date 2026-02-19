const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const Address = email_mod.Address;
const Attachment = email_mod.Attachment;

/// RFC 2045 MIME message builder.
/// Generates a complete RFC 5322 message from an Email struct.
pub const MimeBuilder = struct {
    const boundary = "zzz_mailer_boundary_7x9k2m";
    const alt_boundary = "zzz_mailer_alt_boundary_3p8w";

    /// Build a complete MIME message into the provided buffer.
    /// Returns the slice of the buffer that was written to.
    pub fn build(email: Email, buf: []u8) ?[]const u8 {
        var pos: usize = 0;

        // From header
        pos += appendHeader(buf[pos..], "From", &.{email.from}) orelse return null;

        // To header
        if (email.to.len > 0) {
            pos += appendHeader(buf[pos..], "To", email.to) orelse return null;
        }

        // Cc header
        if (email.cc.len > 0) {
            pos += appendHeader(buf[pos..], "Cc", email.cc) orelse return null;
        }

        // Subject
        pos += appendLine(buf[pos..], "Subject: ", email.subject) orelse return null;

        // MIME-Version
        pos += appendStr(buf[pos..], "MIME-Version: 1.0\r\n") orelse return null;

        // Custom headers
        for (email.headers) |h| {
            pos += appendLine(buf[pos..], h.name, ": ") orelse return null;
            // Re-do: name: value
            pos -= (h.name.len + 2); // undo
            const hdr = std.fmt.bufPrint(buf[pos..], "{s}: {s}\r\n", .{ h.name, h.value }) catch return null;
            pos += hdr.len;
        }

        // Determine message structure
        const has_text = email.text_body != null;
        const has_html = email.html_body != null;
        const has_attachments = email.attachments.len > 0;

        if (has_attachments) {
            // multipart/mixed with nested multipart/alternative
            pos += appendStr(buf[pos..], "Content-Type: multipart/mixed; boundary=\"" ++ boundary ++ "\"\r\n\r\n") orelse return null;

            if (has_text or has_html) {
                pos += appendStr(buf[pos..], "--" ++ boundary ++ "\r\n") orelse return null;
                pos += appendStr(buf[pos..], "Content-Type: multipart/alternative; boundary=\"" ++ alt_boundary ++ "\"\r\n\r\n") orelse return null;

                if (has_text) {
                    pos += appendTextPart(buf[pos..], email.text_body.?, alt_boundary) orelse return null;
                }
                if (has_html) {
                    pos += appendHtmlPart(buf[pos..], email.html_body.?, alt_boundary) orelse return null;
                }

                pos += appendStr(buf[pos..], "--" ++ alt_boundary ++ "--\r\n") orelse return null;
            }

            // Attachments
            for (email.attachments) |att| {
                pos += appendAttachment(buf[pos..], att) orelse return null;
            }

            pos += appendStr(buf[pos..], "--" ++ boundary ++ "--\r\n") orelse return null;
        } else if (has_text and has_html) {
            // multipart/alternative
            pos += appendStr(buf[pos..], "Content-Type: multipart/alternative; boundary=\"" ++ alt_boundary ++ "\"\r\n\r\n") orelse return null;

            pos += appendTextPart(buf[pos..], email.text_body.?, alt_boundary) orelse return null;
            pos += appendHtmlPart(buf[pos..], email.html_body.?, alt_boundary) orelse return null;

            pos += appendStr(buf[pos..], "--" ++ alt_boundary ++ "--\r\n") orelse return null;
        } else if (has_html) {
            pos += appendStr(buf[pos..], "Content-Type: text/html; charset=utf-8\r\n\r\n") orelse return null;
            pos += appendStr(buf[pos..], email.html_body.?) orelse return null;
            pos += appendStr(buf[pos..], "\r\n") orelse return null;
        } else if (has_text) {
            pos += appendStr(buf[pos..], "Content-Type: text/plain; charset=utf-8\r\n\r\n") orelse return null;
            pos += appendStr(buf[pos..], email.text_body.?) orelse return null;
            pos += appendStr(buf[pos..], "\r\n") orelse return null;
        } else {
            pos += appendStr(buf[pos..], "Content-Type: text/plain; charset=utf-8\r\n\r\n") orelse return null;
        }

        return buf[0..pos];
    }

    fn appendStr(buf: []u8, s: []const u8) ?usize {
        if (s.len > buf.len) return null;
        @memcpy(buf[0..s.len], s);
        return s.len;
    }

    fn appendLine(buf: []u8, prefix: []const u8, value: []const u8) ?usize {
        const total = prefix.len + value.len + 2; // +2 for \r\n
        if (total > buf.len) return null;
        @memcpy(buf[0..prefix.len], prefix);
        @memcpy(buf[prefix.len..][0..value.len], value);
        buf[prefix.len + value.len] = '\r';
        buf[prefix.len + value.len + 1] = '\n';
        return total;
    }

    fn appendHeader(buf: []u8, name: []const u8, addrs: []const Address) ?usize {
        var pos: usize = 0;
        const hdr_prefix = std.fmt.bufPrint(buf[pos..], "{s}: ", .{name}) catch return null;
        pos += hdr_prefix.len;

        for (addrs, 0..) |addr, i| {
            if (i > 0) {
                pos += appendStr(buf[pos..], ", ") orelse return null;
            }
            var addr_buf: [256]u8 = undefined;
            const formatted = addr.format(&addr_buf) orelse return null;
            pos += appendStr(buf[pos..], formatted) orelse return null;
        }

        pos += appendStr(buf[pos..], "\r\n") orelse return null;
        return pos;
    }

    fn appendTextPart(buf: []u8, text: []const u8, bnd: []const u8) ?usize {
        var pos: usize = 0;
        pos += appendStr(buf[pos..], "--") orelse return null;
        pos += appendStr(buf[pos..], bnd) orelse return null;
        pos += appendStr(buf[pos..], "\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n") orelse return null;
        pos += appendStr(buf[pos..], text) orelse return null;
        pos += appendStr(buf[pos..], "\r\n") orelse return null;
        return pos;
    }

    fn appendHtmlPart(buf: []u8, html: []const u8, bnd: []const u8) ?usize {
        var pos: usize = 0;
        pos += appendStr(buf[pos..], "--") orelse return null;
        pos += appendStr(buf[pos..], bnd) orelse return null;
        pos += appendStr(buf[pos..], "\r\nContent-Type: text/html; charset=utf-8\r\n\r\n") orelse return null;
        pos += appendStr(buf[pos..], html) orelse return null;
        pos += appendStr(buf[pos..], "\r\n") orelse return null;
        return pos;
    }

    fn appendAttachment(buf: []u8, att: Attachment) ?usize {
        var pos: usize = 0;
        pos += appendStr(buf[pos..], "--" ++ boundary ++ "\r\n") orelse return null;

        const ct = std.fmt.bufPrint(buf[pos..], "Content-Type: {s}; name=\"{s}\"\r\n", .{ att.content_type, att.filename }) catch return null;
        pos += ct.len;

        const disp_str: []const u8 = switch (att.disposition) {
            .attachment => "attachment",
            .@"inline" => "inline",
        };
        const disp = std.fmt.bufPrint(buf[pos..], "Content-Disposition: {s}; filename=\"{s}\"\r\n", .{ disp_str, att.filename }) catch return null;
        pos += disp.len;

        if (att.content_id) |cid| {
            const cid_hdr = std.fmt.bufPrint(buf[pos..], "Content-ID: <{s}>\r\n", .{cid}) catch return null;
            pos += cid_hdr.len;
        }

        pos += appendStr(buf[pos..], "Content-Transfer-Encoding: base64\r\n\r\n") orelse return null;

        // Base64 encode the content
        const encoded_len = std.base64.standard.Encoder.calcSize(att.content.len);
        if (pos + encoded_len + 2 > buf.len) return null;
        _ = std.base64.standard.Encoder.encode(buf[pos..][0..encoded_len], att.content);
        pos += encoded_len;
        pos += appendStr(buf[pos..], "\r\n") orelse return null;

        return pos;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "MIME build text only" {
    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "to@example.com" }},
        .subject = "Hello",
        .text_body = "Hello World",
    };
    var buf: [4096]u8 = undefined;
    const msg = MimeBuilder.build(email, &buf).?;
    try std.testing.expect(std.mem.indexOf(u8, msg, "From: sender@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "To: to@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Subject: Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "MIME-Version: 1.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "text/plain") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Hello World") != null);
}

test "MIME build multipart alternative" {
    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "to@example.com" }},
        .subject = "Hello",
        .text_body = "Hello text",
        .html_body = "<h1>Hello html</h1>",
    };
    var buf: [4096]u8 = undefined;
    const msg = MimeBuilder.build(email, &buf).?;
    try std.testing.expect(std.mem.indexOf(u8, msg, "multipart/alternative") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Hello text") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "<h1>Hello html</h1>") != null);
}

test "MIME build with attachment" {
    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "to@example.com" }},
        .subject = "Hello",
        .text_body = "See attached",
        .attachments = &.{.{
            .filename = "test.txt",
            .content = "file content",
            .content_type = "text/plain",
        }},
    };
    var buf: [8192]u8 = undefined;
    const msg = MimeBuilder.build(email, &buf).?;
    try std.testing.expect(std.mem.indexOf(u8, msg, "multipart/mixed") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "test.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "Content-Transfer-Encoding: base64") != null);
}
