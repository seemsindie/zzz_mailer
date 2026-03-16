# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-02-16

### Added
- `Mailer` core with configurable adapter system
- `Email` struct for composing messages (to, cc, bcc, subject, body)
- SMTP adapter with TLS support
- SendGrid adapter (HTTP API)
- Mailgun adapter (HTTP API)
- Dev adapter (logs to console, no actual sending)
- Test adapter (captures sent emails for assertions)
- Log adapter (structured log output)
- MIME multipart builder (text, HTML, mixed, attachments)
- Inline attachments with Content-ID
- Rate limiting for send operations
- Telemetry hooks (7 event types)
- Dev mailbox (in-memory inbox for development)
