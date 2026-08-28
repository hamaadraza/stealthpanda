// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! navigator.mediaCapabilities (MediaCapabilities). Modern Chrome always
//! exposes it; anti-bot scripts (Cloudflare Turnstile) probe it. decodingInfo /
//! encodingInfo answer "supported, smooth, power-efficient" — coherent with a
//! desktop Chrome that can decode common codecs. Only surfaced when
//! impersonating (see Navigator.getMediaCapabilities).

const js = @import("../js/js.zig");
const Execution = js.Execution;

const MediaCapabilities = @This();

_pad: bool = false,

const Info = struct {
    supported: bool = true,
    smooth: bool = true,
    powerEfficient: bool = true,
};

pub fn decodingInfo(_: *MediaCapabilities, _: js.Value, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(Info{});
}

pub fn encodingInfo(_: *MediaCapabilities, _: js.Value, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(Info{});
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(MediaCapabilities);

    pub const Meta = struct {
        pub const name = "MediaCapabilities";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const decodingInfo = bridge.function(MediaCapabilities.decodingInfo, .{});
    pub const encodingInfo = bridge.function(MediaCapabilities.encodingInfo, .{});
};
