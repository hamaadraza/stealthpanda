// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! Zig binding to the Rust software canvas-2D rasterizer
//! (src/html5ever/stealthpanda_canvas.rs, linked into the same staticlib as
//! html5ever). The 2D context records draw operations into a compact
//! little-endian byte stream using the `Op` opcodes below; `renderPng` hands
//! that stream to Rust (tiny-skia) and returns real PNG bytes.

const std = @import("std");

extern "c" fn lp_canvas_render_png(
    ops_ptr: ?[*]const u8,
    ops_len: usize,
    w: u32,
    h: u32,
    out_len: *usize,
) ?[*]u8;
extern "c" fn lp_canvas_free(ptr: ?[*]u8, len: usize) void;
extern "c" fn lp_canvas_measure_text(ptr: ?[*]const u8, len: usize, px: f32) f32;

/// textBaseline codes (must match stealthpanda_canvas.rs).
pub const Baseline = enum(u8) {
    alphabetic = 0,
    top = 1,
    middle = 2,
    bottom = 3,
    hanging = 4,
    ideographic = 5,

    pub fn fromString(s: []const u8) Baseline {
        const map = std.StaticStringMap(Baseline).initComptime(.{
            .{ "alphabetic", .alphabetic },
            .{ "top", .top },
            .{ "middle", .middle },
            .{ "bottom", .bottom },
            .{ "hanging", .hanging },
            .{ "ideographic", .ideographic },
        });
        return map.get(s) orelse .alphabetic;
    }
};

/// Advance width (px) of `text` at `font_px`, from the bundled font.
pub fn measureText(text: []const u8, font_px: f32) f32 {
    if (text.len == 0) return 0;
    return lp_canvas_measure_text(text.ptr, text.len, font_px);
}

/// Draw-op opcodes. Must stay in sync with stealthpanda_canvas.rs.
pub const Op = enum(u8) {
    set_fill = 0x01,
    fill_rect = 0x02,
    clear_rect = 0x03,
    fill_text = 0x10,
};

/// Renders the recorded op stream to a PNG, returning bytes owned by
/// `allocator` (a copy of the Rust-owned buffer), or null on failure.
pub fn renderPng(allocator: std.mem.Allocator, ops: []const u8, w: u32, h: u32) !?[]u8 {
    var out_len: usize = 0;
    const ptr = lp_canvas_render_png(
        if (ops.len == 0) null else ops.ptr,
        ops.len,
        w,
        h,
        &out_len,
    ) orelse return null;
    defer lp_canvas_free(ptr, out_len);
    if (out_len == 0) return null;
    return try allocator.dupe(u8, ptr[0..out_len]);
}
