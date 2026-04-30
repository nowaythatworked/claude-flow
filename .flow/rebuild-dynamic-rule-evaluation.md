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

- **Storage**: `.flow/rule-cache/<task_file>__<focus_hash>.json` (parent sessions); `.flow/rule-cache/sub__<parent_session>__<agent_id>.json` (subagents); `.flow/rule-cache/eval-log.jsonl` (telemetry); `.flow/rule-cache/pending-signals.jsonl` (PreToolUse-accumulated paths between evals). Lock file as sibling `<state>.json.lock` (mkdir-based atomic). State writes are tmp + atomic rename.
- **Cache shape**: schema_version, task_file, focus, focus_hash, **selected_via_pattern[]**, **selected_via_keyword[]**, **selected_via_llm[]** (injected = union of the three), task_type, trigger_reason, last_eval_ts, last_eval_duration_ms, per_session map of (watermark_uuid, last_seen_ts).
- **Evaluator**: Bun-compiled binary at `${plugin}/bin/flow-rules` (committed in-repo, ad-hoc codesigned via `bun run build` to bypass macOS Gatekeeper). Watermark-bounded transcript extraction (Read results, Edit diffs, Glob/Grep results, recent user/assistant text). Generous truncation: full files <30KB; head 300 + tail 50 lines otherwise; no overall input cap. Disk fallback (`head -100`) for files edited but not read. Single Haiku call with structured output `{ task_type, selected_rules, reason }`. Catalog passed = rule-id + 1-line `relevance` only (never rule bodies). `--max-turns 3` ceiling; no `--tools` flag (claude default tool set); no `--max-budget-usd` (cost analyzed post-hoc via session JSONLs and eval-log). Watermark advanced script-side based on what was included in the digest (never LLM-decided).
- **Recursion guard**: `FLOW_NO_HOOKS=1` env var set in subprocess env before any `claude -p` spawn. First line of every hook (binary's hook commands AND Phase 2 shell scripts): short-circuit if set. End-to-end test exercises this against real claude with a custom plugin.
- **Concurrency**: cooperative `.lock` directory (PID + timestamp + covers_up_to_uuid in `info.json`). Async triggers skip-on-busy. Sync triggers wait up to 15s, then verify watermark coverage, re-eval if stale. Stale-lock reaping at 90s + dead-PID check.
- **Frontmatter shape (presence-inferred, no `eval_mode` field)**: any subset of three fields:
  - `relevance: "<one-line description of when this rule applies>"` → rule becomes an LLM candidate
  - `patterns: ["**/*.tsx", ...]` → glob-matched against file paths the agent touches
  - `keywords: ["component", ...]` → case-insensitive substring match against recent user text + tool args
  - Selection = **union** of all three paths. LLM catalog excludes rules already selected by pattern/keyword (no point asking).
  - Rule with no signal fields → skipped + warned (author opted out).
  - Field renames vs original plan: `applies_to` → `patterns`, `description` → `relevance`. Migration in Phase 7 hand-rewrites each rule.
- **Triggers**: Sync pattern+keyword on every UserPromptSubmit and every PreToolUse (extracts file_path/path/pattern from tool input, appends to pending-signals). Async LLM eval kicked off from both — 30s minimum-spacing debounce blocks stampede. If kickoff is debounced, the path is already in pending-signals so the next eval consumes it. No 5-tool counter or 60s heartbeat needed (every-tool-boundary kickoff covers it).
- **Checkpoints**: `/flow:approve` and `/flow:implement` skill instructions force `flow-rules eval --sync` and require the agent to cross-check the plan against ALL loaded rules (static AND dynamic, prior AND new) every time — not just once.
- **Skill rework**: `build`, `next`, `implement` restructured with named/numbered anchored sections, full instructions per section, audit-shape outputs at checkpoints.
- **Phase-aware reminders**: `phase-gate.sh` reads SESSIONS.json and emits a phase-specific reminder pointing at the correct skill+section, including instruction to re-invoke the skill if the section content isn't recalled.
- **Subagents**: per-subagent cache file (`sub__<parent>__<agent>.json`) warm-started from parent's selection; independent eval against own transcript at `<parent_session>/subagents/agent-<id>.jsonl`.
- **rule-evaluator agent**: retired. Single binary covers all paths (hooks + skills).
- **Tests**: integration tests use real claude (same model as production: haiku); skip via `FLOW_SKIP_REAL_CLAUDE=1` or when `claude` not on PATH. Recursion guard verified by stub-claude env capture + real-claude e2e with custom plugin.

### Deviations from earlier design (during deep-dive / implementation)

These changes were agreed in conversation and superseded earlier sections of the architecture. Captured here so the plan reflects what's actually built.

| Original | Replaced with | Why |
|---|---|---|
| `eval_mode: pattern\|keyword\|llm\|pattern+llm` field | Presence-inferred from which fields are set (`relevance`/`patterns`/`keywords`) | Simpler; rule authors already think in terms of what signals exist; no extra flag to learn |
| Field name `applies_to` | `patterns` | Plural matches the array value; clearer mental model |
| Field name `description` | `relevance` | "Description" is generic; `relevance` names what the field's actually for (the LLM's relevance-decision instruction) |
| 5-tool-counter + 60s heartbeat triggers | Every UserPromptSubmit + every PreToolUse triggers async eval (debounced 30s) | Pending-signals + universal kickoff makes counters/heartbeat redundant; simpler |
| `claude --tools "Read,Glob,Grep"` | No `--tools` flag (claude default set) | User clarification: passing `--tools` only restricts; default already gives claude what it needs |
| `--max-budget-usd` cost cap | None (cost measured post-hoc via session JSONLs) | User accepts cost; cap added complexity for marginal value |
| `claude --bare` for recursion guard | `FLOW_NO_HOOKS=1` env var | `--bare` requires API key auth; user is on OAuth (claude.ai). Env var works with any auth |
| Rule body bodies passed to LLM eval | Only rule-id + `relevance` to LLM; full body loaded only at injection time | Smaller LLM input; clearer separation between "rule selection" and "rule injection" |
| Mock claude in integration tests | Real claude via PATH (skippable via env) | User wants tests close to reality, OK with cost |
| One commit binary in CI | Committed binary in repo, codesigned in build script | Zero-friction install for personal use; Gatekeeper SIGKILL workaround captured in build script |

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

Status: **complete** (commits 244402c, be7292d)

Design simplification during deep-dive: the original plan was to add thin shell wrappers around the binary. Inspection of the Phase 1 implementation showed `flow-rules hook <name>` already handles stdin parsing, recursion guard, sync pattern+keyword, async LLM kickoff, and JSON output — wrappers would add nothing. `hooks.json` now invokes the binary directly. No new shell wrappers.

- [x] Update `hooks/hooks.json`: UserPromptSubmit calls `${CLAUDE_PLUGIN_ROOT}/bin/flow-rules hook user-prompt-submit` (timeout 5, was 60); new PreToolUse entry with matcher `Edit|Write|Read|Glob|Grep` calls `flow-rules hook pre-tool-use` (timeout 5); PostToolUse `periodic-rule-eval` entry dropped entirely
- [x] Add `FLOW_NO_HOOKS=1` short-circuit (after `set -euo pipefail`) to remaining shell hooks: `phase-gate.sh`, `rule-reminder.sh`, `branch-detect.sh`, `inject-session-rules.sh`, `subagent-inject.sh`, `scan-quality.sh`, `phase-guard.sh`. Binary subcommands already have the guard internally.
- [x] Delete obsolete bash scripts: `scripts/evaluate-dynamic-rules.sh` (109 lines), `scripts/eval-rules-core.sh` (236 lines), `scripts/periodic-rule-eval.sh` (141 lines), and `tests/test-eval-rules-core.sh` (would otherwise fail under `run-all.sh`)
- [x] Background kickoff already inside binary (`Bun.spawn` with `stdin/stdout/stderr: "ignore"` + `FLOW_NO_HOOKS=1` env), no shell-side `setsid` needed
- [x] Verified hook timing on macOS: binary cold start 10-30ms steady state; UserPromptSubmit subcommand with real SESSIONS.json + state read ~20-30ms; PreToolUse subcommand with signal append + pattern match ~20ms. All comfortably under 50ms target. ~3000× improvement over the 60s timeout it replaces.
- [x] Pre-existing failures in `tests/test-scripts.sh` (`flow:next skips additionalContext`, `flow:implement skips additionalContext`) confirmed not caused by these changes (`git stash` reproduced them on baseline)

### Phase 2 follow-ups (deferred)

- **`subagent-inject.sh` still reads `/tmp/flow-rule-cache/last-selection-{session_id}.json`** (legacy bash cache path that no longer exists). It falls back to "load all dynamic rules" when the cache is missing, so it's functionally safe but inefficient. Phase 5 (SubagentStart integration) replaces this with the binary's `flow-rules hook subagent-start` and warm-starts from `.flow/rule-cache/`.
- **End-to-end live verification** (see Phase 8) — measuring actual user-visible latency in orbit.

## Phase 3 — Skill rework

Status: **complete** (commit e6fd187)

Six SKILL.md files reworked. Anchor names locked (no em dashes anywhere): `Checkpoint before /flow:approve` (build), `Deep-dive process` + `Checkpoint before /flow:implement` (next), `Implementation rules` (implement). Audit-shape output is required at both checkpoints, enumerating every loaded rule (static + dynamic, equal weight). Phase 4 reminders will grep these heading strings literally.

- [x] `skills/build/SKILL.md` — added "How rules reach you" preamble (injection vs reminder vs cross-check mental model); added Checkpoint before /flow:approve section with full audit-shape; replaced flow:rule-evaluator agent invocation with `flow-rules eval --sync --reason=planning-start`; replaced bulky Implementation phase section with tight "What happens after planning" + "What NOT to do during planning" boundary sections.
- [x] `skills/next/SKILL.md` — renamed step 5 to "Deep-dive process" (anchored); added step 7 "Checkpoint before /flow:implement" with same audit-shape; added "What happens after the deep-dive" + "What NOT to do during the deep-dive" boundary sections.
- [x] `skills/implement/SKILL.md` — top-level "Implementation rules" section consolidates delegation, verification, documentation, and subagent ambiguity handling expectations; anchored numbered steps; "What happens after implementation" + "What NOT to do during implementation" boundary sections. No checkpoint section in /flow:implement (handled upstream by /flow:next).
- [x] `skills/reload-rules/SKILL.md` — replaced agent invocation in step 2 with `flow-rules eval --sync --reason=user-reload` + `state show` + Read of each selected rule file; documented fallback when binary unavailable.
- [x] `skills/rules/SKILL.md` — fixed path drift (`.claude/rules/` → `.flow/rules/always/`).
- [x] `skills/add-rule/SKILL.md` — extended Step 3 with presence-inferred frontmatter spec (`relevance`, `patterns`, `keywords`) for dynamic rules with worked example. Always-on rules don't need frontmatter.

### Phase 3 design decisions

- **Audit-shape is required, not optional.** Skills instruct the agent to produce a verbatim shape listing every static rule (8 in claude-flow) and every dynamic rule with ✓/⚠/✗ symbols + one-line justification per rule. This makes "did the agent re-check?" observable.
- **Cross-check uses equal weight.** Static and dynamic rules treated identically. The skill text emphasizes "don't pick a subset."
- **No em dashes anywhere.** Headings use no separator (preposition only); audit-shape bullets use `:`; prose uses `,` or `.` or `(...)`. Ensures Phase 4 reminder text matches anchor headings byte-for-byte without typographic ambiguity.
- **Eval failure is non-blocking.** If `flow-rules eval --sync` exits non-zero, the skill instructs the agent to surface the error and proceed with cross-check against rules currently in context. Better to ship a slightly-stale check than no check.
- **build/SKILL.md owns the mental-model preamble.** "How rules reach you" lives once in build; next/implement reference it via `§` pointer rather than duplicating.

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
