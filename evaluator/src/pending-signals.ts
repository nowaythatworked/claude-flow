import * as fs from "node:fs";
import * as path from "node:path";
import { cacheDir } from "./paths.ts";

export type PendingSignalTool = "Read" | "Edit" | "Write" | "Glob" | "Grep";

export interface PendingSignal {
  ts: string;
  path: string;
  tool: PendingSignalTool;
  session_id: string;
}

export function pendingSignalsPath(cwd: string): string {
  return path.join(cacheDir(cwd), "pending-signals.jsonl");
}

export function appendPendingSignal(cwd: string, sig: PendingSignal): void {
  fs.mkdirSync(cacheDir(cwd), { recursive: true });
  fs.appendFileSync(pendingSignalsPath(cwd), `${JSON.stringify(sig)}\n`);
}

export function drainPendingSignals(cwd: string): PendingSignal[] {
  const p = pendingSignalsPath(cwd);
  if (!fs.existsSync(p)) return [];
  let raw: string;
  try {
    raw = fs.readFileSync(p, "utf8");
  } catch {
    return [];
  }
  const out: PendingSignal[] = [];
  for (const line of raw.split("\n")) {
    if (line.trim() === "") continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    const sig = toSignal(parsed);
    if (sig) out.push(sig);
  }
  return out;
}

export function truncatePendingSignals(cwd: string): void {
  const p = pendingSignalsPath(cwd);
  fs.mkdirSync(cacheDir(cwd), { recursive: true });
  const tmp = `${p}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, "", "utf8");
  fs.renameSync(tmp, p);
}

function toSignal(v: unknown): PendingSignal | null {
  if (typeof v !== "object" || v === null) return null;
  const ts = Reflect.get(v, "ts");
  const p = Reflect.get(v, "path");
  const tool = Reflect.get(v, "tool");
  const sessionId = Reflect.get(v, "session_id");
  if (typeof ts !== "string") return null;
  if (typeof p !== "string") return null;
  if (typeof sessionId !== "string") return null;
  if (
    tool !== "Read" &&
    tool !== "Edit" &&
    tool !== "Write" &&
    tool !== "Glob" &&
    tool !== "Grep"
  ) {
    return null;
  }
  return { ts, path: p, tool, session_id: sessionId };
}
