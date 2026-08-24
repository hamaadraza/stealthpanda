// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest
// of the project. See LICENSE.

//! curl-impersonate profile selection for the stealth TLS/HTTP2 fingerprint
//! feature. The build links the prebuilt curl-impersonate archive when
//! `-Dtls_impersonate` is set (default on for this fork); see
//! .ai/WORKFLOWS.md ("Stealth / curl-impersonate") and
//! curl-impersonate.version for the pinned release.

const std = @import("std");
const build_config = @import("build_config");

/// True when the curl-impersonate backend was linked in (`-Dtls_impersonate`,
/// default on for this fork). When false the stock from-source libcurl is used
/// and every impersonation code path compiles out.
pub const enabled = build_config.tls_impersonate;

/// Browser profile emulated when `--tls-impersonate` is not given. Valid names
/// come from curl-impersonate; common ones are chrome131, chrome136,
/// safari180 and firefox144. Keep this consistent with the browser identity
/// the JS layer reports (navigator.userAgent / Sec-Ch-Ua) — a Chrome TLS
/// handshake behind a Lightpanda user-agent is itself a bot signal.
pub const default_profile: [:0]const u8 = "chrome131";

/// Runtime spellings that turn impersonation off for a run, even in an
/// impersonate-enabled build (e.g. `--tls-impersonate off`).
pub fn isDisabled(profile: []const u8) bool {
    return profile.len == 0 or
        std.ascii.eqlIgnoreCase(profile, "off") or
        std.ascii.eqlIgnoreCase(profile, "none") or
        std.ascii.eqlIgnoreCase(profile, "false");
}
