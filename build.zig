const std = @import("std");

fn linkOpenSsl(module: *std.Build.Module, openssl_dep: *std.Build.Dependency) void {
    module.linkLibrary(openssl_dep.artifact("ssl"));
    module.linkLibrary(openssl_dep.artifact("crypto"));
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});

    const smtp_enabled = b.option(bool, "smtp", "Enable SMTP adapter (requires OpenSSL)") orelse true;
    const sendgrid_enabled = b.option(bool, "sendgrid", "Enable SendGrid adapter") orelse false;
    const mailgun_enabled = b.option(bool, "mailgun", "Enable Mailgun adapter") orelse false;
    const async_enabled = b.option(bool, "async", "Enable async delivery via zzz_jobs") orelse false;

    const needs_tls = smtp_enabled or sendgrid_enabled or mailgun_enabled;

    // Create a module for the mailer build options so source can query at comptime
    const mailer_options = b.addOptions();
    mailer_options.addOption([]const u8, "package", "zzz_mailer");
    mailer_options.addOption(bool, "smtp_enabled", smtp_enabled);
    mailer_options.addOption(bool, "sendgrid_enabled", sendgrid_enabled);
    mailer_options.addOption(bool, "mailgun_enabled", mailgun_enabled);
    mailer_options.addOption(bool, "async_enabled", async_enabled);

    const zzz_template_dep = b.dependency("zzz_template", .{
        .target = target,
    });

    const mod = b.addModule("zzz_mailer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    mod.addImport("mailer_options", mailer_options.createModule());
    mod.addImport("zzz_template", zzz_template_dep.module("zzz_template"));

    const openssl_dep = if (needs_tls)
        b.dependency("openssl", .{ .target = target })
    else
        null;

    if (needs_tls) {
        linkOpenSsl(mod, openssl_dep.?);
        mod.link_libc = true;
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // No need to re-add OpenSSL here — mod_tests shares mod's root_module,
    // so all linked libraries are already attached.

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
