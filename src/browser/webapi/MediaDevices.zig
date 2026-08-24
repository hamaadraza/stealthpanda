// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! navigator.mediaDevices (MediaDevices). Absent under a Chrome user-agent is a
//! moderate bot signal. Without granted permission Chrome's enumerateDevices()
//! resolves to one entry per kind with empty deviceId/label; getUserMedia
//! rejects with NotAllowedError. Only surfaced when impersonating.

const js = @import("../js/js.zig");
const Execution = js.Execution;

const MediaDevices = @This();

_pad: bool = false,

const DeviceInfo = struct {
    deviceId: []const u8,
    kind: []const u8,
    label: []const u8,
    groupId: []const u8,
};

pub fn enumerateDevices(_: *const MediaDevices, exec: *const Execution) !js.Promise {
    const devices = [_]DeviceInfo{
        .{ .deviceId = "", .kind = "audioinput", .label = "", .groupId = "" },
        .{ .deviceId = "", .kind = "videoinput", .label = "", .groupId = "" },
        .{ .deviceId = "", .kind = "audiooutput", .label = "", .groupId = "" },
    };
    return exec.js.local.?.resolvePromise(devices);
}

// getSupportedConstraints() — Chrome reports all of these as supported (true).
pub fn getSupportedConstraints(_: *const MediaDevices) struct {
    aspectRatio: bool,
    autoGainControl: bool,
    brightness: bool,
    channelCount: bool,
    colorTemperature: bool,
    contrast: bool,
    deviceId: bool,
    echoCancellation: bool,
    exposureCompensation: bool,
    exposureMode: bool,
    exposureTime: bool,
    facingMode: bool,
    focusDistance: bool,
    focusMode: bool,
    frameRate: bool,
    groupId: bool,
    height: bool,
    iso: bool,
    latency: bool,
    noiseSuppression: bool,
    pan: bool,
    pointsOfInterest: bool,
    resizeMode: bool,
    sampleRate: bool,
    sampleSize: bool,
    saturation: bool,
    sharpness: bool,
    tilt: bool,
    torch: bool,
    whiteBalanceMode: bool,
    width: bool,
    zoom: bool,
} {
    return .{
        .aspectRatio = true,
        .autoGainControl = true,
        .brightness = true,
        .channelCount = true,
        .colorTemperature = true,
        .contrast = true,
        .deviceId = true,
        .echoCancellation = true,
        .exposureCompensation = true,
        .exposureMode = true,
        .exposureTime = true,
        .facingMode = true,
        .focusDistance = true,
        .focusMode = true,
        .frameRate = true,
        .groupId = true,
        .height = true,
        .iso = true,
        .latency = true,
        .noiseSuppression = true,
        .pan = true,
        .pointsOfInterest = true,
        .resizeMode = true,
        .sampleRate = true,
        .sampleSize = true,
        .saturation = true,
        .sharpness = true,
        .tilt = true,
        .torch = true,
        .whiteBalanceMode = true,
        .width = true,
        .zoom = true,
    };
}

// getUserMedia() — no camera/mic access, so it rejects like a real Chrome
// without granted permission.
pub fn getUserMedia(_: *const MediaDevices, exec: *const Execution) js.Promise {
    var resolver = js.PromiseResolver.init(exec.js.local.?);
    resolver.rejectError("getUserMedia", .{ .dom_exception = .{ .err = error.NotAllowedError } });
    return resolver.promise();
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(MediaDevices);

    pub const Meta = struct {
        pub const name = "MediaDevices";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const enumerateDevices = bridge.function(MediaDevices.enumerateDevices, .{});
    pub const getSupportedConstraints = bridge.function(MediaDevices.getSupportedConstraints, .{});
    pub const getUserMedia = bridge.function(MediaDevices.getUserMedia, .{});
};
