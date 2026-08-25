// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! A cluster of small JS-environment surfaces that feature-detection libraries
//! (Modernizr, and the bot sensors built on the same idioms) read on a Chrome
//! user-agent. Each is a shallow presence/shape stub, not a functional
//! implementation — the point is coherence: a Chrome UA where
//! `"PushManager" in window` or `"serviceWorker" in navigator` is false is a
//! cheap, loud bot tell (browserleaks/features, detect-headless, etc.).
//!
//! Two kinds live here:
//!   * Inert global *constructors* (PushManager, MediaSource, MediaRecorder,
//!     PublicKeyCredential, SpeechRecognition). Registering a type in
//!     bridge.zig's PageJsApis exposes its name as a `window` constructor, so
//!     `"X" in window` / `typeof X === "function"` hold. They can't be
//!     runtime-gated (a global either exists or not), so — like the other fork
//!     device constructors — they exist unconditionally but are inert: `new X()`
//!     throws `Illegal constructor`, which is exactly Chrome's own behaviour for
//!     PushManager and PublicKeyCredential.
//!   * Instance-backed stubs (ServiceWorkerContainer, DeprecatedStorageQuota)
//!     held by Navigator and surfaced through impersonation-gated accessors
//!     (undefined off-path, like navigator.bluetooth). Registering them also
//!     gives the matching global type Chrome exposes.
//!
//! Scope: shapes only. `serviceWorker.register()` never installs a worker,
//! webkitTemporaryStorage.queryUsageAndQuota() never calls back — good enough
//! for feature detection, not a working platform. Deep behavioural probes
//! remain a residual (see .ai/FORK.md).

const js = @import("../js/js.zig");
const Execution = js.Execution;

// ---------------------------------------------------------------------------
// Inert global constructors
// ---------------------------------------------------------------------------

// One reusable shape for a bare, non-constructable global. `new X()` throws
// (Chrome does the same for PushManager/PublicKeyCredential), while the name
// still resolves as a `function`, satisfying `"X" in window` and `typeof X`.
fn InertGlobal(comptime type_name: [:0]const u8) type {
    return struct {
        const Self = @This();

        // A field so the wrapper has a non-empty backing allocation, matching
        // the other stub types; never actually instantiated.
        _pad: bool = false,

        pub fn illegalConstructor(_: ?js.Value) !*Self {
            return error.IllegalConstructor;
        }

        pub const JsApi = struct {
            pub const bridge = js.Bridge(Self);

            pub const Meta = struct {
                pub const name = type_name;
                pub const prototype_chain = bridge.prototypeChain();
                pub var class_id: bridge.ClassId = undefined;
            };

            pub const constructor = bridge.constructor(Self.illegalConstructor, .{});
        };
    };
}

pub const PushManager = InertGlobal("PushManager");
pub const MediaSource = InertGlobal("MediaSource");
pub const MediaRecorder = InertGlobal("MediaRecorder");
pub const PublicKeyCredential = InertGlobal("PublicKeyCredential");
pub const SpeechRecognition = InertGlobal("SpeechRecognition");

// ---------------------------------------------------------------------------
// navigator.serviceWorker
// ---------------------------------------------------------------------------

// A fresh page with no installed worker: controller is null, ready never
// settles in Chrome either (it resolves once a worker activates), and the query
// methods resolve empty. Enough shape that `navigator.serviceWorker` and its
// methods exist and don't throw.
pub const ServiceWorkerContainer = struct {
    _pad: bool = false,

    // No active worker controls this page yet -> null (JS null, not undefined).
    pub fn getController(_: *const ServiceWorkerContainer) ?*ServiceWorkerContainer {
        return null;
    }

    pub fn register(_: *const ServiceWorkerContainer, _: []const u8, exec: *const Execution) !js.Promise {
        // No worker is actually installed; resolve to undefined (inert).
        return exec.js.local.?.resolvePromise({});
    }

    pub fn getRegistration(_: *const ServiceWorkerContainer, exec: *const Execution) !js.Promise {
        // No registration for this scope — Chrome resolves to undefined here too.
        return exec.js.local.?.resolvePromise({});
    }

    pub fn getRegistrations(_: *const ServiceWorkerContainer, exec: *const Execution) !js.Promise {
        const empty: []const []const u8 = &.{};
        return exec.js.local.?.resolvePromise(empty);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(ServiceWorkerContainer);

        pub const Meta = struct {
            pub const name = "ServiceWorkerContainer";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const controller = bridge.accessor(ServiceWorkerContainer.getController, null, .{});
        pub const register = bridge.function(ServiceWorkerContainer.register, .{});
        pub const getRegistration = bridge.function(ServiceWorkerContainer.getRegistration, .{});
        pub const getRegistrations = bridge.function(ServiceWorkerContainer.getRegistrations, .{});
    };
};

// ---------------------------------------------------------------------------
// navigator.webkitTemporaryStorage / webkitPersistentStorage
// ---------------------------------------------------------------------------

// The legacy Quota Management API object Chrome still exposes. Its two methods
// are callback-based; we register them as no-ops (never invoke the callbacks) —
// feature detection only reads that the object and methods exist.
pub const DeprecatedStorageQuota = struct {
    _pad: bool = false,

    pub fn queryUsageAndQuota(_: *const DeprecatedStorageQuota) void {}
    pub fn requestQuota(_: *const DeprecatedStorageQuota) void {}

    pub const JsApi = struct {
        pub const bridge = js.Bridge(DeprecatedStorageQuota);

        pub const Meta = struct {
            pub const name = "DeprecatedStorageQuota";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const queryUsageAndQuota = bridge.function(DeprecatedStorageQuota.queryUsageAndQuota, .{ .noop = true });
        pub const requestQuota = bridge.function(DeprecatedStorageQuota.requestQuota, .{ .noop = true });
    };
};

pub fn registerTypes() []const type {
    return &.{
        PushManager,
        MediaSource,
        MediaRecorder,
        PublicKeyCredential,
        SpeechRecognition,
        ServiceWorkerContainer,
        DeprecatedStorageQuota,
    };
}
