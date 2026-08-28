// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! window.trustedTypes (TrustedTypePolicyFactory). Chrome exposes it; anti-bot
//! scripts (Cloudflare Turnstile) probe `window.trustedTypes`, and its absence
//! under a Chrome user-agent is a bot signal. Minimal but functional: since we
//! do not enforce a require-trusted-types-for CSP, the created policy's
//! createHTML/createScript/createScriptURL are identity (return the input
//! string), which real code accepts wherever a Trusted* value would go. Only
//! surfaced when impersonating (see Window.getTrustedTypes).

const js = @import("../js/js.zig");

// The policy object returned by trustedTypes.createPolicy(...). A proper tagged
// opaque (NOT empty_with_no_proto): empty_with_no_proto hands methods a dummy
// `&.{}` self (see js/TaggedOpaque.fromJS), fine only for methods that ignore
// self. These do ignore self, but the object must still carry the policy
// prototype (createHTML/...), so it is registered normally with a real field.
pub const TrustedTypePolicy = struct {
    _pad: bool = false,

    // We do not persist the per-policy name (storing the borrowed JS string
    // would dangle); detectors read factory presence, not the policy name.
    pub fn getName(_: *const TrustedTypePolicy) []const u8 {
        return "default";
    }
    pub fn createHTML(_: *TrustedTypePolicy, input: []const u8) []const u8 {
        return input;
    }
    pub fn createScript(_: *TrustedTypePolicy, input: []const u8) []const u8 {
        return input;
    }
    pub fn createScriptURL(_: *TrustedTypePolicy, input: []const u8) []const u8 {
        return input;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(TrustedTypePolicy);
        pub const Meta = struct {
            pub const name = "TrustedTypePolicy";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const name = bridge.accessor(TrustedTypePolicy.getName, null, .{});
        pub const createHTML = bridge.function(TrustedTypePolicy.createHTML, .{});
        pub const createScript = bridge.function(TrustedTypePolicy.createScript, .{});
        pub const createScriptURL = bridge.function(TrustedTypePolicy.createScriptURL, .{});
    };
};

// Shared, stateless singleton handed back from every createPolicy call. A global
// (not a factory field) so its address never aliases the factory's in the
// per-context identity map — a nested policy field at offset 0 would collide
// with the factory and hand back the factory's own wrapper.
var shared_policy: TrustedTypePolicy = .{};

pub const TrustedTypePolicyFactory = struct {
    _pad: bool = false,

    pub fn createPolicy(_: *TrustedTypePolicyFactory, _: []const u8, _: ?js.Value) *TrustedTypePolicy {
        return &shared_policy;
    }
    pub fn isHTML(_: *TrustedTypePolicyFactory, _: js.Value) bool {
        return false;
    }
    pub fn isScript(_: *TrustedTypePolicyFactory, _: js.Value) bool {
        return false;
    }
    pub fn isScriptURL(_: *TrustedTypePolicyFactory, _: js.Value) bool {
        return false;
    }
    pub fn getAttributeType(_: *TrustedTypePolicyFactory, _: []const u8, _: ?[]const u8, _: ?[]const u8, _: ?[]const u8) ?[]const u8 {
        return null;
    }
    pub fn getPropertyType(_: *TrustedTypePolicyFactory, _: []const u8, _: []const u8, _: ?[]const u8) ?[]const u8 {
        return null;
    }
    pub fn getEmptyHTML(_: *const TrustedTypePolicyFactory) []const u8 {
        return "";
    }
    pub fn getEmptyScript(_: *const TrustedTypePolicyFactory) []const u8 {
        return "";
    }
    pub fn getDefaultPolicy(_: *const TrustedTypePolicyFactory) ?*TrustedTypePolicy {
        return null;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(TrustedTypePolicyFactory);
        pub const Meta = struct {
            pub const name = "TrustedTypePolicyFactory";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const createPolicy = bridge.function(TrustedTypePolicyFactory.createPolicy, .{});
        pub const isHTML = bridge.function(TrustedTypePolicyFactory.isHTML, .{});
        pub const isScript = bridge.function(TrustedTypePolicyFactory.isScript, .{});
        pub const isScriptURL = bridge.function(TrustedTypePolicyFactory.isScriptURL, .{});
        pub const getAttributeType = bridge.function(TrustedTypePolicyFactory.getAttributeType, .{});
        pub const getPropertyType = bridge.function(TrustedTypePolicyFactory.getPropertyType, .{});
        pub const emptyHTML = bridge.accessor(TrustedTypePolicyFactory.getEmptyHTML, null, .{});
        pub const emptyScript = bridge.accessor(TrustedTypePolicyFactory.getEmptyScript, null, .{});
        pub const defaultPolicy = bridge.accessor(TrustedTypePolicyFactory.getDefaultPolicy, null, .{ .null_as_undefined = true });
    };
};

pub fn registerTypes() []const type {
    return &.{ TrustedTypePolicyFactory, TrustedTypePolicy };
}
