import { runPatternOnly, unionAllSelected } from "../eval.ts";
import { readState } from "../cache.ts";
import { deriveCacheKey } from "../paths.ts";
import { formatRulesInjection } from "../inject.ts";
import { readSession } from "./user-prompt-submit.ts";

interface PreToolPayload {
  session_id: string;
  cwd: string;
  tool_name: string;
  file_path: string | null;
}

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

  const filePaths = payload.file_path ? [payload.file_path] : [];

  runPatternOnly({
    cwd: payload.cwd,
    taskFile: session.task_file,
    focus: session.focus,
    sessionId: payload.session_id,
    triggerReason: `pre-tool-use:${payload.tool_name}`,
    filePaths,
    text: "",
  });

  const { key } = deriveCacheKey(session.task_file, session.focus);
  const fresh = readState(key, payload.cwd);
  const ids = fresh ? unionAllSelected(fresh) : [];
  const injection = formatRulesInjection(ids, payload.cwd);

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
  if (typeof sessionId !== "string") return null;
  if (typeof cwd !== "string") return null;
  if (typeof toolName !== "string") return null;
  let filePath: string | null = null;
  if (typeof toolInput === "object" && toolInput !== null) {
    const fp = Reflect.get(toolInput, "file_path");
    if (typeof fp === "string") filePath = fp;
  }
  return {
    session_id: sessionId,
    cwd,
    tool_name: toolName,
    file_path: filePath,
  };
}
