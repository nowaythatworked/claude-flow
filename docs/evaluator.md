# `flow-rules` evaluator

The evaluator is a single Bun-compiled binary that decides which dynamic rules apply to the current task. It replaces the old `evaluate-dynamic-rules.sh` + `claude -p` flow that caused 60s latency on every prompt.

The binary is committed at `bin/flow-rules`. Hooks (Phase 2) call it; you can also invoke it manually for debugging.

## What it does

Three selection paths, all running over rules in `.flow/rules/dynamic/*.md`:

| Path | Trigger | Speed |
|---|---|---|
| **Pattern** | Frontmatter `patterns` glob matches a file path | sync, ~ms |
| **Keyword** | Frontmatter `keywords` substring-match recent text | sync, ~ms |
| **LLM** | Frontmatter `relevance` describes when to apply; Haiku decides from a digest | async, ~3-7s |

Selection is the **union** of all three. A rule with multiple signal fields uses each one — pattern/keyword can pre-select before LLM runs. The LLM catalog excludes rules already selected by pattern/keyword (no point asking).

## CLI

```
flow-rules eval [--sync|--async] --reason <r> --cwd <p> --session-id <id>
                [--transcript <path>] [--task-file <name>] [--focus <json>]
                [--cache-key <key>] [--plugin-root <p>]
                # When --task-file and --focus are omitted, the cache key
                # is auto-derived to session__<session-id> (vanilla session).

flow-rules hook user-prompt-submit       # reads Claude Code hook payload from stdin
flow-rules hook pre-tool-use
flow-rules hook subagent-start

flow-rules state show   [--cwd <p>] [--task-file <name>] [--focus <json>] [--session-id <id>]
flow-rules state path   [--cwd <p>] [--task-file <name>] [--focus <json>] [--session-id <id>]
flow-rules state status [--cwd <p>] [--task-file <name>] [--focus <json>] [--session-id <id>] [--brief]

flow-rules cleanup [--cwd <p>] [--dry-run] [--max-eval-log <N>]
                   [--max-pending-signals <N>] [--max-vanilla-cache-age-days <N>]
```

## State files

Per `(task_file, focus)` pair, persisted at:

```
.flow/rule-cache/<task_file>__<focus_hash>.json
```

For **vanilla (non-flow) sessions** — i.e. sessions with no entry in `.flow/SESSIONS.json` — the cache is keyed by full session id:

```
.flow/rule-cache/session__<session_id>.json
```

This per-session keying prevents two concurrent vanilla sessions in the same project from sharing one cache (which would leak rule selections cross-session).

Subagents get their own cache file at `sub__<parent_session>__<agent_id>.json`, warm-started from parent's selection. The parent lookup is a two-step probe: try the flow-cache key first, fall back to `session__<parent>` if SESSIONS.json has no entry.

State shape (JSON):

```ts
{
  schema_version: 1,
  task_file: string,
  focus: string[],
  focus_hash: string,
  selected_via_pattern: string[],   // rule ids
  selected_via_keyword: string[],
  selected_via_llm: string[],
  task_type: string,
  trigger_reason: string,
  last_eval_ts: string,
  last_eval_duration_ms: number,
  per_session: { [session_id]: { watermark_uuid, last_seen_ts } }
}
```

The injected ruleset is the **union** of the three `selected_via_*` arrays.

## Watermark

Each session tracks a `watermark_uuid` — the last transcript entry analyzed by an LLM eval. New evals start from `watermark + 1`, so we never re-analyze the same conversation history. The watermark advances **script-side** after a successful Haiku call; on failure it stays put and the next eval retries from the same point.

## Locking

To prevent concurrent evals from clobbering each other, each cache file has a sibling `.lock/` directory (atomic via `mkdir`). Inside lives `info.json` with `{pid, started_at, trigger, session_id, covers_up_to_uuid}`.

- **Async trigger** while lock held: skip — the in-flight eval will deliver.
- **Sync trigger** while lock held: wait up to `max-wait-ms` for release, then check if the result covers our latest transcript entry. If yes, ride along. If no, re-eval.
- **Stale lock** (>90s OR holding PID dead): reaped and reacquired.

## Recursion guard

When the binary spawns `claude -p` for the LLM eval, it sets `FLOW_NO_HOOKS=1` in the child env. Hook scripts (Phase 2) short-circuit on this var. Without it, the child claude triggers its own UserPromptSubmit hook, which spawns another claude, which… you get the idea — that's the bug we're fixing.

The guard is also honored by the binary's own hook subcommands: `FLOW_NO_HOOKS=1 flow-rules hook user-prompt-submit` returns `{}` immediately.

## Gating model — flow vs vanilla sessions

Hooks split into two groups by what they need from `.flow/SESSIONS.json`:

| Hook | Behavior in flow session | Behavior in vanilla session |
|---|---|---|
| `flow-rules hook user-prompt-submit` | Pattern/keyword sync, async LLM kickoff, delta-inject | Same, keyed by `session__<id>` |
| `flow-rules hook pre-tool-use` | Same | Same, keyed by `session__<id>` |
| `flow-rules hook subagent-start` | Warm-start from parent's flow cache | Warm-start from parent's `session__<id>` cache (if any), else cold-start |
| `phase-gate.sh` (UserPromptSubmit) | Phase reminder | Skipped (no SESSIONS.json) |
| `phase-guard.sh` (PreToolUse Write/Edit) | Write protection during planning/planned | Skipped |
| `branch-detect.sh` (SessionStart) | Detects branched flow sessions | Skipped |
| `inject-session-rules.sh` (SessionStart) | Always-on rule injection | Same |

In short: **dynamic rule evaluation runs in any Claude Code session**. The workflow-specific hooks (phase reminders, write-protection, branch detection) cleanly no-op when there's no flow workflow active.

Cleanup is mtime-driven for vanilla caches: `flow-rules cleanup` reaps `session__<id>.json` files older than `--max-vanilla-cache-age-days` (default 5), unless an active lock holds them. Paired injected ledgers are reaped in tandem.

## Debugging

```bash
# Inspect current selection for a task
flow-rules state show --cwd /path/to/repo --task-file my-task.md --focus '["Phase 1"]'

# See the cache file path
flow-rules state path --cwd /path/to/repo --task-file my-task.md --focus '[]'

# Watch eval activity
tail -f .flow/rule-cache/eval-log.jsonl | jq

# Reset everything for a project
rm -rf .flow/rule-cache/

# Verify recursion guard
FLOW_NO_HOOKS=1 echo '{}' | flow-rules hook user-prompt-submit   # → {}
```

The `eval-log.jsonl` records `{ts, trigger_reason, task_type, selected_via_*, duration_ms, digest_chars, watermark_uuid}` per eval — useful for measuring hot/cold path costs.

## Build

```bash
cd evaluator
bun install
bun run build       # produces ../bin/flow-rules
bun test            # 82 tests across 10 files
bun run typecheck
```

The compiled binary is ~60MB (bundles the Bun runtime). Committed in-repo for zero-friction install.
