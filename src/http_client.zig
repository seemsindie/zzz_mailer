const std = @import("std");
const tls = @import("smtp/tls.zig");

pub const HttpResponse = struct {
    status_code: u16,
    body: []const u8,
};

pub const HttpError = error{
    DnsResolutionFailed,
    ConnectionFailed,
    TlsHandshakeFailed,
    WriteFailed,
    ReadFailed,
    InvalidResponse,
    ResponseTooLarge,
    TlsWriteFailed,
    TlsReadFailed,
};

/// Minimal HTTPS POST client for API adapter backends.
pub fn httpsPost(
    host: []const u8,
    path: []const u8,
    body: []const u8,
    extra_headers: []const u8,
    response_buf: []u8,
) HttpError!HttpResponse {
    // DNS resolution
    var host_z: [256:0]u8 = undefined;
    const host_len = @min(host.len, 255);
    @memcpy(host_z[0..host_len], host[0..host_len]);
    host_z[host_len] = 0;

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

    const addrs = std.posix.getaddrinfo(&host_z, "443", &hints) catch return error.DnsResolutionFailed;
    defer std.posix.freeaddrinfo(addrs);

    // TCP connect
    const sock = std.posix.socket(addrs.family, addrs.socktype, addrs.protocol) catch return error.ConnectionFailed;
    errdefer std.posix.close(sock);

    std.posix.connect(sock, addrs.addr.?, addrs.addrlen) catch return error.ConnectionFailed;

    // TLS handshake
    var tls_client = tls.TlsClient.upgrade(sock, @ptrCast(&host_z)) catch return error.TlsHandshakeFailed;
    defer tls_client.deinit();

    // Build HTTP request
    var req_buf: [8192]u8 = undefined;
    const request = std.fmt.bufPrint(&req_buf,
        "POST {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "{s}" ++
            "\r\n" ++
            "{s}",
        .{ path, host, body.len, extra_headers, body },
    ) catch return error.WriteFailed;

    // Send request
    var sent: usize = 0;
    while (sent < request.len) {
        sent += tls_client.write(request[sent..]) catch return error.WriteFailed;
    }

    // Read response
    var total_read: usize = 0;
    while (total_read < response_buf.len) {
        const n = tls_client.read(response_buf[total_read..]) catch |err| {
            if (err == error.TlsReadFailed and total_read > 0) break;
            return error.ReadFailed;
        };
        if (n == 0) break;
        total_read += n;
    }

    if (total_read < 12) return error.InvalidResponse;

    // Parse status code (HTTP/1.1 XXX ...)
    const response_str = response_buf[0..total_read];
    if (!std.mem.startsWith(u8, response_str, "HTTP/1.1 ") and !std.mem.startsWith(u8, response_str, "HTTP/1.0 ")) {
        return error.InvalidResponse;
    }

    const status_code = std.fmt.parseInt(u16, response_str[9..12], 10) catch return error.InvalidResponse;

    // Find body after \r\n\r\n
    const body_start = std.mem.indexOf(u8, response_str, "\r\n\r\n") orelse return error.InvalidResponse;
    const resp_body = response_str[body_start + 4 ..];

    return .{
        .status_code = status_code,
        .body = resp_body,
    };
}

// ── Tests ──────────────────────────────────────────────────────────────

test "HttpResponse struct" {
    const resp = HttpResponse{ .status_code = 200, .body = "OK" };
    try std.testing.expectEqual(@as(u16, 200), resp.status_code);
    try std.testing.expectEqualStrings("OK", resp.body);
}
