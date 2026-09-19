//! Small blocking synchronization primitives used by Zeno's synchronous engine paths.
const std = @import("std");

pub const Mutex = struct {
    state: std.atomic.Value(bool) = .init(false),

    pub fn lock(self: *Mutex) void {
        while (self.state.swap(true, .acquire)) std.Thread.yield() catch {};
    }

    pub fn unlock(self: *Mutex) void {
        self.state.store(false, .release);
    }
};

pub const RwLock = struct {
    // High bit is writer-held; low bits count readers.
    state: std.atomic.Value(usize) = .init(0),
    const writer_bit: usize = @as(usize, 1) << (@bitSizeOf(usize) - 1);

    pub fn lock(self: *RwLock) void {
        while (true) {
            if (self.tryLock()) return;
            std.Thread.yield() catch {};
        }
    }

    pub fn tryLock(self: *RwLock) bool {
        return @cmpxchgStrong(usize, &self.state.raw, 0, writer_bit, .acquire, .monotonic) == null;
    }

    pub fn unlock(self: *RwLock) void {
        self.state.store(0, .release);
    }

    pub fn lockShared(self: *RwLock) void {
        while (true) {
            const state = self.state.load(.acquire);
            if ((state & writer_bit) == 0 and
                @cmpxchgWeak(usize, &self.state.raw, state, state + 1, .acquire, .monotonic) == null)
            {
                return;
            }
            std.Thread.yield() catch {};
        }
    }

    pub fn unlockShared(self: *RwLock) void {
        _ = self.state.fetchSub(1, .release);
    }
};

pub const Timer = struct {
    started: i96,

    pub fn start() Timer {
        return .{ .started = std.Io.Timestamp.now(std.Options.debug_io, .awake).nanoseconds };
    }

    pub fn read(self: Timer) u64 {
        const now = std.Io.Timestamp.now(std.Options.debug_io, .awake).nanoseconds;
        return @intCast(@max(now - self.started, 0));
    }
};

pub fn sleep(nanoseconds: u64) void {
    std.Io.sleep(
        std.Options.debug_io,
        std.Io.Duration.fromNanoseconds(@intCast(nanoseconds)),
        .boot,
    ) catch {};
}
