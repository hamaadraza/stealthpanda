// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! A privacy-preserving WebRTC surface: RTCPeerConnection, RTCDataChannel,
//! RTCSessionDescription, RTCIceCandidate and RTCPeerConnectionIceEvent.
//!
//! Why it exists: real Chrome always ships WebRTC, so a Chrome user-agent where
//! `typeof RTCPeerConnection === "undefined"` is one of the cheapest, loudest
//! bot checks there is (browserleaks reports "RTCPeerConnection: False").
//!
//! Why it leaks nothing: WebRTC's whole purpose is to discover the host's real
//! local/public IP via STUN — catastrophic on a datacenter/proxy egress. This
//! implementation has no ICE/STUN stack at all: ICE gathering emits only a
//! single mDNS host candidate (`<random-uuid>.local`, no real address) then a
//! null candidate, exactly what Chrome does by default (mDNS obfuscation, since
//! M76). The offer SDP carries `c=IN IP4 0.0.0.0`. Result on browserleaks:
//! "RTCPeerConnection: True" AND "No Leak".
//!
//! Scope: this is a coherent *shape*, not a functional transport — a data
//! channel never actually opens, and a full two-peer loopback with real media
//! would not connect. That deeper level needs an actual ICE/DTLS/SCTP stack.

const std = @import("std");
const lp = @import("lightpanda");

const js = @import("../js/js.zig");
const Frame = @import("../Frame.zig");
const Page = @import("../Page.zig");
const Event = @import("Event.zig");
const EventTarget = @import("EventTarget.zig");

const Execution = js.Execution;
const String = lp.String;
const log = lp.log;

pub fn registerTypes() []const type {
    return &.{
        RTCPeerConnection,
        RTCDataChannel,
        RTCSessionDescription,
        RTCIceCandidate,
        RTCPeerConnectionIceEvent,
    };
}

// ---------------------------------------------------------------------------
// token helpers (used to make each connection's SDP/candidate look distinct)
// ---------------------------------------------------------------------------

const hex_lower = "0123456789abcdef";
const hex_upper = "0123456789ABCDEF";
// The ICE ufrag/pwd alphabet Chrome draws from.
const ice_alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

fn randToken(arena: *lp.Arena, rand: std.Random, len: usize, alphabet: []const u8) ![]const u8 {
    const buf = try arena.alloc(u8, len);
    for (buf) |*c| c.* = alphabet[rand.uintLessThan(usize, alphabet.len)];
    return buf;
}

fn uuidV4(arena: *lp.Arena, rand: std.Random) ![]const u8 {
    const layout = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx";
    const buf = try arena.alloc(u8, layout.len);
    for (layout, 0..) |ch, i| {
        buf[i] = switch (ch) {
            'x' => hex_lower[rand.uintLessThan(u8, 16)],
            'y' => hex_lower[8 + rand.uintLessThan(u8, 4)], // 8..b (RFC4122 variant)
            else => ch, // '-' and the literal '4'
        };
    }
    return buf;
}

// 32 bytes rendered as an uppercase, colon-separated sha-256 fingerprint.
fn fingerprint(arena: *lp.Arena, rand: std.Random) ![]const u8 {
    const buf = try arena.alloc(u8, 32 * 3 - 1);
    var i: usize = 0;
    var b: usize = 0;
    while (b < 32) : (b += 1) {
        if (b > 0) {
            buf[i] = ':';
            i += 1;
        }
        const byte = rand.int(u8);
        buf[i] = hex_upper[byte >> 4];
        buf[i + 1] = hex_upper[byte & 0x0F];
        i += 2;
    }
    return buf;
}

// ---------------------------------------------------------------------------
// RTCPeerConnection
// ---------------------------------------------------------------------------

const RTCPeerConnection = @This();

pub const Proto = EventTarget;

_rc: lp.RC = .{},
_exec: *Execution,
_proto: *EventTarget,
_arena: *lp.Arena,

// Generated identity (all arena-owned, live as long as the connection).
_ufrag: []const u8 = "",
_offer_sdp: []const u8 = "",
_candidate_str: []const u8 = "",
_candidate_address: []const u8 = "",
_candidate_foundation: []const u8 = "",
_candidate_port: u16 = 0,

_has_local: bool = false,
_signaling_state: SignalingState = .stable,
_ice_gathering_state: IceGatheringState = .new,
_gather_step: u8 = 0,

_on_ice_candidate: ?js.Function.Global = null,
_on_ice_gathering_state_change: ?js.Function.Global = null,
_on_ice_connection_state_change: ?js.Function.Global = null,
_on_connection_state_change: ?js.Function.Global = null,
_on_signaling_state_change: ?js.Function.Global = null,
_on_data_channel: ?js.Function.Global = null,
_on_negotiation_needed: ?js.Function.Global = null,
_on_track: ?js.Function.Global = null,
_on_ice_candidate_error: ?js.Function.Global = null,

const SignalingState = enum { stable, have_local_offer };
const IceGatheringState = enum { new, gathering, complete };

pub fn init(_config: ?js.Value, exec: *Execution) !*RTCPeerConnection {
    _ = _config; // iceServers etc. accepted and ignored — we never contact them.
    const arena = try exec.getArena(.small, "RTCPeerConnection");
    errdefer arena.release();

    const pc = try exec._factory.eventTargetWithAllocator(arena.allocator(), RTCPeerConnection{
        ._exec = exec,
        ._arena = arena,
        ._proto = undefined,
    });

    // Per-connection identity, seeded from the pointer so distinct connections
    // differ (real randomness isn't available deterministically here).
    var prng = std.Random.DefaultPrng.init(@intFromPtr(pc));
    const rand = prng.random();

    pc._ufrag = try randToken(arena, rand, 4, ice_alpha);
    const pwd = try randToken(arena, rand, 24, ice_alpha);
    const fp = try fingerprint(arena, rand);
    const uuid = try uuidV4(arena, rand);
    const session_id = rand.int(u63);
    const port: u16 = 50000 + rand.uintLessThan(u16, 15000);
    const foundation = rand.int(u32);

    pc._offer_sdp = try std.fmt.allocPrint(arena.allocator(),
        \\v=0
        \\o=- {d} 2 IN IP4 127.0.0.1
        \\s=-
        \\t=0 0
        \\a=group:BUNDLE 0
        \\a=extmap-allow-mixed
        \\a=msid-semantic: WMS
        \\m=application 9 UDP/DTLS/SCTP webrtc-datachannel
        \\c=IN IP4 0.0.0.0
        \\a=ice-ufrag:{s}
        \\a=ice-pwd:{s}
        \\a=ice-options:trickle
        \\a=fingerprint:sha-256 {s}
        \\a=setup:actpass
        \\a=mid:0
        \\a=sctp-port:5000
        \\a=max-message-size:262144
        \\
    , .{ session_id, pc._ufrag, pwd, fp });
    // Chrome uses CRLF line endings in SDP.
    pc._offer_sdp = try replaceLf(arena.allocator(), pc._offer_sdp);

    pc._candidate_address = try std.fmt.allocPrint(arena.allocator(), "{s}.local", .{uuid});
    pc._candidate_foundation = try std.fmt.allocPrint(arena.allocator(), "{d}", .{foundation});
    pc._candidate_port = port;
    pc._candidate_str = try std.fmt.allocPrint(
        arena.allocator(),
        "candidate:{s} 1 udp 2113937151 {s} {d} typ host generation 0 ufrag {s} network-cost 999",
        .{ pc._candidate_foundation, pc._candidate_address, port, pc._ufrag },
    );

    return pc;
}

// Rewrites '\n' to '\r\n'.
fn replaceLf(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const n = std.mem.count(u8, s, "\n");
    const out = try allocator.alloc(u8, s.len + n);
    var i: usize = 0;
    for (s) |c| {
        if (c == '\n') {
            out[i] = '\r';
            i += 1;
        }
        out[i] = c;
        i += 1;
    }
    return out;
}

pub fn deinit(self: *RTCPeerConnection, _: *Page) void {
    inline for (.{
        "_on_ice_candidate",               "_on_ice_gathering_state_change",
        "_on_ice_connection_state_change", "_on_connection_state_change",
        "_on_signaling_state_change",      "_on_data_channel",
        "_on_negotiation_needed",          "_on_track",
        "_on_ice_candidate_error",
    }) |field| {
        if (@field(self, field)) |cb| cb.release();
    }
    self._arena.release();
}

pub fn acquireRef(self: *RTCPeerConnection) void {
    self._rc.acquire();
}
pub fn releaseRef(self: *RTCPeerConnection, page: *Page) void {
    self._rc.release(self, page);
}
fn asEventTarget(self: *RTCPeerConnection) *EventTarget {
    return self._proto;
}

// --- promise-returning methods ---

const SdpOut = struct { type: []const u8, sdp: []const u8 };

pub fn createOffer(self: *RTCPeerConnection, _opts: ?js.Value, exec: *const Execution) !js.Promise {
    _ = _opts;
    return exec.js.local.?.resolvePromise(SdpOut{ .type = "offer", .sdp = self._offer_sdp });
}

pub fn createAnswer(self: *RTCPeerConnection, _opts: ?js.Value, exec: *const Execution) !js.Promise {
    _ = _opts;
    return exec.js.local.?.resolvePromise(SdpOut{ .type = "answer", .sdp = self._offer_sdp });
}

pub fn setLocalDescription(self: *RTCPeerConnection, _desc: ?js.Value, exec: *Execution) !js.Promise {
    _ = _desc;
    self._has_local = true;
    self._signaling_state = .have_local_offer;
    if (self._ice_gathering_state == .new) {
        self._ice_gathering_state = .gathering;
        self._gather_step = 0;
        exec._scheduler.add(self, iceGatherRun, 1, .{
            .name = "stealth-rtc-ice",
            .blocks_done = true,
        }) catch |err| log.warn(.browser, "stealthpanda: rtc ice schedule", .{ .err = err });
    }
    return exec.js.local.?.resolvePromise({});
}

pub fn setRemoteDescription(_: *RTCPeerConnection, _desc: ?js.Value, exec: *const Execution) !js.Promise {
    _ = _desc;
    return exec.js.local.?.resolvePromise({});
}

pub fn addIceCandidate(_: *RTCPeerConnection, _cand: ?js.Value, exec: *const Execution) !js.Promise {
    _ = _cand;
    return exec.js.local.?.resolvePromise({});
}

pub fn getStats(_: *RTCPeerConnection, _sel: ?js.Value, exec: *const Execution) !js.Promise {
    _ = _sel;
    // A real getStats resolves an RTCStatsReport (a Map); an empty object is a
    // low-fidelity stand-in that at least doesn't reject.
    return exec.js.local.?.resolvePromise(struct {}{});
}

pub fn createDataChannel(_: *RTCPeerConnection, label: []const u8, _opts: ?js.Value, exec: *Execution) !*RTCDataChannel {
    _ = _opts;
    return RTCDataChannel.create(label, exec);
}

pub fn close(self: *RTCPeerConnection) void {
    self._signaling_state = .stable;
}

pub fn restartIce(_: *RTCPeerConnection) void {}

// --- ICE gathering (async, leaks nothing) ---

fn iceGatherRun(ptr: *anyopaque) anyerror!?u32 {
    const self: *RTCPeerConnection = @ptrCast(@alignCast(ptr));
    const exec = self._exec;

    if (self._gather_step == 0) {
        // Emit the single mDNS host candidate (a .local hostname, never a real
        // IP), matching Chrome's default privacy behavior.
        const cand = try exec._factory.create(RTCIceCandidate{
            ._candidate = self._candidate_str,
            ._sdp_mid = "0",
            ._sdp_mline_index = 0,
            ._foundation = self._candidate_foundation,
            ._component = "rtp",
            ._priority = 2113937151,
            ._protocol = "udp",
            ._address = self._candidate_address,
            ._port = self._candidate_port,
            ._typ = "host",
            ._username_fragment = self._ufrag,
        });
        try self.fireIceCandidate(cand);
        self._gather_step = 1;
        // Re-add (not a returned interval) to keep blocks_done=true for the
        // final step, so a settle-on-idle wait pumps until gathering completes.
        exec._scheduler.add(self, iceGatherRun, 3, .{
            .name = "stealth-rtc-ice",
            .blocks_done = true,
        }) catch {};
        return null;
    }

    // Gathering complete: null candidate + iceGatheringState -> complete.
    self._ice_gathering_state = .complete;
    try self.fireIceCandidate(null);
    try self.fireStateEvent("icegatheringstatechange", self._on_ice_gathering_state_change);
    return null;
}

fn fireIceCandidate(self: *RTCPeerConnection, candidate: ?*RTCIceCandidate) !void {
    const exec = self._exec;
    const event = try RTCPeerConnectionIceEvent.initInternal(candidate, exec.page);
    try exec.dispatch(self.asEventTarget(), event.asEvent(), self._on_ice_candidate, .{
        .context = "RTCPeerConnection.icecandidate",
    });
}

fn fireStateEvent(self: *RTCPeerConnection, comptime name: []const u8, handler: ?js.Function.Global) !void {
    const exec = self._exec;
    // Event.init takes a runtime []const u8 (String.wrap is SSO-only, <=12 bytes,
    // too short for "icegatheringstatechange").
    const event = try Event.init(name, null, exec.page);
    try exec.dispatch(self.asEventTarget(), event, handler, .{ .context = "RTCPeerConnection." ++ name });
}

// --- accessors ---

fn getSignalingState(self: *const RTCPeerConnection) []const u8 {
    return switch (self._signaling_state) {
        .stable => "stable",
        .have_local_offer => "have-local-offer",
    };
}
fn getIceGatheringState(self: *const RTCPeerConnection) []const u8 {
    return switch (self._ice_gathering_state) {
        .new => "new",
        .gathering => "gathering",
        .complete => "complete",
    };
}
fn getIceConnectionState(_: *const RTCPeerConnection) []const u8 {
    return "new";
}
fn getConnectionState(_: *const RTCPeerConnection) []const u8 {
    return "new";
}
fn getCanTrickleIceCandidates(_: *const RTCPeerConnection) ?bool {
    return null; // unknown until a remote description is set
}
fn getLocalDescription(self: *const RTCPeerConnection) ?SdpOut {
    if (!self._has_local) return null;
    return .{ .type = "offer", .sdp = self._offer_sdp };
}
fn getRemoteDescription(_: *const RTCPeerConnection) ?SdpOut {
    return null;
}

fn getOnIceCandidate(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_ice_candidate;
}
fn setOnIceCandidate(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_ice_candidate = cb;
}
fn getOnIceGatheringStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_ice_gathering_state_change;
}
fn setOnIceGatheringStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_ice_gathering_state_change = cb;
}
fn getOnIceConnectionStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_ice_connection_state_change;
}
fn setOnIceConnectionStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_ice_connection_state_change = cb;
}
fn getOnConnectionStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_connection_state_change;
}
fn setOnConnectionStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_connection_state_change = cb;
}
fn getOnSignalingStateChange(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_signaling_state_change;
}
fn setOnSignalingStateChange(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_signaling_state_change = cb;
}
fn getOnDataChannel(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_data_channel;
}
fn setOnDataChannel(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_data_channel = cb;
}
fn getOnNegotiationNeeded(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_negotiation_needed;
}
fn setOnNegotiationNeeded(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_negotiation_needed = cb;
}
fn getOnTrack(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_track;
}
fn setOnTrack(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_track = cb;
}
fn getOnIceCandidateError(self: *const RTCPeerConnection) ?js.Function.Global {
    return self._on_ice_candidate_error;
}
fn setOnIceCandidateError(self: *RTCPeerConnection, cb: ?js.Function.Global) void {
    self._on_ice_candidate_error = cb;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(RTCPeerConnection);

    pub const Meta = struct {
        pub const name = "RTCPeerConnection";
        // Chrome still exposes the legacy prefixed alias as the same constructor.
        pub const constructor_alias = "webkitRTCPeerConnection";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(RTCPeerConnection.init, .{});

    pub const createOffer = bridge.function(RTCPeerConnection.createOffer, .{});
    pub const createAnswer = bridge.function(RTCPeerConnection.createAnswer, .{});
    pub const setLocalDescription = bridge.function(RTCPeerConnection.setLocalDescription, .{});
    pub const setRemoteDescription = bridge.function(RTCPeerConnection.setRemoteDescription, .{});
    pub const addIceCandidate = bridge.function(RTCPeerConnection.addIceCandidate, .{});
    pub const getStats = bridge.function(RTCPeerConnection.getStats, .{});
    pub const createDataChannel = bridge.function(RTCPeerConnection.createDataChannel, .{});
    pub const close = bridge.function(RTCPeerConnection.close, .{});
    pub const restartIce = bridge.function(RTCPeerConnection.restartIce, .{ .noop = true });

    pub const signalingState = bridge.accessor(RTCPeerConnection.getSignalingState, null, .{});
    pub const iceGatheringState = bridge.accessor(RTCPeerConnection.getIceGatheringState, null, .{});
    pub const iceConnectionState = bridge.accessor(RTCPeerConnection.getIceConnectionState, null, .{});
    pub const connectionState = bridge.accessor(RTCPeerConnection.getConnectionState, null, .{});
    pub const canTrickleIceCandidates = bridge.accessor(RTCPeerConnection.getCanTrickleIceCandidates, null, .{});
    pub const localDescription = bridge.accessor(RTCPeerConnection.getLocalDescription, null, .{ .null_as_undefined = true });
    pub const remoteDescription = bridge.accessor(RTCPeerConnection.getRemoteDescription, null, .{ .null_as_undefined = true });

    pub const onicecandidate = bridge.accessor(RTCPeerConnection.getOnIceCandidate, RTCPeerConnection.setOnIceCandidate, .{});
    pub const onicegatheringstatechange = bridge.accessor(RTCPeerConnection.getOnIceGatheringStateChange, RTCPeerConnection.setOnIceGatheringStateChange, .{});
    pub const oniceconnectionstatechange = bridge.accessor(RTCPeerConnection.getOnIceConnectionStateChange, RTCPeerConnection.setOnIceConnectionStateChange, .{});
    pub const onconnectionstatechange = bridge.accessor(RTCPeerConnection.getOnConnectionStateChange, RTCPeerConnection.setOnConnectionStateChange, .{});
    pub const onsignalingstatechange = bridge.accessor(RTCPeerConnection.getOnSignalingStateChange, RTCPeerConnection.setOnSignalingStateChange, .{});
    pub const ondatachannel = bridge.accessor(RTCPeerConnection.getOnDataChannel, RTCPeerConnection.setOnDataChannel, .{});
    pub const onnegotiationneeded = bridge.accessor(RTCPeerConnection.getOnNegotiationNeeded, RTCPeerConnection.setOnNegotiationNeeded, .{});
    pub const ontrack = bridge.accessor(RTCPeerConnection.getOnTrack, RTCPeerConnection.setOnTrack, .{});
    pub const onicecandidateerror = bridge.accessor(RTCPeerConnection.getOnIceCandidateError, RTCPeerConnection.setOnIceCandidateError, .{});
};

// ---------------------------------------------------------------------------
// RTCDataChannel — created via RTCPeerConnection.createDataChannel only
// (`new RTCDataChannel()` throws, like Chrome).
// ---------------------------------------------------------------------------

pub const RTCDataChannel = struct {
    pub const Proto = EventTarget;

    _rc: lp.RC = .{},
    _proto: *EventTarget,
    _arena: *lp.Arena,
    _label: []const u8 = "",

    _on_open: ?js.Function.Global = null,
    _on_close: ?js.Function.Global = null,
    _on_message: ?js.Function.Global = null,
    _on_error: ?js.Function.Global = null,
    _on_buffered_amount_low: ?js.Function.Global = null,

    fn create(label: []const u8, exec: *Execution) !*RTCDataChannel {
        const arena = try exec.getArena(.tiny, "RTCDataChannel");
        errdefer arena.release();
        return exec._factory.eventTargetWithAllocator(arena.allocator(), RTCDataChannel{
            ._proto = undefined,
            ._arena = arena,
            ._label = try arena.dupe(u8, label),
        });
    }

    pub fn illegalConstructor(_: ?js.Value) !*RTCDataChannel {
        return error.IllegalConstructor;
    }

    pub fn deinit(self: *RTCDataChannel, _: *Page) void {
        inline for (.{ "_on_open", "_on_close", "_on_message", "_on_error", "_on_buffered_amount_low" }) |field| {
            if (@field(self, field)) |cb| cb.release();
        }
        self._arena.release();
    }
    pub fn acquireRef(self: *RTCDataChannel) void {
        self._rc.acquire();
    }
    pub fn releaseRef(self: *RTCDataChannel, page: *Page) void {
        self._rc.release(self, page);
    }

    fn getLabel(self: *const RTCDataChannel) []const u8 {
        return self._label;
    }
    fn getOrdered(_: *const RTCDataChannel) bool {
        return true;
    }
    fn getProtocol(_: *const RTCDataChannel) []const u8 {
        return "";
    }
    fn getReadyState(_: *const RTCDataChannel) []const u8 {
        return "connecting";
    }
    fn getBufferedAmount(_: *const RTCDataChannel) u32 {
        return 0;
    }
    fn getBufferedAmountLowThreshold(_: *const RTCDataChannel) u32 {
        return 0;
    }
    fn getMaxRetransmits(_: *const RTCDataChannel) ?u32 {
        return null;
    }
    fn getMaxPacketLifeTime(_: *const RTCDataChannel) ?u32 {
        return null;
    }
    fn getNegotiated(_: *const RTCDataChannel) bool {
        return false;
    }
    fn getId(_: *const RTCDataChannel) ?u16 {
        return null;
    }
    fn send(_: *const RTCDataChannel) void {}
    fn dcClose(_: *const RTCDataChannel) void {}

    fn getOnOpen(self: *const RTCDataChannel) ?js.Function.Global {
        return self._on_open;
    }
    fn setOnOpen(self: *RTCDataChannel, cb: ?js.Function.Global) void {
        self._on_open = cb;
    }
    fn getOnClose(self: *const RTCDataChannel) ?js.Function.Global {
        return self._on_close;
    }
    fn setOnClose(self: *RTCDataChannel, cb: ?js.Function.Global) void {
        self._on_close = cb;
    }
    fn getOnMessage(self: *const RTCDataChannel) ?js.Function.Global {
        return self._on_message;
    }
    fn setOnMessage(self: *RTCDataChannel, cb: ?js.Function.Global) void {
        self._on_message = cb;
    }
    fn getOnError(self: *const RTCDataChannel) ?js.Function.Global {
        return self._on_error;
    }
    fn setOnError(self: *RTCDataChannel, cb: ?js.Function.Global) void {
        self._on_error = cb;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCDataChannel);

        pub const Meta = struct {
            pub const name = "RTCDataChannel";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const constructor = bridge.constructor(RTCDataChannel.illegalConstructor, .{});
        pub const label = bridge.accessor(RTCDataChannel.getLabel, null, .{});
        pub const ordered = bridge.accessor(RTCDataChannel.getOrdered, null, .{});
        pub const protocol = bridge.accessor(RTCDataChannel.getProtocol, null, .{});
        pub const readyState = bridge.accessor(RTCDataChannel.getReadyState, null, .{});
        pub const bufferedAmount = bridge.accessor(RTCDataChannel.getBufferedAmount, null, .{});
        pub const bufferedAmountLowThreshold = bridge.accessor(RTCDataChannel.getBufferedAmountLowThreshold, null, .{});
        pub const maxRetransmits = bridge.accessor(RTCDataChannel.getMaxRetransmits, null, .{});
        pub const maxPacketLifeTime = bridge.accessor(RTCDataChannel.getMaxPacketLifeTime, null, .{});
        pub const negotiated = bridge.accessor(RTCDataChannel.getNegotiated, null, .{});
        pub const id = bridge.accessor(RTCDataChannel.getId, null, .{ .null_as_undefined = false });
        pub const send = bridge.function(RTCDataChannel.send, .{ .noop = true });
        pub const close = bridge.function(RTCDataChannel.dcClose, .{ .noop = true });
        pub const onopen = bridge.accessor(RTCDataChannel.getOnOpen, RTCDataChannel.setOnOpen, .{});
        pub const onclose = bridge.accessor(RTCDataChannel.getOnClose, RTCDataChannel.setOnClose, .{});
        pub const onmessage = bridge.accessor(RTCDataChannel.getOnMessage, RTCDataChannel.setOnMessage, .{});
        pub const onerror = bridge.accessor(RTCDataChannel.getOnError, RTCDataChannel.setOnError, .{});
    };
};

// ---------------------------------------------------------------------------
// RTCSessionDescription
// ---------------------------------------------------------------------------

pub const RTCSessionDescription = struct {
    _type: []const u8 = "",
    _sdp: []const u8 = "",

    const SdpInit = struct {
        sdp: ?[]const u8 = null,
        type: ?[]const u8 = null,
    };

    pub fn init(dict_: ?SdpInit, frame: *Frame) !*RTCSessionDescription {
        const dict = dict_ orelse SdpInit{};
        return frame._factory.create(RTCSessionDescription{
            ._type = if (dict.type) |t| try frame.arena.dupe(u8, t) else "",
            ._sdp = if (dict.sdp) |s| try frame.arena.dupe(u8, s) else "",
        });
    }

    fn getType(self: *const RTCSessionDescription) []const u8 {
        return self._type;
    }
    fn getSdp(self: *const RTCSessionDescription) []const u8 {
        return self._sdp;
    }
    fn toJSON(self: *const RTCSessionDescription) SdpOut {
        return .{ .type = self._type, .sdp = self._sdp };
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCSessionDescription);

        pub const Meta = struct {
            pub const name = "RTCSessionDescription";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const constructor = bridge.constructor(RTCSessionDescription.init, .{});
        pub const @"type" = bridge.accessor(RTCSessionDescription.getType, null, .{});
        pub const sdp = bridge.accessor(RTCSessionDescription.getSdp, null, .{});
        pub const toJSON = bridge.function(RTCSessionDescription.toJSON, .{});
    };
};

// ---------------------------------------------------------------------------
// RTCIceCandidate
// ---------------------------------------------------------------------------

pub const RTCIceCandidate = struct {
    _candidate: []const u8 = "",
    _sdp_mid: ?[]const u8 = null,
    _sdp_mline_index: ?u16 = null,
    _foundation: ?[]const u8 = null,
    _component: ?[]const u8 = null,
    _priority: ?u32 = null,
    _protocol: ?[]const u8 = null,
    _address: ?[]const u8 = null,
    _port: ?u16 = null,
    _typ: ?[]const u8 = null,
    _username_fragment: ?[]const u8 = null,

    const CandidateInit = struct {
        candidate: ?[]const u8 = null,
        sdpMLineIndex: ?u16 = null,
        sdpMid: ?[]const u8 = null,
        usernameFragment: ?[]const u8 = null,
    };

    pub fn init(dict_: ?CandidateInit, frame: *Frame) !*RTCIceCandidate {
        const dict = dict_ orelse CandidateInit{};
        return frame._factory.create(RTCIceCandidate{
            ._candidate = if (dict.candidate) |c| try frame.arena.dupe(u8, c) else "",
            ._sdp_mid = if (dict.sdpMid) |m| try frame.arena.dupe(u8, m) else null,
            ._sdp_mline_index = dict.sdpMLineIndex,
            ._username_fragment = if (dict.usernameFragment) |u| try frame.arena.dupe(u8, u) else null,
        });
    }

    fn getCandidate(self: *const RTCIceCandidate) []const u8 {
        return self._candidate;
    }
    fn getSdpMid(self: *const RTCIceCandidate) ?[]const u8 {
        return self._sdp_mid;
    }
    fn getSdpMLineIndex(self: *const RTCIceCandidate) ?u16 {
        return self._sdp_mline_index;
    }
    fn getFoundation(self: *const RTCIceCandidate) ?[]const u8 {
        return self._foundation;
    }
    fn getComponent(self: *const RTCIceCandidate) ?[]const u8 {
        return self._component;
    }
    fn getPriority(self: *const RTCIceCandidate) ?u32 {
        return self._priority;
    }
    fn getProtocol(self: *const RTCIceCandidate) ?[]const u8 {
        return self._protocol;
    }
    fn getAddress(self: *const RTCIceCandidate) ?[]const u8 {
        return self._address;
    }
    fn getPort(self: *const RTCIceCandidate) ?u16 {
        return self._port;
    }
    fn getType(self: *const RTCIceCandidate) ?[]const u8 {
        return self._typ;
    }
    fn getUsernameFragment(self: *const RTCIceCandidate) ?[]const u8 {
        return self._username_fragment;
    }

    const CandidateJson = struct {
        candidate: []const u8,
        sdpMid: ?[]const u8,
        sdpMLineIndex: ?u16,
        usernameFragment: ?[]const u8,
    };
    fn toJSON(self: *const RTCIceCandidate) CandidateJson {
        return .{
            .candidate = self._candidate,
            .sdpMid = self._sdp_mid,
            .sdpMLineIndex = self._sdp_mline_index,
            .usernameFragment = self._username_fragment,
        };
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCIceCandidate);

        pub const Meta = struct {
            pub const name = "RTCIceCandidate";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const constructor = bridge.constructor(RTCIceCandidate.init, .{});
        pub const candidate = bridge.accessor(RTCIceCandidate.getCandidate, null, .{});
        pub const sdpMid = bridge.accessor(RTCIceCandidate.getSdpMid, null, .{ .null_as_undefined = false });
        pub const sdpMLineIndex = bridge.accessor(RTCIceCandidate.getSdpMLineIndex, null, .{ .null_as_undefined = false });
        pub const foundation = bridge.accessor(RTCIceCandidate.getFoundation, null, .{ .null_as_undefined = false });
        pub const component = bridge.accessor(RTCIceCandidate.getComponent, null, .{ .null_as_undefined = false });
        pub const priority = bridge.accessor(RTCIceCandidate.getPriority, null, .{ .null_as_undefined = false });
        pub const protocol = bridge.accessor(RTCIceCandidate.getProtocol, null, .{ .null_as_undefined = false });
        pub const address = bridge.accessor(RTCIceCandidate.getAddress, null, .{ .null_as_undefined = false });
        pub const port = bridge.accessor(RTCIceCandidate.getPort, null, .{ .null_as_undefined = false });
        pub const @"type" = bridge.accessor(RTCIceCandidate.getType, null, .{ .null_as_undefined = false });
        pub const usernameFragment = bridge.accessor(RTCIceCandidate.getUsernameFragment, null, .{ .null_as_undefined = false });
        pub const toJSON = bridge.function(RTCIceCandidate.toJSON, .{});
    };
};

// ---------------------------------------------------------------------------
// RTCPeerConnectionIceEvent — carries the candidate to onicecandidate
// ---------------------------------------------------------------------------

pub const RTCPeerConnectionIceEvent = struct {
    pub const Proto = Event;
    _proto: *Event,
    _candidate: ?*RTCIceCandidate = null,

    const IceEventOptions = struct {};
    const Options = Event.inheritOptions(RTCPeerConnectionIceEvent, IceEventOptions);

    pub fn init(typ: []const u8, _opts: ?Options, page: *Page) !*RTCPeerConnectionIceEvent {
        const arena = try page.getArena(.tiny, "RTCPeerConnectionIceEvent");
        errdefer arena.release();
        const type_string = try String.init(arena.allocator(), typ, .{});
        return build(arena, type_string, _opts orelse Options{}, null, false, page);
    }

    // Internal dispatch path: sets the candidate directly (the JS constructor's
    // eventInitDict candidate parsing isn't needed for our own events).
    fn initInternal(candidate: ?*RTCIceCandidate, page: *Page) !*RTCPeerConnectionIceEvent {
        const arena = try page.getArena(.tiny, "RTCPeerConnectionIceEvent");
        errdefer arena.release();
        return build(arena, comptime .wrap("icecandidate"), Options{}, candidate, true, page);
    }

    fn build(arena: *lp.Arena, typ: String, opts: Options, candidate: ?*RTCIceCandidate, trusted: bool, page: *Page) !*RTCPeerConnectionIceEvent {
        const event = try page.factory.event(arena, typ, RTCPeerConnectionIceEvent{
            ._proto = undefined,
            ._candidate = candidate,
        });
        Event.populatePrototypes(event, opts, trusted);
        return event;
    }

    pub fn asEvent(self: *RTCPeerConnectionIceEvent) *Event {
        return self._proto;
    }

    fn getCandidate(self: *const RTCPeerConnectionIceEvent) ?*RTCIceCandidate {
        return self._candidate;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(RTCPeerConnectionIceEvent);

        pub const Meta = struct {
            pub const name = "RTCPeerConnectionIceEvent";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const constructor = bridge.constructor(RTCPeerConnectionIceEvent.init, .{});
        // candidate is null at end-of-gathering, so it stays JS null (not undefined).
        pub const candidate = bridge.accessor(RTCPeerConnectionIceEvent.getCandidate, null, .{ .null_as_undefined = false });
    };
};
