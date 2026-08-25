// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! Synthetic human-like behavior. A non-interactive fetch emits no pointer
//! motion, so behavioral headless checks (detect-headless's mouse-move test)
//! and bot sensors that score mouse entropy see a dead pointer. When
//! impersonating, this drives a short human-ish mouse path — a momentum random
//! walk that bounces off the viewport edges — dispatching real `mousemove`
//! events with non-zero movementX/Y.
//!
//! The path is spread over real time via the frame scheduler so consecutive
//! events carry realistic, increasing `timeStamp`s (a synchronous burst would
//! share one timestamp — an obvious tell). To make the events actually fire
//! before the page settles, the mover holds a `_pending_load` on the frame:
//! the default fetch waits on the `load` event, and `load` doesn't fire until
//! every pending load clears, so the wait pumps the scheduler for the whole
//! path. `blocks_done=true` likewise keeps the `is_done` fallback from firing.
//!
//! Started from Frame._documentIsLoaded (gated on impersonation + main frame).

const std = @import("std");
const lp = @import("lightpanda");

const Frame = @import("../browser/Frame.zig");
const user_input = @import("../browser/frame/user_input.zig");

const log = lp.log;

// Enough that >50 land after the page's mousemove listener is attached
// (detect-headless needs >50). At ~12ms spacing the path lasts ~0.7s, which
// also bounds how long `load` is held.
const moves: u32 = 58;

const MouseMover = struct {
    frame: *Frame,
    arena: *lp.Arena,
    prng: std.Random.DefaultPrng,
    x: f64,
    y: f64,
    vx: f64 = 0,
    vy: f64 = 0,
    count: u32 = 0,

    fn run(ptr: *anyopaque) anyerror!?u32 {
        const self: *MouseMover = @ptrCast(@alignCast(ptr));
        const frame = self.frame;
        var rand = self.prng.random();

        const viewport = frame._page.getViewport();
        const vw: f64 = @floatFromInt(viewport.width);
        const vh: f64 = @floatFromInt(viewport.height);

        // Momentum (heavy damping) + small random acceleration = a curved,
        // non-linear path rather than a straight line or teleport.
        self.vx = self.vx * 0.82 + (rand.float(f64) - 0.5) * 24;
        self.vy = self.vy * 0.82 + (rand.float(f64) - 0.5) * 24;
        var nx = self.x + self.vx;
        var ny = self.y + self.vy;
        if (nx < 1) {
            nx = 1;
            self.vx = -self.vx;
        }
        if (nx > vw - 1) {
            nx = vw - 1;
            self.vx = -self.vx;
        }
        if (ny < 1) {
            ny = 1;
            self.vy = -self.vy;
        }
        if (ny > vh - 1) {
            ny = vh - 1;
            self.vy = -self.vy;
        }

        const mx = @round(nx - self.x);
        const my = @round(ny - self.y);
        self.x = nx;
        self.y = ny;

        user_input.triggerMouseMoveDelta(frame, @round(nx), @round(ny), mx, my) catch {};

        self.count += 1;
        if (self.count >= moves) {
            self.finish();
            return null;
        }

        // Re-add (rather than return the interval) so the next task keeps
        // blocks_done=true — a plain recurring task is forced to
        // blocks_done=false, which would let the page settle mid-path. Exactly
        // one mover task is ever queued, so teardown runs the finalizer once.
        // ~8–20ms spacing ≈ a 50–120Hz pointer.
        schedule(self, 8 + rand.uintLessThan(u32, 12));
        return null;
    }

    // Release the held pending load (letting `load` fire) and free the arena.
    // Completion path: the task has been removed from the queue, so the
    // finalizer won't also run.
    fn finish(self: *MouseMover) void {
        self.frame.pendingLoadCompleted();
        self.arena.release();
    }

    // Called by the scheduler only if the task is still queued at teardown, i.e.
    // the page is being destroyed — the pending load is moot, just free.
    fn finalize(ptr: *anyopaque) void {
        const self: *MouseMover = @ptrCast(@alignCast(ptr));
        self.arena.release();
    }
};

fn schedule(mover: *MouseMover, in_ms: u32) void {
    mover.frame.js.scheduler.add(mover, MouseMover.run, in_ms, .{
        .name = "stealth-mouse",
        .finalizer = MouseMover.finalize,
        .blocks_done = true,
    }) catch |err| {
        log.warn(.browser, "stealthpanda: mouse reschedule", .{ .err = err });
        mover.finish();
    };
}

/// Start the synthetic mouse path for `frame`. Caller gates on impersonation.
pub fn startMouseMovement(frame: *Frame) void {
    startMouseMovementErr(frame) catch |err| {
        // Errored before taking the pending load, so nothing to release here.
        log.warn(.browser, "stealthpanda: mouse movement", .{ .err = err });
    };
}

fn startMouseMovementErr(frame: *Frame) !void {
    const arena = try frame.getArena(.tiny, "stealth-mouse");
    errdefer arena.release();

    const viewport = frame._page.getViewport();
    const mover = try arena.create(MouseMover);
    mover.* = .{
        .frame = frame,
        .arena = arena,
        .prng = std.Random.DefaultPrng.init(@intFromPtr(frame)),
        .x = @as(f64, @floatFromInt(viewport.width)) * 0.5,
        .y = @as(f64, @floatFromInt(viewport.height)) * 0.5,
    };

    // Hold the `load` event until the path finishes so the wait pumps the
    // scheduler for its whole duration. `schedule` clears this on failure;
    // MouseMover.finish clears it on completion. From here the mover owns the
    // arena and the pending load.
    frame._pending_loads += 1;
    schedule(mover, 12);
}
