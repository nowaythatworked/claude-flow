import { runPatternOnly } from "../eval.ts";
import { readState } from "../cache.ts";
import { deriveCacheKey, deriveSessionCacheKey } from "../paths.ts";
import { computeDeltaInjection } from "./delta-inject.ts";
import { readSession } from "../sessions.ts";
import type { CacheState } from "../types.ts";

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
  const isFlow = session !== null;

  const cacheKey = isFlow
    ? deriveCacheKey(session.task_file, session.focus).key
    : deriveSessionCacheKey(payload.session_id).key;
  const taskFile = isFlow ? session.task_file : "";
  const focus = isFlow ? session.focus : [];

  const prevState = readState(cacheKey, payload.cwd);

  runPatternOnly({
    cwd: payload.cwd,
    taskFile,
    focus,
    sessionId: payload.session_id,
    triggerReason: isFlow
      ? "user-prompt-submit-sync"
      : "user-prompt-submit-sync:vanilla",
    filePaths: [],
    text: payload.prompt,
    cacheKey,
  });

  const fresh = readState(cacheKey, payload.cwd);
  const out = computeDeltaInjection(
    fresh,
    payload.session_id,
    payload.cwd,
    "UserPromptSubmit",
  );

  if (shouldKickAsync(prevState)) {
    spawnAsyncEval(payload, taskFile, focus, cacheKey, isFlow);
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
  taskFile: string,
  focus: string[],
  cacheKey: string,
  isFlow: boolean,
): void {
  const args = [
    "eval",
    "--sync",
    "--cwd",
    payload.cwd,
    "--session-id",
    payload.session_id,
    "--task-file",
    taskFile,
    "--focus",
    JSON.stringify(focus),
    "--cache-key",
    cacheKey,
    "--reason",
    isFlow ? "user-prompt-submit-async" : "user-prompt-submit-async:vanilla",
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
