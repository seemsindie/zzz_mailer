const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const SendResult = email_mod.SendResult;
const http_client = @import("http_client.zig");

/// SendGrid v3 API adapter.
pub const SendGridAdapter = struct {
    pub const Config = struct {
        api_key: []const u8,
    };

    config: Config,

    pub fn init(config: Config) SendGridAdapter {
        return .{ .config = config };
    }

    pub fn deinit(_: *SendGridAdapter) void {}

    pub fn send(self: *SendGridAdapter, email: Email, _: std.mem.Allocator) SendResult {
        // Build JSON payload
        var json_buf: [16384]u8 = undefined;
        const json_body = buildPayload(email, &json_buf) orelse {
            return .{ .success = false, .error_message = "Failed to build SendGrid payload" };
        };

        // Build auth header
        var auth_buf: [512]u8 = undefined;
        const auth_header = std.fmt.bufPrint(&auth_buf,
            "Authorization: Bearer {s}\r\nContent-Type: application/json\r\n",
            .{self.config.api_key},
        ) catch {
            return .{ .success = false, .error_message = "Failed to build auth header" };
        };

        var response_buf: [4096]u8 = undefined;
        const response = http_client.httpsPost(
            "api.sendgrid.com",
            "/v3/mail/send",
            json_body,
            auth_header,
            &response_buf,
        ) catch |err| {
            return .{ .success = false, .error_message = @errorName(err) };
        };

        if (response.status_code >= 200 and response.status_code < 300) {
            return .{ .success = true, .message_id = "sendgrid-msg-id" };
        } else {
            return .{ .success = false, .error_message = "SendGrid API error" };
        }
    }

    fn buildPayload(email: Email, buf: []u8) ?[]const u8 {
        var pos: usize = 0;

        pos += appendStr(buf[pos..], "{\"personalizations\":[{\"to\":[") orelse return null;

        // To addresses
        for (email.to, 0..) |addr, i| {
            if (i > 0) {
                pos += appendStr(buf[pos..], ",") orelse return null;
            }
            const entry = std.fmt.bufPrint(buf[pos..], "{{\"email\":\"{s}\"}}", .{addr.email}) catch return null;
            pos += entry.len;
        }

        pos += appendStr(buf[pos..], "]") orelse return null;

        // CC
        if (email.cc.len > 0) {
            pos += appendStr(buf[pos..], ",\"cc\":[") orelse return null;
            for (email.cc, 0..) |addr, i| {
                if (i > 0) {
                    pos += appendStr(buf[pos..], ",") orelse return null;
                }
                const entry = std.fmt.bufPrint(buf[pos..], "{{\"email\":\"{s}\"}}", .{addr.email}) catch return null;
                pos += entry.len;
            }
            pos += appendStr(buf[pos..], "]") orelse return null;
        }

        // BCC
        if (email.bcc.len > 0) {
            pos += appendStr(buf[pos..], ",\"bcc\":[") orelse return null;
            for (email.bcc, 0..) |addr, i| {
                if (i > 0) {
                    pos += appendStr(buf[pos..], ",") orelse return null;
                }
                const entry = std.fmt.bufPrint(buf[pos..], "{{\"email\":\"{s}\"}}", .{addr.email}) catch return null;
                pos += entry.len;
            }
            pos += appendStr(buf[pos..], "]") orelse return null;
        }

        pos += appendStr(buf[pos..], "}]") orelse return null;

        // From
        const from = std.fmt.bufPrint(buf[pos..], ",\"from\":{{\"email\":\"{s}\"}}", .{email.from.email}) catch return null;
        pos += from.len;

        // Subject
        const subj = std.fmt.bufPrint(buf[pos..], ",\"subject\":\"{s}\"", .{email.subject}) catch return null;
        pos += subj.len;

        // Content
        pos += appendStr(buf[pos..], ",\"content\":[") orelse return null;
        var content_added = false;

        if (email.text_body) |text| {
            const part = std.fmt.bufPrint(buf[pos..], "{{\"type\":\"text/plain\",\"value\":\"{s}\"}}", .{text}) catch return null;
            pos += part.len;
            content_added = true;
        }

        if (email.html_body) |html| {
            if (content_added) {
                pos += appendStr(buf[pos..], ",") orelse return null;
            }
            const part = std.fmt.bufPrint(buf[pos..], "{{\"type\":\"text/html\",\"value\":\"{s}\"}}", .{html}) catch return null;
            pos += part.len;
        }

        pos += appendStr(buf[pos..], "]}") orelse return null;

        return buf[0..pos];
    }

    fn appendStr(buf: []u8, s: []const u8) ?usize {
        if (s.len > buf.len) return null;
        @memcpy(buf[0..s.len], s);
        return s.len;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "SendGridAdapter init" {
    const adapter = SendGridAdapter.init(.{ .api_key = "SG.test-key" });
    try std.testing.expectEqualStrings("SG.test-key", adapter.config.api_key);
}

test "SendGrid payload builder" {
    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "to@example.com" }},
        .subject = "Test",
        .text_body = "Hello",
    };
    var buf: [4096]u8 = undefined;
    const payload = SendGridAdapter.buildPayload(email, &buf).?;
    try std.testing.expect(std.mem.indexOf(u8, payload, "sender@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "to@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "Test") != null);
}
