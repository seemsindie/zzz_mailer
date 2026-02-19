const std = @import("std");
const auth = @import("auth.zig");
const tls = @import("tls.zig");
const mime_mod = @import("../mime.zig");
const email_mod = @import("../email.zig");
const Email = email_mod.Email;
const MimeBuilder = mime_mod.MimeBuilder;

pub const SmtpError = error{
    ConnectionFailed,
    DnsResolutionFailed,
    GreetingFailed,
    EhloFailed,
    StartTlsFailed,
    AuthFailed,
    MailFromFailed,
    RcptToFailed,
    DataFailed,
    MessageBuildFailed,
    QuitFailed,
    TlsWriteFailed,
    TlsReadFailed,
    Unexpected,
};

pub const SmtpConfig = struct {
    host: []const u8 = "localhost",
    port: u16 = 587,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,
    use_starttls: bool = true,
    hostname_buf: [256]u8 = undefined,

    pub fn getHostnameZ(self: *SmtpConfig) [*:0]const u8 {
        const len = @min(self.host.len, 255);
        @memcpy(self.hostname_buf[0..len], self.host[0..len]);
        self.hostname_buf[len] = 0;
        return @ptrCast(&self.hostname_buf);
    }
};

/// SMTP protocol client.
/// Handles EHLO, STARTTLS, AUTH, MAIL FROM, RCPT TO, DATA, QUIT.
pub const SmtpClient = struct {
    config: SmtpConfig,
    fd: ?std.posix.fd_t = null,
    tls_client: ?tls.TlsClient = null,

    pub fn init(config: SmtpConfig) SmtpClient {
        return .{ .config = config };
    }

    /// Connect to the SMTP server.
    pub fn connect(self: *SmtpClient) SmtpError!void {
        // Create a null-terminated host string for getaddrinfo
        var host_z: [256:0]u8 = undefined;
        const host_len = @min(self.config.host.len, 255);
        @memcpy(host_z[0..host_len], self.config.host[0..host_len]);
        host_z[host_len] = 0;

        var port_z: [8:0]u8 = undefined;
        const port_str = std.fmt.bufPrint(&port_z, "{d}", .{self.config.port}) catch return error.ConnectionFailed;
        port_z[port_str.len] = 0;

        const hints = std.posix.addrinfo{
            .flags = 0,
            .family = std.posix.AF.INET,
            .socktype = std.posix.SOCK.STREAM,
            .protocol = 0,
            .addrlen = 0,
            .addr = null,
            .canonname = null,
            .next = null,
        };

        const addrs = std.posix.getaddrinfo(&host_z, @ptrCast(&port_z), &hints) catch return error.DnsResolutionFailed;
        defer std.posix.freeaddrinfo(addrs);

        const sock = std.posix.socket(addrs.family, addrs.socktype, addrs.protocol) catch return error.ConnectionFailed;
        errdefer std.posix.close(sock);

        std.posix.connect(sock, addrs.addr.?, addrs.addrlen) catch return error.ConnectionFailed;
        self.fd = sock;

        // Read greeting (220)
        var buf: [1024]u8 = undefined;
        const n = self.rawRead(&buf) catch return error.GreetingFailed;
        if (n < 3 or !std.mem.startsWith(u8, buf[0..n], "220")) {
            return error.GreetingFailed;
        }
    }

    /// Send EHLO command.
    pub fn ehlo(self: *SmtpClient) SmtpError!void {
        self.writeLine("EHLO localhost") catch return error.EhloFailed;
        var buf: [1024]u8 = undefined;
        const n = self.readResponse(&buf) catch return error.EhloFailed;
        if (n < 3 or !std.mem.startsWith(u8, buf[0..n], "250")) {
            return error.EhloFailed;
        }
    }

    /// Upgrade connection to TLS via STARTTLS.
    pub fn startTls(self: *SmtpClient) SmtpError!void {
        self.writeLine("STARTTLS") catch return error.StartTlsFailed;
        var buf: [1024]u8 = undefined;
        const n = self.readResponse(&buf) catch return error.StartTlsFailed;
        if (n < 3 or !std.mem.startsWith(u8, buf[0..n], "220")) {
            return error.StartTlsFailed;
        }

        // Upgrade to TLS
        var config = self.config;
        self.tls_client = tls.TlsClient.upgrade(self.fd.?, config.getHostnameZ()) catch return error.StartTlsFailed;
    }

    /// Authenticate with the server.
    pub fn authenticate(self: *SmtpClient) SmtpError!void {
        const username = self.config.username orelse return;
        const password = self.config.password orelse return;

        var auth_buf: [512]u8 = undefined;
        const encoded = auth.encodePlain(username, password, &auth_buf) orelse return error.AuthFailed;

        var cmd_buf: [600]u8 = undefined;
        const cmd = std.fmt.bufPrint(&cmd_buf, "AUTH PLAIN {s}", .{encoded}) catch return error.AuthFailed;
        self.writeLine(cmd) catch return error.AuthFailed;

        var buf: [1024]u8 = undefined;
        const n = self.readResponse(&buf) catch return error.AuthFailed;
        if (n < 3 or !std.mem.startsWith(u8, buf[0..n], "235")) {
            return error.AuthFailed;
        }
    }

    /// Send an email message.
    pub fn sendMail(self: *SmtpClient, email: Email) SmtpError!void {
        // MAIL FROM
        var from_buf: [300]u8 = undefined;
        const mail_from = std.fmt.bufPrint(&from_buf, "MAIL FROM:<{s}>", .{email.from.email}) catch return error.MailFromFailed;
        self.writeLine(mail_from) catch return error.MailFromFailed;
        try self.expectResponse("250");

        // RCPT TO for all recipients
        for (email.to) |addr| {
            var rcpt_buf: [300]u8 = undefined;
            const rcpt = std.fmt.bufPrint(&rcpt_buf, "RCPT TO:<{s}>", .{addr.email}) catch return error.RcptToFailed;
            self.writeLine(rcpt) catch return error.RcptToFailed;
            try self.expectResponse("250");
        }
        for (email.cc) |addr| {
            var rcpt_buf: [300]u8 = undefined;
            const rcpt = std.fmt.bufPrint(&rcpt_buf, "RCPT TO:<{s}>", .{addr.email}) catch return error.RcptToFailed;
            self.writeLine(rcpt) catch return error.RcptToFailed;
            try self.expectResponse("250");
        }
        for (email.bcc) |addr| {
            var rcpt_buf: [300]u8 = undefined;
            const rcpt = std.fmt.bufPrint(&rcpt_buf, "RCPT TO:<{s}>", .{addr.email}) catch return error.RcptToFailed;
            self.writeLine(rcpt) catch return error.RcptToFailed;
            try self.expectResponse("250");
        }

        // DATA
        self.writeLine("DATA") catch return error.DataFailed;
        try self.expectResponse("354");

        // Build MIME message
        var mime_buf: [65536]u8 = undefined;
        const message = MimeBuilder.build(email, &mime_buf) orelse return error.MessageBuildFailed;
        self.writeAll(message) catch return error.DataFailed;
        self.writeLine("\r\n.") catch return error.DataFailed;
        try self.expectResponse("250");
    }

    /// Send QUIT command and close connection.
    pub fn quit(self: *SmtpClient) void {
        self.writeLine("QUIT") catch {};
        if (self.tls_client) |*tc| {
            tc.deinit();
            self.tls_client = null;
        }
        if (self.fd) |fd| {
            std.posix.close(fd);
            self.fd = null;
        }
    }

    fn expectResponse(self: *SmtpClient, expected_prefix: []const u8) SmtpError!void {
        var buf: [1024]u8 = undefined;
        const n = self.readResponse(&buf) catch return error.Unexpected;
        if (n < expected_prefix.len or !std.mem.startsWith(u8, buf[0..n], expected_prefix)) {
            return error.Unexpected;
        }
    }

    fn writeLine(self: *SmtpClient, line: []const u8) !void {
        try self.writeAll(line);
        try self.writeAll("\r\n");
    }

    fn writeAll(self: *SmtpClient, data: []const u8) !void {
        if (self.tls_client) |*tc| {
            var sent: usize = 0;
            while (sent < data.len) {
                sent += tc.write(data[sent..]) catch return error.TlsWriteFailed;
            }
        } else if (self.fd) |fd| {
            var sent: usize = 0;
            while (sent < data.len) {
                const n = std.posix.write(fd, data[sent..]) catch return error.ConnectionFailed;
                sent += n;
            }
        } else {
            return error.ConnectionFailed;
        }
    }

    fn readResponse(self: *SmtpClient, buf: []u8) !usize {
        return self.rawRead(buf);
    }

    fn rawRead(self: *SmtpClient, buf: []u8) !usize {
        if (self.tls_client) |*tc| {
            return tc.read(buf) catch return error.TlsReadFailed;
        } else if (self.fd) |fd| {
            return std.posix.read(fd, buf) catch return error.ConnectionFailed;
        } else {
            return error.ConnectionFailed;
        }
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "SmtpClient init" {
    const client = SmtpClient.init(.{
        .host = "smtp.example.com",
        .port = 587,
        .username = "user",
        .password = "pass",
    });
    try std.testing.expectEqualStrings("smtp.example.com", client.config.host);
    try std.testing.expectEqual(@as(u16, 587), client.config.port);
}
