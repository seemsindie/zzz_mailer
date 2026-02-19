const std = @import("std");
const email_mod = @import("email.zig");
const Email = email_mod.Email;
const SendResult = email_mod.SendResult;
const smtp_client = @import("smtp/client.zig");
const SmtpClient = smtp_client.SmtpClient;

/// SMTP adapter wrapping the SmtpClient for the mailer interface.
pub const SmtpAdapter = struct {
    pub const Config = struct {
        host: []const u8 = "localhost",
        port: u16 = 587,
        username: ?[]const u8 = null,
        password: ?[]const u8 = null,
        use_starttls: bool = true,
    };

    config: Config,

    pub fn init(config: Config) SmtpAdapter {
        return .{ .config = config };
    }

    pub fn deinit(_: *SmtpAdapter) void {}

    pub fn send(self: *SmtpAdapter, email: Email, _: std.mem.Allocator) SendResult {
        var client = SmtpClient.init(.{
            .host = self.config.host,
            .port = self.config.port,
            .username = self.config.username,
            .password = self.config.password,
            .use_starttls = self.config.use_starttls,
        });
        defer client.quit();

        client.connect() catch |err| {
            return .{ .success = false, .error_message = @errorName(err) };
        };

        client.ehlo() catch |err| {
            return .{ .success = false, .error_message = @errorName(err) };
        };

        if (self.config.use_starttls) {
            client.startTls() catch |err| {
                return .{ .success = false, .error_message = @errorName(err) };
            };
            // Re-EHLO after STARTTLS
            client.ehlo() catch |err| {
                return .{ .success = false, .error_message = @errorName(err) };
            };
        }

        if (self.config.username != null) {
            client.authenticate() catch |err| {
                return .{ .success = false, .error_message = @errorName(err) };
            };
        }

        client.sendMail(email) catch |err| {
            return .{ .success = false, .error_message = @errorName(err) };
        };

        return .{ .success = true, .message_id = "smtp-msg-id" };
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "SmtpAdapter init" {
    const adapter = SmtpAdapter.init(.{
        .host = "smtp.example.com",
        .port = 465,
    });
    try std.testing.expectEqualStrings("smtp.example.com", adapter.config.host);
    try std.testing.expectEqual(@as(u16, 465), adapter.config.port);
}
