//! zzz_mailer - Email Sending for the Zzz Web Framework
//!
//! Provides email sending with multiple adapter backends (SMTP, SendGrid, Mailgun,
//! Dev, Test, Log), rate limiting, telemetry hooks, and a dev mailbox web UI.
//! All core types are generic over an adapter type.

const std = @import("std");
const mailer_options = @import("mailer_options");

// Core types
pub const email = @import("email.zig");
pub const Email = email.Email;
pub const Address = email.Address;
pub const Attachment = email.Attachment;
pub const Header = email.Header;
pub const SendResult = email.SendResult;
pub const Disposition = email.Disposition;

// Adapter interface
pub const adapter = @import("adapter.zig");

// Mailer
pub const mailer = @import("mailer.zig");
pub const Mailer = mailer.Mailer;

// Adapters - always available
pub const TestAdapter = @import("test_adapter.zig").TestAdapter;
pub const LogAdapter = @import("log_adapter.zig").LogAdapter;
pub const DevAdapter = @import("dev_adapter.zig").DevAdapter;

// Dev mailbox web UI
pub const DevMailbox = @import("dev_mailbox.zig").DevMailbox;

// Feature-gated adapters
pub const SmtpAdapter = if (mailer_options.smtp_enabled) @import("smtp_adapter.zig").SmtpAdapter else struct {};
pub const SendGridAdapter = if (mailer_options.sendgrid_enabled) @import("sendgrid.zig").SendGridAdapter else struct {};
pub const MailgunAdapter = if (mailer_options.mailgun_enabled) @import("mailgun.zig").MailgunAdapter else struct {};

// Convenience aliases
pub const TestMailer = Mailer(TestAdapter);
pub const LogMailer = Mailer(LogAdapter);
pub const DevMailer = Mailer(DevAdapter);
pub const SmtpMailer = if (mailer_options.smtp_enabled) Mailer(SmtpAdapter) else struct {};
pub const SendGridMailer = if (mailer_options.sendgrid_enabled) Mailer(SendGridAdapter) else struct {};
pub const MailgunMailer = if (mailer_options.mailgun_enabled) Mailer(MailgunAdapter) else struct {};

// Supporting modules
pub const rate_limiter = @import("rate_limiter.zig");
pub const RateLimiter = rate_limiter.RateLimiter;

pub const telemetry = @import("telemetry.zig");
pub const Telemetry = telemetry.Telemetry;
pub const Event = telemetry.Event;

pub const mime = @import("mime.zig");
pub const MimeBuilder = mime.MimeBuilder;

pub const serializer = @import("serializer.zig");

pub const version = "0.1.0";

test {
    std.testing.refAllDecls(@This());
}
