// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const builtin = @import("builtin");

const js = @import("../js/js.zig");
const Frame = @import("../Frame.zig");
const Execution = js.Execution;

const PluginArray = @import("PluginArray.zig");
const Permissions = @import("Permissions.zig");
const ModelContext = @import("ModelContext.zig");
const StorageManager = @import("StorageManager.zig");
const NavigatorUAData = @import("NavigatorUAData.zig");
const Geolocation = @import("geolocation/Geolocation.zig");
const NetworkInformation = @import("NetworkInformation.zig");
const MediaDevices = @import("MediaDevices.zig");
const BatteryManager = @import("BatteryManager.zig");
const Bluetooth = @import("Bluetooth.zig");
const Features = @import("Features.zig");
const GPU = @import("GPU.zig");

const Navigator = @This();

comptime {
    // Ensure we don't cause an identity map conflict. Because _geolocation is
    // lazy and, for now, Zig orders the highest-aligned field first, none of
    // the other fields land at offset 0.
    for ([_][]const u8{ "_plugins", "_mime_types", "_connection", "_media_devices", "_battery", "_bluetooth", "_service_worker", "_storage_quota", "_permissions", "_storage", "_ua_data", "_gpu" }) |name| {
        if (@offsetOf(Navigator, name) == 0) @compileError(name ++ " aliases the Navigator");
    }
}

// stealthpanda: the shared PDF plugin/mimetype graph (populated only when
// impersonating, see ensurePdfPlugins). Declared first, and being an internal
// (non-JS-wrapped) pointer-holding field it takes offset 0, keeping the
// JS-wrapped sub-objects below off offset 0 (see the comptime guard). It must
// not be over-aligned: that would change Navigator's pointer alignment and
// break the low-bit pointer tagging the identity map relies on.
_pdf: ?PluginArray.Graph = null,
_plugins: PluginArray = .{},
_mime_types: PluginArray.MimeTypeArray = .{},
// stealthpanda: navigator.connection / navigator.mediaDevices (impersonation-gated).
_connection: NetworkInformation = .{},
_media_devices: MediaDevices = .{},
// stealthpanda: navigator.getBattery() singleton / navigator.bluetooth.
_battery: BatteryManager = .{},
_bluetooth: Bluetooth = .{},
// stealthpanda: navigator.gpu (WebGPU entry point, impersonation-gated).
_gpu: GPU = .{},
// stealthpanda: navigator.serviceWorker / legacy webkit*Storage quota objects
// (impersonation-gated). Shared singletons, like the other stub sub-objects.
_service_worker: Features.ServiceWorkerContainer = .{},
_storage_quota: Features.DeprecatedStorageQuota = .{},
_permissions: Permissions = .{},
_geolocation: ?*Geolocation = null,
_storage: StorageManager = .{},
_ua_data: NavigatorUAData = .{},

pub const init: Navigator = .{};

pub fn getUserAgent(_: *const Navigator, exec: *const Execution) []const u8 {
    return exec.session.browser.http_client.getUserAgent();
}

pub fn getLanguages(_: *const Navigator) [2][]const u8 {
    return .{ "en-US", "en" };
}

pub fn getDoNotTrack(_: *const Navigator) ?[]const u8 {
    return null;
}

pub fn getAppName(_: *const Navigator) []const u8 {
    return "Netscape";
}

pub fn getAppCodeName(_: *const Navigator) []const u8 {
    return "Mozilla";
}

pub fn getAppVersion(_: *const Navigator, exec: *const Execution) []const u8 {
    // stealthpanda: appVersion is the User-Agent with the "Mozilla/" prefix
    // removed. Keep the legacy "1.0" when not impersonating.
    if (exec.session.browser.http_client.impersonateIdentity()) |id| {
        const prefix = "Mozilla/";
        if (std.mem.startsWith(u8, id.user_agent, prefix)) return id.user_agent[prefix.len..];
        return id.user_agent;
    }
    return "1.0";
}

pub fn getLanguage(_: *const Navigator) []const u8 {
    return "en-US";
}

pub fn getOnLine(_: *const Navigator) bool {
    return true;
}

pub fn getCookieEnabled(_: *const Navigator) bool {
    return true;
}

pub fn getHardwareConcurrency(_: *const Navigator, exec: *const Execution) u32 {
    // stealthpanda: a typical desktop Chrome reports 8+; keep 4 off-path.
    if (exec.session.browser.http_client.impersonateIdentity() != null) return 8;
    return 4;
}

pub fn getDeviceMemory(_: *const Navigator) f64 {
    return 8.0;
}

pub fn getMaxTouchPoints(_: *const Navigator) u32 {
    return 0;
}

pub fn getVendor(_: *const Navigator, exec: *const Execution) []const u8 {
    // stealthpanda: Chrome reports "Google Inc."; empty otherwise (Firefox-like).
    if (exec.session.browser.http_client.impersonateIdentity()) |id| return id.vendor;
    return "";
}

pub fn getProduct(_: *const Navigator) []const u8 {
    return "Gecko";
}

// stealthpanda: Chrome/WebKit report a frozen productSub "20030107" and an
// empty vendorSub. undefined off-path (honest Lightpanda doesn't expose them).
pub fn getProductSub(_: *const Navigator, exec: *const Execution) ?[]const u8 {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return "20030107";
}

pub fn getVendorSub(_: *const Navigator, exec: *const Execution) ?[]const u8 {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return "";
}

// stealthpanda: Chrome ships the internal PDF viewer, so navigator
// .pdfViewerEnabled is true (and coherent with the PDF plugins we surface).
// undefined off-path.
pub fn getPdfViewerEnabled(_: *const Navigator, exec: *const Execution) ?bool {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return true;
}

pub fn getWebdriver(_: *const Navigator) bool {
    return false;
}

// Default to false: per https://w3c.github.io/gpc/#javascript-property the
// signal reflects an explicit user preference, and none is configured here.
// Firefox defaults to false; Chrome doesn't expose the property. Returning
// true made GPC-compliant consent managers treat every page load as "reject
// tracking" and skip their consent UI entirely.
pub fn getGlobalPrivacyControl(_: *const Navigator) bool {
    return false;
}

pub fn getPlatform(_: *const Navigator, exec: *const Execution) []const u8 {
    // stealthpanda: match the impersonated OS (navigator.platform, e.g.
    // "MacIntel"), else fall back to the build target.
    if (exec.session.browser.http_client.impersonateIdentity()) |id| return id.platform;
    return switch (builtin.os.tag) {
        .macos => "MacIntel",
        .windows => "Win32",
        .linux => "Linux x86_64",
        .freebsd => "FreeBSD",
        else => "Unknown",
    };
}

/// Returns whether Java is enabled (always false)
pub fn javaEnabled(_: *const Navigator) bool {
    return false;
}

/// Noop, signal that the data was successfully queued
pub fn sendBeacon(_: *const Navigator, url: js.Value, data: ?js.Value) bool {
    _ = url;
    _ = data;
    return true;
}

pub fn getPlugins(self: *Navigator, exec: *const Execution) !*PluginArray {
    try self.ensurePdfPlugins(exec);
    return &self._plugins;
}

pub fn getMimeTypes(self: *Navigator, exec: *const Execution) !*PluginArray.MimeTypeArray {
    try self.ensurePdfPlugins(exec);
    return &self._mime_types;
}

// stealthpanda: build Chrome's shared PDF plugin/mimetype graph once, wiring
// both navigator.plugins and navigator.mimeTypes to it. No-op (arrays stay
// empty) when not impersonating.
fn ensurePdfPlugins(self: *Navigator, exec: *const Execution) !void {
    if (self._pdf != null) return;
    if (exec.session.browser.http_client.impersonateIdentity() == null) return;
    self._pdf = try PluginArray.Graph.build(exec);
    self._plugins._items = self._pdf.?.plugins[0..];
    self._mime_types._items = self._pdf.?.mimes[0..];
}

// stealthpanda: navigator.connection / navigator.mediaDevices — present only
// when impersonating (undefined otherwise, an honest Lightpanda doesn't fake
// browser APIs it lacks).
pub fn getConnection(self: *Navigator, exec: *const Execution) ?*NetworkInformation {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return &self._connection;
}

pub fn getMediaDevices(self: *Navigator, exec: *const Execution) ?*MediaDevices {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return &self._media_devices;
}

// stealthpanda: navigator.gpu — present only when impersonating (undefined
// otherwise). Absence under a Chrome user-agent is a well-known headless tell.
pub fn getGpu(self: *Navigator, exec: *const Execution) ?*GPU {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return &self._gpu;
}

// stealthpanda: navigator.getBattery() — resolves the shared BatteryManager
// (real Chrome returns the same instance from every call).
pub fn getBattery(self: *Navigator, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise(&self._battery);
}

// stealthpanda: navigator.bluetooth — present only when impersonating (undefined
// otherwise, like connection/mediaDevices).
pub fn getBluetooth(self: *Navigator, exec: *const Execution) ?*Bluetooth {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return &self._bluetooth;
}

// stealthpanda: navigator.serviceWorker — every desktop Chrome has it; its
// absence under a Chrome UA is a cheap tell (`"serviceWorker" in navigator`).
// Undefined off-path, like bluetooth.
pub fn getServiceWorker(self: *Navigator, exec: *const Execution) ?*Features.ServiceWorkerContainer {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return &self._service_worker;
}

// stealthpanda: navigator.getGamepads() — present (unprefixed) on desktop
// Chrome. No controllers are connected, so it returns an empty list.
pub fn getGamepads(_: *const Navigator) [0]u32 {
    return .{};
}

// stealthpanda: navigator.vibrate() exists on desktop Chrome (a no-op that
// returns true there). Registered as a noop so the function is simply present
// and truthy for detectors; the return value is not fingerprinted.
pub fn vibrate(_: *const Navigator) bool {
    return true;
}

// stealthpanda: navigator.webkitTemporaryStorage / webkitPersistentStorage —
// the legacy quota objects Chrome still exposes; both must exist for a
// detector's `temporaryStorage && persistentStorage` probe. Gated like the rest.
pub fn getWebkitTemporaryStorage(self: *Navigator, exec: *const Execution) ?*Features.DeprecatedStorageQuota {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return &self._storage_quota;
}

pub fn getWebkitPersistentStorage(self: *Navigator, exec: *const Execution) ?*Features.DeprecatedStorageQuota {
    if (exec.session.browser.http_client.impersonateIdentity() == null) return null;
    return &self._storage_quota;
}

pub fn getPermissions(self: *Navigator) *Permissions {
    return &self._permissions;
}

pub fn getGeolocation(self: *Navigator, exec: *Execution) !*Geolocation {
    if (self._geolocation) |g| {
        return g;
    }
    const g = try exec._factory.create(Geolocation{});
    self._geolocation = g;
    return g;
}

pub fn getStorage(self: *Navigator) *StorageManager {
    return &self._storage;
}

pub fn getUserAgentData(self: *Navigator) *NavigatorUAData {
    return &self._ua_data;
}

pub fn getModelContext(_: *const Navigator, frame: *Frame) *ModelContext {
    return &frame.window._model_context;
}

pub fn registerProtocolHandler(_: *const Navigator, scheme: []const u8, url: [:0]const u8, frame: *const Frame) !void {
    try validateProtocolHandlerScheme(scheme);
    try validateProtocolHandlerURL(url, frame);
}
pub fn unregisterProtocolHandler(_: *const Navigator, scheme: []const u8, url: [:0]const u8, frame: *const Frame) !void {
    try validateProtocolHandlerScheme(scheme);
    try validateProtocolHandlerURL(url, frame);
}

fn validateProtocolHandlerScheme(scheme: []const u8) !void {
    const allowed = std.StaticStringMap(void).initComptime(.{
        .{ "bitcoin", {} },
        .{ "cabal", {} },
        .{ "dat", {} },
        .{ "did", {} },
        .{ "dweb", {} },
        .{ "ethereum", .{} },
        .{ "ftp", {} },
        .{ "ftps", {} },
        .{ "geo", {} },
        .{ "im", {} },
        .{ "ipfs", {} },
        .{ "ipns", .{} },
        .{ "irc", {} },
        .{ "ircs", {} },
        .{ "hyper", {} },
        .{ "magnet", {} },
        .{ "mailto", {} },
        .{ "matrix", {} },
        .{ "mms", {} },
        .{ "news", {} },
        .{ "nntp", {} },
        .{ "openpgp4fpr", {} },
        .{ "sftp", {} },
        .{ "sip", {} },
        .{ "sms", {} },
        .{ "smsto", {} },
        .{ "ssb", {} },
        .{ "ssh", {} },
        .{ "tel", {} },
        .{ "urn", {} },
        .{ "webcal", {} },
        .{ "wtai", {} },
        .{ "xmpp", {} },
    });
    if (allowed.has(scheme)) {
        return;
    }

    if (scheme.len < 5 or !std.mem.startsWith(u8, scheme, "web+")) {
        return error.SecurityError;
    }
    for (scheme[4..]) |b| {
        if (std.ascii.isLower(b) == false) {
            return error.SecurityError;
        }
    }
}

fn validateProtocolHandlerURL(url: [:0]const u8, frame: *const Frame) !void {
    if (std.mem.indexOf(u8, url, "%s") == null) {
        return error.SyntaxError;
    }
    if (frame.isSameOrigin(url) == false) {
        return error.SyntaxError;
    }
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Navigator);

    pub const Meta = struct {
        pub const name = "Navigator";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const userAgent = bridge.accessor(Navigator.getUserAgent, null, .{});
    pub const appName = bridge.accessor(Navigator.getAppName, null, .{});
    pub const appCodeName = bridge.accessor(Navigator.getAppCodeName, null, .{});
    pub const appVersion = bridge.accessor(Navigator.getAppVersion, null, .{});
    pub const platform = bridge.accessor(Navigator.getPlatform, null, .{});
    pub const language = bridge.accessor(Navigator.getLanguage, null, .{});
    pub const languages = bridge.accessor(Navigator.getLanguages, null, .{});
    pub const onLine = bridge.accessor(Navigator.getOnLine, null, .{});
    pub const cookieEnabled = bridge.accessor(Navigator.getCookieEnabled, null, .{});
    pub const hardwareConcurrency = bridge.accessor(Navigator.getHardwareConcurrency, null, .{});
    pub const deviceMemory = bridge.accessor(Navigator.getDeviceMemory, null, .{});
    pub const maxTouchPoints = bridge.accessor(Navigator.getMaxTouchPoints, null, .{});
    pub const vendor = bridge.accessor(Navigator.getVendor, null, .{});
    pub const product = bridge.accessor(Navigator.getProduct, null, .{});
    // stealthpanda: productSub / vendorSub / pdfViewerEnabled (undefined off-path).
    pub const productSub = bridge.accessor(Navigator.getProductSub, null, .{ .null_as_undefined = true });
    pub const vendorSub = bridge.accessor(Navigator.getVendorSub, null, .{ .null_as_undefined = true });
    pub const pdfViewerEnabled = bridge.accessor(Navigator.getPdfViewerEnabled, null, .{ .null_as_undefined = true });
    pub const webdriver = bridge.accessor(Navigator.getWebdriver, null, .{});
    pub const doNotTrack = bridge.accessor(Navigator.getDoNotTrack, null, .{});
    pub const globalPrivacyControl = bridge.accessor(Navigator.getGlobalPrivacyControl, null, .{});

    pub const javaEnabled = bridge.function(Navigator.javaEnabled, .{});
    pub const sendBeacon = bridge.function(Navigator.sendBeacon, .{ .exposed = .window, .noop = true });
    pub const permissions = bridge.accessor(Navigator.getPermissions, null, .{});
    pub const storage = bridge.accessor(Navigator.getStorage, null, .{});
    pub const userAgentData = bridge.accessor(Navigator.getUserAgentData, null, .{});

    // window only
    pub const plugins = bridge.accessor(Navigator.getPlugins, null, .{ .exposed = .window });
    // stealthpanda: navigator.mimeTypes (was absent).
    pub const mimeTypes = bridge.accessor(Navigator.getMimeTypes, null, .{ .exposed = .window });
    // stealthpanda: navigator.connection / navigator.mediaDevices (undefined off-path).
    pub const connection = bridge.accessor(Navigator.getConnection, null, .{ .null_as_undefined = true });
    pub const mediaDevices = bridge.accessor(Navigator.getMediaDevices, null, .{ .null_as_undefined = true });
    pub const gpu = bridge.accessor(Navigator.getGpu, null, .{ .null_as_undefined = true });
    // stealthpanda: navigator.getBattery() / navigator.bluetooth (bluetooth
    // undefined off-path).
    pub const getBattery = bridge.function(Navigator.getBattery, .{});
    pub const bluetooth = bridge.accessor(Navigator.getBluetooth, null, .{ .null_as_undefined = true });
    // stealthpanda: serviceWorker / getGamepads / vibrate / webkit*Storage —
    // JS surfaces feature detectors read on a Chrome UA (see Features.zig).
    pub const serviceWorker = bridge.accessor(Navigator.getServiceWorker, null, .{ .null_as_undefined = true });
    pub const getGamepads = bridge.function(Navigator.getGamepads, .{});
    pub const vibrate = bridge.function(Navigator.vibrate, .{ .noop = true });
    pub const webkitTemporaryStorage = bridge.accessor(Navigator.getWebkitTemporaryStorage, null, .{ .null_as_undefined = true });
    pub const webkitPersistentStorage = bridge.accessor(Navigator.getWebkitPersistentStorage, null, .{ .null_as_undefined = true });
    pub const geolocation = bridge.accessor(Navigator.getGeolocation, null, .{ .exposed = .window });
    pub const modelContext = bridge.accessor(Navigator.getModelContext, null, .{ .exposed = .window });
    pub const registerProtocolHandler = bridge.function(Navigator.registerProtocolHandler, .{ .exposed = .window });
    pub const unregisterProtocolHandler = bridge.function(Navigator.unregisterProtocolHandler, .{ .exposed = .window });
};

const testing = @import("../../testing.zig");
test "WebApi: Navigator" {
    try testing.htmlRunner("navigator", .{});
}
