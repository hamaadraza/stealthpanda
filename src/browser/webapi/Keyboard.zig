// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! navigator.keyboard (Keyboard API). Desktop Chrome exposes it; its absence
//! under a Chrome user-agent is a bot signal (Cloudflare Turnstile probes
//! `navigator.keyboard`). Minimal, coherent surface: getLayoutMap resolves an
//! (empty) layout map, lock resolves, unlock is a no-op. Only surfaced when
//! impersonating (see Navigator.getKeyboard).

const js = @import("../js/js.zig");
const Execution = js.Execution;

const Keyboard = @This();

_pad: bool = false,

pub fn getLayoutMap(_: *Keyboard, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(struct {}{});
}

pub fn lock(_: *Keyboard, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise({});
}

pub fn unlock(_: *Keyboard) void {}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Keyboard);

    pub const Meta = struct {
        pub const name = "Keyboard";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const getLayoutMap = bridge.function(Keyboard.getLayoutMap, .{});
    pub const lock = bridge.function(Keyboard.lock, .{});
    pub const unlock = bridge.function(Keyboard.unlock, .{});
};
