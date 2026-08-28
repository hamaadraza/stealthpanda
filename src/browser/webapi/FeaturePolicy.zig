// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! document.featurePolicy (the Permissions/Feature Policy JS interface). Chrome
//! exposes it on the document; scripts (including Cloudflare's Turnstile
//! api.js) read `document.featurePolicy` as a Chrome-presence probe, and its
//! absence under a Chrome user-agent is a bot signal. We expose the object with
//! the four standard methods. The exact feature list is Chrome-version
//! specific, so we return a stable, well-known core set rather than trying to
//! byte-match a given build (a detector comparing against a known list would
//! see a plausible, non-empty result either way). Only surfaced when
//! impersonating (see Document.getFeaturePolicy).

const FeaturePolicy = @This();

_pad: bool = false,

// A stable core of policy-controlled features Chrome has supported for years.
// Deliberately excludes version-churny client-hint tokens.
const FEATURES = &[_][]const u8{
    "accelerometer",
    "ambient-light-sensor",
    "autoplay",
    "battery",
    "camera",
    "cross-origin-isolated",
    "display-capture",
    "document-domain",
    "encrypted-media",
    "execution-while-not-rendered",
    "execution-while-out-of-viewport",
    "fullscreen",
    "geolocation",
    "gyroscope",
    "hid",
    "idle-detection",
    "magnetometer",
    "microphone",
    "midi",
    "payment",
    "picture-in-picture",
    "publickey-credentials-get",
    "screen-wake-lock",
    "serial",
    "sync-xhr",
    "usb",
    "web-share",
    "xr-spatial-tracking",
};

pub fn allowsFeature(_: *const FeaturePolicy, _: []const u8, _: ?[]const u8) bool {
    // Top-level, same-origin document: the default allowlist permits these.
    return true;
}

pub fn features(_: *const FeaturePolicy) []const []const u8 {
    return FEATURES;
}

pub fn allowedFeatures(_: *const FeaturePolicy) []const []const u8 {
    return FEATURES;
}

pub fn getAllowlistForFeature(_: *const FeaturePolicy, _: []const u8) []const []const u8 {
    return &.{"*"};
}

pub const JsApi = struct {
    const js = @import("../js/js.zig");
    pub const bridge = js.Bridge(FeaturePolicy);

    pub const Meta = struct {
        pub const name = "FeaturePolicy";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const allowsFeature = bridge.function(FeaturePolicy.allowsFeature, .{});
    pub const features = bridge.function(FeaturePolicy.features, .{});
    pub const allowedFeatures = bridge.function(FeaturePolicy.allowedFeatures, .{});
    pub const getAllowlistForFeature = bridge.function(FeaturePolicy.getAllowlistForFeature, .{});
};
