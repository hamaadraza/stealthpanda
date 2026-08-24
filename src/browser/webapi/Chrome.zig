// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! `window.chrome` — the object every real Chrome exposes on every page. Its
//! absence under a Chrome user-agent is one of the loudest bot signals (the
//! puppeteer-extra chrome.app/runtime/csi/loadTimes evasions exist solely for
//! this). Bridged natively so its methods report `[native code]` like Chrome's.
//! Only reachable when --tls-impersonate is active (see Window.getChrome); an
//! honest Lightpanda leaves window.chrome undefined.

const js = @import("../js/js.zig");

const Chrome = @This();

_pad: bool = false,

// chrome.app — present on every page; isInstalled is false without an
// installed PWA, which is the normal case.
pub fn getApp(_: *const Chrome) struct {
    isInstalled: bool,
    InstallState: struct { DISABLED: []const u8, INSTALLED: []const u8, NOT_INSTALLED: []const u8 },
    RunningState: struct { CANNOT_RUN: []const u8, READY_TO_RUN: []const u8, RUNNING: []const u8 },
} {
    return .{
        .isInstalled = false,
        .InstallState = .{ .DISABLED = "disabled", .INSTALLED = "installed", .NOT_INSTALLED = "not_installed" },
        .RunningState = .{ .CANNOT_RUN = "cannot_run", .READY_TO_RUN = "ready_to_run", .RUNNING = "running" },
    };
}

// chrome.runtime — present on every page. Without an extension it exposes the
// enum objects but no `id`. Its mere presence is a common human/bot check.
pub fn getRuntime(_: *const Chrome) struct {
    OnInstalledReason: struct { CHROME_UPDATE: []const u8, INSTALL: []const u8, SHARED_MODULE_UPDATE: []const u8, UPDATE: []const u8 },
    OnRestartRequiredReason: struct { APP_UPDATE: []const u8, OS_UPDATE: []const u8, PERIODIC: []const u8 },
    PlatformArch: struct { ARM: []const u8, ARM64: []const u8, MIPS: []const u8, MIPS64: []const u8, X86_32: []const u8, X86_64: []const u8 },
    PlatformOs: struct { ANDROID: []const u8, CROS: []const u8, LINUX: []const u8, MAC: []const u8, OPENBSD: []const u8, WIN: []const u8 },
    RequestUpdateCheckStatus: struct { NO_UPDATE: []const u8, THROTTLED: []const u8, UPDATE_AVAILABLE: []const u8 },
} {
    return .{
        .OnInstalledReason = .{ .CHROME_UPDATE = "chrome_update", .INSTALL = "install", .SHARED_MODULE_UPDATE = "shared_module_update", .UPDATE = "update" },
        .OnRestartRequiredReason = .{ .APP_UPDATE = "app_update", .OS_UPDATE = "os_update", .PERIODIC = "periodic" },
        .PlatformArch = .{ .ARM = "arm", .ARM64 = "arm64", .MIPS = "mips", .MIPS64 = "mips64", .X86_32 = "x86-32", .X86_64 = "x86-64" },
        .PlatformOs = .{ .ANDROID = "android", .CROS = "cros", .LINUX = "linux", .MAC = "mac", .OPENBSD = "openbsd", .WIN = "win" },
        .RequestUpdateCheckStatus = .{ .NO_UPDATE = "no_update", .THROTTLED = "throttled", .UPDATE_AVAILABLE = "update_available" },
    };
}

// chrome.csi() — legacy page-timing shim Chrome still ships.
pub fn csi(_: *const Chrome) struct {
    startE: f64,
    onloadT: f64,
    pageT: f64,
    tran: u8,
} {
    return .{ .startE = 0, .onloadT = 0, .pageT = 0, .tran = 15 };
}

// chrome.loadTimes() — deprecated but still present in Chrome.
pub fn loadTimes(_: *const Chrome) struct {
    requestTime: f64,
    startLoadTime: f64,
    commitLoadTime: f64,
    finishDocumentLoadTime: f64,
    finishLoadTime: f64,
    firstPaintTime: f64,
    firstPaintAfterLoadTime: f64,
    navigationType: []const u8,
    wasFetchedViaSpdy: bool,
    wasNpnNegotiated: bool,
    npnNegotiatedProtocol: []const u8,
    wasAlternateProtocolAvailable: bool,
    connectionInfo: []const u8,
} {
    return .{
        .requestTime = 0,
        .startLoadTime = 0,
        .commitLoadTime = 0,
        .finishDocumentLoadTime = 0,
        .finishLoadTime = 0,
        .firstPaintTime = 0,
        .firstPaintAfterLoadTime = 0,
        .navigationType = "Other",
        .wasFetchedViaSpdy = true,
        .wasNpnNegotiated = true,
        .npnNegotiatedProtocol = "h2",
        .wasAlternateProtocolAvailable = false,
        .connectionInfo = "h2",
    };
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Chrome);

    pub const Meta = struct {
        pub const name = "Chrome";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const app = bridge.accessor(Chrome.getApp, null, .{});
    pub const runtime = bridge.accessor(Chrome.getRuntime, null, .{});
    pub const csi = bridge.function(Chrome.csi, .{});
    pub const loadTimes = bridge.function(Chrome.loadTimes, .{});
};
