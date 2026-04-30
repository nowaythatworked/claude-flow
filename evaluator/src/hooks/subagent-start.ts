import * as fs from "node:fs";
import { readState } from "../cache.ts";
import { deriveCacheKey } from "../paths.ts";
import { subagentCachePath, ensureCacheDir } from "../cache.ts";
import { computeDeltaInjection } from "./delta-inject.ts";
import { readSession } from "./user-prompt-submit.ts";
import type { CacheState } from "../types.ts";

interface SubagentPayload {
  session_id: string;
  parent_session_id: string;
  agent_id: string;
  cwd: string;
}

export function runSubagentStart(stdin: string): number {
  if (process.env.FLOW_NO_HOOKS === "1") {
    process.stdout.write("{}");
    return 0;
  }
  const payload = parsePayload(stdin);
  if (!payload) {
    process.stdout.write("{}");
    return 0;
  }
  const parentSession = readSession(payload.cwd, payload.parent_session_id);
  if (!parentSession) {
    process.stdout.write("{}");
    return 0;
  }
  const { key } = deriveCacheKey(
    parentSession.task_file,
    parentSession.focus,
  );
  const parentState = readState(key, payload.cwd);
  if (!parentState) {
    process.stdout.write("{}");
    return 0;
  }
  const subState: CacheState = {
    schema_version: 1,
    task_file: parentState.task_file,
    focus: parentState.focus,
    focus_hash: parentState.focus_hash,
    selected_via_pattern: [...parentState.selected_via_pattern],
    selected_via_keyword: [...parentState.selected_via_keyword],
    selected_via_llm: [...parentState.selected_via_llm],
    task_type: parentState.task_type,
    trigger_reason: "subagent-start",
    last_eval_ts: new Date().toISOString(),
    last_eval_duration_ms: 0,
    per_session: {},
  };
  ensureCacheDir(payload.cwd);
  const subPath = subagentCachePath(
    payload.parent_session_id,
    payload.agent_id,
    payload.cwd,
  );
  const tmp = `${subPath}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, JSON.stringify(subState, null, 2), "utf8");
  fs.renameSync(tmp, subPath);

  const out = computeDeltaInjection(
    subState,
    payload.session_id,
    payload.cwd,
    "SubagentStart",
  );
  process.stdout.write(JSON.stringify(out));
  return 0;
}

function parsePayload(stdin: string): SubagentPayload | null {
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
  const parentId = Reflect.get(parsed, "parent_session_id");
  const agentId = Reflect.get(parsed, "agent_id");
  const cwd = Reflect.get(parsed, "cwd");
  if (typeof sessionId !== "string") return null;
  if (typeof parentId !== "string") return null;
  if (typeof agentId !== "string") return null;
  if (typeof cwd !== "string") return null;
  return {
    session_id: sessionId,
    parent_session_id: parentId,
    agent_id: agentId,
    cwd,
  };
}
