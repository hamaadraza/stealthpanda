// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.
//
//! canvas.getContext("webgl2") -> WebGL2RenderingContext. Desktop Chrome (>=56)
//! exposes WebGL2; the type's absence and getContext("webgl2") returning a
//! WebGL1 context are both bot tells (the Cloudflare Turnstile attestation
//! probes `window.WebGL2RenderingContext`). Per the WebGL2 IDL, this is NOT a
//! subclass of WebGLRenderingContext -- both implement WebGLRenderingContextBase
//! as a mixin, so `gl2 instanceof WebGLRenderingContext` is FALSE and every base
//! method/constant is an OWN member of this prototype. We therefore mirror the
//! full WebGL1 surface here (delegating stateful calls to an embedded base
//! context) and add the WebGL2-only methods, constants and getParameter limits.
//! Like WebGL1 this is a report/param spoof, not a real renderer -- see
//! WebGLRenderingContext.zig and .ai/FORK.md.

const std = @import("std");

const js = @import("../../js/js.zig");
const Frame = @import("../../Frame.zig");
const Canvas = @import("../element/html/Canvas.zig");
const OffscreenCanvas = @import("OffscreenCanvas.zig");
const Base = @import("WebGLRenderingContext.zig");
const Execution = js.Execution;

const WebGL2RenderingContext = @This();

// Embedded WebGL1 base context. Holds the shared state (_seed/_canvas/
// _offscreen) and backs every mirrored base method by delegation. It is never
// wrapped as a JS object on its own, so its offset-0 position does not alias
// this context in the identity map.
_gl: Base = .{},

inline fn base(self: *const WebGL2RenderingContext) *const Base {
    return &self._gl;
}

pub fn registerTypes() []const type {
    return &.{
        WebGL2RenderingContext,
        WebGLVertexArrayObject,
        WebGLSampler,
        WebGLSync,
        WebGLQuery,
        WebGLTransformFeedback,
    };
}

// WebGL2-only opaque handle objects (same rationale as the WebGL1 handles).
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
pub const WebGLVertexArrayObject = Handle("WebGLVertexArrayObject");
pub const WebGLSampler = Handle("WebGLSampler");
pub const WebGLSync = Handle("WebGLSync");
pub const WebGLQuery = Handle("WebGLQuery");
pub const WebGLTransformFeedback = Handle("WebGLTransformFeedback");

// A no-op backing every state-changing WebGL1+WebGL2 call (args ignored via
// `.noop = true`).
fn gl2Noop(_: *const WebGL2RenderingContext) void {}
fn gl2IsObject(_: *const WebGL2RenderingContext, _: js.Value) bool {
    return true;
}

// getParameter: WebGL2 adds limits and updates VERSION / SHADING_LANGUAGE_VERSION;
// everything else delegates to the base implementation.
pub fn getParameter(self: *const WebGL2RenderingContext, pname: u32, exec: *const Execution) !js.Value {
    const local = exec.js.local.?;
    return switch (pname) {
        0x1F02 => local.zigValueToJs(@as([]const u8, "WebGL 2.0 (OpenGL ES 3.0 Chromium)"), .{}), // VERSION
        0x8B8C => local.zigValueToJs(@as([]const u8, "WebGL GLSL ES 3.00 (OpenGL ES GLSL ES 3.0 Chromium)"), .{}), // SHADING_LANGUAGE_VERSION
        0x8073 => local.zigValueToJs(@as(u32, 2048), .{}),
        0x88FF => local.zigValueToJs(@as(u32, 2048), .{}),
        0x8CDF => local.zigValueToJs(@as(u32, 8), .{}),
        0x8824 => local.zigValueToJs(@as(u32, 8), .{}),
        0x80E9 => local.zigValueToJs(@as(u32, 150000000), .{}),
        0x80E8 => local.zigValueToJs(@as(u32, 150000000), .{}),
        0x8D57 => local.zigValueToJs(@as(u32, 8), .{}),
        0x8A2F => local.zigValueToJs(@as(u32, 72), .{}),
        0x8A2B => local.zigValueToJs(@as(u32, 14), .{}),
        0x8A2D => local.zigValueToJs(@as(u32, 14), .{}),
        0x8A2E => local.zigValueToJs(@as(u32, 28), .{}),
        0x8A30 => local.zigValueToJs(@as(u32, 65536), .{}),
        0x8A28 => local.zigValueToJs(@as(u32, 256), .{}),
        0x8B49 => local.zigValueToJs(@as(u32, 4096), .{}),
        0x8B4A => local.zigValueToJs(@as(u32, 4096), .{}),
        0x9122 => local.zigValueToJs(@as(u32, 64), .{}),
        0x9125 => local.zigValueToJs(@as(u32, 60), .{}),
        0x8DDF => local.zigValueToJs(@as(u32, 4), .{}),
        0x8904 => local.zigValueToJs(@as(i32, -8), .{}),
        0x8C80 => local.zigValueToJs(@as(u32, 4), .{}),
        0x8C8B => local.zigValueToJs(@as(u32, 4), .{}),
        0x8C8A => local.zigValueToJs(@as(u32, 64), .{}),
        0x9111 => local.zigValueToJs(@as(u32, 0), .{}),
        else => Base.getParameter(self.base(), pname, exec),
    };
}

// --- base surface, mirrored by delegation (self._gl) ---
pub fn getExtension(self: *const WebGL2RenderingContext, name: []const u8, exec: *const Execution) !?Base.Extension {
    return Base.getExtension(self.base(), name, exec);
}
pub fn getSupportedExtensions(self: *const WebGL2RenderingContext) []const []const u8 {
    return Base.getSupportedExtensions(self.base());
}
pub fn getContextAttributes(self: *const WebGL2RenderingContext) @TypeOf(Base.getContextAttributes(undefined)) {
    return Base.getContextAttributes(self.base());
}
pub fn getShaderPrecisionFormat(self: *const WebGL2RenderingContext, a: u32, b: u32) @TypeOf(Base.getShaderPrecisionFormat(undefined, 0, 0)) {
    return Base.getShaderPrecisionFormat(self.base(), a, b);
}
pub fn getCanvas(self: *const WebGL2RenderingContext, exec: *const Execution) !js.Value {
    return Base.getCanvas(self.base(), exec);
}
pub fn getDrawingBufferWidth(self: *const WebGL2RenderingContext) u32 {
    return Base.getDrawingBufferWidth(self.base());
}
pub fn getDrawingBufferHeight(self: *const WebGL2RenderingContext) u32 {
    return Base.getDrawingBufferHeight(self.base());
}
pub fn getDrawingBufferColorSpace(self: *const WebGL2RenderingContext) []const u8 {
    return Base.getDrawingBufferColorSpace(self.base());
}
pub fn setDrawingBufferColorSpace(_: *WebGL2RenderingContext, _: []const u8) void {}
pub fn getUnpackColorSpace(self: *const WebGL2RenderingContext) []const u8 {
    return Base.getUnpackColorSpace(self.base());
}
pub fn setUnpackColorSpace(_: *WebGL2RenderingContext, _: []const u8) void {}
pub fn createShader(self: *const WebGL2RenderingContext, v: js.Value, frame: *Frame) !*Base.WebGLShader {
    return Base.createShader(self.base(), v, frame);
}
pub fn createProgram(self: *const WebGL2RenderingContext, frame: *Frame) !*Base.WebGLProgram {
    return Base.createProgram(self.base(), frame);
}
pub fn createBuffer(self: *const WebGL2RenderingContext, frame: *Frame) !*Base.WebGLBuffer {
    return Base.createBuffer(self.base(), frame);
}
pub fn createTexture(self: *const WebGL2RenderingContext, frame: *Frame) !*Base.WebGLTexture {
    return Base.createTexture(self.base(), frame);
}
pub fn createFramebuffer(self: *const WebGL2RenderingContext, frame: *Frame) !*Base.WebGLFramebuffer {
    return Base.createFramebuffer(self.base(), frame);
}
pub fn createRenderbuffer(self: *const WebGL2RenderingContext, frame: *Frame) !*Base.WebGLRenderbuffer {
    return Base.createRenderbuffer(self.base(), frame);
}
pub fn getUniformLocation(self: *const WebGL2RenderingContext, a: js.Value, b: js.Value, frame: *Frame) !*Base.WebGLUniformLocation {
    return Base.getUniformLocation(self.base(), a, b, frame);
}
pub fn getAttribLocation(self: *const WebGL2RenderingContext, a: js.Value, b: js.Value) i32 {
    return Base.getAttribLocation(self.base(), a, b);
}
pub fn getError(self: *const WebGL2RenderingContext) u32 {
    return Base.getError(self.base());
}
pub fn getShaderParameter(self: *const WebGL2RenderingContext, a: js.Value, b: js.Value) bool {
    return Base.getShaderParameter(self.base(), a, b);
}
pub fn getProgramParameter(self: *const WebGL2RenderingContext, a: js.Value, b: js.Value) bool {
    return Base.getProgramParameter(self.base(), a, b);
}
pub fn getShaderInfoLog(self: *const WebGL2RenderingContext, v: js.Value) []const u8 {
    return Base.getShaderInfoLog(self.base(), v);
}
pub fn getProgramInfoLog(self: *const WebGL2RenderingContext, v: js.Value) []const u8 {
    return Base.getProgramInfoLog(self.base(), v);
}
pub fn getShaderSource(self: *const WebGL2RenderingContext, v: js.Value) []const u8 {
    return Base.getShaderSource(self.base(), v);
}
pub fn checkFramebufferStatus(self: *const WebGL2RenderingContext, v: js.Value) u32 {
    return Base.checkFramebufferStatus(self.base(), v);
}
pub fn isContextLost(self: *const WebGL2RenderingContext) bool {
    return Base.isContextLost(self.base());
}
pub fn isEnabled(self: *const WebGL2RenderingContext, v: js.Value) bool {
    return Base.isEnabled(self.base(), v);
}
pub fn glIsObject(self: *const WebGL2RenderingContext, v: js.Value) bool {
    return Base.glIsObject(self.base(), v);
}
pub fn readPixels(self: *const WebGL2RenderingContext, a: js.Value, b: js.Value, c: js.Value, d: js.Value, e: js.Value, f: js.Value, pixels: js.Object) !void {
    return Base.readPixels(self.base(), a, b, c, d, e, f, pixels);
}

// --- WebGL2-only handle factories + predicates ---
pub fn createVertexArray(_: *const WebGL2RenderingContext, frame: *Frame) !*WebGLVertexArrayObject {
    return frame._factory.create(WebGLVertexArrayObject{});
}
pub fn createSampler(_: *const WebGL2RenderingContext, frame: *Frame) !*WebGLSampler {
    return frame._factory.create(WebGLSampler{});
}
pub fn createQuery(_: *const WebGL2RenderingContext, frame: *Frame) !*WebGLQuery {
    return frame._factory.create(WebGLQuery{});
}
pub fn createTransformFeedback(_: *const WebGL2RenderingContext, frame: *Frame) !*WebGLTransformFeedback {
    return frame._factory.create(WebGLTransformFeedback{});
}
pub fn fenceSync(_: *const WebGL2RenderingContext, frame: *Frame) !*WebGLSync {
    return frame._factory.create(WebGLSync{});
}
pub fn clientWaitSync(_: *const WebGL2RenderingContext, _: js.Value, _: js.Value, _: js.Value) u32 {
    return 0x911A; // ALREADY_SIGNALED
}
pub fn getUniformBlockIndex(_: *const WebGL2RenderingContext, _: js.Value, _: js.Value) u32 {
    return 0;
}
pub fn getFragDataLocation(_: *const WebGL2RenderingContext, _: js.Value, _: js.Value) i32 {
    return 0;
}
pub fn getActiveUniformBlockName(_: *const WebGL2RenderingContext, _: js.Value, _: js.Value) []const u8 {
    return "";
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(WebGL2RenderingContext);

    pub const Meta = struct {
        pub const name = "WebGL2RenderingContext";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    // --- mirrored base methods ---
    pub const getParameter = bridge.function(WebGL2RenderingContext.getParameter, .{});
    pub const getExtension = bridge.function(WebGL2RenderingContext.getExtension, .{});
    pub const getSupportedExtensions = bridge.function(WebGL2RenderingContext.getSupportedExtensions, .{});
    pub const getContextAttributes = bridge.function(WebGL2RenderingContext.getContextAttributes, .{});
    pub const getShaderPrecisionFormat = bridge.function(WebGL2RenderingContext.getShaderPrecisionFormat, .{});
    pub const canvas = bridge.accessor(WebGL2RenderingContext.getCanvas, null, .{});
    pub const drawingBufferWidth = bridge.accessor(WebGL2RenderingContext.getDrawingBufferWidth, null, .{});
    pub const drawingBufferHeight = bridge.accessor(WebGL2RenderingContext.getDrawingBufferHeight, null, .{});
    pub const drawingBufferColorSpace = bridge.accessor(WebGL2RenderingContext.getDrawingBufferColorSpace, WebGL2RenderingContext.setDrawingBufferColorSpace, .{});
    pub const unpackColorSpace = bridge.accessor(WebGL2RenderingContext.getUnpackColorSpace, WebGL2RenderingContext.setUnpackColorSpace, .{});
    pub const createShader = bridge.function(WebGL2RenderingContext.createShader, .{});
    pub const createProgram = bridge.function(WebGL2RenderingContext.createProgram, .{});
    pub const createBuffer = bridge.function(WebGL2RenderingContext.createBuffer, .{});
    pub const createTexture = bridge.function(WebGL2RenderingContext.createTexture, .{});
    pub const createFramebuffer = bridge.function(WebGL2RenderingContext.createFramebuffer, .{});
    pub const createRenderbuffer = bridge.function(WebGL2RenderingContext.createRenderbuffer, .{});
    pub const getUniformLocation = bridge.function(WebGL2RenderingContext.getUniformLocation, .{});
    pub const getAttribLocation = bridge.function(WebGL2RenderingContext.getAttribLocation, .{});
    pub const getError = bridge.function(WebGL2RenderingContext.getError, .{});
    pub const getShaderParameter = bridge.function(WebGL2RenderingContext.getShaderParameter, .{});
    pub const getProgramParameter = bridge.function(WebGL2RenderingContext.getProgramParameter, .{});
    pub const getShaderInfoLog = bridge.function(WebGL2RenderingContext.getShaderInfoLog, .{});
    pub const getProgramInfoLog = bridge.function(WebGL2RenderingContext.getProgramInfoLog, .{});
    pub const getShaderSource = bridge.function(WebGL2RenderingContext.getShaderSource, .{});
    pub const checkFramebufferStatus = bridge.function(WebGL2RenderingContext.checkFramebufferStatus, .{});
    pub const isContextLost = bridge.function(WebGL2RenderingContext.isContextLost, .{});
    pub const isEnabled = bridge.function(WebGL2RenderingContext.isEnabled, .{});
    pub const isBuffer = bridge.function(WebGL2RenderingContext.glIsObject, .{});
    pub const isProgram = bridge.function(WebGL2RenderingContext.glIsObject, .{});
    pub const isShader = bridge.function(WebGL2RenderingContext.glIsObject, .{});
    pub const isTexture = bridge.function(WebGL2RenderingContext.glIsObject, .{});
    pub const isFramebuffer = bridge.function(WebGL2RenderingContext.glIsObject, .{});
    pub const isRenderbuffer = bridge.function(WebGL2RenderingContext.glIsObject, .{});
    pub const readPixels = bridge.function(WebGL2RenderingContext.readPixels, .{});

    // --- WebGL2 handle factories / predicates / small returns ---
    pub const createVertexArray = bridge.function(WebGL2RenderingContext.createVertexArray, .{});
    pub const createSampler = bridge.function(WebGL2RenderingContext.createSampler, .{});
    pub const createQuery = bridge.function(WebGL2RenderingContext.createQuery, .{});
    pub const createTransformFeedback = bridge.function(WebGL2RenderingContext.createTransformFeedback, .{});
    pub const fenceSync = bridge.function(WebGL2RenderingContext.fenceSync, .{});
    pub const isVertexArray = bridge.function(WebGL2RenderingContext.gl2IsObject, .{});
    pub const isSampler = bridge.function(WebGL2RenderingContext.gl2IsObject, .{});
    pub const isSync = bridge.function(WebGL2RenderingContext.gl2IsObject, .{});
    pub const isQuery = bridge.function(WebGL2RenderingContext.gl2IsObject, .{});
    pub const isTransformFeedback = bridge.function(WebGL2RenderingContext.gl2IsObject, .{});
    pub const clientWaitSync = bridge.function(WebGL2RenderingContext.clientWaitSync, .{});
    pub const getUniformBlockIndex = bridge.function(WebGL2RenderingContext.getUniformBlockIndex, .{});
    pub const getFragDataLocation = bridge.function(WebGL2RenderingContext.getFragDataLocation, .{});
    pub const getActiveUniformBlockName = bridge.function(WebGL2RenderingContext.getActiveUniformBlockName, .{});

    // --- mirrored base no-op render stubs ---
    pub const activeTexture = bridge.function(gl2Noop, .{ .noop = true });
    pub const attachShader = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindAttribLocation = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindBuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindFramebuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindRenderbuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindTexture = bridge.function(gl2Noop, .{ .noop = true });
    pub const blendColor = bridge.function(gl2Noop, .{ .noop = true });
    pub const blendEquation = bridge.function(gl2Noop, .{ .noop = true });
    pub const blendEquationSeparate = bridge.function(gl2Noop, .{ .noop = true });
    pub const blendFunc = bridge.function(gl2Noop, .{ .noop = true });
    pub const blendFuncSeparate = bridge.function(gl2Noop, .{ .noop = true });
    pub const bufferData = bridge.function(gl2Noop, .{ .noop = true });
    pub const bufferSubData = bridge.function(gl2Noop, .{ .noop = true });
    pub const clear = bridge.function(gl2Noop, .{ .noop = true });
    pub const clearColor = bridge.function(gl2Noop, .{ .noop = true });
    pub const clearDepth = bridge.function(gl2Noop, .{ .noop = true });
    pub const clearStencil = bridge.function(gl2Noop, .{ .noop = true });
    pub const colorMask = bridge.function(gl2Noop, .{ .noop = true });
    pub const compileShader = bridge.function(gl2Noop, .{ .noop = true });
    pub const copyTexImage2D = bridge.function(gl2Noop, .{ .noop = true });
    pub const copyTexSubImage2D = bridge.function(gl2Noop, .{ .noop = true });
    pub const cullFace = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteBuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteFramebuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteProgram = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteRenderbuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteShader = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteTexture = bridge.function(gl2Noop, .{ .noop = true });
    pub const depthFunc = bridge.function(gl2Noop, .{ .noop = true });
    pub const depthMask = bridge.function(gl2Noop, .{ .noop = true });
    pub const depthRange = bridge.function(gl2Noop, .{ .noop = true });
    pub const detachShader = bridge.function(gl2Noop, .{ .noop = true });
    pub const disable = bridge.function(gl2Noop, .{ .noop = true });
    pub const disableVertexAttribArray = bridge.function(gl2Noop, .{ .noop = true });
    pub const drawArrays = bridge.function(gl2Noop, .{ .noop = true });
    pub const drawElements = bridge.function(gl2Noop, .{ .noop = true });
    pub const enable = bridge.function(gl2Noop, .{ .noop = true });
    pub const enableVertexAttribArray = bridge.function(gl2Noop, .{ .noop = true });
    pub const finish = bridge.function(gl2Noop, .{ .noop = true });
    pub const flush = bridge.function(gl2Noop, .{ .noop = true });
    pub const framebufferRenderbuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const framebufferTexture2D = bridge.function(gl2Noop, .{ .noop = true });
    pub const frontFace = bridge.function(gl2Noop, .{ .noop = true });
    pub const generateMipmap = bridge.function(gl2Noop, .{ .noop = true });
    pub const hint = bridge.function(gl2Noop, .{ .noop = true });
    pub const lineWidth = bridge.function(gl2Noop, .{ .noop = true });
    pub const linkProgram = bridge.function(gl2Noop, .{ .noop = true });
    pub const pixelStorei = bridge.function(gl2Noop, .{ .noop = true });
    pub const polygonOffset = bridge.function(gl2Noop, .{ .noop = true });
    pub const renderbufferStorage = bridge.function(gl2Noop, .{ .noop = true });
    pub const sampleCoverage = bridge.function(gl2Noop, .{ .noop = true });
    pub const scissor = bridge.function(gl2Noop, .{ .noop = true });
    pub const shaderSource = bridge.function(gl2Noop, .{ .noop = true });
    pub const stencilFunc = bridge.function(gl2Noop, .{ .noop = true });
    pub const stencilFuncSeparate = bridge.function(gl2Noop, .{ .noop = true });
    pub const stencilMask = bridge.function(gl2Noop, .{ .noop = true });
    pub const stencilMaskSeparate = bridge.function(gl2Noop, .{ .noop = true });
    pub const stencilOp = bridge.function(gl2Noop, .{ .noop = true });
    pub const stencilOpSeparate = bridge.function(gl2Noop, .{ .noop = true });
    pub const texImage2D = bridge.function(gl2Noop, .{ .noop = true });
    pub const texParameterf = bridge.function(gl2Noop, .{ .noop = true });
    pub const texParameteri = bridge.function(gl2Noop, .{ .noop = true });
    pub const texSubImage2D = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform1f = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform1fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform1i = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform1iv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform2f = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform2fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform2i = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform2iv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform3f = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform3fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform3i = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform3iv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform4f = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform4fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform4i = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform4iv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix2fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix3fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix4fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const useProgram = bridge.function(gl2Noop, .{ .noop = true });
    pub const validateProgram = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib1f = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib1fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib2f = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib2fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib3f = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib3fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib4f = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttrib4fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttribPointer = bridge.function(gl2Noop, .{ .noop = true });
    pub const viewport = bridge.function(gl2Noop, .{ .noop = true });

    // --- WebGL2-only no-op render stubs ---
    pub const copyBufferSubData = bridge.function(gl2Noop, .{ .noop = true });
    pub const getBufferSubData = bridge.function(gl2Noop, .{ .noop = true });
    pub const blitFramebuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const framebufferTextureLayer = bridge.function(gl2Noop, .{ .noop = true });
    pub const invalidateFramebuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const invalidateSubFramebuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const readBuffer = bridge.function(gl2Noop, .{ .noop = true });
    pub const renderbufferStorageMultisample = bridge.function(gl2Noop, .{ .noop = true });
    pub const texStorage2D = bridge.function(gl2Noop, .{ .noop = true });
    pub const texStorage3D = bridge.function(gl2Noop, .{ .noop = true });
    pub const texImage3D = bridge.function(gl2Noop, .{ .noop = true });
    pub const texSubImage3D = bridge.function(gl2Noop, .{ .noop = true });
    pub const copyTexSubImage3D = bridge.function(gl2Noop, .{ .noop = true });
    pub const compressedTexImage3D = bridge.function(gl2Noop, .{ .noop = true });
    pub const compressedTexSubImage3D = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform1ui = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform2ui = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform3ui = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform4ui = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform1uiv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform2uiv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform3uiv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniform4uiv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix3x2fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix4x2fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix2x3fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix4x3fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix2x4fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformMatrix3x4fv = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttribI4i = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttribI4iv = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttribI4ui = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttribI4uiv = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttribIPointer = bridge.function(gl2Noop, .{ .noop = true });
    pub const vertexAttribDivisor = bridge.function(gl2Noop, .{ .noop = true });
    pub const drawArraysInstanced = bridge.function(gl2Noop, .{ .noop = true });
    pub const drawElementsInstanced = bridge.function(gl2Noop, .{ .noop = true });
    pub const drawRangeElements = bridge.function(gl2Noop, .{ .noop = true });
    pub const drawBuffers = bridge.function(gl2Noop, .{ .noop = true });
    pub const clearBufferfv = bridge.function(gl2Noop, .{ .noop = true });
    pub const clearBufferiv = bridge.function(gl2Noop, .{ .noop = true });
    pub const clearBufferuiv = bridge.function(gl2Noop, .{ .noop = true });
    pub const clearBufferfi = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindBufferBase = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindBufferRange = bridge.function(gl2Noop, .{ .noop = true });
    pub const uniformBlockBinding = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindVertexArray = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteVertexArray = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindTransformFeedback = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteTransformFeedback = bridge.function(gl2Noop, .{ .noop = true });
    pub const beginTransformFeedback = bridge.function(gl2Noop, .{ .noop = true });
    pub const endTransformFeedback = bridge.function(gl2Noop, .{ .noop = true });
    pub const transformFeedbackVaryings = bridge.function(gl2Noop, .{ .noop = true });
    pub const pauseTransformFeedback = bridge.function(gl2Noop, .{ .noop = true });
    pub const resumeTransformFeedback = bridge.function(gl2Noop, .{ .noop = true });
    pub const bindSampler = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteSampler = bridge.function(gl2Noop, .{ .noop = true });
    pub const samplerParameteri = bridge.function(gl2Noop, .{ .noop = true });
    pub const samplerParameterf = bridge.function(gl2Noop, .{ .noop = true });
    pub const beginQuery = bridge.function(gl2Noop, .{ .noop = true });
    pub const endQuery = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteQuery = bridge.function(gl2Noop, .{ .noop = true });
    pub const deleteSync = bridge.function(gl2Noop, .{ .noop = true });
    pub const waitSync = bridge.function(gl2Noop, .{ .noop = true });

    // --- mirrored WebGL 1.0 enum constants (own members, as in Chrome) ---
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

    // --- WebGL2-only enum constants ---
    pub const READ_BUFFER = bridge.property(0x0C02, .{ .template = false, .readonly = true });
    pub const UNPACK_ROW_LENGTH = bridge.property(0x0CF2, .{ .template = false, .readonly = true });
    pub const UNPACK_SKIP_ROWS = bridge.property(0x0CF3, .{ .template = false, .readonly = true });
    pub const UNPACK_SKIP_PIXELS = bridge.property(0x0CF4, .{ .template = false, .readonly = true });
    pub const PACK_ROW_LENGTH = bridge.property(0x0D02, .{ .template = false, .readonly = true });
    pub const PACK_SKIP_ROWS = bridge.property(0x0D03, .{ .template = false, .readonly = true });
    pub const PACK_SKIP_PIXELS = bridge.property(0x0D04, .{ .template = false, .readonly = true });
    pub const COLOR = bridge.property(0x1800, .{ .template = false, .readonly = true });
    pub const DEPTH = bridge.property(0x1801, .{ .template = false, .readonly = true });
    pub const STENCIL = bridge.property(0x1802, .{ .template = false, .readonly = true });
    pub const RED = bridge.property(0x1903, .{ .template = false, .readonly = true });
    pub const RGB8 = bridge.property(0x8051, .{ .template = false, .readonly = true });
    pub const RGBA8 = bridge.property(0x8058, .{ .template = false, .readonly = true });
    pub const RGB10_A2 = bridge.property(0x8059, .{ .template = false, .readonly = true });
    pub const TEXTURE_BINDING_3D = bridge.property(0x806A, .{ .template = false, .readonly = true });
    pub const UNPACK_SKIP_IMAGES = bridge.property(0x806D, .{ .template = false, .readonly = true });
    pub const UNPACK_IMAGE_HEIGHT = bridge.property(0x806E, .{ .template = false, .readonly = true });
    pub const TEXTURE_3D = bridge.property(0x806F, .{ .template = false, .readonly = true });
    pub const TEXTURE_WRAP_R = bridge.property(0x8072, .{ .template = false, .readonly = true });
    pub const MAX_3D_TEXTURE_SIZE = bridge.property(0x8073, .{ .template = false, .readonly = true });
    pub const UNSIGNED_INT_2_10_10_10_REV = bridge.property(0x8368, .{ .template = false, .readonly = true });
    pub const MAX_ELEMENTS_VERTICES = bridge.property(0x80E8, .{ .template = false, .readonly = true });
    pub const MAX_ELEMENTS_INDICES = bridge.property(0x80E9, .{ .template = false, .readonly = true });
    pub const TEXTURE_MIN_LOD = bridge.property(0x813A, .{ .template = false, .readonly = true });
    pub const TEXTURE_MAX_LOD = bridge.property(0x813B, .{ .template = false, .readonly = true });
    pub const TEXTURE_BASE_LEVEL = bridge.property(0x813C, .{ .template = false, .readonly = true });
    pub const TEXTURE_MAX_LEVEL = bridge.property(0x813D, .{ .template = false, .readonly = true });
    pub const MIN = bridge.property(0x8007, .{ .template = false, .readonly = true });
    pub const MAX = bridge.property(0x8008, .{ .template = false, .readonly = true });
    pub const DEPTH_COMPONENT24 = bridge.property(0x81A6, .{ .template = false, .readonly = true });
    pub const MAX_TEXTURE_LOD_BIAS = bridge.property(0x84FD, .{ .template = false, .readonly = true });
    pub const TEXTURE_COMPARE_MODE = bridge.property(0x884C, .{ .template = false, .readonly = true });
    pub const TEXTURE_COMPARE_FUNC = bridge.property(0x884D, .{ .template = false, .readonly = true });
    pub const CURRENT_QUERY = bridge.property(0x8865, .{ .template = false, .readonly = true });
    pub const QUERY_RESULT = bridge.property(0x8866, .{ .template = false, .readonly = true });
    pub const QUERY_RESULT_AVAILABLE = bridge.property(0x8867, .{ .template = false, .readonly = true });
    pub const STREAM_READ = bridge.property(0x88E1, .{ .template = false, .readonly = true });
    pub const STREAM_COPY = bridge.property(0x88E2, .{ .template = false, .readonly = true });
    pub const STATIC_READ = bridge.property(0x88E5, .{ .template = false, .readonly = true });
    pub const STATIC_COPY = bridge.property(0x88E6, .{ .template = false, .readonly = true });
    pub const DYNAMIC_READ = bridge.property(0x88E9, .{ .template = false, .readonly = true });
    pub const DYNAMIC_COPY = bridge.property(0x88EA, .{ .template = false, .readonly = true });
    pub const MAX_DRAW_BUFFERS = bridge.property(0x8824, .{ .template = false, .readonly = true });
    pub const DRAW_BUFFER0 = bridge.property(0x8825, .{ .template = false, .readonly = true });
    pub const DRAW_BUFFER1 = bridge.property(0x8826, .{ .template = false, .readonly = true });
    pub const MAX_FRAGMENT_UNIFORM_COMPONENTS = bridge.property(0x8B49, .{ .template = false, .readonly = true });
    pub const SAMPLER_3D = bridge.property(0x8B5F, .{ .template = false, .readonly = true });
    pub const SAMPLER_2D_SHADOW = bridge.property(0x8B62, .{ .template = false, .readonly = true });
    pub const PIXEL_PACK_BUFFER = bridge.property(0x88EB, .{ .template = false, .readonly = true });
    pub const PIXEL_UNPACK_BUFFER = bridge.property(0x88EC, .{ .template = false, .readonly = true });
    pub const PIXEL_PACK_BUFFER_BINDING = bridge.property(0x88ED, .{ .template = false, .readonly = true });
    pub const PIXEL_UNPACK_BUFFER_BINDING = bridge.property(0x88EF, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT2x3 = bridge.property(0x8B65, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT2x4 = bridge.property(0x8B66, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT3x2 = bridge.property(0x8B67, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT3x4 = bridge.property(0x8B68, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT4x2 = bridge.property(0x8B69, .{ .template = false, .readonly = true });
    pub const FLOAT_MAT4x3 = bridge.property(0x8B6A, .{ .template = false, .readonly = true });
    pub const SRGB = bridge.property(0x8C40, .{ .template = false, .readonly = true });
    pub const SRGB8 = bridge.property(0x8C41, .{ .template = false, .readonly = true });
    pub const SRGB8_ALPHA8 = bridge.property(0x8C43, .{ .template = false, .readonly = true });
    pub const COMPARE_REF_TO_TEXTURE = bridge.property(0x884E, .{ .template = false, .readonly = true });
    pub const RGBA32F = bridge.property(0x8814, .{ .template = false, .readonly = true });
    pub const RGB32F = bridge.property(0x8815, .{ .template = false, .readonly = true });
    pub const RGBA16F = bridge.property(0x881A, .{ .template = false, .readonly = true });
    pub const RGB16F = bridge.property(0x881B, .{ .template = false, .readonly = true });
    pub const VERTEX_ATTRIB_ARRAY_INTEGER = bridge.property(0x88FD, .{ .template = false, .readonly = true });
    pub const MAX_ARRAY_TEXTURE_LAYERS = bridge.property(0x88FF, .{ .template = false, .readonly = true });
    pub const MIN_PROGRAM_TEXEL_OFFSET = bridge.property(0x8904, .{ .template = false, .readonly = true });
    pub const MAX_PROGRAM_TEXEL_OFFSET = bridge.property(0x8905, .{ .template = false, .readonly = true });
    pub const MAX_VARYING_COMPONENTS = bridge.property(0x8B4B, .{ .template = false, .readonly = true });
    pub const TEXTURE_2D_ARRAY = bridge.property(0x8C1A, .{ .template = false, .readonly = true });
    pub const TEXTURE_BINDING_2D_ARRAY = bridge.property(0x8C1D, .{ .template = false, .readonly = true });
    pub const R11F_G11F_B10F = bridge.property(0x8C3A, .{ .template = false, .readonly = true });
    pub const RGB9_E5 = bridge.property(0x8C3D, .{ .template = false, .readonly = true });
    pub const HALF_FLOAT = bridge.property(0x140B, .{ .template = false, .readonly = true });
    pub const RG = bridge.property(0x8227, .{ .template = false, .readonly = true });
    pub const RG_INTEGER = bridge.property(0x8228, .{ .template = false, .readonly = true });
    pub const R8 = bridge.property(0x8229, .{ .template = false, .readonly = true });
    pub const RG8 = bridge.property(0x822B, .{ .template = false, .readonly = true });
    pub const R16F = bridge.property(0x822D, .{ .template = false, .readonly = true });
    pub const R32F = bridge.property(0x822E, .{ .template = false, .readonly = true });
    pub const RG16F = bridge.property(0x822F, .{ .template = false, .readonly = true });
    pub const RG32F = bridge.property(0x8230, .{ .template = false, .readonly = true });
    pub const R8I = bridge.property(0x8231, .{ .template = false, .readonly = true });
    pub const R8UI = bridge.property(0x8232, .{ .template = false, .readonly = true });
    pub const R16I = bridge.property(0x8233, .{ .template = false, .readonly = true });
    pub const R16UI = bridge.property(0x8234, .{ .template = false, .readonly = true });
    pub const R32I = bridge.property(0x8235, .{ .template = false, .readonly = true });
    pub const R32UI = bridge.property(0x8236, .{ .template = false, .readonly = true });
    pub const RG8I = bridge.property(0x8237, .{ .template = false, .readonly = true });
    pub const RG8UI = bridge.property(0x8238, .{ .template = false, .readonly = true });
    pub const RG16I = bridge.property(0x8239, .{ .template = false, .readonly = true });
    pub const RG16UI = bridge.property(0x823A, .{ .template = false, .readonly = true });
    pub const RG32I = bridge.property(0x823B, .{ .template = false, .readonly = true });
    pub const RG32UI = bridge.property(0x823C, .{ .template = false, .readonly = true });
    pub const VERTEX_ARRAY_BINDING = bridge.property(0x85B5, .{ .template = false, .readonly = true });
    pub const R8_SNORM = bridge.property(0x8F94, .{ .template = false, .readonly = true });
    pub const RG8_SNORM = bridge.property(0x8F95, .{ .template = false, .readonly = true });
    pub const RGB8_SNORM = bridge.property(0x8F96, .{ .template = false, .readonly = true });
    pub const RGBA8_SNORM = bridge.property(0x8F97, .{ .template = false, .readonly = true });
    pub const SIGNED_NORMALIZED = bridge.property(0x8F9C, .{ .template = false, .readonly = true });
    pub const COPY_READ_BUFFER = bridge.property(0x8F36, .{ .template = false, .readonly = true });
    pub const COPY_WRITE_BUFFER = bridge.property(0x8F37, .{ .template = false, .readonly = true });
    pub const COPY_READ_BUFFER_BINDING = bridge.property(0x8F36, .{ .template = false, .readonly = true });
    pub const UNIFORM_BUFFER = bridge.property(0x8A11, .{ .template = false, .readonly = true });
    pub const UNIFORM_BUFFER_BINDING = bridge.property(0x8A28, .{ .template = false, .readonly = true });
    pub const UNIFORM_BUFFER_START = bridge.property(0x8A29, .{ .template = false, .readonly = true });
    pub const UNIFORM_BUFFER_SIZE = bridge.property(0x8A2A, .{ .template = false, .readonly = true });
    pub const MAX_VERTEX_UNIFORM_BLOCKS = bridge.property(0x8A2B, .{ .template = false, .readonly = true });
    pub const MAX_FRAGMENT_UNIFORM_BLOCKS = bridge.property(0x8A2D, .{ .template = false, .readonly = true });
    pub const MAX_COMBINED_UNIFORM_BLOCKS = bridge.property(0x8A2E, .{ .template = false, .readonly = true });
    pub const MAX_UNIFORM_BUFFER_BINDINGS = bridge.property(0x8A2F, .{ .template = false, .readonly = true });
    pub const MAX_UNIFORM_BLOCK_SIZE = bridge.property(0x8A30, .{ .template = false, .readonly = true });
    pub const UNIFORM_BUFFER_OFFSET_ALIGNMENT = bridge.property(0x8A34, .{ .template = false, .readonly = true });
    pub const FRAGMENT_SHADER_DERIVATIVE_HINT = bridge.property(0x8B8B, .{ .template = false, .readonly = true });
    pub const MAX_SAMPLES = bridge.property(0x8D57, .{ .template = false, .readonly = true });
    pub const SYNC_GPU_COMMANDS_COMPLETE = bridge.property(0x9117, .{ .template = false, .readonly = true });
    pub const ALREADY_SIGNALED = bridge.property(0x911A, .{ .template = false, .readonly = true });
    pub const TIMEOUT_EXPIRED = bridge.property(0x911B, .{ .template = false, .readonly = true });
    pub const CONDITION_SATISFIED = bridge.property(0x911C, .{ .template = false, .readonly = true });
    pub const WAIT_FAILED = bridge.property(0x911D, .{ .template = false, .readonly = true });
    pub const SYNC_FLUSH_COMMANDS_BIT = bridge.property(0x1, .{ .template = false, .readonly = true });
    pub const COLOR_ATTACHMENT1 = bridge.property(0x8CE1, .{ .template = false, .readonly = true });
    pub const MAX_COLOR_ATTACHMENTS = bridge.property(0x8CDF, .{ .template = false, .readonly = true });
    pub const TRANSFORM_FEEDBACK = bridge.property(0x8E22, .{ .template = false, .readonly = true });
    pub const TRANSFORM_FEEDBACK_BUFFER = bridge.property(0x8C8E, .{ .template = false, .readonly = true });
    pub const TRANSFORM_FEEDBACK_BUFFER_BINDING = bridge.property(0x8C8F, .{ .template = false, .readonly = true });
    pub const INTERLEAVED_ATTRIBS = bridge.property(0x8C8C, .{ .template = false, .readonly = true });
    pub const SEPARATE_ATTRIBS = bridge.property(0x8C8D, .{ .template = false, .readonly = true });
    pub const RASTERIZER_DISCARD = bridge.property(0x8C89, .{ .template = false, .readonly = true });
    pub const SAMPLER_BINDING = bridge.property(0x8919, .{ .template = false, .readonly = true });
    pub const QUERY_RESULT_NO_WAIT = bridge.property(0x9194, .{ .template = false, .readonly = true });
    pub const OBJECT_TYPE = bridge.property(0x9112, .{ .template = false, .readonly = true });
    pub const SYNC_CONDITION = bridge.property(0x9113, .{ .template = false, .readonly = true });
    pub const SYNC_STATUS = bridge.property(0x9114, .{ .template = false, .readonly = true });
    pub const SYNC_FLAGS = bridge.property(0x9115, .{ .template = false, .readonly = true });
    pub const SIGNALED = bridge.property(0x9119, .{ .template = false, .readonly = true });
    pub const UNSIGNALED = bridge.property(0x9118, .{ .template = false, .readonly = true });
    pub const TIMEOUT_IGNORED = bridge.property(0xFFFFFFFF, .{ .template = false, .readonly = true });
    pub const MAX_CLIENT_WAIT_TIMEOUT_WEBGL = bridge.property(0x9247, .{ .template = false, .readonly = true });
};
