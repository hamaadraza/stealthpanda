// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! Synthetic human-like behavior. A non-interactive fetch emits no pointer
//! motion, so behavioral headless checks (detect-headless's mouse-move test)
//! and bot sensors that score mouse entropy see a dead pointer. When
//! impersonating, this drives a short human-ish mouse path — a momentum random
//! walk that bounces off the viewport edges — dispatching real `mousemove`
//! events with non-zero movementX/Y.
//!
//! Fired synchronously from Frame._documentIsLoaded (after the page's own
//! scripts have run and attached their listeners, but before the `load` event
//! the default fetch waits on — a scheduler-spread path would never run before
//! `load` completes on a fast page). Gated on impersonation by the caller.

const std = @import("std");
const lp = @import("lightpanda");

const Frame = @import("../browser/Frame.zig");
const user_input = @import("../browser/frame/user_input.zig");

const log = lp.log;

// Enough that >50 land after the page's mousemove listener is attached
// (detect-headless needs >50).
const moves: u32 = 64;

/// Drive the synthetic mouse path for `frame`. Caller gates on impersonation.
pub fn startMouseMovement(frame: *Frame) void {
    fireMousePath(frame) catch |err| {
        log.warn(.browser, "stealthpanda: mouse movement", .{ .err = err });
    };
}

fn fireMousePath(frame: *Frame) !void {
    const viewport = frame._page.getViewport();
    const vw: f64 = @floatFromInt(viewport.width);
    const vh: f64 = @floatFromInt(viewport.height);

    var prng = std.Random.DefaultPrng.init(@intFromPtr(frame));
    var rand = prng.random();

    var x: f64 = vw * 0.5;
    var y: f64 = vh * 0.5;
    var vx: f64 = 0;
    var vy: f64 = 0;

    var i: u32 = 0;
    while (i < moves) : (i += 1) {
        // Momentum (heavy damping) + small random acceleration = a curved,
        // non-linear path rather than a straight line or teleport.
        vx = vx * 0.82 + (rand.float(f64) - 0.5) * 24;
        vy = vy * 0.82 + (rand.float(f64) - 0.5) * 24;
        var nx = x + vx;
        var ny = y + vy;
        if (nx < 1) {
            nx = 1;
            vx = -vx;
        }
        if (nx > vw - 1) {
            nx = vw - 1;
            vx = -vx;
        }
        if (ny < 1) {
            ny = 1;
            vy = -vy;
        }
        if (ny > vh - 1) {
            ny = vh - 1;
            vy = -vy;
        }

        const mx = @round(nx - x);
        const my = @round(ny - y);
        x = nx;
        y = ny;

        // A move that lands on no element is skipped inside the helper.
        user_input.triggerMouseMoveDelta(frame, @round(nx), @round(ny), mx, my) catch {};
    }
}
