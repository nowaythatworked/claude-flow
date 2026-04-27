import * as fs from "node:fs";
import * as path from "node:path";
import type { LockInfo, LockInspection } from "./types.ts";
import { cacheDir, lockDirPath } from "./paths.ts";

const STALE_MS = 90_000;

export function acquireLock(
  cacheKey: string,
  cwd: string,
  info: LockInfo,
): { release: () => void } | null {
  fs.mkdirSync(cacheDir(cwd), { recursive: true });
  const lockDir = lockDirPath(cacheKey, cwd);
  if (!tryMkdir(lockDir)) {
    if (reapIfStale(lockDir)) {
      if (!tryMkdir(lockDir)) return null;
    } else {
      return null;
    }
  }
  const infoPath = path.join(lockDir, "info.json");
  fs.writeFileSync(infoPath, JSON.stringify(info, null, 2), "utf8");
  let released = false;
  const release = (): void => {
    if (released) return;
    released = true;
    try {
      fs.rmSync(lockDir, { recursive: true, force: true });
    } catch {
      // best-effort
    }
  };
  return { release };
}

export function inspectLock(
  cacheKey: string,
  cwd: string,
): LockInspection | null {
  const lockDir = lockDirPath(cacheKey, cwd);
  if (!fs.existsSync(lockDir)) return null;
  const infoPath = path.join(lockDir, "info.json");
  if (!fs.existsSync(infoPath)) {
    const stat = safeStat(lockDir);
    if (!stat) return null;
    const ageMs = Date.now() - stat.mtimeMs;
    return {
      pid: 0,
      startedAt: new Date(stat.mtimeMs).toISOString(),
      coversUpToUuid: null,
      fresh: ageMs <= STALE_MS,
    };
  }
  let info: LockInfo;
  try {
    const raw = fs.readFileSync(infoPath, "utf8");
    const parsed: unknown = JSON.parse(raw);
    if (!isLockInfo(parsed)) return null;
    info = parsed;
  } catch {
    return null;
  }
  const startedMs = Date.parse(info.started_at);
  const ageMs = Number.isFinite(startedMs) ? Date.now() - startedMs : 0;
  const ageFresh = ageMs <= STALE_MS;
  const pidAlive = isPidAlive(info.pid);
  return {
    pid: info.pid,
    startedAt: info.started_at,
    coversUpToUuid: info.covers_up_to_uuid,
    fresh: ageFresh && pidAlive,
  };
}

export async function waitForRelease(
  cacheKey: string,
  cwd: string,
  maxWaitMs: number,
): Promise<boolean> {
  const lockDir = lockDirPath(cacheKey, cwd);
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    if (!fs.existsSync(lockDir)) return true;
    const insp = inspectLock(cacheKey, cwd);
    if (insp && !insp.fresh) {
      reapIfStale(lockDir);
      if (!fs.existsSync(lockDir)) return true;
    }
    await sleep(100);
  }
  return !fs.existsSync(lockDir);
}

function tryMkdir(p: string): boolean {
  try {
    fs.mkdirSync(p);
    return true;
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "EEXIST") return false;
    throw err;
  }
}

function reapIfStale(lockDir: string): boolean {
  const insp = inspectLockDir(lockDir);
  if (!insp) {
    try {
      fs.rmSync(lockDir, { recursive: true, force: true });
      return true;
    } catch {
      return false;
    }
  }
  if (!insp.fresh) {
    try {
      fs.rmSync(lockDir, { recursive: true, force: true });
      return true;
    } catch {
      return false;
    }
  }
  return false;
}

function inspectLockDir(lockDir: string): LockInspection | null {
  if (!fs.existsSync(lockDir)) return null;
  const infoPath = path.join(lockDir, "info.json");
  if (!fs.existsSync(infoPath)) {
    const stat = safeStat(lockDir);
    if (!stat) return null;
    const ageMs = Date.now() - stat.mtimeMs;
    return {
      pid: 0,
      startedAt: new Date(stat.mtimeMs).toISOString(),
      coversUpToUuid: null,
      fresh: ageMs <= STALE_MS,
    };
  }
  let info: LockInfo;
  try {
    const raw = fs.readFileSync(infoPath, "utf8");
    const parsed: unknown = JSON.parse(raw);
    if (!isLockInfo(parsed)) return null;
    info = parsed;
  } catch {
    return null;
  }
  const startedMs = Date.parse(info.started_at);
  const ageMs = Number.isFinite(startedMs) ? Date.now() - startedMs : 0;
  const ageFresh = ageMs <= STALE_MS;
  const pidAlive = isPidAlive(info.pid);
  return {
    pid: info.pid,
    startedAt: info.started_at,
    coversUpToUuid: info.covers_up_to_uuid,
    fresh: ageFresh && pidAlive,
  };
}

function safeStat(p: string): fs.Stats | null {
  try {
    return fs.statSync(p);
  } catch {
    return null;
  }
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

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isLockInfo(v: unknown): v is LockInfo {
  if (typeof v !== "object" || v === null) return false;
  const pid = Reflect.get(v, "pid");
  const startedAt = Reflect.get(v, "started_at");
  const trigger = Reflect.get(v, "trigger");
  const sessionId = Reflect.get(v, "session_id");
  const covers = Reflect.get(v, "covers_up_to_uuid");
  if (typeof pid !== "number") return false;
  if (typeof startedAt !== "string") return false;
  if (typeof trigger !== "string") return false;
  if (typeof sessionId !== "string") return false;
  if (covers !== null && typeof covers !== "string") return false;
  return true;
}
