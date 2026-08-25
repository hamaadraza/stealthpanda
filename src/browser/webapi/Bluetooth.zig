// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! navigator.bluetooth (Web Bluetooth API). Present in desktop Chrome (in a
//! secure context); its absence under a Chrome user-agent is a bot signal
//! (browserleaks flags "Web Bluetooth API: Disabled"). getAvailability()
//! resolves true (a machine with a Bluetooth radio, which every modern Mac has);
//! getDevices() resolves an empty list (no site has been granted a device).
//! Only surfaced when impersonating (see Navigator.getBluetooth).

const js = @import("../js/js.zig");
const Execution = js.Execution;

const Bluetooth = @This();

// Zero-state; the field just gives the wrapper a non-empty allocation.
_pad: bool = false,

pub fn getAvailability(_: *const Bluetooth, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(true);
}

pub fn getDevices(_: *const Bluetooth, exec: *const Execution) !js.Promise {
    // No devices have been granted to this origin -> empty JS array.
    const empty: []const []const u8 = &.{};
    return exec.js.local.?.resolvePromise(empty);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Bluetooth);

    pub const Meta = struct {
        pub const name = "Bluetooth";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const getAvailability = bridge.function(Bluetooth.getAvailability, .{});
    pub const getDevices = bridge.function(Bluetooth.getDevices, .{});
};
