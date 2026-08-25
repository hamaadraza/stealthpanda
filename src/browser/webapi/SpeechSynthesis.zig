// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! window.speechSynthesis (Web Speech API, synthesis half) plus the
//! SpeechSynthesisUtterance constructor. Desktop Chrome exposes both; their
//! absence under a Chrome user-agent is a bot signal. In particular headless
//! Chrome is known to return an *empty* getVoices() list, so a Chrome UA with no
//! voices is itself a headless tell — we return a plausible macOS voice set
//! (Apple's local voices plus Chrome's bundled Google network voices).
//! window.speechSynthesis is only surfaced when impersonating (see
//! Window.getSpeechSynthesis).

const lp = @import("lightpanda");

const js = @import("../js/js.zig");
const Page = @import("../Page.zig");
const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ SpeechSynthesis, SpeechSynthesisUtterance };
}

const SpeechSynthesis = @This();

// Zero-state; the field just gives the wrapper a non-empty allocation.
_pad: bool = false,

// A SpeechSynthesisVoice, returned as a plain object in the getVoices() array.
// (Real Chrome returns SpeechSynthesisVoice instances; a fingerprinter reads the
// name/lang/default fields, which match.)
const Voice = struct {
    voiceURI: []const u8,
    name: []const u8,
    lang: []const u8,
    localService: bool,
    default: bool,
};

// A representative macOS Chrome voice list: Apple's on-device voices
// (localService=true) plus the Google network voices Chrome bundles
// (localService=false). Samantha is the en-US system default.
const voices = [_]Voice{
    .{ .voiceURI = "com.apple.voice.compact.en-US.Samantha", .name = "Samantha", .lang = "en-US", .localService = true, .default = true },
    .{ .voiceURI = "com.apple.voice.compact.en-GB.Daniel", .name = "Daniel", .lang = "en-GB", .localService = true, .default = false },
    .{ .voiceURI = "com.apple.voice.compact.en-AU.Karen", .name = "Karen", .lang = "en-AU", .localService = true, .default = false },
    .{ .voiceURI = "com.apple.eloquence.en-US.Flo", .name = "Flo", .lang = "en-US", .localService = true, .default = false },
    .{ .voiceURI = "Google US English", .name = "Google US English", .lang = "en-US", .localService = false, .default = false },
    .{ .voiceURI = "Google UK English Male", .name = "Google UK English Male", .lang = "en-GB", .localService = false, .default = false },
};

pub fn getVoices(_: *const SpeechSynthesis) []const Voice {
    return &voices;
}

pub fn getSpeaking(_: *const SpeechSynthesis) bool {
    return false;
}
pub fn getPending(_: *const SpeechSynthesis) bool {
    return false;
}
pub fn getPaused(_: *const SpeechSynthesis) bool {
    return false;
}

// speak/cancel/pause/resume are no-ops: there is no audio device, and the
// utterance queue stays empty (speaking/pending stay false).
pub fn speak(_: *const SpeechSynthesis, _: js.Value) void {}
pub fn cancel(_: *const SpeechSynthesis) void {}
pub fn pause(_: *const SpeechSynthesis) void {}
// `resume` is a Zig keyword; expose it under the JS name via @"resume" below.
pub fn resumeSynth(_: *const SpeechSynthesis) void {}

pub const JsApi = struct {
    pub const bridge = js.Bridge(SpeechSynthesis);

    pub const Meta = struct {
        pub const name = "SpeechSynthesis";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
        pub const empty_with_no_proto = true;
    };

    pub const getVoices = bridge.function(SpeechSynthesis.getVoices, .{});
    pub const speaking = bridge.accessor(SpeechSynthesis.getSpeaking, null, .{});
    pub const pending = bridge.accessor(SpeechSynthesis.getPending, null, .{});
    pub const paused = bridge.accessor(SpeechSynthesis.getPaused, null, .{});
    pub const speak = bridge.function(SpeechSynthesis.speak, .{ .noop = true });
    pub const cancel = bridge.function(SpeechSynthesis.cancel, .{ .noop = true });
    pub const pause = bridge.function(SpeechSynthesis.pause, .{ .noop = true });
    pub const @"resume" = bridge.function(SpeechSynthesis.resumeSynth, .{ .noop = true });
};

// window.SpeechSynthesisUtterance — the constructor Chrome pairs with
// speechSynthesis. Stores its text/lang and the settable rate/pitch/volume so a
// round-trip (`new SpeechSynthesisUtterance("x").text === "x"`) holds.
pub const SpeechSynthesisUtterance = struct {
    _rc: lp.RC = .{},
    _arena: *lp.Arena,
    _text: []const u8 = "",
    _lang: []const u8 = "",
    _volume: f64 = 1.0,
    _rate: f64 = 1.0,
    _pitch: f64 = 1.0,

    pub fn init(text_: ?[]const u8, exec: *const Execution) !*SpeechSynthesisUtterance {
        const arena = try exec.getArena(.tiny, "SpeechSynthesisUtterance");
        errdefer arena.release();
        const self = try arena.create(SpeechSynthesisUtterance);
        self.* = .{
            ._arena = arena,
            ._text = if (text_) |t| try arena.dupe(u8, t) else "",
        };
        return self;
    }

    pub fn deinit(self: *SpeechSynthesisUtterance, _: *Page) void {
        self._arena.release();
    }
    pub fn acquireRef(self: *SpeechSynthesisUtterance) void {
        self._rc.acquire();
    }
    pub fn releaseRef(self: *SpeechSynthesisUtterance, page: *Page) void {
        self._rc.release(self, page);
    }

    fn getText(self: *const SpeechSynthesisUtterance) []const u8 {
        return self._text;
    }
    fn setText(self: *SpeechSynthesisUtterance, value: []const u8) !void {
        self._text = try self._arena.dupe(u8, value);
    }
    fn getLang(self: *const SpeechSynthesisUtterance) []const u8 {
        return self._lang;
    }
    fn setLang(self: *SpeechSynthesisUtterance, value: []const u8) !void {
        self._lang = try self._arena.dupe(u8, value);
    }
    fn getVolume(self: *const SpeechSynthesisUtterance) f64 {
        return self._volume;
    }
    fn setVolume(self: *SpeechSynthesisUtterance, value: f64) void {
        self._volume = value;
    }
    fn getRate(self: *const SpeechSynthesisUtterance) f64 {
        return self._rate;
    }
    fn setRate(self: *SpeechSynthesisUtterance, value: f64) void {
        self._rate = value;
    }
    fn getPitch(self: *const SpeechSynthesisUtterance) f64 {
        return self._pitch;
    }
    fn setPitch(self: *SpeechSynthesisUtterance, value: f64) void {
        self._pitch = value;
    }
    fn getVoice(_: *const SpeechSynthesisUtterance) ?js.Value {
        return null;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(SpeechSynthesisUtterance);

        pub const Meta = struct {
            pub const name = "SpeechSynthesisUtterance";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const constructor = bridge.constructor(SpeechSynthesisUtterance.init, .{});
        pub const text = bridge.accessor(getText, setText, .{});
        pub const lang = bridge.accessor(getLang, setLang, .{});
        pub const volume = bridge.accessor(getVolume, setVolume, .{});
        pub const rate = bridge.accessor(getRate, setRate, .{});
        pub const pitch = bridge.accessor(getPitch, setPitch, .{});
        pub const voice = bridge.accessor(getVoice, null, .{ .null_as_undefined = false });
    };
};
