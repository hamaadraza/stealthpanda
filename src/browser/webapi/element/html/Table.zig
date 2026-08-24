const lp = @import("lightpanda");
const Factory = @import("../../../Factory.zig");
const js = @import("../../../js/js.zig");
const Node = @import("../../Node.zig");
const Frame = @import("../../../Frame.zig");
const Element = @import("../../Element.zig");
const HtmlElement = @import("../Html.zig");
const collections = @import("../../collections.zig");

const Table = @This();

pub const Proto = HtmlElement;

_pad: bool = false,
_proto_canary: if (lp.IS_DEBUG) *HtmlElement else void = undefined,

pub fn asElement(self: *Table) *Element {
    return Factory.protoOf(self).asElement();
}
pub fn asNode(self: *Table) *Node {
    return self.asElement().asNode();
}

pub fn getTBodies(self: *Table, frame: *Frame) collections.NodeLive(.child_tag) {
    return collections.NodeLive(.child_tag).init(self.asNode(), .tbody, frame);
}

// HTMLTableElement.insertRow(index=-1): creates a <tr>, inserts it, returns it.
// index -1 or == rows.length appends to the last tbody (creating one if the
// table has none, per spec). Previously unimplemented — pages that build tables
// dynamically (table.insertRow()) threw, which is itself a non-Chrome tell.
pub fn insertRow(self: *Table, index_: ?i32, frame: *Frame) !*Node {
    const num = self.rowCount();
    const index = index_ orelse -1;
    if (index < -1 or index > num) {
        return error.IndexSizeError;
    }
    const tr = try Frame.node_factory.createElementNS(frame, .html, "tr", null);
    if (index == -1 or index == num) {
        const section = try self.lastTbodyOrCreate(frame);
        _ = try section.appendChild(tr, frame);
    } else {
        const ref = self.findRow(index).?;
        _ = try ref.parentNode().?.insertBefore(tr, ref, frame);
    }
    return tr;
}

fn lastTbodyOrCreate(self: *Table, frame: *Frame) !*Node {
    var last: ?*Node = null;
    var it = self.asNode().childrenIterator();
    while (it.next()) |child| {
        const el = child.is(Element) orelse continue;
        if (el.getTag() == .tbody) last = child;
    }
    if (last) |tb| {
        return tb;
    }
    const tbody = try Frame.node_factory.createElementNS(frame, .html, "tbody", null);
    _ = try self.asNode().appendChild(tbody, frame);
    return tbody;
}

fn rowCount(self: *Table) i32 {
    var n: i32 = 0;
    n += self.sectionRowCount(.thead);
    var it = self.asNode().childrenIterator();
    while (it.next()) |child| {
        const el = child.is(Element) orelse continue;
        switch (el.getTag()) {
            .tr => n += 1,
            .tbody => n += trChildCount(child),
            else => {},
        }
    }
    n += self.sectionRowCount(.tfoot);
    return n;
}

fn sectionRowCount(self: *Table, tag: Element.Tag) i32 {
    var n: i32 = 0;
    var it = self.asNode().childrenIterator();
    while (it.next()) |child| {
        const el = child.is(Element) orelse continue;
        if (el.getTag() == tag) n += trChildCount(child);
    }
    return n;
}

fn trChildCount(section: *Node) i32 {
    var n: i32 = 0;
    var it = section.childrenIterator();
    while (it.next()) |child| {
        const el = child.is(Element) orelse continue;
        if (el.getTag() == .tr) n += 1;
    }
    return n;
}

pub fn deleteRow(self: *Table, index: i32, frame: *Frame) !void {
    if (index < -1) {
        return error.IndexSizeError;
    }
    const row = self.findRow(index) orelse {
        if (index == -1) {
            // deleteRow(-1) on a rowless table is a no-op.
            return;
        }
        return error.IndexSizeError;
    };
    _ = try row.parentNode().?.removeChild(row, frame);
}

// Finds the index-th row (or the last row for -1) in spec order: thead, tr,
// tbody then tfoot
fn findRow(self: *Table, index: i32) ?*Node {
    var scan: RowScan = .{ .index = index };

    if (self.scanSectionRows(.thead, &scan)) |row| {
        return row;
    }

    var it = self.asNode().childrenIterator();
    while (it.next()) |child| {
        const el = child.is(Element) orelse continue;
        switch (el.getTag()) {
            .tr => if (scan.check(child)) |row| {
                return row;
            },
            .tbody => if (scanChildRows(child, &scan)) |row| {
                return row;
            },
            else => {},
        }
    }

    if (self.scanSectionRows(.tfoot, &scan)) |row| {
        return row;
    }
    if (index == -1) {
        return scan.last;
    }
    return null;
}

const RowScan = struct {
    index: i32,
    count: i32 = 0,
    last: ?*Node = null,

    fn check(self: *RowScan, row: *Node) ?*Node {
        if (self.count == self.index) {
            return row;
        }
        self.count += 1;
        self.last = row;
        return null;
    }
};

fn scanSectionRows(self: *Table, tag: Element.Tag, scan: *RowScan) ?*Node {
    var it = self.asNode().childrenIterator();
    while (it.next()) |child| {
        const el = child.is(Element) orelse continue;
        if (el.getTag() != tag) {
            continue;
        }
        if (scanChildRows(child, scan)) |row| {
            return row;
        }
    }
    return null;
}

fn scanChildRows(section: *Node, scan: *RowScan) ?*Node {
    var it = section.childrenIterator();
    while (it.next()) |child| {
        const el = child.is(Element) orelse continue;
        if (el.getTag() == .tr) {
            if (scan.check(child)) |row| {
                return row;
            }
        }
    }
    return null;
}

pub const JsApi = struct {
    pub const bridge = js.Bridge(Table);

    pub const Meta = struct {
        pub const name = "HTMLTableElement";
        pub const prototype_chain = bridge.prototypeChain();
        pub var class_id: bridge.ClassId = undefined;
    };

    const reflect = Element.Reflect(Table);
    pub const width = reflect.string("width");
    pub const summary = reflect.string("summary");
    pub const rules = reflect.string("rules");
    pub const frame = reflect.string("frame");
    pub const cellSpacing = reflect.stringNullToEmpty("cellspacing");
    pub const cellPadding = reflect.stringNullToEmpty("cellpadding");
    pub const border = reflect.string("border");
    pub const bgColor = reflect.stringNullToEmpty("bgcolor");
    pub const @"align" = reflect.string("align");

    pub const tBodies = bridge.accessor(Table.getTBodies, null, .{});
    pub const insertRow = bridge.function(Table.insertRow, .{ .ce_reactions = true });
    pub const deleteRow = bridge.function(Table.deleteRow, .{ .ce_reactions = true });
};

const testing = @import("../../../../testing.zig");
test "WebApi: HTML.Table" {
    try testing.htmlRunner("element/html/table.html", .{});
}
