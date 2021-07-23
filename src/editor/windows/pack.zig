const std = @import("std");
const upaya = @import("upaya");
const stb = @import("stb");
const imgui = @import("imgui");

const Camera = @import("../utils/camera.zig").Camera;

const editor = @import("../editor.zig");
const input = editor.input;
const canvas = editor.canvas;
const menubar = editor.menubar;
const sprites = editor.sprites;

const types = @import("../types/types.zig");
const File = types.File;
const Layer = types.Layer;
const Sprite = types.Sprite;

var camera: Camera = .{ .zoom = 0.5 };
var screen_position: imgui.ImVec2 = undefined;
var texture_position: imgui.ImVec2 = undefined;

var packed_texture: ?upaya.Texture = null;
var background: ?upaya.Texture = null;
var atlas: ?upaya.TexturePacker.Atlas = null;

var files: std.ArrayList(types.File) = undefined;
var images: std.ArrayList(upaya.Image) = undefined;
var frames: std.ArrayList(upaya.stb.stbrp_rect) = undefined;
var names: std.ArrayList([]const u8) = undefined;
var origins: std.ArrayList(upaya.math.Point) = undefined;

pub fn addFile(file: File) void {
    if (canvas.getActiveFile()) |f| {
        if (std.mem.eql(u8, f.path.?, file.path.?))
            return;
    }

    for (files.items) |f| {
        if (std.mem.eql(u8, f.path.?, file.path.?))
            return;
    }

    files.append(file) catch unreachable;
    pack();
}

pub fn removeFile(index: usize) void {
    if (files.items.len > 0 and index < files.items.len) {
        _ = files.swapRemove(index);
        //TODO: free memory
        pack();
    }
}

pub fn clear () void {
    if (files.items.len > 0) {
        files.clearAndFree();
    }
}

pub fn init() void {
    files = std.ArrayList(types.File).init(upaya.mem.allocator);
    images = std.ArrayList(upaya.Image).init(upaya.mem.allocator);
    frames = std.ArrayList(upaya.stb.stbrp_rect).init(upaya.mem.allocator);
    names = std.ArrayList([]const u8).init(upaya.mem.allocator);
    origins = std.ArrayList(upaya.math.Point).init(upaya.mem.allocator);
}

pub fn draw() void {
    if (atlas) |_| {
        const width = 1024;
        const height = 768;
        const center = imgui.ogGetWindowCenter();
        imgui.ogSetNextWindowSize(.{ .x = width, .y = height }, imgui.ImGuiCond_Always);
        imgui.ogSetNextWindowPos(.{ .x = center.x - width / 2, .y = center.y - height / 2 }, imgui.ImGuiCond_Always, .{});
        if (imgui.igBeginPopupModal("Pack", &menubar.pack_popup, imgui.ImGuiWindowFlags_NoResize)) {
            defer imgui.igEndPopup();

            if (imgui.ogBeginChildEx("Info", 1, .{ .y = 60 }, true, imgui.ImGuiWindowFlags_MenuBar)) {
                defer imgui.igEndChild();

                if (imgui.igBeginMenuBar()) {
                    defer imgui.igEndMenuBar();
                    imgui.igText("Info");
                }

                if (packed_texture) |texture| {
                    imgui.igValueInt("Width", @intCast(c_int, texture.width));
                    imgui.igSameLine(0, 10);
                    imgui.igValueInt("Height", @intCast(c_int, texture.height));
                }
            }

            if (imgui.ogBeginChildEx("Files", 2, .{ .x = 200 }, true, imgui.ImGuiWindowFlags_MenuBar)) {
                defer imgui.igEndChild();

                if (imgui.igBeginMenuBar()) {
                    defer imgui.igEndMenuBar();
                    imgui.igText("Files");
                }

                if (canvas.getActiveFile()) |file| {
                    const file_name_z = std.cstr.addNullByte(upaya.mem.allocator, file.name) catch unreachable;
                    defer upaya.mem.allocator.free(file_name_z);
                    imgui.igText(@ptrCast([*c]const u8, file_name_z));
                }

                for (files.items) |file, i| {
                    const file_name_z = std.cstr.addNullByte(upaya.mem.allocator, file.name) catch unreachable;
                    defer upaya.mem.allocator.free(file_name_z);
                    imgui.igText(@ptrCast([*c]const u8, file_name_z));

                    imgui.igSameLine(0, 5);
                    if (imgui.ogColoredButton(0x00000000, imgui.icons.minus_circle)) {
                        removeFile(i);
                    }
                }
            }

            imgui.igSameLine(0, 5);

            if (imgui.ogBeginChildEx("Preview", 0, .{}, true, imgui.ImGuiWindowFlags_MenuBar)) {
                defer imgui.igEndChild();

                if (imgui.igBeginMenuBar()) {
                    defer imgui.igEndMenuBar();
                    imgui.igText("Preview");
                }

                screen_position = imgui.ogGetCursorScreenPos();

                if (packed_texture) |texture| {
                    texture_position = .{
                        .x = -@intToFloat(f32, texture.width) / 2,
                        .y = -@intToFloat(f32, texture.height) / 2,
                    };

                    const tl = camera.matrix().transformImVec2(texture_position).add(screen_position);
                    var br = texture_position;
                    br.x += @intToFloat(f32, texture.width);
                    br.y += @intToFloat(f32, texture.height);
                    br = camera.matrix().transformImVec2(br).add(screen_position);

                    imgui.ogImDrawList_AddImage(imgui.igGetWindowDrawList(), background.?.imTextureID(), tl, br, .{}, .{ .x = 1, .y = 1 }, 0xFFFFFFFF);

                    imgui.ogImDrawList_AddImage(imgui.igGetWindowDrawList(), texture.imTextureID(), tl, br, .{}, .{ .x = 1, .y = 1 }, 0xFFFFFFFF);
                }

                if (imgui.igIsWindowHovered(imgui.ImGuiHoveredFlags_None)) {
                    const io = imgui.igGetIO();

                    //pan
                    if (imgui.igIsMouseDragging(imgui.ImGuiMouseButton_Middle, 0)) {
                        input.pan(&camera, imgui.ImGuiMouseButton_Middle);
                    }

                    if (imgui.igIsMouseDragging(imgui.ImGuiMouseButton_Left, 0) and imgui.ogKeyDown(@intCast(usize, imgui.igGetKeyIndex(imgui.ImGuiKey_Space)))) {
                        input.pan(&camera, imgui.ImGuiMouseButton_Left);
                    }

                    // zoom
                    if (io.MouseWheel != 0) {
                        input.zoom(&camera);
                        camera.position.x = @trunc(camera.position.x);
                        camera.position.y = @trunc(camera.position.y);
                    }

                    // round positions if we are finished changing cameras position
                    if (imgui.igIsMouseReleased(imgui.ImGuiMouseButton_Middle) or imgui.ogKeyUp(@intCast(usize, imgui.igGetKeyIndex(imgui.ImGuiKey_Space)))) {
                        camera.position.x = @trunc(camera.position.x);
                        camera.position.y = @trunc(camera.position.y);
                    }
                }
            }
        }
    }
}

pub fn pack() void {
    if (canvas.getActiveFile()) |file| {
        packFile(file);
    }

    for (files.items) |*file| {
        packFile(file);
    }

    if (upaya.TexturePacker.runRectPacker(frames.items)) |size| {
        atlas = upaya.TexturePacker.Atlas.initImages(frames.toOwnedSlice(), origins.toOwnedSlice(), names.toOwnedSlice(), images.toOwnedSlice(), size);

        if (atlas) |a| {
            background = upaya.Texture.initChecker(a.width, a.height, editor.checkerColor1, editor.checkerColor2);
            packed_texture = a.image.asTexture(.nearest);

        }
        
    }
}

fn packFile(file: *types.File) void {
    for (file.layers.items) |layer| {
        for (file.sprites.items) |sprite| {
            const tiles_wide = @divExact(file.width, file.tileWidth);

            const column = @mod(@intCast(i32, sprite.index), tiles_wide);
            const row = @divTrunc(@intCast(i32, sprite.index), tiles_wide);

            const src_x = @intCast(usize, column * file.tileWidth);
            const src_y = @intCast(usize, row * file.tileHeight);

            var sprite_image = upaya.Image.init(@intCast(usize, file.tileWidth), @intCast(usize, file.tileHeight));
            var sprite_origin: upaya.math.Point = .{ .x = @floatToInt(i32, sprite.origin_x), .y = @floatToInt(i32, sprite.origin_y) };
            var sprite_name = std.fmt.allocPrint(upaya.mem.allocator, "{s}_{s}", .{ layer.name, sprite.name }) catch unreachable;

            
            var y: usize = src_y;
            var dst = sprite_image.pixels[(y - src_y) * sprite_image.w ..];

            while (y < src_y + @intCast(usize, file.tileHeight)) : (y += 1) {
                const texture_width = @intCast(usize, layer.texture.width);
                var src_row = layer.image.pixels[src_x + (y * texture_width) .. (src_x + (y * texture_width)) + sprite_image.w];

                std.mem.copy(u32, dst, src_row);
                dst = sprite_image.pixels[(y - src_y) * sprite_image.w ..];
            }

            var containsColor: bool = false;
            for (sprite_image.pixels) |p| {
                if (p & 0xFF000000 != 0) {
                    containsColor = true;
                    break;
                }
            }

            

            if (containsColor) {
                const offset = sprite_image.crop();
                const sprite_rect: stb.stbrp_rect = .{ .id = @intCast(c_int, sprite.index), .w = @intCast(c_ushort, sprite_image.w), .h = @intCast(c_ushort, sprite_image.h) };

                sprite_origin = .{ .x = sprite_origin.x - offset.x, .y = sprite_origin.y - offset.y };

                images.append(sprite_image) catch unreachable;
                names.append(sprite_name) catch unreachable;
                frames.append(sprite_rect) catch unreachable;
                origins.append(sprite_origin) catch unreachable;
            } else {
                sprite_image.deinit();
            }
        }
    }
}
