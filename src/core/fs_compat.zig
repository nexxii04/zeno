//! Synchronous filesystem compatibility helpers used while the storage code adopts std.Io.
const std = @import("std");
const io = std.Options.debug_io;

pub const path = std.Io.Dir.path;

pub const File = struct {
    inner: std.Io.File,
    handle: std.Io.File.Handle,

    pub fn close(self: File) void {
        self.inner.close(io);
    }

    pub fn writeAll(self: File, bytes: []const u8) !void {
        try self.inner.writeStreamingAll(io, bytes);
    }

    pub fn readAll(self: File, buffer: []u8) !usize {
        var total: usize = 0;
        while (total < buffer.len) {
            const rc = std.os.linux.read(self.handle, buffer[total..].ptr, buffer.len - total);
            if (std.os.linux.errno(rc) != .SUCCESS) return error.InputOutput;
            const n: usize = @intCast(rc);
            if (n == 0) break;
            total += n;
        }
        return total;
    }

    pub fn readToEndAlloc(self: File, allocator: std.mem.Allocator, limit: usize) ![]u8 {
        var reader = self.inner.readerStreaming(io, &.{});
        var bytes = std.ArrayList(u8).empty;
        errdefer bytes.deinit(allocator);
        try reader.interface.appendRemainingUnlimited(allocator, &bytes);
        if (bytes.items.len > limit) {
            bytes.deinit(allocator);
            return error.StreamTooLong;
        }
        return bytes.toOwnedSlice(allocator);
    }

    pub fn getEndPos(self: File) !u64 {
        return self.inner.length(io);
    }

    pub fn getPos(self: File) !u64 {
        const rc = std.os.linux.lseek(self.handle, 0, std.os.linux.SEEK.CUR);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.Unseekable;
        return @intCast(rc);
    }

    pub fn sync(self: File) !void {
        const rc = std.os.linux.fsync(self.handle);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.InputOutput;
    }

    pub fn seekTo(self: File, offset: u64) !void {
        const rc = std.os.linux.lseek(self.handle, @intCast(offset), std.os.linux.SEEK.SET);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.Unseekable;
    }

    pub fn seekFromEnd(self: File, offset: i64) !void {
        const end = try self.getEndPos();
        const target = @as(i128, end) + offset;
        if (target < 0) return error.Unseekable;
        try self.seekTo(@intCast(target));
    }

    pub fn setEndPos(self: File, length: u64) !void {
        try self.inner.setLength(io, length);
    }

    pub fn write(self: File, bytes: []const u8) !usize {
        return self.inner.writeStreaming(io, &.{}, &.{bytes}, 1);
    }
};

pub const Dir = struct {
    pub fn openFile(_: Dir, file_path: []const u8, flags: anytype) !File {
        const file = try std.Io.Dir.cwd().openFile(io, file_path, .{
            .mode = if (@hasField(@TypeOf(flags), "mode")) switch (flags.mode) {
                .read_write => .read_write,
                else => .read_only,
            } else .read_only,
        });
        return .{ .inner = file, .handle = file.handle };
    }

    pub fn createFile(_: Dir, file_path: []const u8, flags: anytype) !File {
        const truncate = if (@hasField(@TypeOf(flags), "truncate")) flags.truncate else true;
        const read = if (@hasField(@TypeOf(flags), "read")) flags.read else false;
        const file = try std.Io.Dir.cwd().createFile(io, file_path, .{ .truncate = truncate, .read = read });
        return .{ .inner = file, .handle = file.handle };
    }

    pub fn makePath(_: Dir, dir_path: []const u8) !void {
        try std.Io.Dir.cwd().createDirPath(io, dir_path);
    }

    pub fn deleteFile(_: Dir, file_path: []const u8) !void {
        try std.Io.Dir.cwd().deleteFile(io, file_path);
    }

    pub fn rename(_: Dir, old_path: []const u8, new_path: []const u8) !void {
        try std.Io.Dir.rename(.cwd(), old_path, .cwd(), new_path, io);
    }

    pub fn openFileAbsolute(_: Dir, file_path: []const u8, flags: anytype) !File {
        return openFile(.{}, file_path, flags);
    }
};

pub fn cwd() Dir {
    return .{};
}

pub fn fsync(handle: std.Io.File.Handle) !void {
    const rc = std.os.linux.fsync(handle);
    if (std.os.linux.errno(rc) != .SUCCESS) return error.InputOutput;
}

pub fn dup(handle: std.Io.File.Handle) !std.Io.File.Handle {
    const rc = std.os.linux.dup(handle);
    if (std.os.linux.errno(rc) != .SUCCESS) return error.Unexpected;
    return @intCast(rc);
}
