const std = @import("std");

/// Encode credentials for SMTP AUTH PLAIN (RFC 4616).
/// Format: base64(\0username\0password)
pub fn encodePlain(username: []const u8, password: []const u8, buf: []u8) ?[]const u8 {
    // Build the PLAIN payload: \0username\0password
    var plain_buf: [512]u8 = undefined;
    if (1 + username.len + 1 + password.len > plain_buf.len) return null;

    plain_buf[0] = 0;
    @memcpy(plain_buf[1..][0..username.len], username);
    plain_buf[1 + username.len] = 0;
    @memcpy(plain_buf[2 + username.len ..][0..password.len], password);
    const plain_len = 1 + username.len + 1 + password.len;

    const encoded_len = std.base64.standard.Encoder.calcSize(plain_len);
    if (encoded_len > buf.len) return null;
    _ = std.base64.standard.Encoder.encode(buf[0..encoded_len], plain_buf[0..plain_len]);
    return buf[0..encoded_len];
}

/// Encode credentials for SMTP AUTH LOGIN.
/// Returns base64-encoded username and password separately.
pub fn encodeLogin(value: []const u8, buf: []u8) ?[]const u8 {
    const encoded_len = std.base64.standard.Encoder.calcSize(value.len);
    if (encoded_len > buf.len) return null;
    _ = std.base64.standard.Encoder.encode(buf[0..encoded_len], value);
    return buf[0..encoded_len];
}

// ── Tests ──────────────────────────────────────────────────────────────

test "AUTH PLAIN encoding" {
    var buf: [256]u8 = undefined;
    const encoded = encodePlain("user@example.com", "password123", &buf).?;
    // Verify it decodes back correctly
    var decoded: [512]u8 = undefined;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch unreachable;
    std.base64.standard.Decoder.decode(&decoded, encoded) catch unreachable;
    // First byte should be 0
    try std.testing.expectEqual(@as(u8, 0), decoded[0]);
    // Then username
    try std.testing.expectEqualStrings("user@example.com", decoded[1..17]);
    // Then 0
    try std.testing.expectEqual(@as(u8, 0), decoded[17]);
    // Then password
    try std.testing.expectEqualStrings("password123", decoded[18..decoded_len]);
}

test "AUTH LOGIN encoding" {
    var buf: [256]u8 = undefined;
    const encoded = encodeLogin("user@example.com", &buf).?;
    var decoded: [256]u8 = undefined;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch unreachable;
    std.base64.standard.Decoder.decode(&decoded, encoded) catch unreachable;
    try std.testing.expectEqualStrings("user@example.com", decoded[0..decoded_len]);
}
