import * as fs from "node:fs";
import * as path from "node:path";
import { cacheDir } from "./paths.ts";

const SCHEMA_VERSION = 1;

interface InjectedLedger {
  schema_version: 1;
  session_id: string;
  task_file: string;
  focus_hash: string;
  injected_rule_ids: string[];
  last_injection_ts: string;
}

export function injectedLedgerDir(cwd: string): string {
  return path.join(cacheDir(cwd), "injected");
}

export function injectedLedgerPath(sessionId: string, cwd: string): string {
  return path.join(injectedLedgerDir(cwd), `${sessionId}.json`);
}

export function readInjectedLedger(sessionId: string, cwd: string): string[] {
  const p = injectedLedgerPath(sessionId, cwd);
  if (!fs.existsSync(p)) return [];
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch {
    return [];
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!isInjectedLedger(parsed)) return [];
  if (parsed.schema_version !== SCHEMA_VERSION) return [];
  return parsed.injected_rule_ids;
}

export function appendInjected(
  sessionId: string,
  taskFile: string,
  focusHash: string,
  newIds: string[],
  cwd: string,
): void {
  const existing = readInjectedLedger(sessionId, cwd);
  const seen = new Set(existing);
  const additions: string[] = [];
  for (const id of newIds) {
    if (seen.has(id)) continue;
    seen.add(id);
    additions.push(id);
  }
  if (additions.length === 0) return;
  const merged = [...existing, ...additions];
  const ledger: InjectedLedger = {
    schema_version: SCHEMA_VERSION,
    session_id: sessionId,
    task_file: taskFile,
    focus_hash: focusHash,
    injected_rule_ids: merged,
    last_injection_ts: new Date().toISOString(),
  };
  const dir = injectedLedgerDir(cwd);
  fs.mkdirSync(dir, { recursive: true });
  const p = injectedLedgerPath(sessionId, cwd);
  const tmp = `${p}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(ledger, null, 2), "utf8");
  fs.renameSync(tmp, p);
}

export function clearInjectedLedger(sessionId: string, cwd: string): void {
  const p = injectedLedgerPath(sessionId, cwd);
  if (!fs.existsSync(p)) return;
  try {
    fs.unlinkSync(p);
  } catch {
    // best effort; race with another writer is acceptable
  }
}

function isInjectedLedger(v: unknown): v is InjectedLedger {
  if (!isObject(v)) return false;
  if (getNumber(v, "schema_version") === undefined) return false;
  if (getString(v, "session_id") === undefined) return false;
  if (getString(v, "task_file") === undefined) return false;
  if (getString(v, "focus_hash") === undefined) return false;
  if (getString(v, "last_injection_ts") === undefined) return false;
  if (getStringArray(v, "injected_rule_ids") === undefined) return false;
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
