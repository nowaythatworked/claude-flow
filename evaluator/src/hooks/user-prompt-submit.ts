import * as fs from "node:fs";
import * as path from "node:path";
import { runPatternOnly } from "../eval.ts";
import { readState } from "../cache.ts";
import { deriveCacheKey } from "../paths.ts";
import { computeDeltaInjection } from "./delta-inject.ts";
import type { CacheState } from "../types.ts";

interface SessionRecord {
  phase: string;
  task_file: string;
  focus: string[];
  parent: string | null;
}

interface HookPayload {
  session_id: string;
  transcript_path: string;
  prompt: string;
  cwd: string;
}

const ASYNC_DEBOUNCE_MS = 30_000;

export async function runUserPromptSubmit(stdin: string): Promise<number> {
  if (process.env.FLOW_NO_HOOKS === "1") {
    process.stdout.write("{}");
    return 0;
  }
  const payload = parsePayload(stdin);
  if (!payload) {
    process.stdout.write("{}");
    return 0;
  }
  const session = readSession(payload.cwd, payload.session_id);
  if (!session) {
    process.stdout.write("{}");
    return 0;
  }

  const { key } = deriveCacheKey(session.task_file, session.focus);
  const prevState = readState(key, payload.cwd);

  runPatternOnly({
    cwd: payload.cwd,
    taskFile: session.task_file,
    focus: session.focus,
    sessionId: payload.session_id,
    triggerReason: "user-prompt-submit-sync",
    filePaths: [],
    text: payload.prompt,
  });

  const fresh = readState(key, payload.cwd);
  const out = computeDeltaInjection(
    fresh,
    payload.session_id,
    payload.cwd,
    "UserPromptSubmit",
  );

  if (shouldKickAsync(prevState)) {
    spawnAsyncEval(payload, session);
  }

  process.stdout.write(JSON.stringify(out));
  return 0;
}

function shouldKickAsync(prev: CacheState | null): boolean {
  if (!prev || prev.last_eval_ts === "") return true;
  const last = Date.parse(prev.last_eval_ts);
  if (!Number.isFinite(last)) return true;
  return Date.now() - last >= ASYNC_DEBOUNCE_MS;
}

function spawnAsyncEval(
  payload: HookPayload,
  session: SessionRecord,
): void {
  const args = [
    "eval",
    "--sync",
    "--cwd",
    payload.cwd,
    "--session-id",
    payload.session_id,
    "--task-file",
    session.task_file,
    "--focus",
    JSON.stringify(session.focus),
    "--reason",
    "user-prompt-submit-async",
    "--transcript",
    payload.transcript_path,
  ];
  Bun.spawn({
    cmd: [process.execPath, ...args],
    env: { ...process.env, FLOW_NO_HOOKS: "1" },
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
  });
}

function parsePayload(stdin: string): HookPayload | null {
  const t = stdin.trim();
  if (t === "") return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(t);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) return null;
  const sessionId = Reflect.get(parsed, "session_id");
  const transcript = Reflect.get(parsed, "transcript_path");
  const prompt = Reflect.get(parsed, "prompt");
  const cwd = Reflect.get(parsed, "cwd");
  if (typeof sessionId !== "string") return null;
  if (typeof cwd !== "string") return null;
  return {
    session_id: sessionId,
    transcript_path: typeof transcript === "string" ? transcript : "",
    prompt: typeof prompt === "string" ? prompt : "",
    cwd,
  };
}

export function readSession(
  cwd: string,
  sessionId: string,
): SessionRecord | null {
  const p = path.join(cwd, ".flow", "SESSIONS.json");
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
  if (typeof parsed !== "object" || parsed === null) return null;
  const rec = Reflect.get(parsed, sessionId);
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
