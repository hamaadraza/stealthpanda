# .ai/ — LLM context for this fork

This directory is **owned by the fork** (stealthpanda) and never conflicts with
upstream merges. It holds the context and rules that coding agents (Claude Code,
Cursor, Codex, etc.) need to work on this repo safely.

| File | Purpose | Loaded when |
|---|---|---|
| [FORK.md](FORK.md) | The fork's ground rules: what may be changed and how, so upstream merges stay cheap. | Always (imported by `CLAUDE.md`). |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Map of the codebase: directories, entry points, request flows, the V8 binding layer. | Read on demand before non-trivial changes. |
| [WORKFLOWS.md](WORKFLOWS.md) | Recipes: build, test, sync with upstream, add a Web API, add a CLI flag, add a CDP handler. | Read on demand when doing that task. |

Rules for editing this directory:

- Keep `FORK.md` short — it is loaded into every agent session. Deep reference
  material belongs in the other files.
- When a fork decision changes (new dedicated source dir, new release scheme,
  telemetry policy), update `FORK.md` in the same PR as the code change.
- Upstream's own agent docs live in `AGENTS.md` at the repo root; do not
  duplicate their content here — link to them.
