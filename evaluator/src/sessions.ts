import * as fs from "node:fs";
import * as path from "node:path";

export interface SessionRecord {
  phase: string;
  task_file: string;
  focus: string[];
  parent: string | null;
}

export function sessionsFilePath(cwd: string): string {
  return path.join(cwd, ".flow", "SESSIONS.json");
}

export function readAllSessions(cwd: string): Record<string, SessionRecord> {
  const p = sessionsFilePath(cwd);
  if (!fs.existsSync(p)) return {};
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch {
    return {};
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return {};
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    return {};
  }
  const out: Record<string, SessionRecord> = {};
  for (const key of Object.keys(parsed)) {
    const rec = Reflect.get(parsed, key);
    const session = toSessionRecord(rec);
    if (session !== null) out[key] = session;
  }
  return out;
}

export function readSession(
  cwd: string,
  sessionId: string,
): SessionRecord | null {
  const all = readAllSessions(cwd);
  return all[sessionId] ?? null;
}

function toSessionRecord(rec: unknown): SessionRecord | null {
  if (typeof rec !== "object" || rec === null) return null;
  const phase = Reflect.get(rec, "phase");
  const taskFile = Reflect.get(rec, "task_file");
  const focusRaw = Reflect.get(rec, "focus");
  const parent = Reflect.get(rec, "parent");
  if (typeof phase !== "string") return null;
  if (typeof taskFile !== "string") return null;
  if (!Array.isArray(focusRaw)) return null;
  if (!focusRaw.every((x): x is string => typeof x === "string")) return null;
  return {
    phase,
    task_file: taskFile,
    focus: focusRaw,
    parent: typeof parent === "string" ? parent : null,
  };
}
