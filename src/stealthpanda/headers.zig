// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest
// of the project. See LICENSE.

//! Chrome request-header shaping for the --tls-impersonate feature. A Chrome
//! TLS handshake with non-Chrome request headers (missing Sec-Fetch-*, wrong
//! order, curl's Accept/Accept-Encoding) is flagged by bot managers like
//! Akamai on the very first request, so when impersonating we emit the same
//! headers, values and order a real Chrome does. The mechanism (injecting and
//! reordering a request's header list) lives in HttpClient; this module holds
//! the Chrome-generic data. See [[identity]] for the UA/brand side.
//!
//! Values are identity-agnostic across Chromium builds (Sec-Fetch-*, Accept,
//! Priority don't vary by Chrome version); the per-version bits (User-Agent,
//! Sec-Ch-Ua) come from [[identity]].

const std = @import("std");
const psl = @import("../data/public_suffix_list.zig");

/// Chrome's Accept-Encoding, in Chrome's order (curl decodes all of these).
pub const accept_encoding: [:0]const u8 = "gzip, deflate, br, zstd";

/// Request destination, mapped from HttpClient's Request.ResourceType.
pub const Kind = enum { document, script, stylesheet, xhr_fetch, eventsource };

/// Sec-Fetch-Site relationship between the request initiator and the target.
pub const Site = enum {
    none,
    same_origin,
    same_site,
    cross_site,

    pub fn header(self: Site) [:0]const u8 {
        return switch (self) {
            .none => "none",
            .same_origin => "same-origin",
            .same_site => "same-site",
            .cross_site => "cross-site",
        };
    }
};

/// The Accept value Chrome sends for `kind`, or null to leave the caller's own
/// Accept in place (EventSource already sets `text/event-stream`).
pub fn accept(kind: Kind) ?[:0]const u8 {
    return switch (kind) {
        .document => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        .stylesheet => "text/css,*/*;q=0.1",
        .script, .xhr_fetch => "*/*",
        .eventsource => null,
    };
}

pub fn secFetchDest(kind: Kind) [:0]const u8 {
    return switch (kind) {
        .document => "document",
        .script => "script",
        .stylesheet => "style",
        .xhr_fetch, .eventsource => "empty",
    };
}

pub fn secFetchMode(kind: Kind) [:0]const u8 {
    return switch (kind) {
        .document => "navigate",
        .script, .stylesheet => "no-cors",
        .xhr_fetch, .eventsource => "cors",
    };
}

pub fn priority(kind: Kind) [:0]const u8 {
    return switch (kind) {
        // Chrome: top-level document is the highest, blocking; subresources a
        // notch lower. `i` = incremental.
        .document => "u=0, i",
        else => "u=1, i",
    };
}

// Canonical Chrome HTTP/2 header order for the headers we place in the curl
// slist. When impersonating we add an explicit Accept-Encoding to the list so
// it lands in Chrome's position (curl would otherwise inject it right after the
// pseudo-headers). Cookie stays curl-controlled (CURLOPT_COOKIE). Any header
// not listed sorts (stably) after these, preserving its relative order.
pub const order = [_][]const u8{
    "sec-ch-ua",
    "sec-ch-ua-mobile",
    "sec-ch-ua-platform",
    "upgrade-insecure-requests",
    "user-agent",
    "content-type",
    "accept",
    "origin",
    "sec-fetch-site",
    "sec-fetch-mode",
    "sec-fetch-user",
    "sec-fetch-dest",
    "referer",
    "accept-encoding",
    "accept-language",
    "priority",
};

/// Sort key for `name` in the canonical order; unlisted names sort last.
pub fn orderIndex(name: []const u8) usize {
    for (order, 0..) |o, i| {
        if (std.ascii.eqlIgnoreCase(name, o)) return i;
    }
    return order.len;
}

/// Schemeless same-site test: same registrable domain (eTLD+1). Used to tell
/// Sec-Fetch-Site `same-site` from `cross-site`.
pub fn sameSite(host_a: []const u8, host_b: []const u8) bool {
    return std.mem.eql(u8, registrableDomain(host_a), registrableDomain(host_b));
}

/// The registrable domain (public suffix + one label) of `host`.
fn registrableDomain(host: []const u8) []const u8 {
    var candidate = host;
    while (std.mem.indexOfScalar(u8, candidate, '.')) |dot| {
        const parent = candidate[dot + 1 ..];
        if (psl.lookup(parent)) return candidate;
        candidate = parent;
    }
    return host;
}

test "headers: canonical order + sec-fetch mapping" {
    const testing = std.testing;
    try testing.expect(orderIndex("sec-ch-ua") < orderIndex("user-agent"));
    try testing.expect(orderIndex("user-agent") < orderIndex("sec-fetch-site"));
    try testing.expect(orderIndex("priority") < orderIndex("x-custom")); // unlisted trails
    try testing.expectEqualStrings("document", secFetchDest(.document));
    try testing.expectEqualStrings("navigate", secFetchMode(.document));
    try testing.expectEqualStrings("empty", secFetchDest(.xhr_fetch));
    try testing.expectEqualStrings("cors", secFetchMode(.xhr_fetch));
    try testing.expect(accept(.eventsource) == null);
}
