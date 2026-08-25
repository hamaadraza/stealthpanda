// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.

//! A macOS font-metrics model for defeating font fingerprinting. Detectors
//! enumerate installed fonts by measuring the same string in many font-families
//! and seeing which produce a width different from a generic fallback. Lightpanda
//! has no font stack, so every family measured identically ("1 unique metric" —
//! a loud tell). We can't ship every macOS font, so instead we scale our one
//! real font's advance width (measured via ttf-parser in the canvas rasterizer)
//! by a per-family factor: macOS system fonts get distinct factors (so they read
//! as installed with varied metrics), while unknown families (Windows/Linux
//! fonts) return null and fall through the font stack to the generic fallback
//! (so they read as *not* installed) — keeping the detected set macOS-coherent.

const std = @import("std");

const canvas_raster = @import("canvas_raster.zig");

// Per-family width scale relative to the bundled font's advances. Keys are
// lowercase; the exact factors don't need to be a real macOS metric, only
// distinct-per-installed-font and stable.
const scales = std.StaticStringMap(f64).initComptime(.{
    // Generic families.
    .{ "sans-serif", 1.000 },               .{ "serif", 1.052 },              .{ "monospace", 1.113 },
    .{ "cursive", 0.951 },                  .{ "fantasy", 1.021 },            .{ "system-ui", 1.001 },
    .{ "-apple-system", 1.001 },            .{ "blinkmacsystemfont", 1.001 }, .{ "ui-sans-serif", 1.002 },
    .{ "ui-serif", 1.053 },                 .{ "ui-monospace", 1.112 },       .{ "ui-rounded", 0.995 },
    // Cross-platform fonts that also ship on macOS.
    .{ "helvetica", 0.999 },                .{ "helvetica neue", 0.994 },     .{ "arial", 1.006 },
    .{ "arial black", 1.190 },              .{ "arial narrow", 0.840 },       .{ "times", 1.047 },
    .{ "times new roman", 1.051 },          .{ "georgia", 1.071 },            .{ "verdana", 1.121 },
    .{ "tahoma", 1.058 },                   .{ "trebuchet ms", 1.018 },       .{ "courier", 1.118 },
    .{ "courier new", 1.126 },              .{ "impact", 0.903 },             .{ "comic sans ms", 1.043 },
    .{ "palatino", 1.061 },                 .{ "palatino linotype", 1.062 },  .{ "lucida console", 1.108 },
    .{ "lucida sans unicode", 1.010 },
    // macOS system fonts.
         .{ "san francisco", 1.001 },      .{ "sf pro", 1.001 },
    .{ "sf pro text", 1.001 },              .{ "sf pro display", 1.000 },     .{ "sf mono", 1.107 },
    .{ "sf compact", 0.998 },               .{ "geneva", 1.031 },             .{ "lucida grande", 1.011 },
    .{ "monaco", 1.104 },                   .{ "menlo", 1.109 },              .{ "andale mono", 1.114 },
    .{ "gill sans", 0.981 },                .{ "futura", 1.003 },             .{ "optima", 0.991 },
    .{ "avenir", 0.979 },                   .{ "avenir next", 0.986 },        .{ "didot", 0.968 },
    .{ "baskerville", 1.002 },              .{ "cochin", 0.992 },             .{ "hoefler text", 1.023 },
    .{ "american typewriter", 1.083 },      .{ "apple chancery", 0.902 },     .{ "brush script mt", 0.921 },
    .{ "chalkboard", 1.033 },               .{ "chalkboard se", 1.034 },      .{ "chalkduster", 1.052 },
    .{ "copperplate", 1.101 },              .{ "marker felt", 1.004 },        .{ "noteworthy", 1.044 },
    .{ "papyrus", 1.063 },                  .{ "rockwell", 1.054 },           .{ "savoye let", 0.852 },
    .{ "signpainter", 0.953 },              .{ "skia", 1.005 },               .{ "snell roundhand", 0.902 },
    .{ "zapfino", 1.503 },                  .{ "big caslon", 1.034 },         .{ "bodoni 72", 1.006 },
    .{ "gill sans mt", 0.982 },             .{ "phosphate", 1.070 },          .{ "trattatello", 0.930 },
    .{ "herculanum", 1.088 },               .{ "party let", 0.960 },          .{ "pt sans", 1.001 },
    .{ "pt serif", 1.036 },                 .{ "hiragino sans", 1.200 },      .{ "hiragino kaku gothic pro", 1.200 },
    .{ "hiragino maru gothic pro", 1.200 }, .{ "heiti sc", 1.200 },           .{ "heiti tc", 1.200 },
    .{ "songti sc", 1.210 },                .{ "pingfang sc", 1.200 },        .{ "pingfang tc", 1.200 },
    .{ "apple sd gothic neo", 1.150 },      .{ "apple color emoji", 1.300 },  .{ "apple symbols", 1.100 },
    .{ "webdings", 1.000 },                 .{ "wingdings", 1.000 },          .{ "menlo regular", 1.109 },
});

// Unknown / no family -> resolve like the CSS default (Times/serif), so a bare
// unknown font measures the same as the serif fallback (not "installed").
pub const default_scale: f64 = 1.047;

/// Width scale of the first known family in a CSS font-family list, or null when
/// none is known (an unknown font -> caller keeps walking the stack).
pub fn scaleForFamilyList(list: []const u8) ?f64 {
    var it = std.mem.tokenizeScalar(u8, list, ',');
    while (it.next()) |raw| {
        var buf: [64]u8 = undefined;
        const name = normalize(&buf, raw) orelse continue;
        if (scales.get(name)) |s| return s;
    }
    return null;
}

// Trim whitespace + surrounding quotes and lowercase into buf; null if too long.
fn normalize(buf: []u8, raw: []const u8) ?[]const u8 {
    const s = std.mem.trim(u8, raw, " \t\n\r'\"");
    if (s.len == 0 or s.len > buf.len) return null;
    for (s, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return buf[0..s.len];
}

/// Advance width (px) of `text` at `font_px`, scaled for the given CSS
/// font-family list — the value DOM/canvas measurement reports when impersonating.
pub fn textWidth(text: []const u8, font_px: f32, family_list: []const u8) f64 {
    const base: f64 = canvas_raster.measureText(text, font_px);
    return base * (scaleForFamilyList(family_list) orelse default_scale);
}
