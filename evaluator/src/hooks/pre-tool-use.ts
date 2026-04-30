import { runPatternOnly, unionAllSelected } from "../eval.ts";
import { readState } from "../cache.ts";
import { deriveCacheKey } from "../paths.ts";
import { formatRulesInjection } from "../inject.ts";
import { readSession } from "./user-prompt-submit.ts";
import {
  appendPendingSignal,
  type PendingSignalTool,
} from "../pending-signals.ts";
import type { CacheState } from "../types.ts";

interface PreToolPayload {
  session_id: string;
  transcript_path: string;
  cwd: string;
  tool_name: string;
  tool_input: unknown;
}

const ASYNC_DEBOUNCE_MS = 30_000;

const SIGNAL_TOOLS: ReadonlySet<PendingSignalTool> = new Set([
  "Read",
  "Edit",
  "Write",
  "Glob",
  "Grep",
]);

export function runPreToolUse(stdin: string): number {
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

  const filePaths = extractToolPaths(payload.tool_name, payload.tool_input);
  recordSignals(payload, filePaths);

  const { key } = deriveCacheKey(session.task_file, session.focus);
  const prevState = readState(key, payload.cwd);

  runPatternOnly({
    cwd: payload.cwd,
    taskFile: session.task_file,
    focus: session.focus,
    sessionId: payload.session_id,
    triggerReason: `pre-tool-use:${payload.tool_name}`,
    filePaths,
    text: "",
  });

  const fresh = readState(key, payload.cwd);
  const ids = fresh ? unionAllSelected(fresh) : [];
  const injection = formatRulesInjection(ids, payload.cwd, {
    isInitial: true,
  });

  if (shouldKickAsync(prevState)) {
    spawnAsyncEval(payload, session.task_file, session.focus);
  }

  const out = injection
    ? {
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          additionalContext: injection,
        },
      }
    : {};
  process.stdout.write(JSON.stringify(out));
  return 0;
}

export function extractToolPaths(
  toolName: string,
  toolInput: unknown,
): string[] {
  if (typeof toolInput !== "object" || toolInput === null) return [];
  const out: string[] = [];
  // file_path covers Read, Edit, Write
  if (
    toolName === "Read" ||
    toolName === "Edit" ||
    toolName === "Write"
  ) {
    const fp = Reflect.get(toolInput, "file_path");
    if (typeof fp === "string") out.push(fp);
  }
  // Glob: pattern. Grep: pattern + path.
  if (toolName === "Glob") {
    const pat = Reflect.get(toolInput, "pattern");
    if (typeof pat === "string") out.push(pat);
    const p = Reflect.get(toolInput, "path");
    if (typeof p === "string") out.push(p);
  }
  if (toolName === "Grep") {
    const p = Reflect.get(toolInput, "path");
    if (typeof p === "string") out.push(p);
    const pat = Reflect.get(toolInput, "pattern");
    if (typeof pat === "string") out.push(pat);
  }
  return out;
}

function recordSignals(payload: PreToolPayload, paths: string[]): void {
  if (paths.length === 0) return;
  if (!isSignalTool(payload.tool_name)) return;
  const now = new Date().toISOString();
  for (const p of paths) {
    appendPendingSignal(payload.cwd, {
      ts: now,
      path: p,
      tool: payload.tool_name,
      session_id: payload.session_id,
    });
  }
}

function isSignalTool(name: string): name is PendingSignalTool {
  return SIGNAL_TOOLS.has(name as PendingSignalTool);
}

function shouldKickAsync(prev: CacheState | null): boolean {
  if (!prev || prev.last_eval_ts === "") return true;
  const last = Date.parse(prev.last_eval_ts);
  if (!Number.isFinite(last)) return true;
  return Date.now() - last >= ASYNC_DEBOUNCE_MS;
}

function spawnAsyncEval(
  payload: PreToolPayload,
  taskFile: string,
  focus: string[],
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
    "--reason",
    `pre-tool-use-async:${payload.tool_name}`,
  ];
  if (payload.transcript_path !== "") {
    args.push("--transcript", payload.transcript_path);
  }
  Bun.spawn({
    cmd: [process.execPath, ...args],
    env: { ...process.env, FLOW_NO_HOOKS: "1" },
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
  });
}

function parsePayload(stdin: string): PreToolPayload | null {
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
  const cwd = Reflect.get(parsed, "cwd");
  const toolName = Reflect.get(parsed, "tool_name");
  const toolInput = Reflect.get(parsed, "tool_input");
  const transcriptPath = Reflect.get(parsed, "transcript_path");
  if (typeof sessionId !== "string") return null;
  if (typeof cwd !== "string") return null;
  if (typeof toolName !== "string") return null;
  return {
    session_id: sessionId,
    transcript_path:
      typeof transcriptPath === "string" ? transcriptPath : "",
    cwd,
    tool_name: toolName,
    tool_input: toolInput,
  };
}
