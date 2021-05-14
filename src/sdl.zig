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
const c = @cImport({
    @cInclude("SDL.h");
});

// ----- General -----
pub const GetError = c.SDL_GetError;
pub const Log = c.SDL_Log;
pub const Rect = c.SDL_Rect;
pub const Delay = c.SDL_Delay;
// Constants
pub const TRUE = c.SDL_TRUE;

pub const Mask = struct {
    r: u32,
    g: u32,
    b: u32,
    a: u32,
};

pub const g_mask = Mask{
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
//

// ----- Init -----
pub const Init = c.SDL_Init;
// Constants
pub const INIT_VIDEO = c.SDL_INIT_VIDEO;

// ----- Quit -----
pub const Quit = c.SDL_Quit;

// ----- Event -----
pub const Event = c.SDL_Event;
pub const PollEvent = c.SDL_PollEvent;
// Constants
pub const WINDOWEVENT = c.SDL_WINDOWEVENT;
pub const WINDOWEVENT_RESIZED = c.SDL_WINDOWEVENT_RESIZED;
pub const QUIT = c.SDL_QUIT;
pub const KEYDOWN = c.SDL_KEYDOWN;
pub const K_ESCAPE = c.SDLK_ESCAPE;
pub const K_q = c.SDLK_q;
pub const K_r = c.SDLK_r;

// ----- Renderer -----
pub const Renderer = c.SDL_Renderer;
pub const CreateRenderer = c.SDL_CreateRenderer;
pub const RenderClear = c.SDL_RenderClear;
pub const RenderCopy = c.SDL_RenderCopy;
pub const RenderFillRect = c.SDL_RenderFillRect;
pub const RenderPresent = c.SDL_RenderPresent;
pub const SetRenderDrawColor = c.SDL_SetRenderDrawColor;
pub const DestroyRenderer = c.SDL_DestroyRenderer;
// Constants
pub const RENDERER_PRESENTVSYNC = c.SDL_RENDERER_PRESENTVSYNC;
pub const RENDERER_ACCELERATED = c.SDL_RENDERER_ACCELERATED;

// ----- Window -----
pub const Window = c.SDL_Window;
pub const CreateWindow = c.SDL_CreateWindow;
pub const DestroyWindow = c.SDL_DestroyWindow;
// Constants
pub const WINDOWPOS_CENTERED = c.SDL_WINDOWPOS_CENTERED;
pub const WINDOW_RESIZABLE = c.SDL_WINDOW_RESIZABLE;

// ----- Texture -----
pub const Texture = ?*c.SDL_Texture;
pub const CreateTextureFromSurface = c.SDL_CreateTextureFromSurface;
pub const DestroyTexture = c.SDL_DestroyTexture;

// ----- Surface -----
pub const CreateRGBSurface = c.SDL_CreateRGBSurface;
pub const SetColorKey = c.SDL_SetColorKey;
pub const FreeSurface = c.SDL_FreeSurface;
