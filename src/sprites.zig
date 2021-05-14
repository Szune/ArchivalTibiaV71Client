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
const sdl = @import("sdl.zig");
const br = @import("buffered_reader.zig");

pub const sprite_size: u16 = 32;
var g_mask = sdl.g_mask;

pub fn createSdlTexturesFromSprites(allocator: *std.mem.Allocator, renderer: *sdl.Renderer, file_path_str: []const u8) ![]sdl.Texture {
    return createSpriteTextures(allocator, renderer, file_path_str);
}

fn createSpriteTextures(allocator: *std.mem.Allocator, renderer: *sdl.Renderer, file_path_str: []const u8) ![]sdl.Texture {
    var sprites = loadSpriteData(allocator, file_path_str) catch |err| {
        std.log.err("failed to read {s} ({any})", .{ file_path_str, err });
        return error.LoadingSpritesFailed;
    };
    defer freeSpriteData(allocator, sprites);

    var textures: []sdl.Texture = try allocator.alloc(sdl.Texture, sprites.len);
    for (sprites) |val, idx| {
        if (val.h == 0 and val.w == 0) {
            textures[idx] = null;
            continue;
        }

        var surface = sdl.CreateRGBSurface(0, sprite_size, sprite_size, 32, g_mask.r, g_mask.g, g_mask.b, g_mask.a) orelse {
            sdl.Log("Unable to create surface: %s", sdl.GetError());
            return error.SDLInitializationFailed;
        };
        defer sdl.FreeSurface(surface);

        // set transparent color
        var trsp: u32 = @as(u32, val.transparent) | (255 << 24);
        if (sdl.SetColorKey(surface, sdl.TRUE, trsp) != 0) {
            sdl.Log("Unable to set color key: %s", sdl.GetError());
            return error.SDLInitializationFailed;
        }

        var pixels = @ptrCast([*c]u8, surface.*.pixels);

        var len = surface.*.h * surface.*.pitch;
        {
            var i: usize = 0;
            var spr_idx: usize = 0;
            while (i < len) : (i += 4) {
                pixels[i] = @truncate(u8, val.data[spr_idx]); // R
                pixels[i + 1] = @truncate(u8, val.data[spr_idx] >> 8); // G
                pixels[i + 2] = @truncate(u8, val.data[spr_idx] >> 16); // B
                pixels[i + 3] = 0xFF; // A
                spr_idx += 1;
            }
        }

        var texture = sdl.CreateTextureFromSurface(renderer, surface) orelse {
            sdl.Log("Unable to create texture: %s", sdl.GetError());
            return error.SDLInitializationFailed;
        };

        textures[idx] = texture;
    }
    return textures;
}

pub fn freeSpriteTextures(allocator: *std.mem.Allocator, sprites: []sdl.Texture) !void {
    for (sprites) |val| {
        if (val != null) {
            sdl.DestroyTexture(val);
        }
    }
    allocator.free(sprites);
}

const SpriteData = struct {
    h: u32,
    w: u32,
    transparent: u24,
    data: []u24,
    const Self = @This();

    pub fn free(self: *const Self, allocator: *std.mem.Allocator) !void {
        allocator.free(self.data);
    }
};

fn loadSpriteData(allocator: *std.mem.Allocator, file_path_str: []const u8) LoadError![]SpriteData {
    // file is stored as little endian
    var file = try std.fs.cwd().openFile(file_path_str, .{ .read = true });
    defer file.close();

    var reader = br.BufferedReader.init(&file);
    var version: u32 = try reader.readU32LE();
    var sprite_count: u16 = try reader.readU16LE();

    std.log.debug("{s} version: {d}", .{ file_path_str, version });
    std.log.debug("{s} sprite count: {d}", .{ file_path_str, sprite_count });

    var sprite_positions: []u32 = try allocator.alloc(u32, sprite_count);
    // these are only used to find the sprites in the file
    // no need to keep them around after loading
    defer allocator.free(sprite_positions);

    {
        var i: u16 = 0;
        while (i < sprite_count) : (i += 1) {
            sprite_positions[i] = try reader.readU32LE();
        }
    }

    var sprites: []SpriteData = try allocator.alloc(SpriteData, sprite_count);
    // remember to free if we fail somewhere in this fn
    // try to rewrite this fn to have fewer errors
    // to make the freeing code less spaghettioish
    errdefer allocator.free(sprites);

    {
        var i: u16 = 0;
        while (i < sprite_count) : (i += 1) {
            var pos = sprite_positions[i];
            if (pos < 1) {
                sprites[i] = SpriteData{ .h = 0, .w = 0, .transparent = 0, .data = undefined };
                continue;
            }

            const transpR = try reader.readByte();
            const transpG = try reader.readByte();
            const transpB = try reader.readByte();
            const transp = transpR | (@as(u24, transpG) << 8) | (@as(u24, transpB) << 16);
            const sprite_end = reader.getOffset() + try reader.readU16LE();
            var data: []u24 = try allocator.alloc(u24, sprite_size * sprite_size);
            var pixel_idx: u32 = 0;

            while (reader.getOffset() < sprite_end) {
                var transp_pixels = try reader.readU16LE();
                var color_pixels = try reader.readU16LE();

                {
                    var tp: u16 = 0;
                    while (tp < transp_pixels) : (tp += 1) {
                        data[pixel_idx] = transp;
                        pixel_idx += 1;
                    }
                }

                {
                    var cp: u16 = 0;
                    while (cp < color_pixels) : (cp += 1) {
                        const red = try reader.readByte();
                        const green = try reader.readByte();
                        const blue = try reader.readByte();
                        const pixel = red | (@as(u24, green) << 8) | (@as(u24, blue) << 16);
                        data[pixel_idx] = pixel;
                        pixel_idx += 1;
                    }
                }
            }

            if (pixel_idx < (sprite_size * sprite_size) - 1) {
                while (pixel_idx < (sprite_size * sprite_size)) : (pixel_idx += 1) {
                    data[pixel_idx] = transp;
                }
            }

            // add sprite
            sprites[i] = SpriteData{
                .h = sprite_size,
                .w = sprite_size,
                .transparent = transp,
                .data = data,
            };
        }
    }

    return sprites;
}

pub const LoadError = std.mem.Allocator.Error || br.BRError || std.fs.File.OpenError;

fn freeSpriteData(allocator: *std.mem.Allocator, sprites: []SpriteData) void {
    for (sprites) |val| {
        if (val.h == 0 and val.w == 0) {
            continue;
        }
        val.free(allocator) catch {
            std.log.debug("failed to free sprite data", .{});
        };
    }
    allocator.free(sprites);
}
