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

pub fn createSdlTexturesFromUISprites(allocator: *std.mem.Allocator, renderer: *sdl.Renderer, file_path_str: []const u8) ![]sdl.Texture {
    return createUISpriteTextures(allocator, renderer, file_path_str);
}

fn createUISpriteTextures(allocator: *std.mem.Allocator, renderer: *sdl.Renderer, file_path_str: []const u8) ![]sdl.Texture {
    var sprites = loadSpriteSheets(allocator, file_path_str) catch |err| {
        std.log.err("failed to read {s} ({any})", .{ file_path_str, err });
        return error.LoadingSpritesFailed;
    };
    defer freeSpriteSheets(allocator, sprites);

    var textures: []sdl.Texture = try allocator.alloc(sdl.Texture, sprites.len);
    for (sprites) |val, idx| {
        if (val.h == 0 and val.w == 0) {
            textures[idx] = null;
            continue;
        }

        var surface = sdl.CreateRGBSurface(0, @truncate(u16, val.w) * sprite_size, @truncate(u16, val.h) * sprite_size, 32, g_mask.r, g_mask.g, g_mask.b, g_mask.a) orelse {
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

pub fn freeUISpriteTextures(allocator: *std.mem.Allocator, sprites: []sdl.Texture) !void {
    for (sprites) |val| {
        if (val != null) {
            sdl.DestroyTexture(val);
        }
    }
    allocator.free(sprites);
}

const SpriteSheet = struct {
    h: u32,
    w: u32,
    transparent: u24,
    data: []u24,
    const Self = @This();

    pub fn free(self: *const Self, allocator: *std.mem.Allocator) !void {
        allocator.free(self.data);
    }
};

fn loadSpriteSheets(allocator: *std.mem.Allocator, file_path_str: []const u8) LoadError![]SpriteSheet {
    // file is stored as little endian
    var file = try std.fs.cwd().openFile(file_path_str, .{ .read = true });
    defer file.close();

    var reader = br.BufferedReader.init(&file);

    var version: u32 = try reader.readU32LE();
    var sprite_sheet_count: u16 = try reader.readU16LE();

    std.log.debug("{s} version: {d}", .{ file_path_str, version });
    std.log.debug("{s} sprite sheet count: {d}", .{ file_path_str, sprite_sheet_count });

    var sprites: []SpriteSheet = try allocator.alloc(SpriteSheet, sprite_sheet_count);
    // remember to free if we fail somewhere in this fn
    // try to rewrite this fn to have fewer errors
    // to make the freeing code less spaghettioish
    errdefer allocator.free(sprites);

    var sprite_sheet_positions: [][]u32 = try allocator.alloc([]u32, sprite_sheet_count);
    {
        var i: u16 = 0;
        while (i < sprite_sheet_count) : (i += 1) {
            var width = try reader.readByte();
            var height = try reader.readByte();
            var transparentR = try reader.readByte();
            var transparentG = try reader.readByte();
            var transparentB = try reader.readByte();
            const transparent = transparentR | (@as(u24, transparentG) << 8) | (@as(u24, transparentB) << 16);
            sprite_sheet_positions[i] = try allocator.alloc(u32, @as(u16, width) * @as(u16, height));

            for (sprite_sheet_positions[i]) |_, idx| {
                sprite_sheet_positions[i][idx] = try reader.readU32LE();
            }

            var data: []u24 = try allocator.alloc(u24, (@as(u32, width) * @as(u32, sprite_size)) * (@as(u32, height) * @as(u32, sprite_size)));
            sprites[i] = SpriteSheet{
                .h = height,
                .w = width,
                .transparent = transparent,
                .data = data,
            };
        }
    }
    defer {
        for (sprite_sheet_positions) |arr| {
            allocator.free(arr);
        }
        allocator.free(sprite_sheet_positions);
    }

    const array_slots_per_pixel = 1;

    {
        // loop through all the sprite sheets
        var spr_idx: u16 = 0;
        while (spr_idx < sprite_sheet_count) : (spr_idx += 1) {
            const full_width = sprites[spr_idx].w * sprite_size;
            {
                // loop through all the parts of the current sprite sheet
                var sub_spr_idx: u16 = 0;
                while (sub_spr_idx < sprite_sheet_positions[spr_idx].len) : (sub_spr_idx += 1) {
                    // go to the byte position in the file where the sprite sheet starts
                    try reader.seek(sprite_sheet_positions[spr_idx][sub_spr_idx]);
                    // calculate offsets
                    const box_x = (sub_spr_idx % sprites[spr_idx].w) * sprite_size; // only valid for symmetric sprites
                    const box_y = (sub_spr_idx / sprites[spr_idx].w) * sprite_size; // only valid for symmetric sprites
                    const box_x_offset = box_x * array_slots_per_pixel;
                    const box_y_offset = box_y * full_width * array_slots_per_pixel;
                    const sprite_end = reader.getOffset() + try reader.readU16LE();
                    var pixel_idx: u32 = 0;
                    while (reader.getOffset() < sprite_end) {
                        var transp_pixels = try reader.readU16LE();
                        var color_pixels = try reader.readU16LE();

                        {
                            var tp: u16 = 0;
                            while (tp < transp_pixels) : (tp += 1) {
                                const x = pixel_idx % sprite_size;
                                const y = pixel_idx / sprite_size;
                                const x_offset = x * array_slots_per_pixel;
                                const y_offset = y * full_width * array_slots_per_pixel;
                                const data_idx = box_x_offset + box_y_offset + x_offset + y_offset;
                                sprites[spr_idx].data[data_idx] = sprites[spr_idx].transparent;
                                pixel_idx += 1;
                            }
                        }

                        {
                            var cp: u16 = 0;
                            while (cp < color_pixels) : (cp += 1) {
                                const x = pixel_idx % sprite_size;
                                const y = pixel_idx / sprite_size;
                                const x_offset = x * array_slots_per_pixel;
                                const y_offset = y * full_width * array_slots_per_pixel;
                                const data_idx = box_x_offset + box_y_offset + x_offset + y_offset;

                                const red = try reader.readByte();
                                const green = try reader.readByte();
                                const blue = try reader.readByte();
                                const pixel = red | (@as(u24, green) << 8) | (@as(u24, blue) << 16);
                                sprites[spr_idx].data[data_idx] = pixel;
                                pixel_idx += 1;
                            }
                        }

                        // fix-up loop (might not be necessary):
                        //if (pixel_idx < (sprite_size * sprite_size) - 1) {
                        //while (pixel_idx < (sprite_size * sprite_size)) : (pixel_idx += 1) {
                        //sprites[spr_idx].data[pixel_idx] = sprites[spr_idx].transparent;
                        //}
                        //}
                    }
                }
            }
        }
    }

    return sprites;
}

pub const LoadError = std.mem.Allocator.Error || br.BRError || std.fs.File.OpenError;

fn freeSpriteSheets(allocator: *std.mem.Allocator, sprites: []SpriteSheet) void {
    for (sprites) |val| {
        if (val.h == 0 and val.w == 0) {
            continue;
        }
        val.free(allocator) catch {
            std.log.debug("failed to free UI sprite data", .{});
        };
    }
    allocator.free(sprites);
}
