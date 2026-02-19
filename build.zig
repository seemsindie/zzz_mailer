const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});

    const smtp_enabled = b.option(bool, "smtp", "Enable SMTP adapter (requires OpenSSL)") orelse true;
    const sendgrid_enabled = b.option(bool, "sendgrid", "Enable SendGrid adapter") orelse false;
    const mailgun_enabled = b.option(bool, "mailgun", "Enable Mailgun adapter") orelse false;
    const async_enabled = b.option(bool, "async", "Enable async delivery via zzz_jobs") orelse false;

    const is_macos = target.result.os.tag == .macos;
    const needs_tls = smtp_enabled or sendgrid_enabled or mailgun_enabled;

    // Create a module for the mailer build options so source can query at comptime
    const mailer_options = b.addOptions();
    mailer_options.addOption([]const u8, "package", "zzz_mailer");
    mailer_options.addOption(bool, "smtp_enabled", smtp_enabled);
    mailer_options.addOption(bool, "sendgrid_enabled", sendgrid_enabled);
    mailer_options.addOption(bool, "mailgun_enabled", mailgun_enabled);
    mailer_options.addOption(bool, "async_enabled", async_enabled);

    const mod = b.addModule("zzz_mailer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    mod.addImport("mailer_options", mailer_options.createModule());

    if (needs_tls) {
        mod.linkSystemLibrary("ssl", .{});
        mod.linkSystemLibrary("crypto", .{});
        mod.link_libc = true;
        if (is_macos) {
            mod.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/include" });
            mod.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/lib" });
        }
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    if (needs_tls) {
        mod_tests.root_module.linkSystemLibrary("ssl", .{});
        mod_tests.root_module.linkSystemLibrary("crypto", .{});
        mod_tests.root_module.link_libc = true;
        if (is_macos) {
            mod_tests.root_module.addSystemIncludePath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/include" });
            mod_tests.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/opt/openssl@3/lib" });
        }
    }

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
