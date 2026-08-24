// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! navigator.connection (NetworkInformation). Desktop Chrome always exposes it;
//! its absence under a Chrome user-agent is a moderate bot signal. Values are
//! the low-entropy set Chrome reports by default (it clamps rtt/downlink).
//! Only surfaced when impersonating (see Navigator.getConnection).

const js = @import("../js/js.zig");

const NetworkInformation = @This();

_pad: bool = false,

pub fn getEffectiveType(_: *const NetworkInformation) []const u8 {
    return "4g";
}
pub fn getRtt(_: *const NetworkInformation) u32 {
    return 50;
}
pub fn getDownlink(_: *const NetworkInformation) f64 {
    return 10.0;
}
pub fn getSaveData(_: *const NetworkInformation) bool {
    return false;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(NetworkInformation);

    pub const Meta = struct {
        pub const name = "NetworkInformation";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const effectiveType = bridge.accessor(NetworkInformation.getEffectiveType, null, .{});
    pub const rtt = bridge.accessor(NetworkInformation.getRtt, null, .{});
    pub const downlink = bridge.accessor(NetworkInformation.getDownlink, null, .{});
    pub const saveData = bridge.accessor(NetworkInformation.getSaveData, null, .{});
};
