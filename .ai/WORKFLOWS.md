# Workflows

Build/test basics are in [AGENTS.md](../AGENTS.md) (they apply unchanged):
`make download-v8` once, then `make test` with `F=`/`TEST_FILTER=`/
`TEST_VERBOSE=`/`TEST_FAIL_FIRST=`/`METRICS=` knobs. This file covers the
fork-specific routines and change recipes.

## Toolchain / Zig 0.16 note (read if a build crashes)

Verified working toolchain: **Zig 0.16.0** (the `minimum_zig_version`) + Rust
stable (for the html5ever crate) + `clang`/`xz-utils`. One-time setup gotcha
from CI: create the Zig global-cache tmp dir or zip deps (sqlite) fail —
`mkdir -p "${ZIG_GLOBAL_CACHE_DIR:-$HOME/.cache/zig}/tmp"`.

**The `dev_fast` self-hosted backend (`-fno-llvm`) is unstable on Zig 0.16.0**
for this codebase — it's the default for native Linux x86_64 debug builds, so
a bare `make test` / `make build-dev` can crash the compiler (and even the
unmodified upstream tree fails its test run on it). Build with the LLVM backend
instead:

```bash
ZIGFLAGS="-Ddev_fast=false" make test      # 1238/1238 green
zig build -Ddev_fast=false                 # debug exe → zig-out/bin/lightpanda
zig build check                            # compile-only, already uses LLVM
```

## Sync with upstream

Run regularly (at least weekly — upstream lands multiple PRs per day):

```bash
git fetch upstream
git merge upstream/main
```

- Remote setup (once): `git remote add upstream https://github.com/lightpanda-io/browser.git`
- `git config rerere.enabled true` (once) makes git replay past conflict
  resolutions automatically.
- After the merge: `zig build` (catches fmt drift and compile errors) and
  `make test` must both pass **before pushing**.
- Conflicts should almost always be in the known hot files (see
  [FORK.md](FORK.md)). A conflict anywhere else is a signal the fork edited
  upstream code non-additively — consider restructuring that change.
- Tag fork releases as `v<upstream-ish>-stealthpanda.<n>` so every build maps
  to a known upstream state.

## Stealth / curl-impersonate

The fork links the prebuilt curl-impersonate archive for browser TLS/HTTP2
fingerprints (see [FORK.md](FORK.md) "Fork features"). Default-on, so builds
need the archive cached:

```bash
make download-curl-impersonate   # once per platform; or: make download-deps
```

- The release tag is pinned in
  [src/stealthpanda/curl-impersonate.version](../src/stealthpanda/curl-impersonate.version)
  — the single source of truth both the Makefile and `build.zig` read. Bump it
  there to upgrade, then re-run the download.
- `build.zig`'s `findCurlImpersonate` looks under
  `.lp-cache/curl-impersonate/<tag>/<triple>/`; if the archive is missing it
  fails the build with instructions. `make build-dev` / `make test` fetch it
  automatically.
- To build the **stock** (non-stealth) TLS stack — e.g. offline, or to A/B a
  fingerprint difference — pass `-Dtls_impersonate=false`:

```bash
zig build -Dtls_impersonate=false
```

- Choose the emulated browser at runtime: `--tls-impersonate chrome136`
  (names come from curl-impersonate: chrome*/safari*/firefox*), or
  `--tls-impersonate off` to disable for one run. Default is in
  [src/stealthpanda/impersonate.zig](../src/stealthpanda/impersonate.zig).
- Adding a new asset triple (e.g. musl) means updating both
  `curlImpersonateTriple` in `build.zig` and `CI_TRIPLE` in the `Makefile`.

## Add a new Web API / extend an existing one

1. Read the binding pattern in [ARCHITECTURE.md](ARCHITECTURE.md) first.
2. New interface → new file under [src/browser/webapi/](../src/browser/webapi/)
   (pick the matching subdir), modeled on a close neighbor
   (`net/XMLHttpRequest.zig` is the canonical example).
3. Register it by **appending** to the lists at the bottom of
   [src/browser/js/bridge.zig](../src/browser/js/bridge.zig)
   (`PageJsApis`, and the worker lists if applicable). Append, don't reorder.
4. Add tests: an HTML fixture under
   [src/browser/tests/](../src/browser/tests/) plus a
   `testing.htmlRunner("path/fixture.html", .{})` test at the bottom of the
   implementation file. Known-failing fixtures can be parked as `.skip.html`.
5. Run the focused tests, then the full suite:

```bash
TEST_FILTER="WebApi" make test
```

## Add a CLI flag or command

- The declarative CLI recipe is in [src/Config.zig](../src/Config.zig)
  (~line 346); help text in [src/help.zon](../src/help.zon).
- [src/cli.zig](../src/cli.zig) is the generic comptime parser — it rarely
  needs changes for a new flag.
- These are upstream hot files: keep additions minimal and appended.

## Add or extend a CDP method

- Handlers live in [src/cdp/domains/](../src/cdp/domains/), one file per
  domain; dispatch is a prefix match on the method string in
  [src/cdp/CDP.zig](../src/cdp/CDP.zig).
- Fork-vendor methods belong in a vendor domain (upstream precedent:
  `domains/lp.zig`) rather than spread across standard domains.

## Testing notes beyond AGENTS.md

- One test binary over the whole module; the custom runner
  ([src/test_runner.zig](../src/test_runner.zig)) reads its knobs from env
  vars, not flags. `TEST_FILTER` splits on `#` for main-test # subtest.
- [src/testing.zig](../src/testing.zig) auto-starts an in-process HTTP and
  WebSocket test server; unknown request paths print a loud diagnostic instead
  of 404ing silently.
- Log output is part of the test contract: `testing.expectLog` asserts on
  emitted scopes, `testing.silenceLog` suppresses expected noise.
- **Leaks fail tests** in debug builds. If a test fails with an allocation
  report, fix the missing free — don't suppress it.

## Things not to do

- Don't run the full WPT suite locally without being asked — it needs the
  wpt fork, /etc/hosts entries, and a Go runner, and takes a long time.
- Don't edit generated files by hand
  ([src/data/public_suffix_list.zig](../src/data/public_suffix_list.zig) comes
  from the checked-in Go generator; `src/data/protocol.json` is the CDP spec).
- Don't touch `.github/` workflows or `.plumber.yaml` unless the task is
  explicitly about CI.
- Don't commit `.lp-cache/`, `src/snapshot.bin`, or `src/html5ever/target/`
  (already gitignored).
