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
   forever. Fork-specific features live under a dedicated directory
   (`src/stealthpanda/` — create it when the first feature lands) with minimal,
   clearly necessary touch points into upstream code.
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
