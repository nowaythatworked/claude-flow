import * as fs from "node:fs";
import * as path from "node:path";
import { readState } from "./cache.ts";
import {
  deriveCacheKey,
  deriveSessionCacheKey,
  evalLogPath,
  lockDirPath,
  stateFilePath,
} from "./paths.ts";
import { readInjectedLedger, injectedLedgerPath } from "./injected-ledger.ts";
import type { CacheState, EvalLogEntry, LockInfo } from "./types.ts";

export interface FormatStatusOpts {
  cwd: string;
  taskFile: string;
  focus: string[];
  sessionId: string | null;
  brief: boolean;
}

export function formatStatus(opts: FormatStatusOpts): string {
  // When task-file/focus are absent (vanilla session), key on session id.
  const taskMissing =
    opts.taskFile === "" || opts.taskFile === "unknown.md";
  const sid = opts.sessionId;
  const useVanillaKey =
    taskMissing && opts.focus.length === 0 && sid !== null && sid !== "";
  const key = useVanillaKey
    ? deriveSessionCacheKey(sid).key
    : deriveCacheKey(opts.taskFile, opts.focus).key;
  const state = readState(key, opts.cwd);
  if (!state) {
    return "(no state)\n";
  }
  if (opts.brief) {
    return `${formatBrief(state)}\n`;
  }
  return `${formatDefault(opts, key, state)}\n`;
}

function formatBrief(state: CacheState): string {
  const p = state.selected_via_pattern.length;
  const k = state.selected_via_keyword.length;
  const l = state.selected_via_llm.length;
  const total = p + k + l;
  const ago = relativeAgo(state.last_eval_ts);
  const agoText = ago === null ? "never" : `${ago} ago`;
  return `${total} rules selected (${p} pattern, ${k} keyword, ${l} llm); last eval ${agoText}.`;
}

function formatDefault(
  opts: FormatStatusOpts,
  key: string,
  state: CacheState,
): string {
  const lines: string[] = [];
  lines.push(`Cache: ${path.basename(stateFilePath(key, opts.cwd))}`);
  lines.push(formatLockLine(key, opts.cwd));
  lines.push(formatLastEvalLine(state));
  lines.push(`Task type: ${state.task_type === "" ? "(none)" : state.task_type}`);
  lines.push("");
  lines.push(...formatSelectedRules(state));
  lines.push("");
  lines.push(...formatRecentLog(opts.cwd));
  if (opts.sessionId !== null) {
    lines.push("");
    lines.push(formatInjectedLedger(opts.sessionId, opts.cwd));
  }
  return lines.join("\n");
}

function formatLockLine(key: string, cwd: string): string {
  const dir = lockDirPath(key, cwd);
  if (!fs.existsSync(dir)) return "Lock: not held";
  const infoPath = path.join(dir, "info.json");
  if (!fs.existsSync(infoPath)) {
    return "Lock: held (no info.json)";
  }
  let raw: string;
  try {
    raw = fs.readFileSync(infoPath, "utf8");
  } catch {
    return "Lock: held (info.json unreadable)";
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return "Lock: held (info.json invalid)";
  }
  const info = toLockInfo(parsed);
  if (!info) return "Lock: held (info.json invalid)";
  const startedMs = Date.parse(info.started_at);
  const ageS = Number.isFinite(startedMs)
    ? Math.max(0, Math.round((Date.now() - startedMs) / 1000))
    : 0;
  const covers = info.covers_up_to_uuid ?? "(none)";
  return `Lock: held by PID ${info.pid} (${ageS}s old, covers up to ${covers})`;
}

function formatLastEvalLine(state: CacheState): string {
  if (state.last_eval_ts === "") {
    return "Last eval: (never)";
  }
  const ago = relativeAgo(state.last_eval_ts);
  const agoText = ago === null ? "?" : ago;
  return `Last eval: ${state.last_eval_ts} (${agoText} ago, ${state.last_eval_duration_ms}ms), reason=${state.trigger_reason === "" ? "(none)" : state.trigger_reason}`;
}

function formatSelectedRules(state: CacheState): string[] {
  const p = state.selected_via_pattern;
  const k = state.selected_via_keyword;
  const l = state.selected_via_llm;
  const total = p.length + k.length + l.length;
  if (total === 0) {
    return ["Selected rules: none"];
  }
  const out: string[] = [`Selected rules (${total}):`];
  if (p.length > 0) out.push(`  via pattern: ${p.join(", ")}`);
  if (k.length > 0) out.push(`  via keyword: ${k.join(", ")}`);
  if (l.length > 0) out.push(`  via llm:     ${l.join(", ")}`);
  return out;
}

function formatRecentLog(cwd: string): string[] {
  const p = evalLogPath(cwd);
  if (!fs.existsSync(p)) {
    return ["Recent eval log: empty"];
  }
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch {
    return ["Recent eval log: empty"];
  }
  const allLines = raw.split("\n").filter((line) => line.trim() !== "");
  if (allLines.length === 0) {
    return ["Recent eval log: empty"];
  }
  const last5 = allLines.slice(-5);
  const out: string[] = ["Recent eval log (last 5):"];
  for (const line of last5) {
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    const entry = toEvalLogEntry(parsed);
    if (!entry) continue;
    const time = entry.ts.length >= 19 ? entry.ts.slice(11, 19) : entry.ts;
    const total =
      entry.selected_via_pattern.length +
      entry.selected_via_keyword.length +
      entry.selected_via_llm.length;
    out.push(
      `  ${time} ${entry.trigger_reason}  ${total} rules  ${entry.duration_ms}ms`,
    );
  }
  return out;
}

function formatInjectedLedger(sessionId: string, cwd: string): string {
  const p = injectedLedgerPath(sessionId, cwd);
  if (!fs.existsSync(p)) {
    return "Injected ledger: empty";
  }
  const ids = readInjectedLedger(sessionId, cwd);
  return `Injected ledger (this session): ${ids.length} rule(s) already injected`;
}

function relativeAgo(ts: string): string | null {
  if (ts === "") return null;
  const ms = Date.parse(ts);
  if (!Number.isFinite(ms)) return null;
  const deltaMs = Math.max(0, Date.now() - ms);
  const deltaS = Math.round(deltaMs / 1000);
  if (deltaS < 60) return `${deltaS}s`;
  const deltaM = Math.round(deltaS / 60);
  if (deltaM < 60) return `${deltaM}m`;
  const deltaH = Math.round(deltaM / 60);
  if (deltaH < 24) return `${deltaH}h`;
  const deltaD = Math.round(deltaH / 24);
  return `${deltaD}d`;
}

function toLockInfo(v: unknown): LockInfo | null {
  if (typeof v !== "object" || v === null) return null;
  const pid = Reflect.get(v, "pid");
  const startedAt = Reflect.get(v, "started_at");
  const trigger = Reflect.get(v, "trigger");
  const sessionId = Reflect.get(v, "session_id");
  const covers = Reflect.get(v, "covers_up_to_uuid");
  if (typeof pid !== "number") return null;
  if (typeof startedAt !== "string") return null;
  if (typeof trigger !== "string") return null;
  if (typeof sessionId !== "string") return null;
  if (covers !== null && typeof covers !== "string") return null;
  return {
    pid,
    started_at: startedAt,
    trigger,
    session_id: sessionId,
    covers_up_to_uuid: covers,
  };
}

function toEvalLogEntry(v: unknown): EvalLogEntry | null {
  if (typeof v !== "object" || v === null) return null;
  const ts = Reflect.get(v, "ts");
  const triggerReason = Reflect.get(v, "trigger_reason");
  const taskType = Reflect.get(v, "task_type");
  const sp = Reflect.get(v, "selected_via_pattern");
  const sk = Reflect.get(v, "selected_via_keyword");
  const sl = Reflect.get(v, "selected_via_llm");
  const duration = Reflect.get(v, "duration_ms");
  const digest = Reflect.get(v, "digest_chars");
  const watermark = Reflect.get(v, "watermark_uuid");
  if (typeof ts !== "string") return null;
  if (typeof triggerReason !== "string") return null;
  if (typeof taskType !== "string") return null;
  if (!isStringArray(sp)) return null;
  if (!isStringArray(sk)) return null;
  if (!isStringArray(sl)) return null;
  if (typeof duration !== "number") return null;
  if (typeof digest !== "number") return null;
  if (watermark !== null && typeof watermark !== "string") return null;
  return {
    ts,
    trigger_reason: triggerReason,
    task_type: taskType,
    selected_via_pattern: sp,
    selected_via_keyword: sk,
    selected_via_llm: sl,
    duration_ms: duration,
    digest_chars: digest,
    watermark_uuid: watermark,
  };
}

function isStringArray(v: unknown): v is string[] {
  if (!Array.isArray(v)) return false;
  return v.every((x): x is string => typeof x === "string");
}
