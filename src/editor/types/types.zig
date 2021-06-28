const std = @import("std");
const upaya = @import("upaya");

pub const File = struct {
    name: []const u8,
    width: i32,
    height: i32,
    tileWidth: i32,
    tileHeight: i32,
    background: upaya.Texture,
    layers: std.ArrayList(Layer),
    sprites: std.ArrayList(Sprite),

    pub fn deinit (self: *File) void {
        for (self.layers.items) |layer| {
            layer.texture.deinit();
            layer.image.deinit();
        }
        self.layers.deinit();
        self.background.deinit();
        self.sprites.deinit();
    }
};

pub const Layer = struct {
    name: []const u8,
    texture: upaya.Texture,
    image: upaya.Image,
    hidden: bool = false,

    pub fn updateTexture (self: Layer) void {
        self.texture.setColorData(self.image.pixels);
    }
};

pub const Sprite = struct {
    name: []const u8,
    index: usize,
    origin: upaya.math.Vec2,
};

pub const Animation = struct {
    name: []const u8,
    start: usize,
    length: usize,
};