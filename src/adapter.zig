const std = @import("std");

/// Comptime validation that an adapter type has all required declarations.
pub fn validate(comptime Adapter: type) void {
    if (!@hasDecl(Adapter, "Config")) {
        @compileError("Adapter missing 'Config' type");
    }

    const required_methods = .{
        "init",
        "deinit",
        "send",
    };

    inline for (required_methods) |method| {
        if (!@hasDecl(Adapter, method)) {
            @compileError("Adapter missing '" ++ method ++ "' method");
        }
    }
}

test "validate accepts TestAdapter" {
    const TestAdapter = @import("test_adapter.zig").TestAdapter;
    validate(TestAdapter);
}

test "validate accepts LogAdapter" {
    const LogAdapter = @import("log_adapter.zig").LogAdapter;
    validate(LogAdapter);
}

test "validate accepts DevAdapter" {
    const DevAdapter = @import("dev_adapter.zig").DevAdapter;
    validate(DevAdapter);
}
