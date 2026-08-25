// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! Process timezone pinning. A residential/proxy egress with an `Intl…timeZone`
//! of "UTC" is a datacenter tell (a real user's timezone matches their
//! location). V8/ICU read the timezone from the `TZ` environment variable at
//! first use, so setting it before the V8 platform initializes makes Date/Intl
//! report the configured zone. See Config.timezone() and main.zig.

const std = @import("std");

extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn tzset() void;

/// Pin the process timezone to `tz` (an IANA name, e.g. "America/New_York").
/// Must run before the first Date/Intl use — i.e. before V8 platform init.
pub fn setProcessTimezone(tz: [:0]const u8) void {
    _ = setenv("TZ", tz.ptr, 1);
    tzset();
}
