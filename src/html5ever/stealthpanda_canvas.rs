// stealthpanda fork feature. Licensed under AGPL-3.0-only, same as the rest of
// the project. See LICENSE.
//
// Software canvas-2D rasterizer. Lightpanda has no rendering engine, so
// `canvas.toDataURL()` returns a fixed 1x1 blank PNG — a loud canvas-fingerprint
// tell under a Chrome identity. This module (inspired by Cloudflare's Kitesurf,
// which software-rasterizes with Blitz/Parley) replays a recorded 2D display
// list into a CPU pixmap (tiny-skia) so the canvas produces genuine, correctly
// sized, non-blank pixels. It is NOT pixel-identical to Chrome's GPU Skia — no
// software rasterizer is — but it is a real rendered canvas rather than a stub.
//
// The Zig side records draw ops into a compact little-endian byte stream and
// calls in here; we render and hand back a PNG (and, for getImageData, the raw
// straight-alpha RGBA).

use tiny_skia::{BlendMode, Color, FillRule, Paint, PathBuilder, Pixmap, Rect, Transform};
use ttf_parser::{Face, OutlineBuilder};

// Bundled font (Noto Sans, Latin subset, SIL OFL). Canvas fingerprint text is
// rendered with this regardless of the requested family — Lightpanda has no
// font stack, and any consistent glyph set makes the canvas non-blank.
static FONT_BYTES: &[u8] = include_bytes!("stealthpanda_font.ttf");

// Opcodes — must match the Zig encoder in CanvasRenderingContext2D.zig.
const OP_SET_FILL: u8 = 0x01;
const OP_FILL_RECT: u8 = 0x02;
const OP_CLEAR_RECT: u8 = 0x03;
const OP_FILL_TEXT: u8 = 0x10;

struct Reader<'a> {
    d: &'a [u8],
    i: usize,
}

impl<'a> Reader<'a> {
    fn u8(&mut self) -> Option<u8> {
        let v = *self.d.get(self.i)?;
        self.i += 1;
        Some(v)
    }
    fn u32(&mut self) -> Option<u32> {
        let b = self.d.get(self.i..self.i + 4)?;
        self.i += 4;
        Some(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn f32(&mut self) -> Option<f32> {
        let b = self.d.get(self.i..self.i + 4)?;
        self.i += 4;
        Some(f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn rgba(&mut self) -> Option<[u8; 4]> {
        let b = self.d.get(self.i..self.i + 4)?;
        self.i += 4;
        Some([b[0], b[1], b[2], b[3]])
    }
    fn bytes(&mut self, n: usize) -> Option<&'a [u8]> {
        let b = self.d.get(self.i..self.i + n)?;
        self.i += n;
        Some(b)
    }
}

// Builds a tiny-skia path from a glyph outline, transforming font units into
// canvas pixels (font Y is up with origin at the baseline; canvas Y is down).
struct GlyphBuilder {
    pb: PathBuilder,
    scale: f32,
    ox: f32,       // pen x (glyph origin)
    baseline: f32, // canvas y of the baseline
}
impl GlyphBuilder {
    fn tx(&self, x: f32) -> f32 {
        self.ox + x * self.scale
    }
    fn ty(&self, y: f32) -> f32 {
        self.baseline - y * self.scale
    }
}
impl OutlineBuilder for GlyphBuilder {
    fn move_to(&mut self, x: f32, y: f32) {
        self.pb.move_to(self.tx(x), self.ty(y));
    }
    fn line_to(&mut self, x: f32, y: f32) {
        self.pb.line_to(self.tx(x), self.ty(y));
    }
    fn quad_to(&mut self, x1: f32, y1: f32, x: f32, y: f32) {
        self.pb.quad_to(self.tx(x1), self.ty(y1), self.tx(x), self.ty(y));
    }
    fn curve_to(&mut self, x1: f32, y1: f32, x2: f32, y2: f32, x: f32, y: f32) {
        self.pb
            .cubic_to(self.tx(x1), self.ty(y1), self.tx(x2), self.ty(y2), self.tx(x), self.ty(y));
    }
    fn close(&mut self) {
        self.pb.close();
    }
}

fn face() -> Option<Face<'static>> {
    Face::parse(FONT_BYTES, 0).ok()
}

// textBaseline codes — must match the Zig encoder.
fn baseline_y(kind: u8, y: f32, ascent: f32, descent: f32) -> f32 {
    match kind {
        1 => y + ascent,                    // top
        2 => y + (ascent + descent) / 2.0,  // middle
        3 => y + descent,                   // bottom
        4 => y + ascent,                    // hanging (approx = top)
        5 => y + descent,                   // ideographic (approx = bottom)
        _ => y,                             // alphabetic (default)
    }
}

fn draw_text(pixmap: &mut Pixmap, fill: [u8; 4], text: &str, x: f32, y: f32, baseline_kind: u8, px: f32) {
    let face = match face() {
        Some(f) => f,
        None => return,
    };
    let upem = face.units_per_em() as f32;
    if upem <= 0.0 || px <= 0.0 {
        return;
    }
    let scale = px / upem;
    let ascent = face.ascender() as f32 * scale;
    let descent = face.descender() as f32 * scale; // negative (below baseline)
    let baseline = baseline_y(baseline_kind, y, ascent, descent);

    let mut paint = Paint::default();
    paint.set_color_rgba8(fill[0], fill[1], fill[2], fill[3]);
    paint.anti_alias = true;

    let mut pen_x = x;
    for ch in text.chars() {
        let gid = match face.glyph_index(ch) {
            Some(g) => g,
            None => {
                pen_x += px * 0.5;
                continue;
            }
        };
        let mut gb = GlyphBuilder {
            pb: PathBuilder::new(),
            scale,
            ox: pen_x,
            baseline,
        };
        if face.outline_glyph(gid, &mut gb).is_some() {
            if let Some(path) = gb.pb.finish() {
                pixmap.fill_path(&path, &paint, FillRule::Winding, Transform::identity(), None);
            }
        }
        pen_x += face.glyph_hor_advance(gid).unwrap_or(0) as f32 * scale;
    }
}

fn fill_rect(pixmap: &mut Pixmap, fill: [u8; 4], x: f32, y: f32, w: f32, h: f32) {
    if let Some(rect) = Rect::from_xywh(x, y, w, h) {
        let mut paint = Paint::default();
        paint.set_color_rgba8(fill[0], fill[1], fill[2], fill[3]);
        paint.anti_alias = true;
        pixmap.fill_rect(rect, &paint, Transform::identity(), None);
    }
}

fn render(ops: &[u8], w: u32, h: u32) -> Option<Pixmap> {
    let mut pixmap = Pixmap::new(w.max(1), h.max(1))?;
    let mut fill: [u8; 4] = [0, 0, 0, 255];
    let mut r = Reader { d: ops, i: 0 };

    while let Some(op) = r.u8() {
        match op {
            OP_SET_FILL => {
                if let Some(c) = r.rgba() {
                    fill = c;
                }
            }
            OP_FILL_RECT => {
                let (x, y, rw, rh) = (r.f32()?, r.f32()?, r.f32()?, r.f32()?);
                fill_rect(&mut pixmap, fill, x, y, rw, rh);
            }
            OP_CLEAR_RECT => {
                let (x, y, rw, rh) = (r.f32()?, r.f32()?, r.f32()?, r.f32()?);
                if let Some(rect) = Rect::from_xywh(x, y, rw, rh) {
                    let mut paint = Paint::default();
                    paint.set_color(Color::TRANSPARENT);
                    paint.blend_mode = BlendMode::Clear;
                    pixmap.fill_rect(rect, &paint, Transform::identity(), None);
                }
            }
            OP_FILL_TEXT => {
                let x = r.f32()?;
                let y = r.f32()?;
                let baseline = r.u8()?;
                let px = r.f32()?;
                let len = r.u32()? as usize;
                let bytes = r.bytes(len)?;
                if let Ok(text) = std::str::from_utf8(bytes) {
                    draw_text(&mut pixmap, fill, text, x, y, baseline, px);
                }
            }
            _ => break, // unknown opcode: stop for forward-compat safety
        }
    }
    Some(pixmap)
}

// stealthpanda: real JPEG encoder. JPEG has no alpha and canvas serialization
// composites over black; tiny-skia stores premultiplied RGBA, and premultiplied-
// over-black equals the stored RGB, so the premultiplied channels go straight
// out. Chrome's default canvas JPEG quality is ~0.92.
fn encode_jpeg(pixmap: &Pixmap) -> Option<Vec<u8>> {
    use jpeg_encoder::{ColorType, Encoder};
    let w = u16::try_from(pixmap.width()).ok()?;
    let h = u16::try_from(pixmap.height()).ok()?;
    let mut rgb = Vec::with_capacity(pixmap.width() as usize * pixmap.height() as usize * 3);
    for px in pixmap.pixels() {
        rgb.push(px.red());
        rgb.push(px.green());
        rgb.push(px.blue());
    }
    let mut buf = Vec::new();
    Encoder::new(&mut buf, 92)
        .encode(&rgb, w, h, ColorType::Rgb)
        .ok()?;
    Some(buf)
}

// stealthpanda: real (lossless) WebP encoder. WebP keeps alpha, so demultiply
// tiny-skia's premultiplied pixels back to straight RGBA.
fn encode_webp(pixmap: &Pixmap) -> Option<Vec<u8>> {
    use image_webp::{ColorType, WebPEncoder};
    let w = pixmap.width();
    let h = pixmap.height();
    let mut rgba = Vec::with_capacity(w as usize * h as usize * 4);
    for px in pixmap.pixels() {
        let c = px.demultiply();
        rgba.push(c.red());
        rgba.push(c.green());
        rgba.push(c.blue());
        rgba.push(c.alpha());
    }
    let mut buf = Vec::new();
    WebPEncoder::new(&mut buf)
        .encode(&rgba, w, h, ColorType::Rgba8)
        .ok()?;
    Some(buf)
}

/// Renders the op stream and encodes it as `format` (0 = PNG, 1 = JPEG,
/// 2 = WebP — must match canvas_raster.zig ImageFormat). Returns a heap pointer
/// (length in `out_len`) that the caller must release with `lp_canvas_free`, or
/// null on failure.
#[no_mangle]
pub extern "C" fn lp_canvas_render(
    ops_ptr: *const u8,
    ops_len: usize,
    w: u32,
    h: u32,
    format: u8,
    out_len: *mut usize,
) -> *mut u8 {
    let ops: &[u8] = if ops_ptr.is_null() || ops_len == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(ops_ptr, ops_len) }
    };

    let pixmap = match render(ops, w, h) {
        Some(p) => p,
        None => {
            unsafe { *out_len = 0 };
            return std::ptr::null_mut();
        }
    };

    let encoded = match format {
        1 => encode_jpeg(&pixmap),
        2 => encode_webp(&pixmap),
        _ => pixmap.encode_png().ok(),
    };

    match encoded {
        Some(bytes) => {
            let boxed = bytes.into_boxed_slice();
            let len = boxed.len();
            let ptr = Box::into_raw(boxed) as *mut u8;
            unsafe { *out_len = len };
            ptr
        }
        None => {
            unsafe { *out_len = 0 };
            std::ptr::null_mut()
        }
    }
}

/// Advance width (CSS px) of `text` at `px` font size, using the bundled font.
#[no_mangle]
pub extern "C" fn lp_canvas_measure_text(ptr: *const u8, len: usize, px: f32) -> f32 {
    if ptr.is_null() || len == 0 {
        return 0.0;
    }
    let bytes = unsafe { std::slice::from_raw_parts(ptr, len) };
    let text = match std::str::from_utf8(bytes) {
        Ok(s) => s,
        Err(_) => return 0.0,
    };
    let face = match face() {
        Some(f) => f,
        None => return 0.0,
    };
    let upem = face.units_per_em() as f32;
    if upem <= 0.0 {
        return 0.0;
    }
    let scale = px / upem;
    let mut w = 0.0f32;
    for ch in text.chars() {
        if let Some(gid) = face.glyph_index(ch) {
            w += face.glyph_hor_advance(gid).unwrap_or(0) as f32 * scale;
        } else {
            w += px * 0.5;
        }
    }
    w
}

/// Frees a buffer returned by `lp_canvas_render`.
#[no_mangle]
pub extern "C" fn lp_canvas_free(ptr: *mut u8, len: usize) {
    if ptr.is_null() || len == 0 {
        return;
    }
    unsafe {
        let slice = std::slice::from_raw_parts_mut(ptr, len);
        drop(Box::from_raw(slice as *mut [u8]));
    }
}
