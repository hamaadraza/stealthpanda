# Architecture map

Lightpanda is a text-only headless browser in Zig: V8 for JavaScript, the Rust
`html5ever` crate for HTML/XML parsing, libcurl (BoringSSL) for networking, and
**no rendering engine**. Everything compiles into one Zig module named
`lightpanda`, rooted at [src/lightpanda.zig](../src/lightpanda.zig) — any file
can `@import("lightpanda")` for the shared surface (`App`, `Config`, `Server`,
`Browser`, `Session`, `Page`, `Frame`, `js`, `mcp`, `HttpClient`, …).

## Entry points and run flow

- [src/main.zig](../src/main.zig) — the `lightpanda` executable. `main()` picks
  the allocator (leak-detecting DebugAllocator in debug, `c_allocator` in
  release), then: parse args → set up logging → install signal handler →
  `App.init` → dispatch on mode.
- [src/cli.zig](../src/cli.zig) is a **comptime CLI builder**, not a command
  handler. The declarative recipe lives in
  [src/Config.zig](../src/Config.zig) (~line 346). Commands: `serve`, `fetch`,
  `mcp`, `agent`, `run` (rewritten internally to `.agent`), `version`. Help text
  is in [src/help.zon](../src/help.zon). No command defaults to `serve`.
- [src/App.zig](../src/App.zig) — process-wide singleton: `Config`, V8 platform
  + snapshot, `Network`, `Telemetry`, `Watchdog`, `ArenaPool`.
- Two extra executables in [build.zig](../build.zig): `snapshot_creator`
  ([src/main_snapshot_creator.zig](../src/main_snapshot_creator.zig)) and
  `skills` ([src/main_skills.zig](../src/main_skills.zig)).

**Serve (CDP)**: `main` → [src/Server.zig](../src/Server.zig) `run()` — a poll
loop on the main thread; each WebSocket connection gets its own thread and its
own V8 isolate, but socket reads are centralized back into the main loop. Data
flows `Server` → [src/cdp/CDP.zig](../src/cdp/CDP.zig) `dispatch` → per-domain
handler in [src/cdp/domains/](../src/cdp/domains/) → `Browser`/`Session`/`Page`.

**Fetch**: `main` spawns a dedicated thread because **a V8 isolate has thread
affinity** — the `Browser` must be created, used, and destroyed on one thread.
The actual navigate + wait + dump is `fetch()` in
[src/lightpanda.zig](../src/lightpanda.zig) (~line 211).

**MCP**: stdio server ([src/mcp/Server.zig](../src/mcp/Server.zig), one V8
isolate per session) or HTTP transport
([src/mcp/HttpServer.zig](../src/mcp/HttpServer.zig)); can co-host a CDP server
via `--cdp-port`.

**Agent**: terminal LLM agent in [src/agent/](../src/agent/), multi-provider
via the `zenai` dependency; the LLM-facing browser tool surface is
[src/browser/tools.zig](../src/browser/tools.zig).

## Directory map

| Path | Role |
|---|---|
| [src/browser/](../src/browser/) | The bulk (~420 files). Core object graph: `Browser.zig` → `Session.zig` → `Page.zig` → `Frame.zig`; plus `ScriptManager`, `StyleManager`, `EventManager`, `Factory.zig`, dump/markdown output, forms/links/actions helpers. |
| [src/browser/webapi/](../src/browser/webapi/) | ~330 Web API implementations, **one file per interface**. Subdirs: `net/` (XHR, Fetch, WebSocket, EventSource), `element/html/`, `element/svg/`, `css/`, `event/`, `streams/`, `storage/idb/`, `crypto/`, `collections/`, `selector/`, and more. |
| [src/browser/js/](../src/browser/js/) | V8 embedding layer. `bridge.zig` = comptime reflection engine + the master API registration lists; `Env.zig`, `Context.zig`, `Caller.zig` (runtime marshalling), `Snapshot.zig` (build-time V8 startup snapshot), `Inspector.zig` (CDP debugger), `Scheduler.zig` (microtasks/timers). |
| [src/browser/frame/](../src/browser/frame/) | DOM construction from parse events (`node_factory.zig`), mutation observers, preload scanning, synthetic user input. |
| [src/browser/parser/](../src/browser/parser/) | FFI into the Rust parser (`html5ever.zig`) and the Zig-side tree sink (`Parser.zig`). |
| [src/browser/xpath/](../src/browser/xpath/), [src/browser/css/](../src/browser/css/) | Self-contained XPath 1.0 engine; CSS tokenizer/parser/media queries. |
| [src/browser/tests/](../src/browser/tests/) | ~480 HTML/JS fixtures for the WebAPI tests (see WORKFLOWS.md). |
| [src/cdp/](../src/cdp/) | Chrome DevTools Protocol server; `CDP.zig` dispatches to ~22 domain handlers in `domains/` (`page`, `dom`, `network`, `runtime`, `target`, `fetch`, `input`, plus vendor domains `lp.zig`, `webmcp.zig`). `Node.zig` holds the backendNodeId registry. |
| [src/mcp/](../src/mcp/) | MCP server: protocol, router, tools, resources, stdio + HTTP transports. |
| [src/agent/](../src/agent/) | Terminal LLM agent: conversation loop, TUI rendering, slash commands, session→script export (`save.zig`), provider auth. |
| [src/network/](../src/network/) | `HttpClient.zig` (libcurl multi-handle), `Network.zig` event loop, WebSockets, robots.txt gate, ad-block filter engine, IP filtering, rate limiting, HTTP cache (`cache/` — fs or SQLite). |
| [src/storage/](../src/storage/) | SQLite layer (`sqlite/Sqlite.zig` + connection pool); backs cache, cookies, IndexedDB persistence. |
| [src/script/](../src/script/) | "PandaScript" runtime: replayable JS automation scripts, recorder, tool schemas. |
| [src/telemetry/](../src/telemetry/) | Opt-out usage telemetry (generic `TelemetryT(Provider)` + upstream's provider). |
| [src/sys/](../src/sys/) | C-library shims: libcurl, libcrypto, sockets/poll, URL/IDNA via Rust FFI. |
| [src/html5ever/](../src/html5ever/) | The Rust crate (`litefetch_html5ever`): html5ever/xml5ever, `encoding_rs`, rust-url. Built by cargo during `zig build`, statically linked. |
| [src/data/](../src/data/) | Generated/static data: CDP `protocol.json`, public suffix list. |
| src/*.zig (core) | `Server.zig`, `Config.zig`, `cli.zig`, `Notification.zig` (pub/sub bus), `Inbox.zig` (cross-thread messaging), `SemanticTree.zig` (accessibility-style tree for LLMs), `log.zig`, `Metrics.zig`, crash/core-dump/signal handling, `Watchdog.zig`, `Updater.zig`, `cookies.zig`, `datetime.zig`, `slab.zig`, `Arena.zig`/`ArenaPool.zig`. |

## The Web API binding pattern (read before adding/changing any Web API)

There is **no IDL codegen** — everything is comptime reflection:

1. Each interface is a plain Zig struct with a nested `pub const JsApi`.
   Canonical example: the bottom of
   [src/browser/webapi/net/XMLHttpRequest.zig](../src/browser/webapi/net/XMLHttpRequest.zig).
   The shape: `pub const bridge = js.Bridge(T);`, a `Meta` (JS class name,
   prototype chain, mutable `class_id`), a `bridge.constructor(...)`, and one
   `pub const` per member via `bridge.accessor(...)`, `bridge.function(...)`,
   or `bridge.property(...)` (plus `indexed`/`iterator`/`callable` variants for
   exotic objects).
2. Inheritance is **physical struct embedding**: a type's first field is
   `_proto: *Parent`. [src/browser/Factory.zig](../src/browser/Factory.zig)
   allocates the whole prototype chain contiguously in a slab, so
   `*Text` → `*CharacterData` → `*Node` → `*EventTarget` are offset views of
   one allocation.
3. Registration: append the type to the master lists at the bottom of
   [src/browser/js/bridge.zig](../src/browser/js/bridge.zig) —
   `PageJsApis` (~line 945, the Window/page global set),
   `DedicatedWorkerJsApis` / `SharedWorkerJsApis`, and the union `JsApis`.
4. [src/browser/js/Env.zig](../src/browser/js/Env.zig) creates one
   `v8.FunctionTemplate` per registered type;
   [src/browser/js/Snapshot.zig](../src/browser/js/Snapshot.zig) bakes the
   templates into a V8 startup snapshot at build time. If a new API doesn't
   appear at runtime, the snapshot may need regenerating
   (`zig build snapshot_creator`).

## Build system

Dependencies are pinned in [build.zig.zon](../build.zig.zon) — no submodules:
V8 (via `lightpanda-io/zig-v8-fork`), curl (compiled from source by
`build.zig`), BoringSSL, zlib, brotli, nghttp2, sqlite3, `zenai` (LLM SDK),
`isocline` (readline for the agent TUI). The html5ever Rust crate is **not** a
Zig package — `build.zig` shells out to `cargo build`, so **cargo is a hard
build prerequisite**. Prebuilt V8 is found in `.lp-cache/` (populate with
`make download-v8`; without it V8 builds from source, 10+ minutes). The version
tags are read from `.github/actions/install/action.yml` — a deliberate single
source of truth shared by `build.zig` and the Makefile.

Notable `zig build` options: `-Ddev_fast` (Linux debug, shared V8),
`-Dsnapshot_path`, `-Dwpt_extensions`, `-Dtsan`/`-Dasan`. The `check` step
compile-checks without linking. **The default step depends on `zig fmt`** —
formatting drift fails the build.
