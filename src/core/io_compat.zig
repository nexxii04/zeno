//! Bounded in-memory reader used by the storage codecs.
pub const FixedBufferStream = struct {
    bytes: []const u8,
    pos: usize = 0,

    pub fn reader(self: *FixedBufferStream) *FixedBufferStream {
        return self;
    }

    pub fn readByte(self: *FixedBufferStream) !u8 {
        if (self.pos >= self.bytes.len) return error.EndOfStream;
        const byte = self.bytes[self.pos];
        self.pos += 1;
        return byte;
    }

    pub fn readNoEof(self: *FixedBufferStream, out: []u8) !void {
        if (self.bytes.len -| self.pos < out.len) return error.EndOfStream;
        @memcpy(out, self.bytes[self.pos .. self.pos + out.len]);
        self.pos += out.len;
    }
};

pub fn fixedBufferStream(bytes: []const u8) FixedBufferStream {
    return .{ .bytes = bytes };
}
