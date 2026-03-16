# zzz_mailer

Email sending library for the zzz web framework.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/Zig-0.16.0-orange.svg)](https://ziglang.org/)

A pluggable email delivery library built on the adapter pattern. Ships with adapters for SMTP, SendGrid, Mailgun, and several development/testing helpers. Supports MIME multipart, attachments, rate limiting, and telemetry hooks.

## Features

- **Adapter pattern** -- compile-time validated interface with `init`, `deinit`, and `send`
- **SMTP adapter** -- direct SMTP delivery with STARTTLS and authentication
- **SendGrid adapter** -- SendGrid v3 REST API integration
- **Mailgun adapter** -- Mailgun REST API with multipart form encoding
- **Dev adapter** -- in-memory ring buffer with a web UI for local development
- **Log adapter** -- prints emails to stderr, always returns success
- **Test adapter** -- in-memory store with assertion helpers (`allSentCount`, `lastSentSubject`, `sentToAddress`)
- **Email composition** -- to, cc, bcc, reply-to, text/HTML bodies, attachments, custom headers
- **Attachments** -- binary content with content type, disposition (inline or attachment), and content ID
- **Rate limiting** -- token-bucket rate limiter with configurable max-per-second
- **Telemetry** -- event hooks for `email_sending`, `email_sent`, `email_failed`, and `rate_limited`

## Quick Start

### Sending with SMTP

```zig
const zzz_mailer = @import("zzz_mailer");
const Mailer = zzz_mailer.Mailer;
const SmtpAdapter = zzz_mailer.SmtpAdapter;
const Email = zzz_mailer.Email;

var mailer = Mailer(SmtpAdapter).init(.{
    .adapter = .{
        .host = "smtp.example.com",
        .port = 587,
        .username = "user",
        .password = "pass",
        .use_starttls = true,
    },
});
defer mailer.deinit();

const email = Email{
    .from = .{ .email = "noreply@example.com", .name = "My App" },
    .to = &.{.{ .email = "user@example.com" }},
    .subject = "Welcome!",
    .text_body = "Thanks for signing up.",
    .html_body = "<h1>Welcome!</h1><p>Thanks for signing up.</p>",
};

const result = mailer.send(email, allocator);
if (!result.success) {
    std.log.err("Send failed: {s}", .{result.error_message orelse "unknown"});
}
```

### Sending with SendGrid

```zig
var mailer = Mailer(zzz_mailer.SendGridAdapter).init(.{
    .adapter = .{ .api_key = "SG.your-api-key" },
});
defer mailer.deinit();

_ = mailer.send(email, allocator);
```

### Sending with Mailgun

```zig
var mailer = Mailer(zzz_mailer.MailgunAdapter).init(.{
    .adapter = .{
        .api_key = "key-your-api-key",
        .domain = "mg.example.com",
    },
});
defer mailer.deinit();

_ = mailer.send(email, allocator);
```

### Development Adapter

The dev adapter stores emails in memory so you can inspect them through a web UI during local development.

```zig
var mailer = Mailer(zzz_mailer.DevAdapter).init(.{});
defer mailer.deinit();

_ = mailer.send(email, allocator);

// Query stored emails
const count = mailer.adapter.sentCount();
const stored = mailer.adapter.getEmail(0).?;
std.debug.print("Subject: {s}\n", .{stored.getSubject()});
```

### Test Adapter

```zig
test "sends welcome email" {
    var mailer = Mailer(zzz_mailer.TestAdapter).init(.{});
    defer mailer.deinit();

    _ = mailer.send(email, std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), mailer.adapter.allSentCount());
    try std.testing.expectEqualStrings("Welcome!", mailer.adapter.lastSentSubject().?);
    try std.testing.expect(mailer.adapter.sentToAddress("user@example.com"));
}
```

### Rate Limiting

```zig
var mailer = Mailer(SmtpAdapter).init(.{
    .adapter = .{ .host = "smtp.example.com" },
    .rate_limit = .{ .max_per_second = 10.0 },
});
```

### Telemetry

```zig
var telemetry = zzz_mailer.Telemetry{};
telemetry.attach(&myHandler);

var mailer = Mailer(SmtpAdapter).init(.{ .adapter = .{} });
mailer.telemetry = &telemetry;
```

## Adapters

| Adapter | Use Case | Config |
|---------|----------|--------|
| `SmtpAdapter` | Production SMTP delivery | host, port, username, password, use_starttls |
| `SendGridAdapter` | SendGrid v3 API | api_key |
| `MailgunAdapter` | Mailgun API | api_key, domain |
| `DevAdapter` | Local development with web UI | (none) |
| `LogAdapter` | Debug logging to stderr | prefix |
| `TestAdapter` | Unit test assertions | (none) |

## Building

```bash
zig build        # Build
zig build test   # Run tests
```

## Documentation

Full documentation available at [docs.zzz.seemsindie.com](https://docs.zzz.seemsindie.com) under the Mailer section.

## Ecosystem

| Package | Description |
|---------|-------------|
| [zzz.zig](https://github.com/seemsindie/zzz.zig) | Core web framework |
| [zzz_db](https://github.com/seemsindie/zzz_db) | Database ORM (SQLite + PostgreSQL) |
| [zzz_jobs](https://github.com/seemsindie/zzz_jobs) | Background job processing |
| [zzz_mailer](https://github.com/seemsindie/zzz_mailer) | Email sending |
| [zzz_template](https://github.com/seemsindie/zzz_template) | Template engine |
| [zzz_cli](https://github.com/seemsindie/zzz_cli) | CLI tooling |

## Requirements

- Zig 0.16.0-dev.2535+b5bd49460 or later

## License

MIT License -- Copyright (c) 2026 Ivan Stamenkovic
