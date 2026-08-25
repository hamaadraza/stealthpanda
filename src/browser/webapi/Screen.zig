// Copyright (C) 2023-2025  Lightpanda (Selecy SAS)
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

const js = @import("../js/js.zig");
const Frame = @import("../Frame.zig");
const EventTarget = @import("EventTarget.zig");

pub fn registerTypes() []const type {
    return &.{
        Screen,
        Orientation,
    };
}

const Screen = @This();

pub const Proto = EventTarget;

_proto: *EventTarget,
_orientation: ?*Orientation = null,

pub fn asEventTarget(self: *Screen) *EventTarget {
    return self._proto;
}

pub fn getOrientation(self: *Screen, frame: *Frame) !*Orientation {
    if (self._orientation) |orientation| {
        return orientation;
    }
    const orientation = try Orientation.init(frame);
    self._orientation = orientation;
    return orientation;
}

pub fn getWidth(_: *const Screen, frame: *Frame) u32 {
    return frame._page.getViewport().width;
}

pub fn getHeight(_: *const Screen, frame: *Frame) u32 {
    const h = frame._page.getViewport().height;
    // stealthpanda: off-path the screen == the layout viewport (honest
    // Lightpanda). When impersonating, a real monitor is taller than the
    // browser's content area: report a physical screen that leaves room for the
    // window chrome (+88 in outerHeight) plus the menu bar, so the invariant a
    // real browser always satisfies — outerHeight <= availHeight <= screen —
    // holds. outerHeight is viewport+88 and availHeight is screen-25 below, so
    // +120 keeps outer(1168) < avail(1175) < screen(1200) for a 1080 viewport.
    if (impersonating(frame)) return h + 120;
    return h;
}

fn impersonating(frame: *Frame) bool {
    return frame._session.browser.http_client.impersonateIdentity() != null;
}

// stealthpanda: the usable screen area. Off-path keeps Lightpanda's fixed 1040;
// on-path it tracks the (larger) physical screen minus the macOS menu bar (~25).
pub fn getAvailHeight(_: *const Screen, frame: *Frame) u32 {
    if (impersonating(frame)) return frame._page.getViewport().height + 95;
    return 1040;
}

// stealthpanda: real browsers always expose availLeft/availTop as numbers;
// their absence (undefined) is a tell. On macOS the menu bar occupies the top
// (~25px), the left edge is flush (0). undefined off-path.
pub fn getAvailLeft(_: *const Screen, frame: *Frame) ?i32 {
    if (!impersonating(frame)) return null;
    return 0;
}

pub fn getAvailTop(_: *const Screen, frame: *Frame) ?i32 {
    if (!impersonating(frame)) return null;
    return 25;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Screen);

    pub const Meta = struct {
        pub const name = "Screen";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const width = bridge.accessor(Screen.getWidth, null, .{});
    pub const height = bridge.accessor(Screen.getHeight, null, .{});
    pub const availWidth = bridge.accessor(Screen.getWidth, null, .{});
    // stealthpanda: availHeight is now impersonation-aware (was property 1040);
    // availLeft/availTop added (undefined off-path).
    pub const availHeight = bridge.accessor(Screen.getAvailHeight, null, .{});
    pub const availLeft = bridge.accessor(Screen.getAvailLeft, null, .{ .null_as_undefined = true });
    pub const availTop = bridge.accessor(Screen.getAvailTop, null, .{ .null_as_undefined = true });
    pub const colorDepth = bridge.property(24, .{ .template = false });
    pub const pixelDepth = bridge.property(24, .{ .template = false });
    pub const orientation = bridge.accessor(Screen.getOrientation, null, .{});
};

pub const Orientation = struct {
    pub const Proto = EventTarget;

    _proto: *EventTarget,

    pub fn init(frame: *Frame) !*Orientation {
        return frame._factory.eventTarget(Orientation{
            ._proto = undefined,
        });
    }

    pub fn asEventTarget(self: *Orientation) *EventTarget {
        return self._proto;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Orientation);

        pub const Meta = struct {
            pub const name = "ScreenOrientation";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };

        pub const angle = bridge.property(0, .{ .template = false });
        pub const @"type" = bridge.property("landscape-primary", .{ .template = false });
    };
};
