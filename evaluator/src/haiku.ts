import type { HaikuOutput } from "./types.ts";

const SCHEMA = {
  type: "object",
  properties: {
    task_type: { type: "string" },
    selected_rules: { type: "array", items: { type: "string" } },
    reason: { type: "string" },
  },
  required: ["task_type", "selected_rules", "reason"],
} as const;

export function buildClaudeArgs(): string[] {
  return [
    "claude",
    "-p",
    "--model",
    "haiku",
    "--output-format",
    "json",
    "--json-schema",
    JSON.stringify(SCHEMA),
    "--max-turns",
    "3",
    "--no-session-persistence",
  ];
}

export async function evaluate(digest: string): Promise<HaikuOutput> {
  const env = { ...process.env, FLOW_NO_HOOKS: "1" };
  const proc = Bun.spawn({
    cmd: buildClaudeArgs(),
    env,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  proc.stdin.write(digest);
  await proc.stdin.end();
  const stdout = await new Response(proc.stdout).text();
  await proc.exited;
  if (proc.exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(
      `claude haiku exited ${proc.exitCode}: ${stderr.slice(0, 500)}`,
    );
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch (err) {
    throw new Error(
      `claude haiku output is not JSON: ${(err as Error).message}; got: ${stdout.slice(0, 200)}`,
    );
  }
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error(`claude haiku output is not an object`);
  }
  const structured = Reflect.get(parsed, "structured_output");
  if (structured === undefined || structured === null) {
    throw new Error(
      `claude haiku output missing structured_output field: ${JSON.stringify(parsed).slice(0, 200)}`,
    );
  }
  if (!isHaikuOutput(structured)) {
    throw new Error(
      `claude haiku structured_output shape mismatch: ${JSON.stringify(structured).slice(0, 200)}`,
    );
  }
  return structured;
}

function isHaikuOutput(v: unknown): v is HaikuOutput {
  if (typeof v !== "object" || v === null) return false;
  const tt = Reflect.get(v, "task_type");
  const sr = Reflect.get(v, "selected_rules");
  const rs = Reflect.get(v, "reason");
  if (typeof tt !== "string") return false;
  if (typeof rs !== "string") return false;
  if (!Array.isArray(sr)) return false;
  if (!sr.every((x): x is string => typeof x === "string")) return false;
  return true;
}
