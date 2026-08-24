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
   [build.zig](../build.zig), [build.zig.zon](../build.zig.zon).
4. **Never edit `.github/` workflows casually.** Upstream enforces a
   supply-chain policy (`.plumber.yaml`) over them; fork CI changes should be
   separate, deliberate commits.
5. **Do not rewrite `AGENTS.md`, `README.md`, or other upstream docs** beyond
   the small fork-note blocks already present. Fork documentation goes in
   `.ai/`.

## Fork features

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
  **Remaining refinements** (not yet done): match Chrome's exact request
  **header order**; add Safari/Firefox identity profiles (only chrome131/chrome136
  are pinned today — other targets keep the Lightpanda identity); honour the CDP
  `userAgentMetadata` override; set `navigator.hardwareConcurrency`/`deviceMemory`
  from the profile.

## Fork-specific facts

- **License is AGPL-3.0-only.** All fork code stays AGPL. If the fork is ever
  offered as a network service, its source must be made available to users.
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
  the html5ever crate.
- `zig build` fails on formatting drift — the default step depends on `zig fmt`.
- The test runner fails any test that leaks memory in debug builds. Free what
  you allocate in tests.
- Mirror neighboring code: `@import` alias case follows the file's basename;
  prefer `.{ ... }` struct-init inference where the type is known.
