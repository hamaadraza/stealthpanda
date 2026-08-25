// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! navigator.getBattery() -> BatteryManager (Battery Status API). Desktop Chrome
//! exposes this; its absence under a Chrome user-agent is a bot signal
//! (browserleaks flags "Battery Status API: Disabled"). Reports a plugged-in,
//! fully-charged machine — the standard reading Chrome gives on a desktop with
//! no battery (charging, chargingTime 0, dischargingTime Infinity, level 1).
//! Only surfaced when impersonating (see Navigator.getBattery). A singleton:
//! real Chrome returns the same BatteryManager from every getBattery() call.

const std = @import("std");

const js = @import("../js/js.zig");

const BatteryManager = @This();

// Zero-state; the field just gives the wrapper a non-empty allocation.
_pad: bool = false,

pub fn getCharging(_: *const BatteryManager) bool {
    return true;
}

pub fn getChargingTime(_: *const BatteryManager) f64 {
    return 0;
}

pub fn getDischargingTime(_: *const BatteryManager) f64 {
    // A machine on AC power never discharges -> Infinity, per spec.
    return std.math.inf(f64);
}

pub fn getLevel(_: *const BatteryManager) f64 {
    return 1.0;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(BatteryManager);

    pub const Meta = struct {
        pub const name = "BatteryManager";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const charging = bridge.accessor(BatteryManager.getCharging, null, .{});
    pub const chargingTime = bridge.accessor(BatteryManager.getChargingTime, null, .{});
    pub const dischargingTime = bridge.accessor(BatteryManager.getDischargingTime, null, .{});
    pub const level = bridge.accessor(BatteryManager.getLevel, null, .{});
};
