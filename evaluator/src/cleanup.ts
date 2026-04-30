import * as fs from "node:fs";
import * as path from "node:path";
import { cacheDir, evalLogPath } from "./paths.ts";
import { injectedLedgerDir } from "./injected-ledger.ts";
import { pendingSignalsPath } from "./pending-signals.ts";
import { readAllSessions, sessionsFilePath } from "./sessions.ts";
import type { LockInfo } from "./types.ts";

const STALE_LOCK_MS = 90_000;

export interface CleanupOpts {
  cwd: string;
  dryRun: boolean;
  maxEvalLog: number;
  maxPendingSignals: number;
}

export interface CleanupReport {
  subagentCachesDeleted: string[];
  injectedLedgersDeleted: string[];
  staleLocksReaped: string[];
  evalLogTruncated: { from: number; to: number };
  pendingSignalsTruncated: { from: number; to: number };
}

export function runCleanup(opts: CleanupOpts): CleanupReport {
  // Safety: if SESSIONS.json is missing, refuse to mark anything as orphan
  // (we can't tell what's live without it).
  const haveSessions = fs.existsSync(sessionsFilePath(opts.cwd));
  const sessions = haveSessions ? readAllSessions(opts.cwd) : null;

  const subagentCachesDeleted =
    sessions === null
      ? []
      : sweepSubagentCaches(
          opts.cwd,
          new Set(Object.keys(sessions)),
          opts.dryRun,
        );
  const injectedLedgersDeleted =
    sessions === null
      ? []
      : sweepInjectedLedgers(
          opts.cwd,
          new Set(Object.keys(sessions)),
          opts.dryRun,
        );
  const staleLocksReaped = sweepStaleLocks(opts.cwd, opts.dryRun);
  const evalLogTruncated = truncateJsonl(
    evalLogPath(opts.cwd),
    opts.maxEvalLog,
    opts.dryRun,
  );
  const pendingSignalsTruncated = truncateJsonl(
    pendingSignalsPath(opts.cwd),
    opts.maxPendingSignals,
    opts.dryRun,
  );

  return {
    subagentCachesDeleted,
    injectedLedgersDeleted,
    staleLocksReaped,
    evalLogTruncated,
    pendingSignalsTruncated,
  };
}

function sweepSubagentCaches(
  cwd: string,
  liveSessionIds: Set<string>,
  dryRun: boolean,
): string[] {
  const dir = cacheDir(cwd);
  if (!fs.existsSync(dir)) return [];
  const deleted: string[] = [];
  for (const name of fs.readdirSync(dir)) {
    if (!name.startsWith("sub__") || !name.endsWith(".json")) continue;
    const parentId = parseSubagentParentId(name);
    if (parentId === null) continue;
    if (liveSessionIds.has(parentId)) continue;
    deleted.push(name);
    if (!dryRun) {
      try {
        fs.unlinkSync(path.join(dir, name));
      } catch {
        // best-effort
      }
    }
  }
  return deleted;
}

function parseSubagentParentId(filename: string): string | null {
  // sub__<parent>__<agent>.json
  const stem = filename.slice("sub__".length, -".json".length);
  const sepIdx = stem.indexOf("__");
  if (sepIdx <= 0) return null;
  return stem.slice(0, sepIdx);
}

function sweepInjectedLedgers(
  cwd: string,
  liveSessionIds: Set<string>,
  dryRun: boolean,
): string[] {
  const dir = injectedLedgerDir(cwd);
  if (!fs.existsSync(dir)) return [];
  const deleted: string[] = [];
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith(".json")) continue;
    const sessionId = name.slice(0, -".json".length);
    if (sessionId === "") continue;
    if (liveSessionIds.has(sessionId)) continue;
    deleted.push(name);
    if (!dryRun) {
      try {
        fs.unlinkSync(path.join(dir, name));
      } catch {
        // best-effort
      }
    }
  }
  return deleted;
}

function sweepStaleLocks(cwd: string, dryRun: boolean): string[] {
  const dir = cacheDir(cwd);
  if (!fs.existsSync(dir)) return [];
  const reaped: string[] = [];
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith(".json.lock")) continue;
    const lockDir = path.join(dir, name);
    let stat: fs.Stats;
    try {
      stat = fs.statSync(lockDir);
    } catch {
      continue;
    }
    if (!stat.isDirectory()) continue;
    if (!isLockStale(lockDir)) continue;
    reaped.push(name);
    if (!dryRun) {
      try {
        fs.rmSync(lockDir, { recursive: true, force: true });
      } catch {
        // best-effort
      }
    }
  }
  return reaped;
}

function isLockStale(lockDir: string): boolean {
  const infoPath = path.join(lockDir, "info.json");
  if (!fs.existsSync(infoPath)) {
    // No info.json: judge by dir mtime alone
    let stat: fs.Stats;
    try {
      stat = fs.statSync(lockDir);
    } catch {
      return false;
    }
    return Date.now() - stat.mtimeMs > STALE_LOCK_MS;
  }
  let raw: string;
  try {
    raw = fs.readFileSync(infoPath, "utf8");
  } catch {
    return false;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return false;
  }
  const info = toLockInfo(parsed);
  if (info === null) return false;
  const startedMs = Date.parse(info.started_at);
  if (!Number.isFinite(startedMs)) return false;
  const ageMs = Date.now() - startedMs;
  if (ageMs <= STALE_LOCK_MS) return false;
  return !isPidAlive(info.pid);
}

function isPidAlive(pid: number): boolean {
  if (!Number.isFinite(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ESRCH") return false;
    if (code === "EPERM") return true;
    return false;
  }
}

function truncateJsonl(
  filePath: string,
  maxLines: number,
  dryRun: boolean,
): { from: number; to: number } {
  if (!fs.existsSync(filePath)) return { from: 0, to: 0 };
  let raw: string;
  try {
    raw = fs.readFileSync(filePath, "utf8");
  } catch {
    return { from: 0, to: 0 };
  }
  const lines = raw.split("\n").filter((l) => l !== "");
  const from = lines.length;
  if (from <= maxLines) {
    return { from, to: from };
  }
  const kept = lines.slice(from - maxLines);
  if (!dryRun) {
    const tmp = `${filePath}.tmp.${process.pid}`;
    fs.writeFileSync(tmp, `${kept.join("\n")}\n`, "utf8");
    fs.renameSync(tmp, filePath);
  }
  return { from, to: kept.length };
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
