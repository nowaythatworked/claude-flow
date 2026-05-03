import type {
  CacheState,
  ExtractedContent,
  LockInfo,
  RuleCatalog,
  HaikuOutput,
} from "./types.ts";
import { deriveCacheKey } from "./paths.ts";
import { readState, writeState, initState } from "./cache.ts";
import { acquireLock } from "./lock.ts";
import { loadCatalog, buildLLMCatalog } from "./catalog.ts";
import { extractSinceWatermark } from "./transcript.ts";
import { matchPatterns, matchKeywords } from "./matcher.ts";
import { buildDigest } from "./digest.ts";
import { evaluate as haikuEvaluate, resolveEvalModel } from "./haiku.ts";
import { appendLog } from "./log.ts";
import {
  drainPendingSignals,
  truncatePendingSignals,
} from "./pending-signals.ts";

export interface FullEvalOpts {
  cwd: string;
  taskFile: string;
  focus: string[];
  sessionId: string;
  transcriptPath: string | null;
  triggerReason: string;
  /**
   * Optional cache key override. When provided, the eval reads/writes state
   * under this key instead of `deriveCacheKey(taskFile, focus)`. Used by
   * vanilla (non-flow) sessions to key cache by `session__<id>`.
   */
  cacheKey?: string;
}

export interface PatternOnlyOpts {
  cwd: string;
  taskFile: string;
  focus: string[];
  sessionId: string;
  triggerReason: string;
  filePaths: string[];
  text: string;
  /** Optional cache key override (see FullEvalOpts.cacheKey). */
  cacheKey?: string;
}

export type EvalResult =
  | { kind: "ok"; state: CacheState }
  | { kind: "lock_held" }
  | { kind: "skipped"; reason: string };

export async function runFullEval(opts: FullEvalOpts): Promise<EvalResult> {
  const start = Date.now();
  const key = opts.cacheKey ?? deriveCacheKey(opts.taskFile, opts.focus).key;

  const lockInfo: LockInfo = {
    pid: process.pid,
    started_at: new Date().toISOString(),
    trigger: opts.triggerReason,
    session_id: opts.sessionId,
    covers_up_to_uuid: null,
  };
  const lock = acquireLock(key, opts.cwd, lockInfo);
  if (!lock) return { kind: "lock_held" };

  try {
    let state = readState(key, opts.cwd);
    if (!state) {
      state = initState(opts.taskFile, opts.focus, opts.cwd);
    }

    const catalog: RuleCatalog = loadCatalog(opts.cwd);
    const watermark =
      state.per_session[opts.sessionId]?.watermark_uuid ?? null;

    const extracted: ExtractedContent = opts.transcriptPath
      ? extractSinceWatermark(opts.transcriptPath, watermark)
      : {
          filesInScope: { reads: new Map(), edits: new Map() },
          globResults: [],
          recentUserText: [],
          recentAssistantText: [],
          newWatermarkCandidate: watermark ?? "",
        };

    const pendingSignals = drainPendingSignals(opts.cwd);
    const signalPaths = uniqueStrings(
      pendingSignals.map((s) => s.path),
    );

    const transcriptPaths = collectFilePaths(extracted);
    const allPathsForMatching = uniqueStrings([
      ...transcriptPaths,
      ...signalPaths,
    ]);
    const text = collectText(extracted);

    const patternHits = matchPatterns(allPathsForMatching, catalog);
    const keywordHits = matchKeywords(text, catalog);

    const alreadySelected = new Set<string>([...patternHits, ...keywordHits]);
    const llmCatalog = buildLLMCatalog(catalog, alreadySelected);

    let haiku: HaikuOutput | null = null;
    let digest = "";
    if (llmCatalog.length > 0) {
      digest = buildDigest(
        extracted,
        [...alreadySelected],
        llmCatalog,
        signalPaths,
      );
      const model = resolveEvalModel(opts.triggerReason);
      try {
        haiku = await haikuEvaluate(digest, model);
      } catch (err) {
        process.stderr.write(
          `[flow-rules] ${model} eval failed: ${(err as Error).message}\n`,
        );
      }
    }

    const llmHits = haiku
      ? haiku.selected_rules.filter((id) => catalog.has(id))
      : state.selected_via_llm;

    state.selected_via_pattern = patternHits;
    state.selected_via_keyword = keywordHits;
    state.selected_via_llm = llmHits;
    if (haiku) state.task_type = haiku.task_type;
    state.trigger_reason = opts.triggerReason;
    state.last_eval_ts = new Date().toISOString();
    state.last_eval_duration_ms = Date.now() - start;

    if (haiku && extracted.newWatermarkCandidate !== "") {
      state.per_session[opts.sessionId] = {
        watermark_uuid: extracted.newWatermarkCandidate,
        last_seen_ts: state.last_eval_ts,
      };
    }

    // truncate signals only when consumed end-to-end:
    //   - no LLM catalog needed → signals fully handled via pattern match
    //   - LLM catalog present and haiku succeeded → fully handled
    // if haiku was needed but failed, leave signals so the next eval retries
    const signalsConsumed = llmCatalog.length === 0 || haiku !== null;
    if (signalsConsumed && pendingSignals.length > 0) {
      truncatePendingSignals(opts.cwd);
    }

    writeState(key, state, opts.cwd);

    appendLog(opts.cwd, {
      ts: state.last_eval_ts,
      trigger_reason: opts.triggerReason,
      task_type: state.task_type,
      selected_via_pattern: state.selected_via_pattern,
      selected_via_keyword: state.selected_via_keyword,
      selected_via_llm: state.selected_via_llm,
      duration_ms: state.last_eval_duration_ms,
      digest_chars: digest.length,
      watermark_uuid: state.per_session[opts.sessionId]?.watermark_uuid ?? null,
    });

    return { kind: "ok", state };
  } finally {
    lock.release();
  }
}

export function runPatternOnly(opts: PatternOnlyOpts): EvalResult {
  const start = Date.now();
  const key = opts.cacheKey ?? deriveCacheKey(opts.taskFile, opts.focus).key;
  const lockInfo: LockInfo = {
    pid: process.pid,
    started_at: new Date().toISOString(),
    trigger: opts.triggerReason,
    session_id: opts.sessionId,
    covers_up_to_uuid: null,
  };
  const lock = acquireLock(key, opts.cwd, lockInfo);
  if (!lock) return { kind: "lock_held" };

  try {
    let state = readState(key, opts.cwd);
    if (!state) {
      state = initState(opts.taskFile, opts.focus, opts.cwd);
    }
    const catalog = loadCatalog(opts.cwd);
    const newPattern = matchPatterns(opts.filePaths, catalog);
    const newKeyword = matchKeywords(opts.text, catalog);

    state.selected_via_pattern = mergeUnique(
      state.selected_via_pattern,
      newPattern,
    );
    state.selected_via_keyword = mergeUnique(
      state.selected_via_keyword,
      newKeyword,
    );
    state.trigger_reason = opts.triggerReason;
    state.last_eval_ts = new Date().toISOString();
    state.last_eval_duration_ms = Date.now() - start;

    writeState(key, state, opts.cwd);

    appendLog(opts.cwd, {
      ts: state.last_eval_ts,
      trigger_reason: opts.triggerReason,
      task_type: state.task_type,
      selected_via_pattern: state.selected_via_pattern,
      selected_via_keyword: state.selected_via_keyword,
      selected_via_llm: state.selected_via_llm,
      duration_ms: state.last_eval_duration_ms,
      digest_chars: 0,
      watermark_uuid: state.per_session[opts.sessionId]?.watermark_uuid ?? null,
    });

    return { kind: "ok", state };
  } finally {
    lock.release();
  }
}

export function unionAllSelected(state: CacheState): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const id of [
    ...state.selected_via_pattern,
    ...state.selected_via_keyword,
    ...state.selected_via_llm,
  ]) {
    if (seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

function mergeUnique(a: string[], b: string[]): string[] {
  const seen = new Set<string>(a);
  const out = [...a];
  for (const id of b) {
    if (!seen.has(id)) {
      seen.add(id);
      out.push(id);
    }
  }
  return out;
}

function uniqueStrings(values: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const v of values) {
    if (seen.has(v)) continue;
    seen.add(v);
    out.push(v);
  }
  return out;
}

function collectFilePaths(extracted: ExtractedContent): string[] {
  const out = new Set<string>();
  for (const k of extracted.filesInScope.reads.keys()) out.add(k);
  for (const k of extracted.filesInScope.edits.keys()) out.add(k);
  for (const list of extracted.globResults) {
    for (const p of list) out.add(p);
  }
  return [...out];
}

function collectText(extracted: ExtractedContent): string {
  return [
    ...extracted.recentUserText,
    ...extracted.recentAssistantText,
  ].join("\n");
}
