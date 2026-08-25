# Fork rules (stealthpanda)

This repo is a fork of [lightpanda-io/browser](https://github.com/lightpanda-io/browser)
(Lightpanda: a headless browser written from scratch in Zig — V8 for JS, Rust
html5ever for parsing, libcurl for networking, no rendering engine). The fork
adds its own features while **continuously merging upstream `main`**. Every rule
below exists to keep those merges cheap.

Deep context, read before non-trivial work:
- [.ai/ARCHITECTURE.md](ARCHITECTURE.md) — codebase map and request flows.
- [.ai/WORKFLOWS.md](WORKFLOWS.md) — build/test/sync recipes and how-tos.
- [AGENTS.md](../AGENTS.md) — upstream's build, test, and style conventions
  (they apply here unchanged).

## Mergeability rules (the important part)

1. **Prefer new files over edits to upstream files.** A line added in a
   fork-owned file never conflicts; a line changed in an upstream file conflicts
   forever. Fork-specific code lives under [src/stealthpanda/](../src/stealthpanda/)
   with minimal, clearly necessary touch points into upstream code.
2. **When you must edit an upstream file, be additive and local.** Append to
   registration lists rather than reordering them; add new functions rather than
   rewriting existing ones; never reformat or restructure upstream code you are
   not changing.
3. **Hot files — touch with extra care** (upstream edits these constantly):
   [src/Config.zig](../src/Config.zig) and [src/cli.zig](../src/cli.zig) (CLI
   flags), [src/browser/js/bridge.zig](../src/browser/js/bridge.zig) (the
   `PageJsApis`/`JsApis` registration lists at the bottom),
   [build.zig](../build.zig), [build.zig.zon](../build.zig.zon). The fork also now
   makes small, additive edits to other upstream files that merges may conflict
   on — expect and re-apply them: the `Type` enum/union + subtype switches in
   [EventTarget.zig](../src/browser/webapi/EventTarget.zig) and
   [Event.zig](../src/browser/webapi/Event.zig) (WebRTC event targets),
   `contentAxis` in [Element.zig](../src/browser/webapi/Element.zig) (font
   measurement), the `TZ`-pin line in [main.zig](../src/main.zig), the geolocation
   grant in [Browser.zig](../src/browser/Browser.zig), additive members for the
   HTML5 feature-detection surfaces in
   [Navigator.zig](../src/browser/webapi/Navigator.zig) /
   [Window.zig](../src/browser/webapi/Window.zig) /
   [Document.zig](../src/browser/webapi/Document.zig), the impersonation-gated
   codec block in [Media.zig](../src/browser/webapi/element/html/Media.zig)
   `canPlayType`, native `isPointInPath` in
   [CanvasRenderingContext2D.zig](../src/browser/webapi/canvas/CanvasRenderingContext2D.zig),
   and the Rust crate
   ([Cargo.toml](../src/html5ever/Cargo.toml) / [lib.rs](../src/html5ever/lib.rs)).
   Each is documented under its feature in **Fork features** below.
4. **Never edit `.github/` workflows casually.** Upstream enforces a
   supply-chain policy (`.plumber.yaml`) over them; fork CI changes should be
   separate, deliberate commits.
5. **Do not rewrite `AGENTS.md`, `README.md`, or other upstream docs** beyond
   the small fork-note blocks already present. Fork documentation goes in
   `.ai/`.

## Fork features

The stealth work spans three layers: the **network fingerprint** (TLS / HTTP2 /
headers), the **static JS environment** (what a bot sensor reads synchronously),
and **behavioral / rendered** surfaces (mouse motion, canvas & WebGL pixels, font
metrics, timezone). One rule governs all of them:

> **Everything is impersonation-gated.** A feature is active only when a TLS
> profile is selected (`--tls-impersonate` != `off`). Off-path — which includes
> **every test** ([src/testing.zig](../src/testing.zig) sets `--tls-impersonate
> off`) — the browser is byte-identical to upstream Lightpanda. The gate is
> usually `http_client.impersonateIdentity() != null`; navigator/window
> accessors return `undefined` off-path, and constructor globals (which can't be
> runtime-gated) simply exist unconditionally but stay inert.
>
> These are **native Zig** (not injected JS): every faked function toStrings as
> `[native code]`, the structural advantage over puppeteer-extra-stealth. New
> web-API types are registered in the `PageJsApis` list of
> [src/browser/js/bridge.zig](../src/browser/js/bridge.zig) (a hot file — append
> only).

### Network fingerprint

- **Stealth TLS/HTTP2 fingerprint** ([src/stealthpanda/impersonate.zig](../src/stealthpanda/impersonate.zig)):
  links the prebuilt [curl-impersonate](https://github.com/lexiforest/curl-impersonate)
  archive instead of the from-source libcurl, so the TLS ClientHello (JA3/JA4),
  cipher/extension order and HTTP/2 SETTINGS match a real browser. Gated behind
  `-Dtls_impersonate` (default **on**); runtime profile via `--tls-impersonate
  <name>` (default `chrome131`, `off` to disable). Touch points into upstream:
  the `linkCurl` branch in [build.zig](../build.zig), the `curl_easy_impersonate`
  wrapper + `impersonate_enabled` flag in
  [src/sys/libcurl.zig](../src/sys/libcurl.zig), the `reset()` call in
  [src/network/http.zig](../src/network/http.zig), the `tls_impersonate` CLI
  option + `tlsImpersonate()` accessor in [src/Config.zig](../src/Config.zig),
  and the Makefile download target.

- **Chrome request headers** ([src/stealthpanda/headers.zig](../src/stealthpanda/headers.zig)):
  when impersonating, `HttpClient.chromeizeHeaders` (called from `configureConn`)
  injects the browser-managed headers Chrome sends that Lightpanda omitted
  (`Sec-Fetch-Site`/`-Mode`/`-User`/`-Dest`, `Upgrade-Insecure-Requests`,
  `Priority`), swaps in Chrome's `Accept`/`Accept-Encoding`, and reorders the
  header list into Chrome's exact HTTP/2 order (wire order == `req_headers`
  order). Sec-Fetch-Site is computed per request-context from the initiator vs
  target origin. Verified byte-for-byte against a real Chrome navigation on
  tls.peet.ws. **Note:** a perfect request fingerprint (TLS + HTTP/2 + headers)
  is necessary but not sufficient against Akamai Bot Manager — it still hard-403s
  a **datacenter/hosting egress IP** (IP reputation) before any JS runs, and
  beyond that runs a JS sensor (`_abck` cookie) that inspects the JS
  environment. Getting past those needs a residential/mobile proxy
  (`--http-proxy`) and much deeper JS-environment work, respectively.

### Coherent browser identity

- **Coherent browser identity** ([src/stealthpanda/identity.zig](../src/stealthpanda/identity.zig)):
  when a TLS profile is active, the `User-Agent`, `Sec-Ch-Ua`/`-Mobile`/`-Platform`
  headers and the JS surfaces (`navigator.userAgent`, `.platform`, `.appVersion`,
  `.vendor`, `navigator.userAgentData.*`) all report the same browser as the
  handshake — values copied from curl-impersonate's own per-target headers (its
  desktop Chrome builds present a macOS identity). Off-path (impersonation off,
  including all tests) is byte-identical to Lightpanda. Touch points:
  `Config.HttpHeaders` (runtime `impersonate` identity),
  `HttpClient.baselineHeaders`/`impersonateIdentity`, and the getters in
  [Navigator.zig](../src/browser/webapi/Navigator.zig) /
  [NavigatorUAData.zig](../src/browser/webapi/NavigatorUAData.zig). Tests run
  with `--tls-impersonate off` (set in [src/testing.zig](../src/testing.zig)).
  `navigator.userAgentData.getHighEntropyValues` reports `architecture: "arm"`
  and a macOS `platformVersion` from the profile — coherent with the frozen
  "Intel Mac OS X 10_15_7" UA + Apple-Metal WebGL renderer that a real
  Apple-Silicon Chrome presents. **Remaining refinements** (not yet done): add
  Safari/Firefox identity profiles (only chrome131/chrome136 are pinned today —
  other targets keep the Lightpanda identity); honour the CDP `userAgentMetadata`
  override; drive per-profile `hardwareConcurrency`/`deviceMemory` (both are fixed
  at `8` when impersonating today).

### Static JS-environment stealth

Native surfaces a bot sensor reads synchronously. Registered in
[bridge.zig](../src/browser/js/bridge.zig) `PageJsApis`; navigator/window
accessors return `undefined` off-path.

- **window.chrome** ([Chrome.zig](../src/browser/webapi/Chrome.zig)) —
  `app`/`runtime`/`csi`/`loadTimes` (a Chrome UA with no `window.chrome` is a
  loud tell).
- **navigator.plugins / mimeTypes**
  ([PluginArray.zig](../src/browser/webapi/PluginArray.zig)) — Chrome's shared
  5-plugin / 2-mimetype PDF graph with cross-referenced prototypes;
  `navigator.pdfViewerEnabled` = true; `productSub`/`vendorSub`
  ([Navigator.zig](../src/browser/webapi/Navigator.zig)).
- **navigator.connection / mediaDevices**
  ([NetworkInformation.zig](../src/browser/webapi/NetworkInformation.zig),
  [MediaDevices.zig](../src/browser/webapi/MediaDevices.zig)) — 4g/rtt/downlink;
  audioinput/videoinput/audiooutput devices.
- **Battery / Web Bluetooth / SpeechSynthesis / Web Audio**
  ([BatteryManager.zig](../src/browser/webapi/BatteryManager.zig),
  [Bluetooth.zig](../src/browser/webapi/Bluetooth.zig),
  [SpeechSynthesis.zig](../src/browser/webapi/SpeechSynthesis.zig),
  [WebAudio.zig](../src/browser/webapi/WebAudio.zig)) — `navigator.getBattery()`,
  `navigator.bluetooth`, `speechSynthesis.getVoices()` (a plausible macOS voice
  set — headless Chrome's *empty* voice list is itself a tell), `AudioContext` +
  destination/analyser nodes. The device constructors are unconditional globals.
- **WebGL parameters**
  ([WebGLRenderingContext.zig](../src/browser/webapi/canvas/WebGLRenderingContext.zig)) —
  `getParameter` returns Chrome's `VENDOR`/`RENDERER`/`VERSION` strings and the
  Apple-M1 `UNMASKED_*` GPU strings, the full WebGL 1.0 enum-constant set,
  `getContextAttributes`, `getShaderPrecisionFormat`. Context is `null` off-path
  ([Canvas.zig](../src/browser/webapi/element/html/Canvas.zig) `getContext`).
- **Screen / window geometry**
  ([Screen.zig](../src/browser/webapi/Screen.zig),
  [Window.zig](../src/browser/webapi/Window.zig)) — a coherent 1920×1200 WUXGA
  screen with macOS menu-bar `avail*` insets (invariant `inner < outer < avail <
  screen`, which a real browser always satisfies); `isSecureContext` reports the
  real value for the origin (an https page with `isSecureContext=false` is
  impossible).
- **HTML5 feature-detection surfaces**
  ([Features.zig](../src/browser/webapi/Features.zig)) — the cluster of JS
  globals/methods a Modernizr-style sensor (browserleaks/features,
  detect-headless) reads on a Chrome UA. Impersonation-gated Navigator members
  (`serviceWorker`, `getGamepads()`, `vibrate`, `webkitTemporaryStorage` /
  `webkitPersistentStorage`), `window.webkitRequestFileSystem`, and
  `document.exitFullscreen` / `exitPointerLock` (all in
  [Navigator.zig](../src/browser/webapi/Navigator.zig) /
  [Window.zig](../src/browser/webapi/Window.zig) /
  [Document.zig](../src/browser/webapi/Document.zig)); plus the inert global
  constructors `PushManager` / `MediaSource` / `MediaRecorder` /
  `PublicKeyCredential` / `SpeechRecognition` and the instance-backed
  `ServiceWorkerContainer` / `DeprecatedStorageQuota` (unconditional globals —
  `new X()` throws, exactly Chrome's behaviour for PushManager/PublicKeyCredential).
  The **crash-critical** piece is native `CanvasRenderingContext2D.isPointInPath`:
  the features runner calls each detector uncaught, so a *missing* canvas method
  throws and aborts the whole single pass, leaving the page with **no
  fingerprint at all** — a far louder tell than any single value. Media codecs:
  `canPlayType` ([Media.zig](../src/browser/webapi/element/html/Media.zig)), when
  impersonating, answers Theora/HEVC/AV1 unsupported and HLS `maybe` to match
  desktop Chrome on macOS (upstream's container-only check mis-reported them);
  `canvas.toDataURL` honours the requested `image/jpeg` · `image/webp` MIME label.

### Behavioral

- **Synthetic mouse movement**
  ([behavior.zig](../src/stealthpanda/behavior.zig)) — started from
  `Frame._documentIsLoaded` on the root frame when impersonating: a momentum
  random-walk pointer path (~58 `mousemove` events with real `movementX/Y` and
  coherent, increasing `timeStamp`s) spread over real time via the frame
  scheduler. It holds a `_pending_load` so the events fire before the `load`-based
  fetch settles. Defeats behavioral "dead pointer" checks (detect-headless
  mouse-move). Touch point: the `_documentIsLoaded` hook + `pub`
  `pendingLoadCompleted` in [Frame.zig](../src/browser/Frame.zig).

### Rendered surfaces (software rasterization)

Upstream has no rendering engine, so canvas/WebGL/font-metric fingerprints were
blank or threw — loud tells. Inspired by Cloudflare's Kitesurf (CPU rasterization
in Rust), these produce real pixels/metrics without a GPU.

- **Software canvas-2D rasterizer**
  ([src/html5ever/stealthpanda_canvas.rs](../src/html5ever/stealthpanda_canvas.rs)
  + [canvas_raster.zig](../src/stealthpanda/canvas_raster.zig)): the 2D context
  ([CanvasRenderingContext2D.zig](../src/browser/webapi/canvas/CanvasRenderingContext2D.zig))
  records draw ops into a byte stream; Rust replays them with **tiny-skia**
  (fills/paths) + **ttf-parser** glyph outlines using a bundled 27 KB Noto Sans
  Latin subset ([stealthpanda_font.ttf](../src/html5ever/stealthpanda_font.ttf),
  SIL OFL). `canvas.toDataURL()`
  ([Canvas.zig](../src/browser/webapi/element/html/Canvas.zig)) returns a real,
  correctly-sized PNG instead of a 1×1 blank; `measureText` returns real
  advances. **Built into the existing html5ever staticlib** (a second Rust
  staticlib collides on std/panic symbols) — touch points: `tiny-skia` +
  `ttf-parser` in [src/html5ever/Cargo.toml](../src/html5ever/Cargo.toml), a `mod`
  line in [src/html5ever/lib.rs](../src/html5ever/lib.rs), file-tracking in
  [build.zig](../build.zig).
- **WebGL render stubs**
  ([WebGLRenderingContext.zig](../src/browser/webapi/canvas/WebGLRenderingContext.zig)):
  ~95 render methods (one shared no-op via `.noop`), opaque handle types
  (`WebGLShader`/`Program`/`Buffer`/…), `gl.canvas`/`drawingBufferWidth`, and a
  `readPixels` that fills the caller's buffer with **per-session deterministic
  noise** (seeded from the session pointer). The render + `readPixels` path now
  completes, so the WebGL *image* hash computes (was a `readPixels: TypeError`).
  Real GPU rendering (SwiftShader-class) is out of scope — Kitesurf skips it too.
- **Font metrics** ([fonts.zig](../src/stealthpanda/fonts.zig)): a macOS
  font-scale model. `canvas.measureText` and **DOM text measurement**
  ([Element.zig](../src/browser/webapi/Element.zig) `contentAxis`, gated — this
  is core layout, a hot file) scale the bundled-font advance per requested
  family: known macOS fonts get distinct factors (read as *installed*), unknown
  families fall through the CSS stack to the generic fallback (read as *not
  installed*). browserleaks/fonts goes from "1 unique metric" (flat 5×5) to a
  varied, macOS-coherent set; this also fixes the general text-element 5×5 tell.

### Environment / geolocation

- **Timezone & geolocation** ([geo.zig](../src/stealthpanda/geo.zig)):
  `--timezone <IANA>` pins the process `TZ` before V8/ICU initializes (via
  [main.zig](../src/main.zig), before `App.init`), defaulting to
  `America/New_York` when impersonating so `Intl`/`Date` stop reporting the host's
  UTC (a datacenter tell). `--geolocation "lat,lon[,accuracy]"` grants the
  geolocation permission and populates Lightpanda's existing `geolocation_override`
  in [Browser.zig](../src/browser/Browser.zig), so `getCurrentPosition` returns
  coordinates instead of "User denied". CLI options + `timezone()`/`geolocation()`
  accessors in [src/Config.zig](../src/Config.zig). Pair with `--http-proxy` so
  IP + timezone + coordinates all agree.

### Misc DOM

- **Table `insertRow` / `insertCell`**
  ([element/html/Table.zig](../src/browser/webapi/element/html/Table.zig),
  [element/html/TableRow.zig](../src/browser/webapi/element/html/TableRow.zig)) —
  standard methods some detectors exercise; unconditional (not gated).

### Known residuals (deep / architectural)

Honest limits, useful when deciding what to work on next:

- **IP reputation** is the wall the network fingerprint can't cross — a
  datacenter egress is hard-403'd by Akamai-class managers before any JS. Needs a
  residential/mobile `--http-proxy`.
- **Canvas / WebGL image hashes don't match a real GPU** — the CPU rasterizer +
  our bundled font (canvas) and the `readPixels` noise (WebGL) are *plausible and
  non-blank*, but won't land in a "known real Chrome" cluster; a detector that
  re-renders a known scene and compares would notice.
- **Fonts are one bundled font scaled per family**, not real per-font glyph
  metrics; the font fingerprint is deterministic (all instances share it — which
  is fine: a real machine's font set is stable).
- **No layout engine** — text measurement is a single-line advance sum (no
  kerning/wrapping/`letter-spacing`); a full engine (Blitz/Stylo/Parley, à la
  Kitesurf) is deliberately *not* integrated because it would break
  upstream-mergeability. See the WebGL2, `queryLocalFonts`, and audio-render
  vectors as further-out surfaces.
- **browserleaks/features CSS & element bits stay `false`** — after the
  crash-fix and the API-presence/codec work, the browser produces a full,
  plausible features fingerprint and matches Chrome on every API-presence and
  media-codec probe, but the ~60 CSS style-property / layout-render / element
  detectors (`appearance`, `csscolumns*`, `cssvhunit`, `flexgap`,
  `generatedcontent`, `details`/`meter`/`ruby`, `inlinesvg`/`mathml`, …) still
  report unsupported — they need real style-property tables and a layout engine
  (the residual above). The **features hash differing from a given Chrome is not
  itself a tell**: browserleaks MD5s the boolean set for uniqueness, it is not
  matched against a known-Chrome database — every browser build hashes
  differently.
- **`toDataURL("image/jpeg" | "image/webp")`** reports the correct
  `data:image/<type>` prefix, but the encoded bytes are still PNG (the rasterizer
  has no JPEG/WebP encoder) — same byte-level residual class as the canvas image
  hash above: fine for feature detection, visible to a decoder that parses the
  payload.

## Fork-specific facts

- **License is AGPL-3.0-only.** All fork code stays AGPL. If the fork is ever
  offered as a network service, its source must be made available to users. The
  one bundled binary asset,
  [src/html5ever/stealthpanda_font.ttf](../src/html5ever/stealthpanda_font.ttf)
  (Noto Sans, Latin subset), is under the SIL Open Font License — compatible with
  AGPL redistribution; keep its license intact if replacing it.
- **Telemetry**: upstream sends opt-out usage telemetry to lightpanda.io
  ([src/telemetry/](../src/telemetry/)). Check the fork's current policy before
  building release binaries; `LIGHTPANDA_DISABLE_TELEMETRY=true` disables it at
  runtime.
- **Updater**: [src/Updater.zig](../src/Updater.zig) relates to upstream's
  release channel — verify behavior before shipping fork binaries.
- **Upstream sync** is a routine task — see "Sync with upstream" in
  [WORKFLOWS.md](WORKFLOWS.md). After every merge, `make test` must pass and
  `zig build` must succeed (it enforces `zig fmt`).

## Quality gates (from upstream, enforced locally)

- Zig **0.16** (`build.zig.zon` `minimum_zig_version`); Rust/cargo required for
  the html5ever crate — which now also builds the fork's canvas rasterizer
  (`tiny-skia` + `ttf-parser`, added in
  [src/html5ever/Cargo.toml](../src/html5ever/Cargo.toml)).
- `zig build` fails on formatting drift — the default step depends on `zig fmt`.
- The test runner fails any test that leaks memory in debug builds. Free what
  you allocate in tests.
- Mirror neighboring code: `@import` alias case follows the file's basename;
  prefer `.{ ... }` struct-init inference where the type is known.
