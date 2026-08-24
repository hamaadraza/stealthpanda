// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

const js = @import("../../js/js.zig");
const Frame = @import("../../Frame.zig");
const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{
        WebGLRenderingContext,
        // Extension types should be runtime generated. We might want
        // to revisit this.
        Extension.Type.WEBGL_debug_renderer_info,
        Extension.Type.WEBGL_lose_context,
    };
}

const WebGLRenderingContext = @This();

// Zero-state context; the field just gives the factory a non-empty allocation.
_pad: u8 = 0,

/// On Chrome and Safari, a call to `getSupportedExtensions` returns total of 39.
/// The reference for it lists lesser number of extensions:
/// https://developer.mozilla.org/en-US/docs/Web/API/WebGL_API/Using_Extensions#extension_list
pub const Extension = union(enum) {
    ANGLE_instanced_arrays: void,
    EXT_blend_minmax: void,
    EXT_clip_control: void,
    EXT_color_buffer_half_float: void,
    EXT_depth_clamp: void,
    EXT_disjoint_timer_query: void,
    EXT_float_blend: void,
    EXT_frag_depth: void,
    EXT_polygon_offset_clamp: void,
    EXT_shader_texture_lod: void,
    EXT_texture_compression_bptc: void,
    EXT_texture_compression_rgtc: void,
    EXT_texture_filter_anisotropic: void,
    EXT_texture_mirror_clamp_to_edge: void,
    EXT_sRGB: void,
    KHR_parallel_shader_compile: void,
    OES_element_index_uint: void,
    OES_fbo_render_mipmap: void,
    OES_standard_derivatives: void,
    OES_texture_float: void,
    OES_texture_float_linear: void,
    OES_texture_half_float: void,
    OES_texture_half_float_linear: void,
    OES_vertex_array_object: void,
    WEBGL_blend_func_extended: void,
    WEBGL_color_buffer_float: void,
    WEBGL_compressed_texture_astc: void,
    WEBGL_compressed_texture_etc: void,
    WEBGL_compressed_texture_etc1: void,
    WEBGL_compressed_texture_pvrtc: void,
    WEBGL_compressed_texture_s3tc: void,
    WEBGL_compressed_texture_s3tc_srgb: void,
    WEBGL_debug_renderer_info: *Type.WEBGL_debug_renderer_info,
    WEBGL_debug_shaders: void,
    WEBGL_depth_texture: void,
    WEBGL_draw_buffers: void,
    WEBGL_lose_context: *Type.WEBGL_lose_context,
    WEBGL_multi_draw: void,
    WEBGL_polygon_mode: void,

    /// Reified enum type from the fields of this union.
    const Kind = blk: {
        const info = @typeInfo(Extension).@"union";
        const fields = info.fields;
        const Tag = std.math.IntFittingRange(0, if (fields.len == 0) 0 else fields.len - 1);
        var names: [fields.len][:0]const u8 = undefined;
        for (fields, 0..) |field, i| {
            names[i] = field.name;
        }

        break :blk @Enum(Tag, .exhaustive, &names, &std.simd.iota(Tag, fields.len));
    };

    /// Returns the `Extension.Kind` by its name.
    fn find(name: []const u8) ?Kind {
        // Just to make you really sad, this function has to be case-insensitive.
        // So here we copy what's being done in `std.meta.stringToEnum` but replace
        // the comparison function.
        const kvs = comptime build_kvs: {
            const T = Extension.Kind;
            const EnumKV = struct { []const u8, T };
            var kvs_array: [@typeInfo(T).@"enum".fields.len]EnumKV = undefined;
            for (@typeInfo(T).@"enum".fields, 0..) |enumField, i| {
                kvs_array[i] = .{ enumField.name, @field(T, enumField.name) };
            }
            break :build_kvs kvs_array[0..];
        };
        const Map = std.StaticStringMapWithEql(Extension.Kind, std.static_string_map.eqlAsciiIgnoreCase);
        const map = Map.initComptime(kvs);
        return map.get(name);
    }

    /// Extension types.
    pub const Type = struct {
        pub const WEBGL_debug_renderer_info = struct {
            _: u8 = 0,
            pub const UNMASKED_VENDOR_WEBGL: u64 = 0x9245;
            pub const UNMASKED_RENDERER_WEBGL: u64 = 0x9246;

            pub const JsApi = struct {
                pub const bridge = js.Bridge(WEBGL_debug_renderer_info);

                pub const Meta = struct {
                    pub const name = "WEBGL_debug_renderer_info";

                    pub const prototype_chain = bridge.prototypeChain();
                    pub var class_id: bridge.ClassId = undefined;
                };

                pub const UNMASKED_VENDOR_WEBGL = bridge.property(WEBGL_debug_renderer_info.UNMASKED_VENDOR_WEBGL, .{ .template = false, .readonly = true });
                pub const UNMASKED_RENDERER_WEBGL = bridge.property(WEBGL_debug_renderer_info.UNMASKED_RENDERER_WEBGL, .{ .template = false, .readonly = true });
            };
        };

        pub const WEBGL_lose_context = struct {
            _: u8 = 0,
            pub fn loseContext(_: *const WEBGL_lose_context) void {}
            pub fn restoreContext(_: *const WEBGL_lose_context) void {}

            pub const JsApi = struct {
                pub const bridge = js.Bridge(WEBGL_lose_context);

                pub const Meta = struct {
                    pub const name = "WEBGL_lose_context";

                    pub const prototype_chain = bridge.prototypeChain();
                    pub var class_id: bridge.ClassId = undefined;
                };

                pub const loseContext = bridge.function(WEBGL_lose_context.loseContext, .{ .noop = true });
                pub const restoreContext = bridge.function(WEBGL_lose_context.restoreContext, .{ .noop = true });
            };
        };
    };
};

/// getParameter(GLenum). The return type varies by pname (string / number /
/// array), so we build a js.Value. stealthpanda: only reachable when
/// impersonating (getContext returns null otherwise), and reports the same
/// values a real Chrome does — the vendor/renderer strings especially are a
/// primary WebGL fingerprint.
pub fn getParameter(_: *const WebGLRenderingContext, pname: u32, exec: *const Execution) !js.Value {
    const local = exec.js.local.?;
    const id = exec.session.browser.http_client.impersonateIdentity();
    return switch (pname) {
        0x1F00 => local.zigValueToJs(@as([]const u8, "WebKit"), .{}), // VENDOR
        0x1F01 => local.zigValueToJs(@as([]const u8, "WebKit WebGL"), .{}), // RENDERER
        0x1F02 => local.zigValueToJs(@as([]const u8, "WebGL 1.0 (OpenGL ES 2.0 Chromium)"), .{}), // VERSION
        0x8B8C => local.zigValueToJs(@as([]const u8, "WebGL GLSL ES 1.0 (OpenGL ES GLSL ES 1.0 Chromium)"), .{}), // SHADING_LANGUAGE_VERSION
        // UNMASKED_VENDOR_WEBGL / UNMASKED_RENDERER_WEBGL — the real GPU strings.
        0x9245 => local.zigValueToJs(@as([]const u8, if (id) |i| i.webgl_vendor else "Google Inc."), .{}),
        0x9246 => local.zigValueToJs(@as([]const u8, if (id) |i| i.webgl_renderer else "ANGLE"), .{}),
        // Common numeric limits (ANGLE Metal on macOS typical values).
        0x0D33, 0x851C, 0x84E8 => local.zigValueToJs(@as(u32, 16384), .{}), // MAX_TEXTURE / CUBE_MAP / RENDERBUFFER_SIZE
        0x8869 => local.zigValueToJs(@as(u32, 16), .{}), // MAX_VERTEX_ATTRIBS
        0x8DFB, 0x8DFD => local.zigValueToJs(@as(u32, 1024), .{}), // MAX_VERTEX/FRAGMENT_UNIFORM_VECTORS
        0x8DFC => local.zigValueToJs(@as(u32, 30), .{}), // MAX_VARYING_VECTORS
        0x8872, 0x8B4C => local.zigValueToJs(@as(u32, 16), .{}), // MAX_TEXTURE_IMAGE_UNITS / VERTEX_TEXTURE_IMAGE_UNITS
        0x8B4D => local.zigValueToJs(@as(u32, 32), .{}), // MAX_COMBINED_TEXTURE_IMAGE_UNITS
        0x0D3A => local.zigValueToJs(@as([]const i32, &.{ 32767, 32767 }), .{}), // MAX_VIEWPORT_DIMS
        0x846D => local.zigValueToJs(@as([]const f32, &.{ 1, 1024 }), .{}), // ALIASED_POINT_SIZE_RANGE
        0x846E => local.zigValueToJs(@as([]const f32, &.{ 1, 1 }), .{}), // ALIASED_LINE_WIDTH_RANGE
        else => local.zigValueToJs(@as(?u8, null), .{}), // unhandled → null
    };
}

/// Enables a WebGL extension.
pub fn getExtension(_: *const WebGLRenderingContext, name: []const u8, frame: *Frame) !?Extension {
    const tag = Extension.find(name) orelse return null;

    return switch (tag) {
        .WEBGL_debug_renderer_info => {
            const info = try frame._factory.create(Extension.Type.WEBGL_debug_renderer_info{});
            return .{ .WEBGL_debug_renderer_info = info };
        },
        .WEBGL_lose_context => {
            const ctx = try frame._factory.create(Extension.Type.WEBGL_lose_context{});
            return .{ .WEBGL_lose_context = ctx };
        },
        inline else => |comptime_enum| @unionInit(Extension, @tagName(comptime_enum), {}),
    };
}

/// Returns a list of all the supported WebGL extensions.
pub fn getSupportedExtensions(_: *const WebGLRenderingContext) []const []const u8 {
    return std.meta.fieldNames(Extension.Kind);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(WebGLRenderingContext);

    pub const Meta = struct {
        pub const name = "WebGLRenderingContext";

        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const getParameter = bridge.function(WebGLRenderingContext.getParameter, .{});
    pub const getExtension = bridge.function(WebGLRenderingContext.getExtension, .{});
    pub const getSupportedExtensions = bridge.function(WebGLRenderingContext.getSupportedExtensions, .{});
};

// getContext('web-gl') currently returns null, so this cannot be tested
// const testing = @import("../../../testing.zig");
// test "WebApi: WebGLRenderingContext" {
//     try testing.htmlRunner("canvas/webgl_rendering_context.html", .{});
// }
