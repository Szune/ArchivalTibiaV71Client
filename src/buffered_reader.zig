//
// ArchivalTibiaV71Client is a custom game client for the ArchivalTibiaV71 project.
// Copyright (C) 2021  Carl Erik Patrik Iwarson
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
const std = @import("std");
pub const BRError = std.mem.Allocator.Error || std.os.PReadError;

pub const BufferedReader = struct {
    available: usize,
    buffer_pos: usize,
    stream_offset: usize,
    stream: *const std.fs.File,
    buffer: [4096]u8,
    eof: bool,
    err: ?BRError,

    const Self = @This();

    fn readMore(self: *Self) BRError!void {
        self.stream_offset += self.buffer_pos;
        self.available = try self.stream.pread(&self.buffer, self.stream_offset);
        if (self.available == 0) {
            self.eof = true;
        }
        self.buffer_pos = 0;
    }

    fn ensureAvailable(self: *Self, size: comptime usize) BRError!void {
        if (self.available <= 0) {
            try self.readMore();
        } else {
            const overflow = (self.buffer_pos + size) % self.available;
            if (overflow == 0) {
                try self.readMore();
            }
        }
    }

    fn overflowedRead(self: *Self, comptime size: usize) BRError![size]u8 {
        const overflow = (self.buffer_pos + size) % self.available;
        var tmp: [size]u8 = undefined;
        {
            var i: usize = 0;
            while (i < size - overflow) : (i += 1) {
                tmp[i] = self.buffer[self.buffer_pos + i];
            }
        }

        self.buffer_pos += size - overflow;

        try self.readMore();
        defer self.buffer_pos = overflow;

        {
            var i: usize = 0;
            while (i < overflow) : (i += 1) {
                tmp[(size - overflow) + i] = self.buffer[i];
            }
        }
        return tmp;
    }

    fn toU16LE(bytes: []const u8) callconv(.Inline) u16 {
        return bytes[0] | (@as(u16, bytes[1]) << 8);
    }

    fn toU32LE(bytes: []const u8) callconv(.Inline) u32 {
        return bytes[0] | (@as(u32, bytes[1]) << 8) | (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24);
    }

    pub fn readByte(self: *Self) BRError!u8 {
        const size = 1;
        try self.ensureAvailable(size);
        if (self.buffer_pos + size < self.available) {
            defer self.buffer_pos += size;
            return self.buffer[self.buffer_pos];
        } else {
            const overflow = (self.buffer_pos + size) % self.available;
            try self.readMore();
            defer self.buffer_pos = overflow;
            return self.buffer[self.buffer_pos];
        }
    }

    /// Reads a little endian u16
    pub fn readU16LE(self: *Self) BRError!u16 {
        const size = 2;
        try self.ensureAvailable(size);
        if (self.buffer_pos + size < self.available) {
            defer self.buffer_pos += size;
            return toU16LE(self.buffer[self.buffer_pos .. self.buffer_pos + size]);
        } else {
            var tmp = try self.overflowedRead(size);
            return tmp[0] | (@as(u16, tmp[1]) << 8);
        }
    }

    /// Reads a little endian u32
    pub fn readU32LE(self: *Self) BRError!u32 {
        const size = 4;
        try self.ensureAvailable(size);
        if (self.buffer_pos + size < self.available) {
            defer self.buffer_pos += size;
            return toU32LE(self.buffer[self.buffer_pos .. self.buffer_pos + size]);
        } else {
            var tmp = try self.overflowedRead(size);
            return tmp[0] | (@as(u32, tmp[1]) << 8) | (@as(u32, tmp[2]) << 16) | (@as(u32, tmp[3]) << 24);
        }
    }

    pub fn seek(self: *Self, pos: usize) BRError!void {
        self.stream_offset = pos;
        self.available = try self.stream.pread(&self.buffer, self.stream_offset);
        if (self.available == 0) {
            self.eof = true;
        }
        self.buffer_pos = 0;
    }

    pub fn getOffset(self: *Self) usize {
        return self.stream_offset + self.buffer_pos;
    }
};
