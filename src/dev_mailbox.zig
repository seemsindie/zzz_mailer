const std = @import("std");
const DevAdapter = @import("dev_adapter.zig").DevAdapter;

/// Dev mailbox web UI for browsing emails sent through the DevAdapter.
/// Provides standalone HTML rendering functions that controllers can call.
pub const DevMailbox = struct {
    adapter: *DevAdapter,

    pub fn init(adapter: *DevAdapter) DevMailbox {
        return .{ .adapter = adapter };
    }

    /// Render the inbox page listing all stored emails.
    pub fn renderInbox(self: *DevMailbox, buf: []u8) ?[]const u8 {
        var pos: usize = 0;
        pos += appendStr(buf[pos..], inbox_header) orelse return null;

        const count = self.adapter.availableCount();
        if (count == 0) {
            pos += appendStr(buf[pos..], "<tr><td colspan=\"4\" style=\"text-align:center;color:#999;padding:40px\">No emails yet. Send one to see it here.</td></tr>\n") orelse return null;
        } else {
            // List emails in reverse order (newest first)
            var i: usize = count;
            while (i > 0) {
                i -= 1;
                const email = self.adapter.getEmail(i) orelse continue;
                const row = std.fmt.bufPrint(buf[pos..],
                    \\<tr onclick="window.location='/__zzz/mailbox/{d}'" style="cursor:pointer">
                    \\<td>{s}</td>
                    \\<td>{s}</td>
                    \\<td><a href="/__zzz/mailbox/{d}">{s}</a></td>
                    \\<td>{d}</td>
                    \\</tr>
                    \\
                , .{
                    i,
                    email.getFrom(),
                    email.getTo(),
                    i,
                    email.getSubject(),
                    email.timestamp,
                }) catch break;
                pos += row.len;
            }
        }

        pos += appendStr(buf[pos..], inbox_footer) orelse return null;
        return buf[0..pos];
    }

    /// Render the detail page for a single email.
    pub fn renderDetail(self: *DevMailbox, index: usize, buf: []u8) ?[]const u8 {
        const email = self.adapter.getEmail(index) orelse return null;
        var pos: usize = 0;

        pos += appendStr(buf[pos..], detail_header) orelse return null;

        const info = std.fmt.bufPrint(buf[pos..],
            \\<div class="field"><strong>From:</strong> {s}</div>
            \\<div class="field"><strong>To:</strong> {s}</div>
            \\
        , .{
            email.getFrom(),
            email.getTo(),
        }) catch return null;
        pos += info.len;

        if (email.cc_len > 0) {
            const cc = std.fmt.bufPrint(buf[pos..],
                \\<div class="field"><strong>Cc:</strong> {s}</div>
                \\
            , .{email.getCc()}) catch return null;
            pos += cc.len;
        }
        if (email.bcc_len > 0) {
            const bcc = std.fmt.bufPrint(buf[pos..],
                \\<div class="field"><strong>Bcc:</strong> {s}</div>
                \\
            , .{email.getBcc()}) catch return null;
            pos += bcc.len;
        }

        const subj = std.fmt.bufPrint(buf[pos..],
            \\<div class="field"><strong>Subject:</strong> {s}</div>
            \\<div class="field"><strong>Timestamp:</strong> {d}</div>
            \\
        , .{ email.getSubject(), email.timestamp }) catch return null;
        pos += subj.len;

        // Text body
        if (email.text_body_len > 0) {
            pos += appendStr(buf[pos..], "<h3>Text Body</h3>\n<pre class=\"body\">") orelse return null;
            pos += appendStr(buf[pos..], email.getTextBody()) orelse return null;
            pos += appendStr(buf[pos..], "</pre>\n") orelse return null;
        }

        // HTML body (preview in sandboxed iframe)
        if (email.html_body_len > 0) {
            const iframe = std.fmt.bufPrint(buf[pos..],
                \\<h3>HTML Body</h3>
                \\<iframe src="/__zzz/mailbox/{d}/html" sandbox="" style="width:100%;height:400px;border:1px solid #ddd;border-radius:4px"></iframe>
                \\
            , .{index}) catch return null;
            pos += iframe.len;
        }

        pos += appendStr(buf[pos..], detail_footer) orelse return null;
        return buf[0..pos];
    }

    /// Return the raw HTML body for iframe embedding.
    pub fn renderHtmlBody(self: *DevMailbox, index: usize) ?[]const u8 {
        const email = self.adapter.getEmail(index) orelse return null;
        if (email.html_body_len == 0) return null;
        return email.getHtmlBody();
    }

    fn appendStr(buf: []u8, s: []const u8) ?usize {
        if (s.len > buf.len) return null;
        @memcpy(buf[0..s.len], s);
        return s.len;
    }

    const inbox_header =
        \\<!DOCTYPE html>
        \\<html><head>
        \\<meta charset="utf-8">
        \\<title>zzz Mailbox</title>
        \\<meta http-equiv="refresh" content="5">
        \\<style>
        \\  * { box-sizing: border-box; margin: 0; padding: 0; }
        \\  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f5f5; color: #333; padding: 20px; }
        \\  .container { max-width: 960px; margin: 0 auto; }
        \\  h1 { margin-bottom: 8px; font-size: 24px; }
        \\  .subtitle { color: #666; margin-bottom: 20px; font-size: 14px; }
        \\  table { width: 100%; border-collapse: collapse; background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        \\  th { background: #667eea; color: #fff; padding: 12px 16px; text-align: left; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px; }
        \\  td { padding: 12px 16px; border-bottom: 1px solid #eee; font-size: 14px; }
        \\  tr:hover td { background: #f8f9ff; }
        \\  a { color: #667eea; text-decoration: none; }
        \\  a:hover { text-decoration: underline; }
        \\  .actions { margin-top: 16px; }
        \\  .btn { display: inline-block; padding: 8px 16px; background: #e53e3e; color: #fff; border: none; border-radius: 4px; cursor: pointer; font-size: 13px; text-decoration: none; }
        \\  .btn:hover { background: #c53030; }
        \\</style>
        \\</head><body>
        \\<div class="container">
        \\<h1>zzz Dev Mailbox</h1>
        \\<p class="subtitle">Emails sent in development (auto-refreshes every 5s)</p>
        \\<table>
        \\<tr><th>From</th><th>To</th><th>Subject</th><th>Timestamp</th></tr>
        \\
    ;

    const inbox_footer =
        \\</table>
        \\<div class="actions">
        \\<form method="POST" action="/__zzz/mailbox/clear" style="display:inline">
        \\<button type="submit" class="btn">Clear All</button>
        \\</form>
        \\</div>
        \\</div>
        \\</body></html>
        \\
    ;

    const detail_header =
        \\<!DOCTYPE html>
        \\<html><head>
        \\<meta charset="utf-8">
        \\<title>zzz Mailbox - Email Detail</title>
        \\<style>
        \\  * { box-sizing: border-box; margin: 0; padding: 0; }
        \\  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f5f5f5; color: #333; padding: 20px; }
        \\  .container { max-width: 960px; margin: 0 auto; }
        \\  h1 { margin-bottom: 16px; font-size: 24px; }
        \\  .back { display: inline-block; margin-bottom: 16px; color: #667eea; text-decoration: none; font-size: 14px; }
        \\  .back:hover { text-decoration: underline; }
        \\  .card { background: #fff; border-radius: 8px; padding: 24px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        \\  .field { margin-bottom: 8px; font-size: 14px; }
        \\  h3 { margin: 20px 0 8px; font-size: 16px; color: #555; }
        \\  pre.body { background: #f9f9f9; padding: 16px; border-radius: 4px; font-size: 13px; white-space: pre-wrap; word-wrap: break-word; border: 1px solid #eee; }
        \\</style>
        \\</head><body>
        \\<div class="container">
        \\<a href="/__zzz/mailbox" class="back">&larr; Back to Inbox</a>
        \\<h1>Email Detail</h1>
        \\<div class="card">
        \\
    ;

    const detail_footer =
        \\</div>
        \\</div>
        \\</body></html>
        \\
    ;
};

// ── Tests ──────────────────────────────────────────────────────────────

test "DevMailbox renders empty inbox" {
    const email_mod = @import("email.zig");
    _ = email_mod;
    var adapter = DevAdapter.init(.{});
    var mailbox = DevMailbox.init(&adapter);

    var buf: [16384]u8 = undefined;
    const html = mailbox.renderInbox(&buf).?;
    try std.testing.expect(std.mem.indexOf(u8, html, "zzz Dev Mailbox") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "No emails yet") != null);
}

test "DevMailbox renders inbox with emails" {
    const Email = @import("email.zig").Email;
    var adapter = DevAdapter.init(.{});

    _ = adapter.send(Email{
        .from = .{ .email = "test@example.com" },
        .to = &.{.{ .email = "user@example.com" }},
        .subject = "Welcome!",
        .text_body = "Hello",
    }, std.testing.allocator);

    var mailbox = DevMailbox.init(&adapter);
    var buf: [16384]u8 = undefined;
    const html = mailbox.renderInbox(&buf).?;
    try std.testing.expect(std.mem.indexOf(u8, html, "Welcome!") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "test@example.com") != null);
}

test "DevMailbox renders detail page" {
    const Email = @import("email.zig").Email;
    var adapter = DevAdapter.init(.{});

    _ = adapter.send(Email{
        .from = .{ .email = "sender@example.com" },
        .to = &.{.{ .email = "user@example.com" }},
        .subject = "Detail Test",
        .text_body = "Body content here",
        .html_body = "<h1>HTML Body</h1>",
    }, std.testing.allocator);

    var mailbox = DevMailbox.init(&adapter);
    var buf: [16384]u8 = undefined;
    const html = mailbox.renderDetail(0, &buf).?;
    try std.testing.expect(std.mem.indexOf(u8, html, "sender@example.com") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Body content here") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "iframe") != null);
}

test "DevMailbox returns raw html body" {
    const Email = @import("email.zig").Email;
    var adapter = DevAdapter.init(.{});

    _ = adapter.send(Email{
        .from = .{ .email = "sender@example.com" },
        .subject = "Test",
        .html_body = "<p>Hello HTML</p>",
    }, std.testing.allocator);

    var mailbox = DevMailbox.init(&adapter);
    const html = mailbox.renderHtmlBody(0).?;
    try std.testing.expectEqualStrings("<p>Hello HTML</p>", html);
}
