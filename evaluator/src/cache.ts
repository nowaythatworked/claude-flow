import * as fs from "node:fs";
import * as path from "node:path";
import type { CacheState } from "./types.ts";
import { cacheDir, deriveCacheKey, stateFilePath } from "./paths.ts";

const SCHEMA_VERSION = 1;

export function readState(cacheKey: string, cwd: string): CacheState | null {
  const p = stateFilePath(cacheKey, cwd);
  if (!fs.existsSync(p)) return null;
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch {
    return null;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!isCacheState(parsed)) return null;
  if (parsed.schema_version !== SCHEMA_VERSION) return null;
  return parsed;
}

export function writeState(
  cacheKey: string,
  state: CacheState,
  cwd: string,
): void {
  const dir = cacheDir(cwd);
  fs.mkdirSync(dir, { recursive: true });
  const p = stateFilePath(cacheKey, cwd);
  const tmp = `${p}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(state, null, 2), "utf8");
  fs.renameSync(tmp, p);
}

export function initState(
  taskFile: string,
  focus: string[],
  _cwd: string,
): CacheState {
  const { focusHash } = deriveCacheKey(taskFile, focus);
  return {
    schema_version: SCHEMA_VERSION,
    task_file: taskFile,
    focus,
    focus_hash: focusHash,
    selected_via_pattern: [],
    selected_via_keyword: [],
    selected_via_llm: [],
    task_type: "",
    trigger_reason: "",
    last_eval_ts: "",
    last_eval_duration_ms: 0,
    per_session: {},
  };
}

function isCacheState(v: unknown): v is CacheState {
  if (!isObject(v)) return false;
  if (getNumber(v, "schema_version") === undefined) return false;
  if (getString(v, "task_file") === undefined) return false;
  if (getStringArray(v, "focus") === undefined) return false;
  if (getString(v, "focus_hash") === undefined) return false;
  if (getStringArray(v, "selected_via_pattern") === undefined) return false;
  if (getStringArray(v, "selected_via_keyword") === undefined) return false;
  if (getStringArray(v, "selected_via_llm") === undefined) return false;
  if (getString(v, "task_type") === undefined) return false;
  if (getString(v, "trigger_reason") === undefined) return false;
  if (getString(v, "last_eval_ts") === undefined) return false;
  if (getNumber(v, "last_eval_duration_ms") === undefined) return false;
  const perSession = Reflect.get(v, "per_session");
  if (!isObject(perSession)) return false;
  for (const key of Object.keys(perSession)) {
    const w = Reflect.get(perSession, key);
    if (!isObject(w)) return false;
    if (getString(w, "watermark_uuid") === undefined) return false;
    if (getString(w, "last_seen_ts") === undefined) return false;
  }
  return true;
}

function isObject(v: unknown): v is object {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function getString(v: object, key: string): string | undefined {
  const val = Reflect.get(v, key);
  return typeof val === "string" ? val : undefined;
}

function getNumber(v: object, key: string): number | undefined {
  const val = Reflect.get(v, key);
  return typeof val === "number" ? val : undefined;
}

function getStringArray(v: object, key: string): string[] | undefined {
  const val = Reflect.get(v, key);
  if (!Array.isArray(val)) return undefined;
  if (!val.every((x): x is string => typeof x === "string")) return undefined;
  return val;
}

export function ensureCacheDir(cwd: string): void {
  fs.mkdirSync(cacheDir(cwd), { recursive: true });
}

export function subagentCachePath(
  parentSessionId: string,
  agentId: string,
  cwd: string,
): string {
  return path.join(cacheDir(cwd), `sub__${parentSessionId}__${agentId}.json`);
}
