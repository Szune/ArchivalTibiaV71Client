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
const br = @import("buffered_reader.zig");
const c = @cImport({
    @cInclude("SDL.h");
});

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const game_width = 800;
const game_height = 640;
const sprite_size = 32;

const Mask = struct {
    r: u32,
    g: u32,
    b: u32,
    a: u32,
};

const g_mask = Mask{
    .r = 0x000000ff,
    .g = 0x0000ff00,
    .b = 0x00ff0000,
    .a = 0xff000000,
};

//    const g_mask: Mask =
//        if (c.SDL_BYTEORDER == c.SDL_BIG_ENDIAN)
//    {
//        Mask{
//            .r = 0xff000000,
//            .g = 0x00ff0000,
//            .b = 0x0000ff00,
//            .a = 0x000000ff,
//        };
//    } else {
//        Mask{
//            .r = 0x000000ff,
//            .g = 0x0000ff00,
//            .b = 0x00ff0000,
//            .a = 0xff000000,
//        };
//    };

pub const SpriteData = struct {
    h: u32,
    w: u32,
    transparent: u24,
    data: []u24,
    const Self = @This();

    pub fn free(self: *const Self) !void {
        gpa.allocator.free(self.data);
    }
};

pub const LoadError = std.mem.Allocator.Error || br.BRError || std.fs.File.OpenError;

pub fn freeSpriteData(sprites: []SpriteData) void {
    for (sprites) |val| {
        if (val.h == 0 and val.w == 0) {
            continue;
        }
        val.free() catch {
            std.log.debug("failed to free sprite data", .{});
        };
    }
    gpa.allocator.free(sprites);
}

pub fn loadSpriteData() LoadError![]SpriteData {
    // file is stored as little endian
    var file = try std.fs.cwd().openFile("Game.spr", .{ .read = true });
    defer file.close();

    var reader = br.BufferedReader{
        .available = 0,
        .buffer_pos = 0,
        .stream_offset = 0,
        .stream = &file,
        .buffer = undefined,
        .eof = false,
        .err = null,
    };

    var version: u32 = try reader.readU32LE();
    var sprite_count: u16 = try reader.readU16LE();

    std.log.debug("Game.spr version: {d}", .{version});
    std.log.debug("Game.spr sprite count: {d}", .{sprite_count});

    var sprite_positions: []u32 = try gpa.allocator.alloc(u32, sprite_count);
    // these are only used to find the sprites in the file
    // no need to keep them around after loading
    defer gpa.allocator.free(sprite_positions);

    {
        var i: u16 = 0;
        while (i < sprite_count) : (i += 1) {
            sprite_positions[i] = try reader.readU32LE();
        }
    }

    var sprites: []SpriteData = try gpa.allocator.alloc(SpriteData, sprite_count);
    // remember to free if we fail somewhere in this fn
    // try to rewrite this fn to have fewer errors
    // to make the freeing code less spaghettioish
    errdefer gpa.allocator.free(sprites);

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
            var data: []u24 = try gpa.allocator.alloc(u24, sprite_size * sprite_size);
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
const SDL_Texture = ?*c.SDL_Texture;

pub fn createSpriteTextures(renderer: *c.SDL_Renderer, sprites: []SpriteData) ![]SDL_Texture {
    var textures: []SDL_Texture = try gpa.allocator.alloc(SDL_Texture, sprites.len);
    for (sprites) |val, idx| {
        if (val.h == 0 and val.w == 0) {
            textures[idx] = null;
            continue;
        }

        var surface = c.SDL_CreateRGBSurface(0, sprite_size, sprite_size, 32, g_mask.r, g_mask.g, g_mask.b, g_mask.a) orelse {
            c.SDL_Log("Unable to create surface: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        // set transparent color
        var trsp: u32 = @as(u32, val.transparent) | (255 << 24);
        if (c.SDL_SetColorKey(surface, c.SDL_TRUE, trsp) != 0) {
            c.SDL_Log("Unable to set color key: %s", c.SDL_GetError());
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

        var texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse {
            c.SDL_Log("Unable to create texture: %s", c.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        c.SDL_FreeSurface(surface);

        textures[idx] = texture;
    }
    return textures;
}

pub fn freeSpriteTextures(sprites: []SDL_Texture) !void {
    for (sprites) |val| {
        if (val != null) {
            c.SDL_DestroyTexture(val);
        }
    }
    gpa.allocator.free(sprites);
}

pub fn main() anyerror!void {
    defer _ = gpa.deinit();

    // using SDL2 for rendering
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow("ArchivalTibiaV71Client", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, game_width, game_height, 0) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    const renderer = c.SDL_CreateRenderer(window, 0, c.SDL_RENDERER_PRESENTVSYNC) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    var spriteData = loadSpriteData() catch |err| {
        std.log.err("failed to read Game.spr ({any})", .{err});
        return error.LoadingSpritesFailed;
    };

    var sprites = try createSpriteTextures(renderer, spriteData);
    freeSpriteData(spriteData);
    defer freeSpriteTextures(sprites) catch |err| {
        std.log.err("failed to free textures ({any})", .{err});
    };

    var frame: usize = 0;

    drawLoop: while (true) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => break :drawLoop,
                c.SDL_KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        c.SDLK_ESCAPE, c.SDLK_q => break :drawLoop,
                        else => {},
                    }
                },
                else => {},
            }

            _ = c.SDL_RenderClear(renderer);
            _ = c.SDL_SetRenderDrawColor(renderer, 0x22, 0x22, 0x22, 0x22);
            var rect = c.SDL_Rect{ .x = 0, .y = 0, .w = game_width, .h = game_height };
            _ = c.SDL_RenderFillRect(renderer, &rect);
            _ = c.SDL_RenderCopy(renderer, sprites[196], 0, &c.SDL_Rect{ .x = 0, .y = 0, .w = sprite_size, .h = sprite_size });
            _ = c.SDL_RenderCopy(renderer, sprites[197], 0, &c.SDL_Rect{ .x = sprite_size, .y = 0, .w = sprite_size, .h = sprite_size });
            c.SDL_RenderPresent(renderer);
            c.SDL_Delay(10);
        }
    }
}
