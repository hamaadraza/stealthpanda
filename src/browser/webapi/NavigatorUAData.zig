// Copyright (C) 2023-2026  Lightpanda (Selecy SAS)
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

const builtin = @import("builtin");

const Config = @import("../../Config.zig");
const identity = @import("../../stealthpanda/identity.zig");
const js = @import("../js/js.zig");
const Execution = js.Execution;

const NavigatorUAData = @This();

_pad: bool = false,

// stealthpanda: the JS brand shape is owned by the identity module so the
// impersonation profiles and the Lightpanda default share one type.
const Brand = identity.JsBrand;

// Lightpanda default brands, rendered once at comptime. `brands` (low-entropy)
// carries the major version; `full_version_list` (high-entropy) the full one.
const lightpanda_brands = toJs(Config.HttpHeaders.brands, false);
const lightpanda_full_version_list = toJs(Config.HttpHeaders.brands, true);

pub fn getBrands(_: *const NavigatorUAData, exec: *const Execution) []const Brand {
    return activeBrands(exec);
}

pub fn getMobile(_: *const NavigatorUAData, exec: *const Execution) bool {
    if (identityOf(exec)) |id| return id.mobile;
    return false;
}

pub fn getPlatform(_: *const NavigatorUAData, exec: *const Execution) []const u8 {
    if (identityOf(exec)) |id| return id.ua_platform;
    return uaPlatform();
}

pub fn toJSON(_: *const NavigatorUAData, exec: *const Execution) struct {
    brands: []const Brand,
    mobile: bool,
    platform: []const u8,
} {
    return .{
        .mobile = if (identityOf(exec)) |id| id.mobile else false,
        .brands = activeBrands(exec),
        .platform = if (identityOf(exec)) |id| id.ua_platform else uaPlatform(),
    };
}

pub fn getHighEntropyValues(_: *const NavigatorUAData, hints: []const []const u8, exec: *const Execution) !js.Promise {
    // This should always return `brands` + `mobile` + `platform` and then whatever
    // "hints" field is requested (assuming the browser has permission), but it's
    // also valid to just return everything.

    _ = hints;

    const id = identityOf(exec);
    const full_version_list = if (id) |i| i.full_version_list else &lightpanda_full_version_list;

    return exec.js.local.?.resolvePromise(.{
        .brands = activeBrands(exec),
        .mobile = if (id) |i| i.mobile else false,
        .platform = if (id) |i| i.ua_platform else uaPlatform(),
        // stealthpanda: when impersonating, arch/bitness/platformVersion come
        // from the identity profile (e.g. "arm"/"64" for Apple Silicon, coherent
        // with the Apple-Metal WebGL renderer) rather than the build host's CPU.
        .architecture = if (id) |i| i.arch else uaArchitecture(),
        .bitness = if (id) |i| i.bitness else uaBitness(),
        .model = "",
        .platformVersion = if (id) |i| i.platform_version else "",
        .uaFullVersion = if (full_version_list.len > 0) full_version_list[0].version else "1.0.0.0",
        .fullVersionList = full_version_list,
        .wow64 = false,
        .formFactor = [_][]const u8{"Desktop"},
    });
}

fn identityOf(exec: *const Execution) ?identity.Identity {
    return exec.session.browser.http_client.impersonateIdentity();
}

fn activeBrands(exec: *const Execution) []const Brand {
    if (identityOf(exec)) |id| return id.brands;
    return &lightpanda_brands;
}

/// Maps the Config brand triples to the JS brand shape. `full` selects the full
/// version (fullVersionList) over the major version (userAgentData.brands).
fn toJs(comptime src: anytype, comptime full: bool) [src.len]Brand {
    var arr: [src.len]Brand = undefined;
    for (src, 0..) |b, i| {
        arr[i] = .{ .brand = b.brand, .version = if (full) b.full_version else b.version };
    }
    return arr;
}

fn uaPlatform() []const u8 {
    return switch (builtin.os.tag) {
        .macos => "macOS",
        .windows => "Windows",
        .linux => "Linux",
        .freebsd => "FreeBSD",
        else => "Unknown",
    };
}

fn uaArchitecture() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86, .x86_64 => "x86",
        .aarch64, .aarch64_be, .arm, .armeb => "arm",
        else => "",
    };
}

fn uaBitness() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64, .aarch64, .aarch64_be, .powerpc64, .powerpc64le, .riscv64 => "64",
        else => "32",
    };
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(NavigatorUAData);

    pub const Meta = struct {
        pub const name = "NavigatorUAData";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const brands = bridge.accessor(NavigatorUAData.getBrands, null, .{});
    pub const mobile = bridge.accessor(NavigatorUAData.getMobile, null, .{});
    pub const platform = bridge.accessor(NavigatorUAData.getPlatform, null, .{});
    pub const toJSON = bridge.function(NavigatorUAData.toJSON, .{});
    pub const getHighEntropyValues = bridge.function(NavigatorUAData.getHighEntropyValues, .{});
};
