// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest
// of the project. See LICENSE.

//! Browser identity profiles that keep the JS layer (navigator.userAgent,
//! navigator.userAgentData, navigator.platform/vendor/appVersion) and the HTTP
//! client-hint headers (User-Agent, Sec-Ch-Ua*) consistent with the TLS/HTTP2
//! fingerprint selected by --tls-impersonate. A Chrome handshake behind a
//! Lightpanda user-agent is itself a bot signal, so when a profile is active
//! every identity surface reports the same browser.
//!
//! Values mirror what curl-impersonate itself sends for each target — its
//! desktop Chrome builds present a macOS identity, so the headers we emit match
//! the handshake the linked archive produces. Chose a profile in [[impersonate]].
//!
//! To pin a new target: copy its `sec-ch-ua` (brand order + GREASE string) from
//! the curl-impersonate archive and a real stable build number, add a Profile
//! const, and list it in `forProfile`.

const std = @import("std");

/// Brand/version triple used to build both the low-entropy Sec-Ch-Ua header
/// (major `version`) and the high-entropy full-version list (`full_version`).
pub const Brand = struct {
    brand: [:0]const u8,
    version: [:0]const u8,
    full_version: [:0]const u8,
};

/// JS-facing brand entry (navigator.userAgentData.brands / fullVersionList).
/// NavigatorUAData reuses this type so the fork owns the shape and there is no
/// import cycle back through Config.
pub const JsBrand = struct {
    brand: []const u8,
    version: []const u8,
};

/// A coherent browser identity. `ua_platform` is navigator.userAgentData
/// .platform (e.g. "macOS"); `platform` is navigator.platform (e.g. "MacIntel")
/// — the two legitimately differ. `sec_ch_ua_platform` is the quoted header
/// value. `mobile` drives Sec-Ch-Ua-Mobile (?0/?1) and userAgentData.mobile.
pub const Identity = struct {
    user_agent: [:0]const u8,
    vendor: [:0]const u8,
    platform: [:0]const u8,
    ua_platform: [:0]const u8,
    sec_ch_ua: [:0]const u8,
    sec_ch_ua_full_version_list: [:0]const u8,
    sec_ch_ua_platform: [:0]const u8,
    sec_ch_ua_mobile: [:0]const u8,
    mobile: bool,
    brands: []const JsBrand,
    full_version_list: []const JsBrand,
    // WebGL UNMASKED_VENDOR_WEBGL / UNMASKED_RENDERER_WEBGL. Chrome's Mac UA is
    // frozen at "Intel Mac OS X 10_15_7" on every Mac including Apple Silicon,
    // so an Apple-Metal renderer is coherent with the macOS identity.
    webgl_vendor: [:0]const u8,
    webgl_renderer: [:0]const u8,
};

// curl-impersonate ships one fixed UA per desktop Chrome target, all on macOS.
const mac_ua_prefix = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/";
const mac_ua_suffix = ".0.0.0 Safari/537.36";
const chrome_vendor = "Google Inc.";
const grease_v24 = Brand{ .brand = "Not_A Brand", .version = "24", .full_version = "24.0.0.0" };

// Brand lists: order and GREASE string copied verbatim from the
// curl-impersonate archive; full_version from a real stable build.
const chrome131_src = [_]Brand{
    .{ .brand = "Google Chrome", .version = "131", .full_version = "131.0.6778.86" },
    .{ .brand = "Chromium", .version = "131", .full_version = "131.0.6778.86" },
    grease_v24,
};
const chrome136_src = [_]Brand{
    .{ .brand = "Chromium", .version = "136", .full_version = "136.0.7103.114" },
    .{ .brand = "Google Chrome", .version = "136", .full_version = "136.0.7103.114" },
    .{ .brand = "Not.A/Brand", .version = "99", .full_version = "99.0.0.0" },
};

// Comptime renderings; each is a stable top-level const so &... is a valid slice.
const chrome131_brands = brandsToJs(&chrome131_src, false);
const chrome131_fvl = brandsToJs(&chrome131_src, true);
const chrome136_brands = brandsToJs(&chrome136_src, false);
const chrome136_fvl = brandsToJs(&chrome136_src, true);

const chrome131 = Identity{
    .user_agent = mac_ua_prefix ++ "131" ++ mac_ua_suffix,
    .vendor = chrome_vendor,
    .platform = "MacIntel",
    .ua_platform = "macOS",
    .sec_ch_ua = secChUa(&chrome131_src, false),
    .sec_ch_ua_full_version_list = secChUa(&chrome131_src, true),
    .sec_ch_ua_platform = "\"macOS\"",
    .sec_ch_ua_mobile = "?0",
    .mobile = false,
    .brands = &chrome131_brands,
    .full_version_list = &chrome131_fvl,
    .webgl_vendor = "Google Inc. (Apple)",
    .webgl_renderer = "ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)",
};
const chrome136 = Identity{
    .user_agent = mac_ua_prefix ++ "136" ++ mac_ua_suffix,
    .vendor = chrome_vendor,
    .platform = "MacIntel",
    .ua_platform = "macOS",
    .sec_ch_ua = secChUa(&chrome136_src, false),
    .sec_ch_ua_full_version_list = secChUa(&chrome136_src, true),
    .sec_ch_ua_platform = "\"macOS\"",
    .sec_ch_ua_mobile = "?0",
    .mobile = false,
    .brands = &chrome136_brands,
    .full_version_list = &chrome136_fvl,
    .webgl_vendor = "Google Inc. (Apple)",
    .webgl_renderer = "ANGLE (Apple, ANGLE Metal Renderer: Apple M1, Unspecified Version)",
};

/// Identity for a curl-impersonate profile name, or null when we have no
/// pinned mapping — the caller then keeps the default Lightpanda identity
/// rather than claiming a browser we can't render coherently (e.g. Safari or
/// an unlisted Chrome build).
pub fn forProfile(profile: []const u8) ?Identity {
    if (std.mem.eql(u8, profile, "chrome131")) return chrome131;
    if (std.mem.eql(u8, profile, "chrome136")) return chrome136;
    return null;
}

/// Renders `"Brand";v="version"` pairs. `full` selects full_version (for the
/// Sec-Ch-Ua-Full-Version-List header) over the major version (Sec-Ch-Ua).
fn secChUa(comptime brands: []const Brand, comptime full: bool) [:0]const u8 {
    return comptime blk: {
        var out: [:0]const u8 = "";
        for (brands, 0..) |b, i| {
            const sep = if (i == 0) "" else ", ";
            const v = if (full) b.full_version else b.version;
            out = out ++ sep ++ "\"" ++ b.brand ++ "\";v=\"" ++ v ++ "\"";
        }
        break :blk out;
    };
}

/// Renders the JS brand array. `full` selects full_version (fullVersionList)
/// over the major version (userAgentData.brands).
fn brandsToJs(comptime src: []const Brand, comptime full: bool) [src.len]JsBrand {
    var arr: [src.len]JsBrand = undefined;
    for (src, 0..) |b, i| {
        arr[i] = .{ .brand = b.brand, .version = if (full) b.full_version else b.version };
    }
    return arr;
}

const testing = std.testing;

test "identity: chrome131 profile is coherent" {
    const id = forProfile("chrome131").?;
    try testing.expectEqualStrings(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        id.user_agent,
    );
    // Brand order + GREASE string must match curl-impersonate's chrome131.
    try testing.expectEqualStrings("\"Google Chrome\";v=\"131\", \"Chromium\";v=\"131\", \"Not_A Brand\";v=\"24\"", id.sec_ch_ua);
    try testing.expectEqualStrings("\"macOS\"", id.sec_ch_ua_platform);
    try testing.expectEqualStrings("macOS", id.ua_platform);
    try testing.expectEqualStrings("MacIntel", id.platform);
    try testing.expectEqual(false, id.mobile);
    // Low-entropy brands are major; the full list carries the build number.
    try testing.expectEqualStrings("131", id.brands[0].version);
    try testing.expectEqualStrings("131.0.6778.86", id.full_version_list[0].version);
}

test "identity: unknown/non-chrome profiles have no mapping" {
    try testing.expect(forProfile("safari180") == null);
    try testing.expect(forProfile("chrome99") == null);
}
