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
const Canvas = @import("../element/html/Canvas.zig");
const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{
        WebGLRenderingContext,
        // Extension types should be runtime generated. We might want
        // to revisit this.
        Extension.Type.WEBGL_debug_renderer_info,
        Extension.Type.WEBGL_lose_context,
        // stealthpanda: opaque handle objects returned by the render stubs.
        WebGLShader,
        WebGLProgram,
        WebGLBuffer,
        WebGLTexture,
        WebGLFramebuffer,
        WebGLRenderbuffer,
        WebGLUniformLocation,
    };
}

const WebGLRenderingContext = @This();

// stealthpanda: per-session seed for the readPixels noise (set by getContext
// from the session pointer, so it's stable within a session and varies across
// launches via ASLR). Also serves as the factory's non-empty allocation.
_seed: u64 = 0,
// stealthpanda: back-reference to the owning canvas (gl.canvas /
// gl.drawingBufferWidth/Height; fingerprint scripts read gl.canvas.width).
_canvas: *Canvas = undefined,

// stealthpanda: opaque WebGL handle objects. Real WebGL rendering needs a GPU
// (a line even Cloudflare's Kitesurf doesn't cross), so we can't produce a
// GPU-accurate image. But a Chrome UA whose gl.createShader/drawArrays/readPixels
// throw is a loud tell, so these stubs let the render sequence complete and
// readPixels returns per-session noise (chosen over a constant, fleet-shared
// hash) — the WebGL *report* fingerprint (params/extensions/unmasked) is fully
// spoofed separately in getParameter.
fn Handle(comptime type_name: [:0]const u8) type {
    return struct {
        const Self = @This();
        _pad: u8 = 0,
        pub const JsApi = struct {
            pub const bridge = js.Bridge(Self);
            pub const Meta = struct {
                pub const name = type_name;
                pub const prototype_chain = bridge.prototypeChain();
                pub var class_id: bridge.ClassId = undefined;
            };
        };
    };
}
pub const WebGLShader = Handle("WebGLShader");
pub const WebGLProgram = Handle("WebGLProgram");
pub const WebGLBuffer = Handle("WebGLBuffer");
pub const WebGLTexture = Handle("WebGLTexture");
pub const WebGLFramebuffer = Handle("WebGLFramebuffer");
pub const WebGLRenderbuffer = Handle("WebGLRenderbuffer");
pub const WebGLUniformLocation = Handle("WebGLUniformLocation");

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

/// getContextAttributes() — the options the context was created with. A real
/// WebGL context always has this method; its absence (undefined) is a headless
/// tell. Fixed to Chrome's defaults.
pub fn getContextAttributes(_: *const WebGLRenderingContext) struct {
    alpha: bool,
    antialias: bool,
    depth: bool,
    desynchronized: bool,
    failIfMajorPerformanceCaveat: bool,
    powerPreference: []const u8,
    premultipliedAlpha: bool,
    preserveDrawingBuffer: bool,
    stencil: bool,
    xrCompatible: bool,
} {
    return .{
        .alpha = true,
        .antialias = true,
        .depth = true,
        .desynchronized = false,
        .failIfMajorPerformanceCaveat = false,
        .powerPreference = "default",
        .premultipliedAlpha = true,
        .preserveDrawingBuffer = false,
        .stencil = false,
        .xrCompatible = false,
    };
}

/// getShaderPrecisionFormat(shaderType, precisionType) → {rangeMin, rangeMax,
/// precision}. Desktop Chrome/ANGLE promotes every float precision to highp
/// (127/127/23); integer precisions report 31/30/0. Another primary WebGL
/// fingerprint, and a missing method is a tell.
pub fn getShaderPrecisionFormat(_: *const WebGLRenderingContext, shader_type: u32, precision_type: u32) struct {
    rangeMin: i32,
    rangeMax: i32,
    precision: i32,
} {
    _ = shader_type;
    return switch (precision_type) {
        // LOW_INT / MEDIUM_INT / HIGH_INT
        0x8DF3, 0x8DF4, 0x8DF5 => .{ .rangeMin = 31, .rangeMax = 30, .precision = 0 },
        // LOW_FLOAT / MEDIUM_FLOAT / HIGH_FLOAT (and anything else)
        else => .{ .rangeMin = 127, .rangeMax = 127, .precision = 23 },
    };
}

// stealthpanda: WebGL render stubs. A shared no-op backs every state-changing
// call (viewport, draw*, uniform*, bind*, etc.) — with `.noop = true` the JS
// stub ignores its arguments, so one nullary fn covers every arity.
fn glNoop(_: *const WebGLRenderingContext) void {}

pub fn getCanvas(self: *const WebGLRenderingContext) *Canvas {
    return self._canvas;
}
pub fn getDrawingBufferWidth(self: *const WebGLRenderingContext) u32 {
    return self._canvas.getWidth();
}
pub fn getDrawingBufferHeight(self: *const WebGLRenderingContext) u32 {
    return self._canvas.getHeight();
}

// Handle factories — the render code chains these objects but never inspects
// them, so an opaque instance per call is enough.
pub fn createShader(_: *const WebGLRenderingContext, _: js.Value, frame: *Frame) !*WebGLShader {
    return frame._factory.create(WebGLShader{});
}
pub fn createProgram(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLProgram {
    return frame._factory.create(WebGLProgram{});
}
pub fn createBuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLBuffer {
    return frame._factory.create(WebGLBuffer{});
}
pub fn createTexture(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLTexture {
    return frame._factory.create(WebGLTexture{});
}
pub fn createFramebuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLFramebuffer {
    return frame._factory.create(WebGLFramebuffer{});
}
pub fn createRenderbuffer(_: *const WebGLRenderingContext, frame: *Frame) !*WebGLRenderbuffer {
    return frame._factory.create(WebGLRenderbuffer{});
}
pub fn getUniformLocation(_: *const WebGLRenderingContext, _: js.Value, _: js.Value, frame: *Frame) !*WebGLUniformLocation {
    return frame._factory.create(WebGLUniformLocation{});
}
pub fn getAttribLocation(_: *const WebGLRenderingContext, _: js.Value, _: js.Value) i32 {
    return 0;
}
pub fn getError(_: *const WebGLRenderingContext) u32 {
    return 0; // NO_ERROR
}
// Compile/link/validate always "succeed" so the render sequence proceeds; any
// other query returns a truthy value that also works as a count.
pub fn getShaderParameter(_: *const WebGLRenderingContext, _: js.Value, _: js.Value) bool {
    return true;
}
pub fn getProgramParameter(_: *const WebGLRenderingContext, _: js.Value, _: js.Value) bool {
    return true;
}
pub fn getShaderInfoLog(_: *const WebGLRenderingContext, _: js.Value) []const u8 {
    return "";
}
pub fn getProgramInfoLog(_: *const WebGLRenderingContext, _: js.Value) []const u8 {
    return "";
}
pub fn getShaderSource(_: *const WebGLRenderingContext, _: js.Value) []const u8 {
    return "";
}
pub fn checkFramebufferStatus(_: *const WebGLRenderingContext, _: js.Value) u32 {
    return 0x8CD5; // FRAMEBUFFER_COMPLETE
}
pub fn isContextLost(_: *const WebGLRenderingContext) bool {
    return false;
}
pub fn isEnabled(_: *const WebGLRenderingContext, _: js.Value) bool {
    return false;
}
pub fn glIsObject(_: *const WebGLRenderingContext, _: js.Value) bool {
    return true;
}

// The readback buffer types readPixels can be handed (mirrors the crypto
// RandomValues shape; integer arrays cover the common UNSIGNED_BYTE path).
const PixelBuffer = union(enum) {
    int8: []i8,
    uint8: []u8,
    int16: []i16,
    uint16: []u16,
    int32: []i32,
    uint32: []u32,
    float32: []f32,

    fn asBytes(self: PixelBuffer) []u8 {
        return switch (self) {
            .int8 => |b| @as([*]u8, @ptrCast(b.ptr))[0..b.len],
            .uint8 => |b| b,
            .int16 => |b| @as([*]u8, @ptrCast(b.ptr))[0 .. b.len * 2],
            .uint16 => |b| @as([*]u8, @ptrCast(b.ptr))[0 .. b.len * 2],
            .int32 => |b| @as([*]u8, @ptrCast(b.ptr))[0 .. b.len * 4],
            .uint32 => |b| @as([*]u8, @ptrCast(b.ptr))[0 .. b.len * 4],
            .float32 => |b| @as([*]u8, @ptrCast(b.ptr))[0 .. b.len * 4],
        };
    }
};

// Fills the caller's pixel buffer with per-session deterministic noise (seeded
// from _seed), so the WebGL image hash is stable within a session but differs
// across sessions. Never throws (a real gl.readPixels doesn't).
pub fn readPixels(
    self: *const WebGLRenderingContext,
    _: js.Value,
    _: js.Value,
    _: js.Value,
    _: js.Value,
    _: js.Value,
    _: js.Value,
    pixels: js.Object,
) !void {
    var into = pixels.toZig(PixelBuffer) catch return;
    const buf = into.asBytes();
    if (buf.len == 0) return;
    var prng = std.Random.DefaultPrng.init(self._seed);
    const rand = prng.random();
    var i: usize = 0;
    while (i + 4 <= buf.len) : (i += 4) {
        buf[i] = rand.int(u8);
        buf[i + 1] = rand.int(u8);
        buf[i + 2] = rand.int(u8);
        buf[i + 3] = 255; // opaque
    }
    while (i < buf.len) : (i += 1) buf[i] = rand.int(u8);
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
    pub const getContextAttributes = bridge.function(WebGLRenderingContext.getContextAttributes, .{});
    pub const getShaderPrecisionFormat = bridge.function(WebGLRenderingContext.getShaderPrecisionFormat, .{});

    // stealthpanda: gl.canvas / drawing buffer size.
    pub const canvas = bridge.accessor(WebGLRenderingContext.getCanvas, null, .{});
    pub const drawingBufferWidth = bridge.accessor(WebGLRenderingContext.getDrawingBufferWidth, null, .{});
    pub const drawingBufferHeight = bridge.accessor(WebGLRenderingContext.getDrawingBufferHeight, null, .{});

    // stealthpanda: WebGL render stubs (return values).
    pub const createShader = bridge.function(WebGLRenderingContext.createShader, .{});
    pub const createProgram = bridge.function(WebGLRenderingContext.createProgram, .{});
    pub const createBuffer = bridge.function(WebGLRenderingContext.createBuffer, .{});
    pub const createTexture = bridge.function(WebGLRenderingContext.createTexture, .{});
    pub const createFramebuffer = bridge.function(WebGLRenderingContext.createFramebuffer, .{});
    pub const createRenderbuffer = bridge.function(WebGLRenderingContext.createRenderbuffer, .{});
    pub const getUniformLocation = bridge.function(WebGLRenderingContext.getUniformLocation, .{});
    pub const getAttribLocation = bridge.function(WebGLRenderingContext.getAttribLocation, .{});
    pub const getError = bridge.function(WebGLRenderingContext.getError, .{});
    pub const getShaderParameter = bridge.function(WebGLRenderingContext.getShaderParameter, .{});
    pub const getProgramParameter = bridge.function(WebGLRenderingContext.getProgramParameter, .{});
    pub const getShaderInfoLog = bridge.function(WebGLRenderingContext.getShaderInfoLog, .{});
    pub const getProgramInfoLog = bridge.function(WebGLRenderingContext.getProgramInfoLog, .{});
    pub const getShaderSource = bridge.function(WebGLRenderingContext.getShaderSource, .{});
    pub const checkFramebufferStatus = bridge.function(WebGLRenderingContext.checkFramebufferStatus, .{});
    pub const isContextLost = bridge.function(WebGLRenderingContext.isContextLost, .{});
    pub const isEnabled = bridge.function(WebGLRenderingContext.isEnabled, .{});
    pub const isBuffer = bridge.function(WebGLRenderingContext.glIsObject, .{});
    pub const isProgram = bridge.function(WebGLRenderingContext.glIsObject, .{});
    pub const isShader = bridge.function(WebGLRenderingContext.glIsObject, .{});
    pub const isTexture = bridge.function(WebGLRenderingContext.glIsObject, .{});
    pub const isFramebuffer = bridge.function(WebGLRenderingContext.glIsObject, .{});
    pub const isRenderbuffer = bridge.function(WebGLRenderingContext.glIsObject, .{});
    pub const readPixels = bridge.function(WebGLRenderingContext.readPixels, .{});
    // stealthpanda: WebGL render stubs (no-ops; args ignored via .noop).
    pub const activeTexture = bridge.function(glNoop, .{ .noop = true });
    pub const attachShader = bridge.function(glNoop, .{ .noop = true });
    pub const bindAttribLocation = bridge.function(glNoop, .{ .noop = true });
    pub const bindBuffer = bridge.function(glNoop, .{ .noop = true });
    pub const bindFramebuffer = bridge.function(glNoop, .{ .noop = true });
    pub const bindRenderbuffer = bridge.function(glNoop, .{ .noop = true });
    pub const bindTexture = bridge.function(glNoop, .{ .noop = true });
    pub const blendColor = bridge.function(glNoop, .{ .noop = true });
    pub const blendEquation = bridge.function(glNoop, .{ .noop = true });
    pub const blendEquationSeparate = bridge.function(glNoop, .{ .noop = true });
    pub const blendFunc = bridge.function(glNoop, .{ .noop = true });
    pub const blendFuncSeparate = bridge.function(glNoop, .{ .noop = true });
    pub const bufferData = bridge.function(glNoop, .{ .noop = true });
    pub const bufferSubData = bridge.function(glNoop, .{ .noop = true });
    pub const clear = bridge.function(glNoop, .{ .noop = true });
    pub const clearColor = bridge.function(glNoop, .{ .noop = true });
    pub const clearDepth = bridge.function(glNoop, .{ .noop = true });
    pub const clearStencil = bridge.function(glNoop, .{ .noop = true });
    pub const colorMask = bridge.function(glNoop, .{ .noop = true });
    pub const compileShader = bridge.function(glNoop, .{ .noop = true });
    pub const copyTexImage2D = bridge.function(glNoop, .{ .noop = true });
    pub const copyTexSubImage2D = bridge.function(glNoop, .{ .noop = true });
    pub const cullFace = bridge.function(glNoop, .{ .noop = true });
    pub const deleteBuffer = bridge.function(glNoop, .{ .noop = true });
    pub const deleteFramebuffer = bridge.function(glNoop, .{ .noop = true });
    pub const deleteProgram = bridge.function(glNoop, .{ .noop = true });
    pub const deleteRenderbuffer = bridge.function(glNoop, .{ .noop = true });
    pub const deleteShader = bridge.function(glNoop, .{ .noop = true });
    pub const deleteTexture = bridge.function(glNoop, .{ .noop = true });
    pub const depthFunc = bridge.function(glNoop, .{ .noop = true });
    pub const depthMask = bridge.function(glNoop, .{ .noop = true });
    pub const depthRange = bridge.function(glNoop, .{ .noop = true });
    pub const detachShader = bridge.function(glNoop, .{ .noop = true });
    pub const disable = bridge.function(glNoop, .{ .noop = true });
    pub const disableVertexAttribArray = bridge.function(glNoop, .{ .noop = true });
    pub const drawArrays = bridge.function(glNoop, .{ .noop = true });
    pub const drawElements = bridge.function(glNoop, .{ .noop = true });
    pub const enable = bridge.function(glNoop, .{ .noop = true });
    pub const enableVertexAttribArray = bridge.function(glNoop, .{ .noop = true });
    pub const finish = bridge.function(glNoop, .{ .noop = true });
    pub const flush = bridge.function(glNoop, .{ .noop = true });
    pub const framebufferRenderbuffer = bridge.function(glNoop, .{ .noop = true });
    pub const framebufferTexture2D = bridge.function(glNoop, .{ .noop = true });
    pub const frontFace = bridge.function(glNoop, .{ .noop = true });
    pub const generateMipmap = bridge.function(glNoop, .{ .noop = true });
    pub const hint = bridge.function(glNoop, .{ .noop = true });
    pub const lineWidth = bridge.function(glNoop, .{ .noop = true });
    pub const linkProgram = bridge.function(glNoop, .{ .noop = true });
    pub const pixelStorei = bridge.function(glNoop, .{ .noop = true });
    pub const polygonOffset = bridge.function(glNoop, .{ .noop = true });
    pub const renderbufferStorage = bridge.function(glNoop, .{ .noop = true });
    pub const sampleCoverage = bridge.function(glNoop, .{ .noop = true });
    pub const scissor = bridge.function(glNoop, .{ .noop = true });
    pub const shaderSource = bridge.function(glNoop, .{ .noop = true });
    pub const stencilFunc = bridge.function(glNoop, .{ .noop = true });
    pub const stencilFuncSeparate = bridge.function(glNoop, .{ .noop = true });
    pub const stencilMask = bridge.function(glNoop, .{ .noop = true });
    pub const stencilMaskSeparate = bridge.function(glNoop, .{ .noop = true });
    pub const stencilOp = bridge.function(glNoop, .{ .noop = true });
    pub const stencilOpSeparate = bridge.function(glNoop, .{ .noop = true });
    pub const texImage2D = bridge.function(glNoop, .{ .noop = true });
    pub const texParameterf = bridge.function(glNoop, .{ .noop = true });
    pub const texParameteri = bridge.function(glNoop, .{ .noop = true });
    pub const texSubImage2D = bridge.function(glNoop, .{ .noop = true });
    pub const uniform1f = bridge.function(glNoop, .{ .noop = true });
    pub const uniform1fv = bridge.function(glNoop, .{ .noop = true });
    pub const uniform1i = bridge.function(glNoop, .{ .noop = true });
    pub const uniform1iv = bridge.function(glNoop, .{ .noop = true });
    pub const uniform2f = bridge.function(glNoop, .{ .noop = true });
    pub const uniform2fv = bridge.function(glNoop, .{ .noop = true });
    pub const uniform2i = bridge.function(glNoop, .{ .noop = true });
    pub const uniform2iv = bridge.function(glNoop, .{ .noop = true });
    pub const uniform3f = bridge.function(glNoop, .{ .noop = true });
    pub const uniform3fv = bridge.function(glNoop, .{ .noop = true });
    pub const uniform3i = bridge.function(glNoop, .{ .noop = true });
    pub const uniform3iv = bridge.function(glNoop, .{ .noop = true });
    pub const uniform4f = bridge.function(glNoop, .{ .noop = true });
    pub const uniform4fv = bridge.function(glNoop, .{ .noop = true });
    pub const uniform4i = bridge.function(glNoop, .{ .noop = true });
    pub const uniform4iv = bridge.function(glNoop, .{ .noop = true });
    pub const uniformMatrix2fv = bridge.function(glNoop, .{ .noop = true });
    pub const uniformMatrix3fv = bridge.function(glNoop, .{ .noop = true });
    pub const uniformMatrix4fv = bridge.function(glNoop, .{ .noop = true });
    pub const useProgram = bridge.function(glNoop, .{ .noop = true });
    pub const validateProgram = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib1f = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib1fv = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib2f = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib2fv = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib3f = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib3fv = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib4f = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttrib4fv = bridge.function(glNoop, .{ .noop = true });
    pub const vertexAttribPointer = bridge.function(glNoop, .{ .noop = true });
    pub const viewport = bridge.function(glNoop, .{ .noop = true });

    // stealthpanda: the full WebGL 1.0 enum constant set. Real fingerprint
    // scripts use `gl.getParameter(gl.VENDOR)` etc.; without these the
    // constant reads undefined -> getParameter(0) -> null, and enumerating
    // the prototype yields far fewer keys than a real context. Values are
    // the standard GLenums.
    pub const DEPTH_BUFFER_BIT = bridge.property(0x100, .{ .template = false, .readonly = true });
    pub const STENCIL_BUFFER_BIT = bridge.property(0x400, .{ .template = false, .readonly = true });
    pub const COLOR_BUFFER_BIT = bridge.property(0x4000, .{ .template = false, .readonly = true });
    pub const POINTS = bridge.property(0x0, .{ .template = false, .readonly = true });
    pub const LINES = bridge.property(0x1, .{ .template = false, .readonly = true });
    pub const LINE_LOOP = bridge.property(0x2, .{ .template = false, .readonly = true });
    pub const LINE_STRIP = bridge.property(0x3, .{ .template = false, .readonly = true });
    pub const TRIANGLES = bridge.property(0x4, .{ .template = false, .readonly = true });
    pub const TRIANGLE_STRIP = bridge.property(0x5, .{ .template = false, .readonly = true });
    pub const TRIANGLE_FAN = bridge.property(0x6, .{ .template = false, .readonly = true });
    pub const ZERO = bridge.property(0x0, .{ .template = false, .readonly = true });
    pub const ONE = bridge.property(0x1, .{ .template = false, .readonly = true });
    pub const SRC_COLOR = bridge.property(0x300, .{ .template = false, .readonly = true });
    pub const ONE_MINUS_SRC_COLOR = bridge.property(0x301, .{ .template = false, .readonly = true });
    pub const SRC_ALPHA = bridge.property(0x302, .{ .template = false, .readonly = true });
    pub const ONE_MINUS_SRC_ALPHA = bridge.property(0x303, .{ .template = false, .readonly = true });
    pub const DST_ALPHA = bridge.property(0x304, .{ .template = false, .readonly = true });
    pub const ONE_MINUS_DST_ALPHA = bridge.property(0x305, .{ .template = false, .readonly = true });
    pub const DST_COLOR = bridge.property(0x306, .{ .template = false, .readonly = true });
    pub const ONE_MINUS_DST_COLOR = bridge.property(0x307, .{ .template = false, .readonly = true });
    pub const SRC_ALPHA_SATURATE = bridge.property(0x308, .{ .template = false, .readonly = true });
    pub const FUNC_ADD = bridge.property(0x8006, .{ .template = false, .readonly = true });
    pub const BLEND_EQUATION = bridge.property(0x8009, .{ .template = false, .readonly = true });
    pub const BLEND_EQUATION_RGB = bridge.property(0x8009, .{ .template = false, .readonly = true });
    pub const BLEND_EQUATION_ALPHA = bridge.property(0x883D, .{ .template = false, .readonly = true });
    pub const FUNC_SUBTRACT = bridge.property(0x800A, .{ .template = false, .readonly = true });
    pub const FUNC_REVERSE_SUBTRACT = bridge.property(0x800B, .{ .template = false, .readonly = true });
    pub const BLEND_DST_RGB = bridge.property(0x80C8, .{ .template = false, .readonly = true });
    pub const BLEND_SRC_RGB = bridge.property(0x80C9, .{ .template = false, .readonly = true });
    pub const BLEND_DST_ALPHA = bridge.property(0x80CA, .{ .template = false, .readonly = true });
    pub const BLEND_SRC_ALPHA = bridge.property(0x80CB, .{ .template = false, .readonly = true });
    pub const CONSTANT_COLOR = bridge.property(0x8001, .{ .template = false, .readonly = true });
    pub const ONE_MINUS_CONSTANT_COLOR = bridge.property(0x8002, .{ .template = false, .readonly = true });
    pub const CONSTANT_ALPHA = bridge.property(0x8003, .{ .template = false, .readonly = true });
    pub const ONE_MINUS_CONSTANT_ALPHA = bridge.property(0x8004, .{ .template = false, .readonly = true });
    pub const BLEND_COLOR = bridge.property(0x8005, .{ .template = false, .readonly = true });
    pub const ARRAY_BUFFER = bridge.property(0x8892, .{ .template = false, .readonly = true });
    pub const ELEMENT_ARRAY_BUFFER = bridge.property(0x8893, .{ .template = false, .readonly = true });
    pub const ARRAY_BUFFER_BINDING = bridge.property(0x8894, .{ .template = false, .readonly = true });
    pub const ELEMENT_ARRAY_BUFFER_BINDING = bridge.property(0x8895, .{ .template = false, .readonly = true });
    pub const STREAM_DRAW = bridge.property(0x88E0, .{ .template = false, .readonly = true });
    pub const STATIC_DRAW = bridge.property(0x88E4, .{ .template = false, .readonly = true });
    pub const DYNAMIC_DRAW = bridge.property(0x88E8, .{ .template = false, .readonly = true });
    pub const BUFFER_SIZE = bridge.property(0x8764, .{ .template = false, .readonly = true });
    pub const BUFFER_USAGE = bridge.property(0x8765, .{ .template = false, .readonly = true });
    pub const CURRENT_VERTEX_ATTRIB = bridge.property(0x8626, .{ .template = false, .readonly = true });
    pub const FRONT = bridge.property(0x404, .{ .template = false, .readonly = true });
    pub const BACK = bridge.property(0x405, .{ .template = false, .readonly = true });
    pub const FRONT_AND_BACK = bridge.property(0x408, .{ .template = false, .readonly = true });
    pub const CULL_FACE = bridge.property(0xB44, .{ .template = false, .readonly = true });
    pub const BLEND = bridge.property(0xBE2, .{ .template = false, .readonly = true });
    pub const DITHER = bridge.property(0xBD0, .{ .template = false, .readonly = true });
    pub const STENCIL_TEST = bridge.property(0xB90, .{ .template = false, .readonly = true });
    pub const DEPTH_TEST = bridge.property(0xB71, .{ .template = false, .readonly = true });
    pub const SCISSOR_TEST = bridge.property(0xC11, .{ .template = false, .readonly = true });
    pub const POLYGON_OFFSET_FILL = bridge.property(0x8037, .{ .template = false, .readonly = true });
    pub const SAMPLE_ALPHA_TO_COVERAGE = bridge.property(0x809E, .{ .template = false, .readonly = true });
    pub const SAMPLE_COVERAGE = bridge.property(0x80A0, .{ .template = false, .readonly = true });
    pub const NO_ERROR = bridge.property(0x0, .{ .template = false, .readonly = true });
    pub const INVALID_ENUM = bridge.property(0x500, .{ .template = false, .readonly = true });
    pub const INVALID_VALUE = bridge.property(0x501, .{ .template = false, .readonly = true });
    pub const INVALID_OPERATION = bridge.property(0x502, .{ .template = false, .readonly = true });
    pub const OUT_OF_MEMORY = bridge.property(0x505, .{ .template = false, .readonly = true });
    pub const INVALID_FRAMEBUFFER_OPERATION = bridge.property(0x506, .{ .template = false, .readonly = true });
    pub const CW = bridge.property(0x900, .{ .template = false, .readonly = true });
    pub const CCW = bridge.property(0x901, .{ .template = false, .readonly = true });
    pub const LINE_WIDTH = bridge.property(0xB21, .{ .template = false, .readonly = true });
    pub const ALIASED_POINT_SIZE_RANGE = bridge.property(0x846D, .{ .template = false, .readonly = true });
    pub const ALIASED_LINE_WIDTH_RANGE = bridge.property(0x846E, .{ .template = false, .readonly = true });
    pub const CULL_FACE_MODE = bridge.property(0xB45, .{ .template = false, .readonly = true });
    pub const FRONT_FACE = bridge.property(0xB46, .{ .template = false, .readonly = true });
    pub const DEPTH_RANGE = bridge.property(0xB70, .{ .template = false, .readonly = true });
    pub const DEPTH_WRITEMASK = bridge.property(0xB72, .{ .template = false, .readonly = true });
    pub const DEPTH_CLEAR_VALUE = bridge.property(0xB73, .{ .template = false, .readonly = true });
    pub const DEPTH_FUNC = bridge.property(0xB74, .{ .template = false, .readonly = true });
    pub const STENCIL_CLEAR_VALUE = bridge.property(0xB91, .{ .template = false, .readonly = true });
    pub const STENCIL_FUNC = bridge.property(0xB92, .{ .template = false, .readonly = true });
    pub const STENCIL_FAIL = bridge.property(0xB94, .{ .template = false, .readonly = true });
    pub const STENCIL_PASS_DEPTH_FAIL = bridge.property(0xB95, .{ .template = false, .readonly = true });
    pub const STENCIL_PASS_DEPTH_PASS = bridge.property(0xB96, .{ .template = false, .readonly = true });
    pub const STENCIL_REF = bridge.property(0xB97, .{ .template = false, .readonly = true });
    pub const STENCIL_VALUE_MASK = bridge.property(0xB93, .{ .template = false, .readonly = true });
    pub const STENCIL_WRITEMASK = bridge.property(0xB98, .{ .template = false, .readonly = true });
    pub const STENCIL_BACK_FUNC = bridge.property(0x8800, .{ .template = false, .readonly = true });
    pub const STENCIL_BACK_FAIL = bridge.property(0x8801, .{ .template = false, .readonly = true });
    pub const STENCIL_BACK_PASS_DEPTH_FAIL = bridge.property(0x8802, .{ .template = false, .readonly = true });
    pub const STENCIL_BACK_PASS_DEPTH_PASS = bridge.property(0x8803, .{ .template = false, .readonly = true });
    pub const STENCIL_BACK_REF = bridge.property(0x8CA3, .{ .template = false, .readonly = true });
    pub const STENCIL_BACK_VALUE_MASK = bridge.property(0x8CA4, .{ .template = false, .readonly = true });
    pub const STENCIL_BACK_WRITEMASK = bridge.property(0x8CA5, .{ .template = false, .readonly = true });
    pub const VIEWPORT = bridge.property(0xBA2, .{ .template = false, .readonly = true });
    pub const SCISSOR_BOX = bridge.property(0xC10, .{ .template = false, .readonly = true });
    pub const COLOR_CLEAR_VALUE = bridge.property(0xC22, .{ .template = false, .readonly = true });
    pub const COLOR_WRITEMASK = bridge.property(0xC23, .{ .template = false, .readonly = true });
    pub const UNPACK_ALIGNMENT = bridge.property(0xCF5, .{ .template = false, .readonly = true });
    pub const PACK_ALIGNMENT = bridge.property(0xD05, .{ .template = false, .readonly = true });
    pub const MAX_TEXTURE_SIZE = bridge.property(0xD33, .{ .template = false, .readonly = true });
    pub const MAX_VIEWPORT_DIMS = bridge.property(0xD3A, .{ .template = false, .readonly = true });
    pub const SUBPIXEL_BITS = bridge.property(0xD50, .{ .template = false, .readonly = true });
    pub const RED_BITS = bridge.property(0xD52, .{ .template = false, .readonly = true });
    pub const GREEN_BITS = bridge.property(0xD53, .{ .template = false, .readonly = true });
    pub const BLUE_BITS = bridge.property(0xD54, .{ .template = false, .readonly = true });
    pub const ALPHA_BITS = bridge.property(0xD55, .{ .template = false, .readonly = true });
    pub const DEPTH_BITS = bridge.property(0xD56, .{ .template = false, .readonly = true });
    pub const STENCIL_BITS = bridge.property(0xD57, .{ .template = false, .readonly = true });
    pub const POLYGON_OFFSET_UNITS = bridge.property(0x2A00, .{ .template = false, .readonly = true });
    pub const POLYGON_OFFSET_FACTOR = bridge.property(0x8038, .{ .template = false, .readonly = true });
    pub const TEXTURE_BINDING_2D = bridge.property(0x8069, .{ .template = false, .readonly = true });
    pub const SAMPLE_BUFFERS = bridge.property(0x80A8, .{ .template = false, .readonly = true });
    pub const SAMPLES = bridge.property(0x80A9, .{ .template = false, .readonly = true });
    pub const SAMPLE_COVERAGE_VALUE = bridge.property(0x80AA, .{ .template = false, .readonly = true });
    pub const SAMPLE_COVERAGE_INVERT = bridge.property(0x80AB, .{ .template = false, .readonly = true });
    pub const COMPRESSED_TEXTURE_FORMATS = bridge.property(0x86A3, .{ .template = false, .readonly = true });
    pub const NUM_COMPRESSED_TEXTURE_FORMATS = bridge.property(0x86A2, .{ .template = false, .readonly = true });
    pub const DONT_CARE = bridge.property(0x1100, .{ .template = false, .readonly = true });
    pub const FASTEST = bridge.property(0x1101, .{ .template = false, .readonly = true });
    pub const NICEST = bridge.property(0x1102, .{ .template = false, .readonly = true });
    pub const GENERATE_MIPMAP_HINT = bridge.property(0x8192, .{ .template = false, .readonly = true });
    pub const BYTE = bridge.property(0x1400, .{ .template = false, .readonly = true });
    pub const UNSIGNED_BYTE = bridge.property(0x1401, .{ .template = false, .readonly = true });
    pub const SHORT = bridge.property(0x1402, .{ .template = false, .readonly = true });
    pub const UNSIGNED_SHORT = bridge.property(0x1403, .{ .template = false, .readonly = true });
    pub const INT = bridge.property(0x1404, .{ .template = false, .readonly = true });
    pub const UNSIGNED_INT = bridge.property(0x1405, .{ .template = false, .readonly = true });
    pub const FLOAT = bridge.property(0x1406, .{ .template = false, .readonly = true });
    pub const DEPTH_COMPONENT = bridge.property(0x1902, .{ .template = false, .readonly = true });
    pub const ALPHA = bridge.property(0x1906, .{ .template = false, .readonly = true });
    pub const RGB = bridge.property(0x1907, .{ .template = false, .readonly = true });
    pub const RGBA = bridge.property(0x1908, .{ .template = false, .readonly = true });
    pub const LUMINANCE = bridge.property(0x1909, .{ .template = false, .readonly = true });
    pub const LUMINANCE_ALPHA = bridge.property(0x190A, .{ .template = false, .readonly = true });
    pub const UNSIGNED_SHORT_4_4_4_4 = bridge.property(0x8033, .{ .template = false, .readonly = true });
    pub const UNSIGNED_SHORT_5_5_5_1 = bridge.property(0x8034, .{ .template = false, .readonly = true });
    pub const UNSIGNED_SHORT_5_6_5 = bridge.property(0x8363, .{ .template = false, .readonly = true });
    pub const FRAGMENT_SHADER = bridge.property(0x8B30, .{ .template = false, .readonly = true });
    pub const VERTEX_SHADER = bridge.property(0x8B31, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_ATTRIBS = bridge.property(0x8869, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_UNIFORM_VECTORS = bridge.property(0x8DFB, .{ .template = false, .readonly = true });
    pub const MAX_VARYING_VECTORS = bridge.property(0x8DFC, .{ .template = false, .readonly = true });
    pub const MAX_COMBINED_TEXTURE_IMAGE_UNITS = bridge.property(0x8B4D, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_TEXTURE_IMAGE_UNITS = bridge.property(0x8B4C, .{ .template = false, .readonly = true });
    pub const MAX_TEXTURE_IMAGE_UNITS = bridge.property(0x8872, .{ .template = false, .readonly = true });
    pub const MAX_FRAGMENT_UNIFORM_VECTORS = bridge.property(0x8DFD, .{ .template = false, .readonly = true });
    pub const SHADER_TYPE = bridge.property(0x8B4F, .{ .template = false, .readonly = true });
    pub const DELETE_STATUS = bridge.property(0x8B80, .{ .template = false, .readonly = true });
    pub const LINK_STATUS = bridge.property(0x8B82, .{ .template = false, .readonly = true });
    pub const VALIDATE_STATUS = bridge.property(0x8B83, .{ .template = false, .readonly = true });
    pub const ATTACHED_SHADERS = bridge.property(0x8B85, .{ .template = false, .readonly = true });
    pub const ACTIVE_UNIFORMS = bridge.property(0x8B86, .{ .template = false, .readonly = true });
    pub const ACTIVE_ATTRIBUTES = bridge.property(0x8B89, .{ .template = false, .readonly = true });
    pub const SHADING_LANGUAGE_VERSION = bridge.property(0x8B8C, .{ .template = false, .readonly = true });
    pub const CURRENT_PROGRAM = bridge.property(0x8B8D, .{ .template = false, .readonly = true });
    pub const COMPILE_STATUS = bridge.property(0x8B81, .{ .template = false, .readonly = true });
    pub const NEVER = bridge.property(0x200, .{ .template = false, .readonly = true });
    pub const LESS = bridge.property(0x201, .{ .template = false, .readonly = true });
    pub const EQUAL = bridge.property(0x202, .{ .template = false, .readonly = true });
    pub const LEQUAL = bridge.property(0x203, .{ .template = false, .readonly = true });
    pub const GREATER = bridge.property(0x204, .{ .template = false, .readonly = true });
    pub const NOTEQUAL = bridge.property(0x205, .{ .template = false, .readonly = true });
    pub const GEQUAL = bridge.property(0x206, .{ .template = false, .readonly = true });
    pub const ALWAYS = bridge.property(0x207, .{ .template = false, .readonly = true });
    pub const KEEP = bridge.property(0x1E00, .{ .template = false, .readonly = true });
    pub const REPLACE = bridge.property(0x1E01, .{ .template = false, .readonly = true });
    pub const INCR = bridge.property(0x1E02, .{ .template = false, .readonly = true });
    pub const DECR = bridge.property(0x1E03, .{ .template = false, .readonly = true });
    pub const INVERT = bridge.property(0x150A, .{ .template = false, .readonly = true });
    pub const INCR_WRAP = bridge.property(0x8507, .{ .template = false, .readonly = true });
    pub const DECR_WRAP = bridge.property(0x8508, .{ .template = false, .readonly = true });
    pub const VENDOR = bridge.property(0x1F00, .{ .template = false, .readonly = true });
    pub const RENDERER = bridge.property(0x1F01, .{ .template = false, .readonly = true });
    pub const VERSION = bridge.property(0x1F02, .{ .template = false, .readonly = true });
    pub const NEAREST = bridge.property(0x2600, .{ .template = false, .readonly = true });
    pub const LINEAR = bridge.property(0x2601, .{ .template = false, .readonly = true });
    pub const NEAREST_MIPMAP_NEAREST = bridge.property(0x2700, .{ .template = false, .readonly = true });
    pub const LINEAR_MIPMAP_NEAREST = bridge.property(0x2701, .{ .template = false, .readonly = true });
    pub const NEAREST_MIPMAP_LINEAR = bridge.property(0x2702, .{ .template = false, .readonly = true });
    pub const LINEAR_MIPMAP_LINEAR = bridge.property(0x2703, .{ .template = false, .readonly = true });
    pub const TEXTURE_MAG_FILTER = bridge.property(0x2800, .{ .template = false, .readonly = true });
    pub const TEXTURE_MIN_FILTER = bridge.property(0x2801, .{ .template = false, .readonly = true });
    pub const TEXTURE_WRAP_S = bridge.property(0x2802, .{ .template = false, .readonly = true });
    pub const TEXTURE_WRAP_T = bridge.property(0x2803, .{ .template = false, .readonly = true });
    pub const TEXTURE_2D = bridge.property(0xDE1, .{ .template = false, .readonly = true });
    pub const TEXTURE = bridge.property(0x1702, .{ .template = false, .readonly = true });
    pub const TEXTURE_CUBE_MAP = bridge.property(0x8513, .{ .template = false, .readonly = true });
    pub const TEXTURE_BINDING_CUBE_MAP = bridge.property(0x8514, .{ .template = false, .readonly = true });
    pub const TEXTURE_CUBE_MAP_POSITIVE_X = bridge.property(0x8515, .{ .template = false, .readonly = true });
    pub const TEXTURE_CUBE_MAP_NEGATIVE_X = bridge.property(0x8516, .{ .template = false, .readonly = true });
    pub const TEXTURE_CUBE_MAP_POSITIVE_Y = bridge.property(0x8517, .{ .template = false, .readonly = true });
    pub const TEXTURE_CUBE_MAP_NEGATIVE_Y = bridge.property(0x8518, .{ .template = false, .readonly = true });
    pub const TEXTURE_CUBE_MAP_POSITIVE_Z = bridge.property(0x8519, .{ .template = false, .readonly = true });
    pub const TEXTURE_CUBE_MAP_NEGATIVE_Z = bridge.property(0x851A, .{ .template = false, .readonly = true });
    pub const MAX_CUBE_MAP_TEXTURE_SIZE = bridge.property(0x851C, .{ .template = false, .readonly = true });
    pub const ACTIVE_TEXTURE = bridge.property(0x84E0, .{ .template = false, .readonly = true });
    pub const REPEAT = bridge.property(0x2901, .{ .template = false, .readonly = true });
    pub const CLAMP_TO_EDGE = bridge.property(0x812F, .{ .template = false, .readonly = true });
    pub const MIRRORED_REPEAT = bridge.property(0x8370, .{ .template = false, .readonly = true });
    pub const FLOAT_VEC2 = bridge.property(0x8B50, .{ .template = false, .readonly = true });
    pub const FLOAT_VEC3 = bridge.property(0x8B51, .{ .template = false, .readonly = true });
    pub const FLOAT_VEC4 = bridge.property(0x8B52, .{ .template = false, .readonly = true });
    pub const INT_VEC2 = bridge.property(0x8B53, .{ .template = false, .readonly = true });
    pub const INT_VEC3 = bridge.property(0x8B54, .{ .template = false, .readonly = true });
    pub const INT_VEC4 = bridge.property(0x8B55, .{ .template = false, .readonly = true });
    pub const BOOL = bridge.property(0x8B56, .{ .template = false, .readonly = true });
    pub const BOOL_VEC2 = bridge.property(0x8B57, .{ .template = false, .readonly = true });
    pub const BOOL_VEC3 = bridge.property(0x8B58, .{ .template = false, .readonly = true });
    pub const BOOL_VEC4 = bridge.property(0x8B59, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT2 = bridge.property(0x8B5A, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT3 = bridge.property(0x8B5B, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT4 = bridge.property(0x8B5C, .{ .template = false, .readonly = true });
    pub const SAMPLER_2D = bridge.property(0x8B5E, .{ .template = false, .readonly = true });
    pub const SAMPLER_CUBE = bridge.property(0x8B60, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_ENABLED = bridge.property(0x8622, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_SIZE = bridge.property(0x8623, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_STRIDE = bridge.property(0x8624, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_TYPE = bridge.property(0x8625, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_NORMALIZED = bridge.property(0x886A, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_POINTER = bridge.property(0x8645, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_BUFFER_BINDING = bridge.property(0x889F, .{ .template = false, .readonly = true });
    pub const IMPLEMENTATION_COLOR_READ_TYPE = bridge.property(0x8B9A, .{ .template = false, .readonly = true });
    pub const IMPLEMENTATION_COLOR_READ_FORMAT = bridge.property(0x8B9B, .{ .template = false, .readonly = true });
    pub const LOW_FLOAT = bridge.property(0x8DF0, .{ .template = false, .readonly = true });
    pub const MEDIUM_FLOAT = bridge.property(0x8DF1, .{ .template = false, .readonly = true });
    pub const HIGH_FLOAT = bridge.property(0x8DF2, .{ .template = false, .readonly = true });
    pub const LOW_INT = bridge.property(0x8DF3, .{ .template = false, .readonly = true });
    pub const MEDIUM_INT = bridge.property(0x8DF4, .{ .template = false, .readonly = true });
    pub const HIGH_INT = bridge.property(0x8DF5, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_UNIFORM_COMPONENTS = bridge.property(0x8B4A, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER = bridge.property(0x8D40, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER = bridge.property(0x8D41, .{ .template = false, .readonly = true });
    pub const RGBA4 = bridge.property(0x8056, .{ .template = false, .readonly = true });
    pub const RGB5_A1 = bridge.property(0x8057, .{ .template = false, .readonly = true });
    pub const RGB565 = bridge.property(0x8D62, .{ .template = false, .readonly = true });
    pub const DEPTH_COMPONENT16 = bridge.property(0x81A5, .{ .template = false, .readonly = true });
    pub const STENCIL_INDEX8 = bridge.property(0x8D48, .{ .template = false, .readonly = true });
    pub const DEPTH_STENCIL = bridge.property(0x84F9, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_WIDTH = bridge.property(0x8D42, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_HEIGHT = bridge.property(0x8D43, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_INTERNAL_FORMAT = bridge.property(0x8D44, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_RED_SIZE = bridge.property(0x8D50, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_GREEN_SIZE = bridge.property(0x8D51, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_BLUE_SIZE = bridge.property(0x8D52, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_ALPHA_SIZE = bridge.property(0x8D53, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_DEPTH_SIZE = bridge.property(0x8D54, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_STENCIL_SIZE = bridge.property(0x8D55, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE = bridge.property(0x8CD0, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_ATTACHMENT_OBJECT_NAME = bridge.property(0x8CD1, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_ATTACHMENT_TEXTURE_LEVEL = bridge.property(0x8CD2, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_ATTACHMENT_TEXTURE_CUBE_MAP_FACE = bridge.property(0x8CD3, .{ .template = false, .readonly = true });
    pub const COLOR_ATTACHMENT0 = bridge.property(0x8CE0, .{ .template = false, .readonly = true });
    pub const DEPTH_ATTACHMENT = bridge.property(0x8D00, .{ .template = false, .readonly = true });
    pub const STENCIL_ATTACHMENT = bridge.property(0x8D20, .{ .template = false, .readonly = true });
    pub const DEPTH_STENCIL_ATTACHMENT = bridge.property(0x821A, .{ .template = false, .readonly = true });
    pub const NONE = bridge.property(0x0, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_COMPLETE = bridge.property(0x8CD5, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_INCOMPLETE_ATTACHMENT = bridge.property(0x8CD6, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT = bridge.property(0x8CD7, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_INCOMPLETE_DIMENSIONS = bridge.property(0x8CD9, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_UNSUPPORTED = bridge.property(0x8CDD, .{ .template = false, .readonly = true });
    pub const FRAMEBUFFER_BINDING = bridge.property(0x8CA6, .{ .template = false, .readonly = true });
    pub const RENDERBUFFER_BINDING = bridge.property(0x8CA7, .{ .template = false, .readonly = true });
    pub const MAX_RENDERBUFFER_SIZE = bridge.property(0x84E8, .{ .template = false, .readonly = true });
    pub const UNPACK_FLIP_Y_WEBGL = bridge.property(0x9240, .{ .template = false, .readonly = true });
    pub const UNPACK_PREMULTIPLY_ALPHA_WEBGL = bridge.property(0x9241, .{ .template = false, .readonly = true });
    pub const CONTEXT_LOST_WEBGL = bridge.property(0x9242, .{ .template = false, .readonly = true });
    pub const UNPACK_COLORSPACE_CONVERSION_WEBGL = bridge.property(0x9243, .{ .template = false, .readonly = true });
    pub const BROWSER_DEFAULT_WEBGL = bridge.property(0x9244, .{ .template = false, .readonly = true });
    pub const TEXTURE0 = bridge.property(0x84C0, .{ .template = false, .readonly = true });
    pub const TEXTURE1 = bridge.property(0x84C1, .{ .template = false, .readonly = true });
    pub const TEXTURE2 = bridge.property(0x84C2, .{ .template = false, .readonly = true });
    pub const TEXTURE3 = bridge.property(0x84C3, .{ .template = false, .readonly = true });
    pub const TEXTURE4 = bridge.property(0x84C4, .{ .template = false, .readonly = true });
    pub const TEXTURE5 = bridge.property(0x84C5, .{ .template = false, .readonly = true });
    pub const TEXTURE6 = bridge.property(0x84C6, .{ .template = false, .readonly = true });
    pub const TEXTURE7 = bridge.property(0x84C7, .{ .template = false, .readonly = true });
    pub const TEXTURE8 = bridge.property(0x84C8, .{ .template = false, .readonly = true });
    pub const TEXTURE9 = bridge.property(0x84C9, .{ .template = false, .readonly = true });
    pub const TEXTURE10 = bridge.property(0x84CA, .{ .template = false, .readonly = true });
    pub const TEXTURE11 = bridge.property(0x84CB, .{ .template = false, .readonly = true });
    pub const TEXTURE12 = bridge.property(0x84CC, .{ .template = false, .readonly = true });
    pub const TEXTURE13 = bridge.property(0x84CD, .{ .template = false, .readonly = true });
    pub const TEXTURE14 = bridge.property(0x84CE, .{ .template = false, .readonly = true });
    pub const TEXTURE15 = bridge.property(0x84CF, .{ .template = false, .readonly = true });
    pub const TEXTURE16 = bridge.property(0x84D0, .{ .template = false, .readonly = true });
    pub const TEXTURE17 = bridge.property(0x84D1, .{ .template = false, .readonly = true });
    pub const TEXTURE18 = bridge.property(0x84D2, .{ .template = false, .readonly = true });
    pub const TEXTURE19 = bridge.property(0x84D3, .{ .template = false, .readonly = true });
    pub const TEXTURE20 = bridge.property(0x84D4, .{ .template = false, .readonly = true });
    pub const TEXTURE21 = bridge.property(0x84D5, .{ .template = false, .readonly = true });
    pub const TEXTURE22 = bridge.property(0x84D6, .{ .template = false, .readonly = true });
    pub const TEXTURE23 = bridge.property(0x84D7, .{ .template = false, .readonly = true });
    pub const TEXTURE24 = bridge.property(0x84D8, .{ .template = false, .readonly = true });
    pub const TEXTURE25 = bridge.property(0x84D9, .{ .template = false, .readonly = true });
    pub const TEXTURE26 = bridge.property(0x84DA, .{ .template = false, .readonly = true });
    pub const TEXTURE27 = bridge.property(0x84DB, .{ .template = false, .readonly = true });
    pub const TEXTURE28 = bridge.property(0x84DC, .{ .template = false, .readonly = true });
    pub const TEXTURE29 = bridge.property(0x84DD, .{ .template = false, .readonly = true });
    pub const TEXTURE30 = bridge.property(0x84DE, .{ .template = false, .readonly = true });
    pub const TEXTURE31 = bridge.property(0x84DF, .{ .template = false, .readonly = true });
    pub const TRUE = bridge.property(0x1, .{ .template = false, .readonly = true });
    pub const FALSE = bridge.property(0x0, .{ .template = false, .readonly = true });
};

// getContext('web-gl') currently returns null, so this cannot be tested
// const testing = @import("../../../testing.zig");
// test "WebApi: WebGLRenderingContext" {
//     try testing.htmlRunner("canvas/webgl_rendering_context.html", .{});
// }
