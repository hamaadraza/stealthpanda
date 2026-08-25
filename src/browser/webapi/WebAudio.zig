// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! A minimal, coherent Web Audio API surface: AudioContext plus its
//! AudioDestinationNode and AnalyserNode. Desktop Chrome always exposes Web
//! Audio; its absence under a Chrome user-agent is a bot signal (browserleaks
//! flags "Web Audio API: Disabled" and reads the node properties surfaced here).
//!
//! Scope: this reports the static node fingerprint (sample rate, channel layout,
//! FFT/decibel defaults) that a real macOS Chrome reports. It does NOT run a DSP
//! graph — the render-based *audio fingerprint* (OfflineAudioContext + oscillator
//! -> compressor -> hash) is a separate, deeper vector and is intentionally not
//! implemented, so OfflineAudioContext is left absent rather than present-but-
//! broken (a wrong render hash is a stronger tell than a missing constructor).

const js = @import("../js/js.zig");
const Execution = js.Execution;

pub fn registerTypes() []const type {
    return &.{ AudioContext, AudioDestinationNode, AnalyserNode };
}

// ---------------------------------------------------------------------------
// AudioContext (BaseAudioContext surface)
// ---------------------------------------------------------------------------

const AudioContext = @This();

_destination: *AudioDestinationNode,
// macOS CoreAudio commonly runs at 48 kHz; Chrome's AudioContext follows the
// hardware rate.
_sample_rate: f64 = 48000,

const Options = struct {
    sampleRate: ?f64 = null,
};

pub fn init(options_: ?Options, exec: *const Execution) !*AudioContext {
    const destination = try exec._factory.create(AudioDestinationNode{});
    return exec._factory.create(AudioContext{
        ._destination = destination,
        ._sample_rate = if (options_) |o| (o.sampleRate orelse 48000) else 48000,
    });
}

pub fn getDestination(self: *const AudioContext) *AudioDestinationNode {
    return self._destination;
}

pub fn getSampleRate(self: *const AudioContext) f64 {
    return self._sample_rate;
}

// A fresh AudioContext is gated by Chrome's autoplay policy until a user
// gesture, so without interaction it stays "suspended".
pub fn getState(_: *const AudioContext) []const u8 {
    return "suspended";
}

pub fn getBaseLatency(_: *const AudioContext) f64 {
    return 0.005333333333333333; // 256 frames / 48000, a typical Chrome value
}

pub fn createAnalyser(_: *const AudioContext, exec: *const Execution) !*AnalyserNode {
    return exec._factory.create(AnalyserNode{});
}

// `resume`/`suspend` are Zig keywords; exposed under their JS names below.
pub fn resumeCtx(_: *const AudioContext, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise({});
}
pub fn suspendCtx(_: *const AudioContext, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise({});
}
pub fn close(_: *const AudioContext, exec: *const Execution) !js.Promise {
    return exec.js.local.?.resolvePromise({});
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(AudioContext);

    pub const Meta = struct {
        pub const name = "AudioContext";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const constructor = bridge.constructor(AudioContext.init, .{});
    pub const destination = bridge.accessor(AudioContext.getDestination, null, .{});
    pub const sampleRate = bridge.accessor(AudioContext.getSampleRate, null, .{});
    pub const state = bridge.accessor(AudioContext.getState, null, .{});
    pub const baseLatency = bridge.accessor(AudioContext.getBaseLatency, null, .{});
    pub const createAnalyser = bridge.function(AudioContext.createAnalyser, .{});
    pub const @"resume" = bridge.function(AudioContext.resumeCtx, .{});
    pub const @"suspend" = bridge.function(AudioContext.suspendCtx, .{});
    pub const close = bridge.function(AudioContext.close, .{});
};

// ---------------------------------------------------------------------------
// AudioDestinationNode
// ---------------------------------------------------------------------------

pub const AudioDestinationNode = struct {
    _pad: bool = false,

    fn getMaxChannelCount(_: *const AudioDestinationNode) u32 {
        return 2;
    }
    fn getNumberOfInputs(_: *const AudioDestinationNode) u32 {
        return 1;
    }
    fn getNumberOfOutputs(_: *const AudioDestinationNode) u32 {
        return 0;
    }
    fn getChannelCount(_: *const AudioDestinationNode) u32 {
        return 2;
    }
    fn getChannelCountMode(_: *const AudioDestinationNode) []const u8 {
        return "explicit";
    }
    fn getChannelInterpretation(_: *const AudioDestinationNode) []const u8 {
        return "speakers";
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(AudioDestinationNode);

        pub const Meta = struct {
            pub const name = "AudioDestinationNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const maxChannelCount = bridge.accessor(AudioDestinationNode.getMaxChannelCount, null, .{});
        pub const numberOfInputs = bridge.accessor(AudioDestinationNode.getNumberOfInputs, null, .{});
        pub const numberOfOutputs = bridge.accessor(AudioDestinationNode.getNumberOfOutputs, null, .{});
        pub const channelCount = bridge.accessor(AudioDestinationNode.getChannelCount, null, .{});
        pub const channelCountMode = bridge.accessor(AudioDestinationNode.getChannelCountMode, null, .{});
        pub const channelInterpretation = bridge.accessor(AudioDestinationNode.getChannelInterpretation, null, .{});
    };
};

// ---------------------------------------------------------------------------
// AnalyserNode
// ---------------------------------------------------------------------------

pub const AnalyserNode = struct {
    _pad: bool = false,

    fn getFftSize(_: *const AnalyserNode) u32 {
        return 2048;
    }
    fn getFrequencyBinCount(_: *const AnalyserNode) u32 {
        return 1024;
    }
    fn getMinDecibels(_: *const AnalyserNode) f64 {
        return -100;
    }
    fn getMaxDecibels(_: *const AnalyserNode) f64 {
        return -30;
    }
    fn getSmoothingTimeConstant(_: *const AnalyserNode) f64 {
        return 0.8;
    }
    fn getNumberOfInputs(_: *const AnalyserNode) u32 {
        return 1;
    }
    fn getNumberOfOutputs(_: *const AnalyserNode) u32 {
        return 1;
    }
    fn getChannelCount(_: *const AnalyserNode) u32 {
        return 2;
    }
    fn getChannelCountMode(_: *const AnalyserNode) []const u8 {
        return "max";
    }
    fn getChannelInterpretation(_: *const AnalyserNode) []const u8 {
        return "speakers";
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(AnalyserNode);

        pub const Meta = struct {
            pub const name = "AnalyserNode";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const fftSize = bridge.accessor(AnalyserNode.getFftSize, null, .{});
        pub const frequencyBinCount = bridge.accessor(AnalyserNode.getFrequencyBinCount, null, .{});
        pub const minDecibels = bridge.accessor(AnalyserNode.getMinDecibels, null, .{});
        pub const maxDecibels = bridge.accessor(AnalyserNode.getMaxDecibels, null, .{});
        pub const smoothingTimeConstant = bridge.accessor(AnalyserNode.getSmoothingTimeConstant, null, .{});
        pub const numberOfInputs = bridge.accessor(AnalyserNode.getNumberOfInputs, null, .{});
        pub const numberOfOutputs = bridge.accessor(AnalyserNode.getNumberOfOutputs, null, .{});
        pub const channelCount = bridge.accessor(AnalyserNode.getChannelCount, null, .{});
        pub const channelCountMode = bridge.accessor(AnalyserNode.getChannelCountMode, null, .{});
        pub const channelInterpretation = bridge.accessor(AnalyserNode.getChannelInterpretation, null, .{});
    };
};
