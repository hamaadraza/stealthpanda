// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! navigator.gpu (WebGPU entry point). Desktop Chrome (>=113) always exposes
//! `navigator.gpu`; its absence under a Chrome user-agent is a well-known
//! headless/bot signal (detectors check `'gpu' in navigator`). We expose the
//! `GPU` object with the two members a probe reads first — `requestAdapter()`
//! and `getPreferredCanvasFormat()` — and resolve `requestAdapter` to `null`,
//! which is exactly what a Chrome build with no usable/allow-listed GPU adapter
//! returns (a common, coherent real-Chrome state). We deliberately do NOT fake
//! a full GPUAdapter graph: a half-built adapter is a louder tell than a null
//! one. Only surfaced when impersonating (see Navigator.getGpu).

const js = @import("../js/js.zig");
const Execution = js.Execution;

const GPU = @This();

_pad: bool = false,

// The canvas format a real Chrome prefers on macOS/Apple GPUs.
pub fn getPreferredCanvasFormat(_: *const GPU) []const u8 {
    return "bgra8unorm";
}

// Resolves to null: Chrome returns a null adapter when no suitable/allow-listed
// GPU is available. Matches headless / GPU-disabled Chrome, and never throws.
pub fn requestAdapter(_: *GPU, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(@as(?u8, null));
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(GPU);

    pub const Meta = struct {
        pub const name = "GPU";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const requestAdapter = bridge.function(GPU.requestAdapter, .{});
    pub const getPreferredCanvasFormat = bridge.function(GPU.getPreferredCanvasFormat, .{});
};
