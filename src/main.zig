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
const spr = @import("sprites.zig");
const ui_spr = @import("ui_sprites.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

var game_width: i32 = 800;
var game_height: i32 = 640;

const map_y: u16 = 16;
const map_x: u16 = 16;

fn init_map() [map_y][map_x]u16 {
    comptime {
        var map: [map_y][map_x]u16 = undefined;
        var i: u16 = 42;
        {
            var y = 0;
            while (y < map_y) : (y += 1) {
                var x = 0;
                while (x < map_x) : (x += 1) {
                    map[y][x] = i;
                    //i += 1;
                }
            }
        }
        return map;
    }
}

const basic_map: [map_y][map_x]u16 = init_map();

pub fn main() anyerror!void {
    defer _ = gpa.deinit();

    // using SDL2 for rendering
    if (sdl.Init(sdl.INIT_VIDEO) != 0) {
        sdl.Log("Unable to initialize SDL: %s", sdl.GetError());
        return error.SDLInitializationFailed;
    }
    defer sdl.Quit();

    const window: *sdl.Window = sdl.CreateWindow("ArchivalTibiaV71Client", sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED, game_width, game_height, sdl.WINDOW_RESIZABLE) orelse {
        sdl.Log("Unable to create window: %s", sdl.GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.DestroyWindow(window);

    const renderer: *sdl.Renderer = sdl.CreateRenderer(window, -1, sdl.RENDERER_PRESENTVSYNC | sdl.RENDERER_ACCELERATED) orelse {
        sdl.Log("Unable to create renderer: %s", sdl.GetError());
        return error.SDLInitializationFailed;
    };
    defer sdl.DestroyRenderer(renderer);

    var ui_sprites = try ui_spr.createSdlTexturesFromUISprites(&gpa.allocator, renderer, "Game.pic");
    defer ui_spr.freeUISpriteTextures(&gpa.allocator, ui_sprites) catch |err| {
        std.log.err("failed to free UI textures ({any})", .{err});
    };

    var sprites = try spr.createSdlTexturesFromSprites(&gpa.allocator, renderer, "Game.spr");
    defer spr.freeSpriteTextures(&gpa.allocator, sprites) catch |err| {
        std.log.err("failed to free textures ({any})", .{err});
    };

    var frame: usize = 0;
    var rotating = false;

    drawLoop: while (true) {
        var event: sdl.Event = undefined;
        while (sdl.PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.WINDOWEVENT => {
                    if (event.window.event == sdl.WINDOWEVENT_RESIZED) {
                        game_width = event.window.data1;
                        game_height = event.window.data2;
                    }
                },
                sdl.QUIT => break :drawLoop,
                sdl.KEYDOWN => {
                    switch (event.key.keysym.sym) {
                        sdl.K_ESCAPE, sdl.K_q => break :drawLoop,
                        sdl.K_r => rotating = !rotating,
                        else => {},
                    }
                },
                else => {},
            }
        }

        _ = sdl.RenderClear(renderer);
        _ = sdl.SetRenderDrawColor(renderer, 0x22, 0x22, 0x22, 0x22);
        var full_rect = sdl.Rect{ .x = 0, .y = 0, .w = game_width, .h = game_height };
        _ = sdl.RenderFillRect(renderer, &full_rect);
        _ = sdl.RenderCopy(renderer, ui_sprites[0], 0, &full_rect);
        //        for (basic_map) |sprite_row, y| {
        //            for (sprite_row) |sprite, x| {
        //                _ = sdl.RenderCopy(renderer, sprites[sprite + (frame % 100)], 0, &sdl.Rect{ .x = @truncate(u16, x) * spr.sprite_size, .y = @truncate(u16, y) * spr.sprite_size, .w = spr.sprite_size, .h = spr.sprite_size });
        //            }
        //        }
        sdl.RenderPresent(renderer);
        if (rotating) {
            frame += 1;
        }
        sdl.Delay(17);
    }
}
