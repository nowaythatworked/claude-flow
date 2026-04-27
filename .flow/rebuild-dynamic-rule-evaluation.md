# Rebuild Dynamic Rule Evaluation

## Context

Investigation found that `evaluate-dynamic-rules.sh` causes ~60s latency on every UserPromptSubmit in production (orbit). Across 16 user prompts in 6 orbit sessions: median 68s, 100% over 55s. Root cause: hook fires on every prompt, calls `claude -p haiku` with up to 150K-char transcript + 15-rule catalog, recursively triggers itself via plugin hook re-entry, never completes within 60s timeout, never writes cache, every subsequent prompt repeats the path. Existing skip heuristic (<30 chars + cache) cannot engage because cache is never written.

The system needs to be rebuilt — not patched.

## Goals

- UserPromptSubmit hook latency: <50ms hot path, <500ms cold path. Never 60s.
- Rule selection is incremental, watermark-driven, not a from-scratch recomputation.
- Synchronous correctness checkpoints at `/flow:approve` and `/flow:implement`.
- Branched sessions and subagents work cleanly.
- Single source of truth for rule selection logic.

## Architecture (locked)

- **Storage**: `.flow/rule-cache/<task_file>__<focus_hash>.json` (parent sessions); `.flow/rule-cache/sub__<parent_session>__<agent_id>.json` (subagents); `.flow/rule-cache/eval-log.jsonl` (telemetry). Lock file as sibling `<state>.json.lock`. State writes are tmp + atomic rename.
- **Cache shape**: schema_version, task_file, focus, focus_hash, selected_rules, task_type, trigger_reason, last_eval_ts, last_eval_duration_ms, per_session map of (watermark_uuid, last_seen_ts).
- **Evaluator**: Bun-compiled binary at `${CLAUDE_PLUGIN_ROOT}/bin/flow-rules`. Watermark-bounded transcript extraction (Read results, Edit diffs, Glob/Grep results, recent user/assistant text). Generous truncation: full files <30KB; head 300 + tail 50 lines otherwise; no overall input cap. Single Haiku call with structured output `{ task_type, selected_rules, reason }`. Catalog passed = rule-id + 1-line description only (never rule bodies). Tools enabled (Read, Glob, Grep) with `maxTurns: 3` ceiling. Watermark advanced script-side based on what was included in the digest (never LLM-decided).
- **Recursion guard**: `FLOW_NO_HOOKS=1` env var set before any subprocess `claude -p`. First line of every hook script: short-circuit if set.
- **Concurrency**: cooperative `.lock` file (PID + timestamp + covers_up_to_uuid). Async triggers skip-on-busy. Sync triggers wait up to 15s, then verify watermark coverage, re-eval if stale. Stale-lock reaping at 90s + dead-PID check.
- **Modes (rule frontmatter)**: `pattern` | `pattern+llm` | `llm` | `keyword`. Default = `llm`; `applies_to` upgrades default to `pattern+llm`. No `always` mode (`.flow/rules/` directory is the always-on path).
- **Triggers**: Sync pattern+keyword on every UserPromptSubmit and on PreToolUse(Edit|Write|Read|Glob|Grep). Async LLM eval kickoff on UserPromptSubmit + every 5 tool calls + 60s heartbeat. 30s minimum spacing between LLM evals.
- **Checkpoints**: `/flow:approve` and `/flow:implement` skill instructions force `flow-rules eval --sync` and require the agent to cross-check the plan against ALL loaded rules (static AND dynamic, prior AND new) every time — not just once.
- **Skill rework**: `build`, `next`, `implement` restructured with named/numbered anchored sections, full instructions per section, audit-shape outputs at checkpoints.
- **Phase-aware reminders**: `phase-gate.sh` reads SESSIONS.json and emits a phase-specific reminder pointing at the correct skill+section, including instruction to re-invoke the skill if the section content isn't recalled.
- **Subagents**: per-subagent cache file warm-started from parent's selection; independent eval against own transcript.
- **rule-evaluator agent**: retired. Single binary covers all paths (hooks + skills).

## Phase 1 — Evaluator core

Status: **complete** (commits 4871433, e06b2ee, 837deeb)

- [x] Initialize Bun project at `evaluator/` with TypeScript (strict, ES2022, noUncheckedIndexedAccess)
- [x] Cache schema + atomic-write helpers — `cache.ts`, tmp file + `fs.renameSync`, schema_version validation
- [x] Lock primitive — `lock.ts`, `mkdir`-based atomic, `info.json` inside lock dir, 90s + dead-PID stale reap, `waitForRelease` with 100ms polling
- [x] JSONL transcript parser — `transcript.ts`, watermark-bounded, Read/Edit/Glob/Grep + last 5 user + last 5 assistant text bursts
- [x] Glob matcher — `matcher.ts`, minimatch with `dot:true` for `patterns` field
- [x] Keyword matcher — `matcher.ts`, case-insensitive substring against recent text
- [x] Rule-catalog builder — `catalog.ts`, descriptions only (rule bodies loaded only at injection time); skips signal-less rules with warning
- [x] Digest builder with truncation — `digest.ts`, full <30KB / head 300 + tail 50 / disk fallback head 100 for edited-but-not-read
- [x] Haiku invoker — `haiku.ts`, `Bun.spawn` of `claude -p --model haiku --json-schema --no-session-persistence`, no `--tools` (defaults), no `--max-budget-usd`
- [x] Watermark advancement — script-side, only persists after successful Haiku response
- [x] eval-log.jsonl appender — `log.ts`, fs.appendFileSync with structured entry per eval
- [x] `FLOW_NO_HOOKS=1` recursion guard — set in child env before spawning `claude`; honored by binary's own hook subcommands
- [x] CLI surface — `cli.ts`, all eval/hook/state subcommands per spec
- [x] Build to `bin/flow-rules` — bun build --compile, 60MB; **ad-hoc codesigned** to bypass macOS Gatekeeper kills on unsigned binaries with `com.apple.provenance` xattr
- [x] Tests — 82 passing across 10 files: cache, lock, frontmatter, matcher, catalog, transcript, digest, inject, paths, integration. Mock claude via PATH override; integration test verifies pattern+keyword+LLM merge, watermark advance, lock release, log append, haiku-failure-no-watermark-advance
- [x] Frontmatter shape implemented as approved: `relevance`, `patterns`, `keywords` (no `eval_mode`); presence-inferred selection logic; LLM catalog excludes already pattern/keyword-selected rules
- [x] Per-subagent cache file shape (`sub__<parent>__<agent>.json`) + warm-start from parent's selection — `subagent-start.ts`
- [x] Frontmatter stripping for injection — `inject.ts`, body-only with header
- [x] Documentation — `docs/evaluator.md` (CLI, state files, locking, recursion guard, debugging); README "Internals" section linking to docs/

### Phase 1 follow-ups (commits dcb2fdb, 01e4467, 5f62f83)

- [x] **Codesign in build script** (dcb2fdb): `bun run build` now appends `codesign -s - ../bin/flow-rules` (wrapped with `|| true` for non-macOS). Bun-compiled binaries inherit `com.apple.provenance` xattr that triggers Gatekeeper SIGKILL on read/hash without a signature.
- [x] **PreToolUse async kickoff + pending-signals** (01e4467): every PreToolUse extracts file_path/path/pattern from tool input, appends to `.flow/rule-cache/pending-signals.jsonl`, runs sync pattern+keyword match (additive), spawns detached async LLM eval (30s debounce). Next `runFullEval` drains pending-signals into pattern matcher + digest. Truncates on successful eval; preserves on failure for retry. This closes both gap (a) "every-5-tool-uses trigger" and (c) "Glob.path handling" — every tool boundary now feeds the eval pipeline.
- [x] **`--max-turns 3` in haiku.ts** (01e4467): hard ceiling on tool-use loops claude might take.
- [x] **Real claude in integration tests** (01e4467): mock-claude removed; integration test invokes real `claude -p --model haiku`, asserts state shape + deterministic pattern path; treats LLM selection as shape-only (model variance). Skips on `FLOW_SKIP_REAL_CLAUDE=1` or missing `claude` binary. Test count: 82 → 107.

### Still deferred

- **60s heartbeat** for forced eval if nothing has happened — could be added but cheap to skip; in practice every UserPromptSubmit and every PreToolUse already kicks the eval (debounced).
- **End-to-end live verification in orbit** — happens in Phase 8.

## Phase 2 — Hook integration

- [ ] Replace `evaluate-dynamic-rules.sh` with thin shell wrapper that calls `flow-rules hook user-prompt-submit`
- [ ] Replace `periodic-rule-eval.sh` (drop entirely; superseded by background trigger from binary)
- [ ] Add `pre-tool-use-rules.sh` for PreToolUse(Edit|Write|Read|Glob|Grep) running pattern+keyword pass only
- [ ] Update `hooks/hooks.json` matchers and timeouts
- [ ] All hook scripts: first-line `FLOW_NO_HOOKS` short-circuit
- [ ] Background eval kickoff via `setsid + & + disown`
- [ ] Verify hook timing: hot path UserPromptSubmit <50ms; PreToolUse pattern <30ms

## Phase 3 — Skill rework

- [ ] Restructure `skills/build/SKILL.md` with named anchor sections; add explicit `Checkpoint — before /flow:approve` section with full instructions and required audit-shape output (enumerate rules checked + result per rule)
- [ ] Restructure `skills/next/SKILL.md` with named anchor sections; add `Deep-dive process` section and `Checkpoint — before /flow:implement` section with same audit-shape requirement
- [ ] Restructure `skills/implement/SKILL.md` with named anchor sections; add `Implementation rules` section
- [ ] Each checkpoint section explicitly requires: cross-check plan against ALL loaded rules (static + dynamic, prior + new), every time, even if checkpoint ran earlier in the conversation
- [ ] Skills replace any `Agent flow:rule-evaluator` invocations with direct `flow-rules eval --sync` calls

## Phase 4 — Phase-aware reminders

- [ ] Rewrite `scripts/phase-gate.sh` to read SESSIONS.json (phase + focus + task_file)
- [ ] Emit dynamic reminder per state: planning → /flow:build § Checkpoint; planned no-focus → /flow:next § Deep-dive process; planned + focus → /flow:next § Checkpoint; implementing → /flow:implement § Implementation rules
- [ ] Reminder template: terse pointer + section name + "if you cannot recall, re-invoke /flow:<skill> or Read SKILL.md"
- [ ] Drop the bloated rule-summary text; reminders point, don't teach
- [ ] Update `inject-session-rules.sh` if it overlaps

## Phase 5 — SubagentStart integration

- [ ] Update `subagent-inject.sh` to read parent's `(task_file, focus_hash)` cache and write a fresh `sub__<parent>__<agent>.json` cache file warm-started with parent's `selected_rules`
- [ ] Subagent's own UserPromptSubmit / PreToolUse hooks operate on its own cache file keyed by its session_id
- [ ] Subagent transcript discovered at `<parent_session>/subagents/agent-<id>.jsonl`
- [ ] Cleanup: subagent cache files included in periodic sweep

## Phase 6 — Retire rule-evaluator agent

- [ ] Delete `agents/rule-evaluator.md` and version mirrors in `~/.claude/plugins/cache/`
- [ ] Remove references from `README.md`
- [ ] Remove `Agent flow:rule-evaluator` invocations from `skills/reload-rules/SKILL.md` and `skills/build/SKILL.md` (replaced by direct `flow-rules eval --sync` in Phase 3)
- [ ] Verify no lingering references via grep

## Phase 7 — Rule frontmatter migration

- [ ] Audit each dynamic rule by hand: `claude-flow/.flow/rules/dynamic/debug-hooks.md` + the 15 rules in orbit (`cockpit-mobile`, `design-system`, `domain-glossary`, `event-bus-patterns`, `external-api`, `geocoding`, `infra-sst`, `mantine-conventions`, `meilisearch-indexing`, `product-brick-runtime-types`, `qax-query-accelerator`, `react-components`, `redux-local-db`, `shop-remix`, `storybook-patterns`, `trpc-routers`)
- [ ] For each: set `eval_mode` (pattern | pattern+llm | llm | keyword), populate `applies_to` globs, populate `keywords` list, refine `description` for the catalog
- [ ] Per-rule decisions documented inline in the rule file

## Phase 8 — Production verification

- [ ] Measure UserPromptSubmit gap on a fresh orbit session: target median <10s, p95 <20s
- [ ] Measure PreToolUse hook latency: target <30ms p99
- [ ] Confirm cache + eval-log files are populated
- [ ] Confirm `/flow:approve` and `/flow:implement` checkpoints produce audit-shape output (enumerate rules + per-rule result)
- [ ] Confirm subagent eval works independently in a delegated `flow:dev` task
- [ ] Confirm branched sessions share cache correctly
- [ ] Confirm recursion guard prevents nested `claude -p` from re-entering hooks

## Phase 9 — Optional follow-ups

- [ ] `/flow:rules-status` debugging skill (show current selection, watermark, last eval time, last trigger reason, recent log entries)
- [ ] Telemetry surface in `/flow:phase` output
- [ ] Periodic cache cleanup (subagent caches older than N days)

## Out of scope (for now)

- Pre-staging file content into agent context as part of rule injection (was Option A in evaluator design — deferred until B2+tools metrics justify it)
- `Stop` hook checkpoint backstop (covered by phase-aware reminder + skill instructions)
- Cross-project rule selection sharing
- Rule heat-map / unused-rule pruning report
