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

// stealthpanda: an empty navigator.plugins (and absent navigator.mimeTypes) is
// a classic headless signature. When impersonating, this exposes Chrome's fixed
// post-2020 PDF plugin set — 5 plugins all sharing the same 2 mime types — via
// the shared Graph built once by Navigator. Off-path the arrays stay empty
// (`_items = &.{}`), so honest Lightpanda is unchanged.

const std = @import("std");
const js = @import("../js/js.zig");
const Frame = @import("../Frame.zig");
const Execution = js.Execution;
const GenericIterator = @import("collections/iterator.zig").Entry;

pub fn registerTypes() []const type {
    return &.{ PluginArray, Plugin, MimeTypeArray, MimeType, PluginIterator, MimeTypeIterator };
}

// Chrome's fixed plugin names; all point at the built-in PDF viewer.
const plugin_names = [_][:0]const u8{
    "PDF Viewer",
    "Chrome PDF Viewer",
    "Chromium PDF Viewer",
    "Microsoft Edge PDF Viewer",
    "WebKit built-in PDF",
};
const mime_names = [_][:0]const u8{ "application/pdf", "text/pdf" };

const filename = "internal-pdf-viewer";
const description = "Portable Document Format";

/// The plugin/mimetype object graph, built once and shared between
/// navigator.plugins and navigator.mimeTypes so their objects have the same
/// identities Chrome's do (mimeType.enabledPlugin === plugins[0], etc.).
pub const Graph = struct {
    plugins: [plugin_names.len]*Plugin,
    mimes: [mime_names.len]*MimeType,

    pub fn build(exec: *const Execution) !Graph {
        var mimes: [mime_names.len]*MimeType = undefined;
        for (mime_names, 0..) |t, i| {
            mimes[i] = try exec._factory.create(MimeType{ .mime_type = t });
        }
        var plugins: [plugin_names.len]*Plugin = undefined;
        for (plugin_names, 0..) |name, i| {
            plugins[i] = try exec._factory.create(Plugin{ .name = name, ._mimes = mimes });
        }
        for (mimes) |m| m._plugin = plugins[0]; // enabledPlugin = "PDF Viewer"
        return .{ .plugins = plugins, .mimes = mimes };
    }
};

const PluginArray = @This();

_items: []const *Plugin = &.{},

pub fn getLength(self: *const PluginArray) u32 {
    return @intCast(self._items.len);
}
pub fn refresh(_: *const PluginArray) void {}
pub fn getAtIndex(self: *const PluginArray, index: usize) ?*Plugin {
    if (index >= self._items.len) return null;
    return self._items[index];
}
pub fn getByName(self: *const PluginArray, name: []const u8) ?*Plugin {
    for (self._items) |p| {
        if (std.mem.eql(u8, p.name, name)) return p;
    }
    return null;
}
fn values(self: *const PluginArray, frame: *Frame) !*PluginIterator {
    return .init(.{ .items = self._items, .index = 0 }, frame);
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(PluginArray);

    pub const Meta = struct {
        pub const name = "PluginArray";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    pub const length = bridge.accessor(PluginArray.getLength, null, .{});
    pub const refresh = bridge.function(PluginArray.refresh, .{});
    pub const @"[int]" = bridge.indexed(PluginArray.getAtIndex, null, .{ .null_as_undefined = true });
    pub const @"[str]" = bridge.namedIndexed(PluginArray.getByName, null, null, null, null, .{ .null_as_undefined = true });
    pub const item = bridge.function(_item, .{});
    fn _item(self: *const PluginArray, index: i32) ?*Plugin {
        if (index < 0) return null;
        return self.getAtIndex(@intCast(index));
    }
    pub const namedItem = bridge.function(PluginArray.getByName, .{});
    pub const symbol_iterator = bridge.iterator(PluginArray.values, .{});
};

const Plugin = struct {
    name: [:0]const u8,
    _mimes: [mime_names.len]*MimeType,

    pub fn getName(self: *const Plugin) [:0]const u8 {
        return self.name;
    }
    pub fn getFilename(_: *const Plugin) [:0]const u8 {
        return filename;
    }
    pub fn getDescription(_: *const Plugin) [:0]const u8 {
        return description;
    }
    pub fn getLength(self: *const Plugin) u32 {
        return @intCast(self._mimes.len);
    }
    pub fn getAtIndex(self: *const Plugin, index: usize) ?*MimeType {
        if (index >= self._mimes.len) return null;
        return self._mimes[index];
    }
    pub fn getByName(self: *const Plugin, name: []const u8) ?*MimeType {
        for (self._mimes) |m| {
            if (std.mem.eql(u8, m.mime_type, name)) return m;
        }
        return null;
    }
    fn values(self: *const Plugin, frame: *Frame) !*MimeTypeIterator {
        return .init(.{ .items = &self._mimes, .index = 0 }, frame);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(Plugin);
        pub const Meta = struct {
            pub const name = "Plugin";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const name = bridge.accessor(Plugin.getName, null, .{});
        pub const filename = bridge.accessor(Plugin.getFilename, null, .{});
        pub const description = bridge.accessor(Plugin.getDescription, null, .{});
        pub const length = bridge.accessor(Plugin.getLength, null, .{});
        pub const @"[int]" = bridge.indexed(Plugin.getAtIndex, null, .{ .null_as_undefined = true });
        pub const @"[str]" = bridge.namedIndexed(Plugin.getByName, null, null, null, null, .{ .null_as_undefined = true });
        pub const item = bridge.function(_item, .{});
        fn _item(self: *const Plugin, index: i32) ?*MimeType {
            if (index < 0) return null;
            return self.getAtIndex(@intCast(index));
        }
        pub const namedItem = bridge.function(Plugin.getByName, .{});
        pub const symbol_iterator = bridge.iterator(Plugin.values, .{});
    };
};

const MimeType = struct {
    mime_type: [:0]const u8,
    _plugin: *Plugin = undefined,

    pub fn getType(self: *const MimeType) [:0]const u8 {
        return self.mime_type;
    }
    pub fn getSuffixes(_: *const MimeType) [:0]const u8 {
        return "pdf";
    }
    pub fn getDescription(_: *const MimeType) [:0]const u8 {
        return description;
    }
    pub fn getEnabledPlugin(self: *const MimeType) *Plugin {
        return self._plugin;
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeType);
        pub const Meta = struct {
            pub const name = "MimeType";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const @"type" = bridge.accessor(MimeType.getType, null, .{});
        pub const suffixes = bridge.accessor(MimeType.getSuffixes, null, .{});
        pub const description = bridge.accessor(MimeType.getDescription, null, .{});
        pub const enabledPlugin = bridge.accessor(MimeType.getEnabledPlugin, null, .{});
    };
};

pub const MimeTypeArray = struct {
    _items: []const *MimeType = &.{},

    pub fn getLength(self: *const MimeTypeArray) u32 {
        return @intCast(self._items.len);
    }
    pub fn getAtIndex(self: *const MimeTypeArray, index: usize) ?*MimeType {
        if (index >= self._items.len) return null;
        return self._items[index];
    }
    pub fn getByName(self: *const MimeTypeArray, name: []const u8) ?*MimeType {
        for (self._items) |m| {
            if (std.mem.eql(u8, m.mime_type, name)) return m;
        }
        return null;
    }
    fn values(self: *const MimeTypeArray, frame: *Frame) !*MimeTypeIterator {
        return .init(.{ .items = self._items, .index = 0 }, frame);
    }

    pub const JsApi = struct {
        pub const bridge = js.Bridge(MimeTypeArray);
        pub const Meta = struct {
            pub const name = "MimeTypeArray";
            pub const prototype_chain = bridge.prototypeChain();
            pub var class_id: bridge.ClassId = undefined;
        };
        pub const length = bridge.accessor(MimeTypeArray.getLength, null, .{});
        pub const @"[int]" = bridge.indexed(MimeTypeArray.getAtIndex, null, .{ .null_as_undefined = true });
        pub const @"[str]" = bridge.namedIndexed(MimeTypeArray.getByName, null, null, null, null, .{ .null_as_undefined = true });
        pub const item = bridge.function(_item, .{});
        fn _item(self: *const MimeTypeArray, index: i32) ?*MimeType {
            if (index < 0) return null;
            return self.getAtIndex(@intCast(index));
        }
        pub const namedItem = bridge.function(MimeTypeArray.getByName, .{});
        pub const symbol_iterator = bridge.iterator(MimeTypeArray.values, .{});
    };
};

const PluginIterator = GenericIterator(PluginIter, null);
const PluginIter = struct {
    items: []const *Plugin,
    index: usize,
    pub fn next(self: *PluginIter, _: *Frame) ?*Plugin {
        if (self.index >= self.items.len) return null;
        defer self.index += 1;
        return self.items[self.index];
    }
};

const MimeTypeIterator = GenericIterator(MimeTypeIter, null);
const MimeTypeIter = struct {
    items: []const *MimeType,
    index: usize,
    pub fn next(self: *MimeTypeIter, _: *Frame) ?*MimeType {
        if (self.index >= self.items.len) return null;
        defer self.index += 1;
        return self.items[self.index];
    }
};
