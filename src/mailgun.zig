const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const SendResult = email_mod.SendResult;
const http_client = @import("http_client.zig");

/// Mailgun REST API adapter.
pub const MailgunAdapter = struct {
    pub const Config = struct {
        api_key: []const u8,
        domain: []const u8,
    };

    config: Config,

    pub fn init(config: Config) MailgunAdapter {
        return .{ .config = config };
    }

    pub fn deinit(_: *MailgunAdapter) void {}

    pub fn send(self: *MailgunAdapter, email: Email, _: std.mem.Allocator) SendResult {
        // Build multipart/form-data body
        const boundary = "zzz_mailgun_boundary_k8m3x";
        var body_buf: [16384]u8 = undefined;
        const body = buildFormData(email, &body_buf, boundary) orelse {
            return .{ .success = false, .error_message = "Failed to build Mailgun form data" };
        };

        // Build auth header (Basic auth: "api:key" base64 encoded)
        var auth_raw_buf: [512]u8 = undefined;
        const auth_raw = std.fmt.bufPrint(&auth_raw_buf, "api:{s}", .{self.config.api_key}) catch {
            return .{ .success = false, .error_message = "Failed to build auth" };
        };

        var b64_buf: [1024]u8 = undefined;
        const b64_len = std.base64.standard.Encoder.calcSize(auth_raw.len);
        _ = std.base64.standard.Encoder.encode(b64_buf[0..b64_len], auth_raw);

        var headers_buf: [2048]u8 = undefined;
        const headers = std.fmt.bufPrint(&headers_buf,
            "Authorization: Basic {s}\r\nContent-Type: multipart/form-data; boundary={s}\r\n",
            .{ b64_buf[0..b64_len], boundary },
        ) catch {
            return .{ .success = false, .error_message = "Failed to build headers" };
        };

        // Build path
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "/v3/{s}/messages", .{self.config.domain}) catch {
            return .{ .success = false, .error_message = "Failed to build path" };
        };

        var response_buf: [4096]u8 = undefined;
        const response = http_client.httpsPost(
            "api.mailgun.net",
            path,
            body,
            headers,
            &response_buf,
        ) catch |err| {
            return .{ .success = false, .error_message = @errorName(err) };
        };

        if (response.status_code >= 200 and response.status_code < 300) {
            return .{ .success = true, .message_id = "mailgun-msg-id" };
        } else {
            return .{ .success = false, .error_message = "Mailgun API error" };
        }
    }

    fn buildFormData(email: Email, buf: []u8, boundary: []const u8) ?[]const u8 {
        var pos: usize = 0;

        // from
        pos += addFormField(buf[pos..], boundary, "from", email.from.email) orelse return null;

        // to
        for (email.to) |addr| {
            pos += addFormField(buf[pos..], boundary, "to", addr.email) orelse return null;
        }

        // cc
        for (email.cc) |addr| {
            pos += addFormField(buf[pos..], boundary, "cc", addr.email) orelse return null;
        }

        // bcc
        for (email.bcc) |addr| {
            pos += addFormField(buf[pos..], boundary, "bcc", addr.email) orelse return null;
        }

        // subject
        pos += addFormField(buf[pos..], boundary, "subject", email.subject) orelse return null;

        // text body
        if (email.text_body) |text| {
            pos += addFormField(buf[pos..], boundary, "text", text) orelse return null;
        }

        // html body
        if (email.html_body) |html| {
            pos += addFormField(buf[pos..], boundary, "html", html) orelse return null;
        }

        // Closing boundary
        const closing = std.fmt.bufPrint(buf[pos..], "--{s}--\r\n", .{boundary}) catch return null;
        pos += closing.len;

        return buf[0..pos];
    }

    fn addFormField(buf: []u8, boundary: []const u8, name: []const u8, value: []const u8) ?usize {
        const part = std.fmt.bufPrint(buf,
            "--{s}\r\nContent-Disposition: form-data; name=\"{s}\"\r\n\r\n{s}\r\n",
            .{ boundary, name, value },
        ) catch return null;
        return part.len;
    }

    fn appendStr(buf: []u8, s: []const u8) ?usize {
        if (s.len > buf.len) return null;
        @memcpy(buf[0..s.len], s);
        return s.len;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "MailgunAdapter init" {
    const adapter = MailgunAdapter.init(.{
        .api_key = "key-test123",
        .domain = "mg.example.com",
    });
    try std.testing.expectEqualStrings("key-test123", adapter.config.api_key);
    try std.testing.expectEqualStrings("mg.example.com", adapter.config.domain);
}

test "Mailgun form data builder" {
    const email = Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "to@example.com" }},
        .subject = "Test",
        .text_body = "Hello",
    };
    var buf: [4096]u8 = undefined;
    const payload = MailgunAdapter.buildFormData(email, &buf, "boundary123").?;
    try std.testing.expect(std.mem.indexOf(u8, payload, "sender@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "to@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "Test") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "Hello") != null);
}
