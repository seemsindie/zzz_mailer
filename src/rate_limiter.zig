const std = @import("std");

const c = @cImport({
    @cInclude("time.h");
});

fn timestampMs() i64 {
    var ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
    return @as(i64, @intCast(ts.tv_sec)) * 1000 + @divTrunc(@as(i64, @intCast(ts.tv_nsec)), 1_000_000);
}

fn sleepMs(ms: u32) void {
    var ts: c.struct_timespec = .{
        .tv_sec = @intCast(@divTrunc(ms, 1000)),
        .tv_nsec = @intCast(@as(u64, @mod(ms, 1000)) * 1_000_000),
    };
    _ = c.nanosleep(&ts, &ts);
}

/// Token-bucket rate limiter for email sending.
pub const RateLimiter = struct {
    max_per_second: f64,
    tokens: f64,
    last_refill_ms: i64,
    mutex: std.atomic.Mutex = .unlocked,

    pub const Config = struct {
        max_per_second: f64 = 10.0,
    };

    pub fn init(config: Config) RateLimiter {
        return .{
            .max_per_second = config.max_per_second,
            .tokens = config.max_per_second,
            .last_refill_ms = timestampMs(),
        };
    }

    /// Try to acquire a token. Returns true if allowed, false if rate-limited.
    pub fn acquire(self: *RateLimiter) bool {
        while (!self.mutex.tryLock()) {}
        defer self.mutex.unlock();

        self.refill();

        if (self.tokens >= 1.0) {
            self.tokens -= 1.0;
            return true;
        }
        return false;
    }

    /// Block until a token is available, then acquire it.
    pub fn acquireBlocking(self: *RateLimiter) void {
        while (true) {
            if (self.acquire()) return;
            sleepMs(10);
        }
    }

    fn refill(self: *RateLimiter) void {
        const now = timestampMs();
        const elapsed_ms = now - self.last_refill_ms;
        if (elapsed_ms <= 0) return;

        const elapsed_s: f64 = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
        const new_tokens = elapsed_s * self.max_per_second;
        self.tokens = @min(self.tokens + new_tokens, self.max_per_second);
        self.last_refill_ms = now;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "rate limiter allows tokens up to max" {
    var limiter = RateLimiter.init(.{ .max_per_second = 2.0 });
    try std.testing.expect(limiter.acquire());
    try std.testing.expect(limiter.acquire());
    // Third should fail (only 2 tokens)
    try std.testing.expect(!limiter.acquire());
}

test "rate limiter refills over time" {
    var limiter = RateLimiter.init(.{ .max_per_second = 100.0 });
    // Drain all tokens
    var count: usize = 0;
    while (limiter.acquire()) {
        count += 1;
        if (count > 200) break;
    }
    // After sleeping briefly, tokens should refill
    sleepMs(50);
    try std.testing.expect(limiter.acquire());
}
