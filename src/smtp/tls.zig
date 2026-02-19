const std = @import("std");

pub const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
    @cInclude("openssl/crypto.h");
});

pub const TlsError = error{
    ContextCreationFailed,
    SslObjectCreationFailed,
    SniSetupFailed,
    HandshakeFailed,
};

/// TLS client connection wrapping an existing socket fd.
pub const TlsClient = struct {
    ctx: *c.SSL_CTX,
    ssl: *c.SSL,

    /// Upgrade an existing TCP socket to TLS (client-side STARTTLS).
    pub fn upgrade(fd: std.posix.fd_t, hostname: ?[*:0]const u8) TlsError!TlsClient {
        const method = c.TLS_client_method() orelse return error.ContextCreationFailed;
        const ctx = c.SSL_CTX_new(method) orelse return error.ContextCreationFailed;
        errdefer c.SSL_CTX_free(ctx);

        // Set minimum TLS version to 1.2
        if (c.SSL_CTX_set_min_proto_version(ctx, c.TLS1_2_VERSION) != 1) {
            return error.ContextCreationFailed;
        }

        const ssl = c.SSL_new(ctx) orelse return error.SslObjectCreationFailed;
        errdefer c.SSL_free(ssl);

        // Set SNI hostname if provided
        if (hostname) |host| {
            if (c.SSL_set_tlsext_host_name(ssl, host) != 1) {
                return error.SniSetupFailed;
            }
        }

        if (c.SSL_set_fd(ssl, fd) != 1) {
            return error.HandshakeFailed;
        }

        const ret = c.SSL_connect(ssl);
        if (ret != 1) {
            return error.HandshakeFailed;
        }

        return .{ .ctx = ctx, .ssl = ssl };
    }

    /// Write data over TLS.
    pub fn write(self: *TlsClient, data: []const u8) !usize {
        const ret = c.SSL_write(self.ssl, data.ptr, @intCast(data.len));
        if (ret <= 0) return error.TlsWriteFailed;
        return @intCast(ret);
    }

    /// Read data over TLS.
    pub fn read(self: *TlsClient, buf: []u8) !usize {
        const ret = c.SSL_read(self.ssl, buf.ptr, @intCast(buf.len));
        if (ret <= 0) return error.TlsReadFailed;
        return @intCast(ret);
    }

    /// Shut down TLS and free resources.
    pub fn deinit(self: *TlsClient) void {
        _ = c.SSL_shutdown(self.ssl);
        c.SSL_free(self.ssl);
        c.SSL_CTX_free(self.ctx);
    }
};
