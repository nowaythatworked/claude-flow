import type { HaikuOutput } from "./types.ts";

export type EvalModel = "haiku" | "sonnet";

// Trigger reasons that warrant the higher-quality model. These are the
// user-driven checkpoints from /flow:approve and /flow:implement skills,
// where the agent must cross-check the plan against every loaded rule.
// Routine async evals stay on haiku.
const SONNET_REASONS: ReadonlySet<string> = new Set([
  "pre-approve-checkpoint",
  "pre-implement-checkpoint",
]);

export function resolveEvalModel(triggerReason: string): EvalModel {
  return SONNET_REASONS.has(triggerReason) ? "sonnet" : "haiku";
}

const SCHEMA = {
  type: "object",
  properties: {
    task_type: { type: "string" },
    selected_rules: { type: "array", items: { type: "string" } },
    reason: { type: "string" },
  },
  required: ["task_type", "selected_rules", "reason"],
} as const;

export function buildClaudeArgs(model: EvalModel = "haiku"): string[] {
  return [
    "claude",
    "-p",
    "--model",
    model,
    "--output-format",
    "json",
    "--json-schema",
    JSON.stringify(SCHEMA),
    "--max-turns",
    "3",
    "--no-session-persistence",
  ];
}

export async function evaluate(
  digest: string,
  model: EvalModel = "haiku",
): Promise<HaikuOutput> {
  const env = { ...process.env, FLOW_NO_HOOKS: "1" };
  const proc = Bun.spawn({
    cmd: buildClaudeArgs(model),
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
      `claude ${model} exited ${proc.exitCode}: ${stderr.slice(0, 500)}`,
    );
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch (err) {
    throw new Error(
      `claude ${model} output is not JSON: ${(err as Error).message}; got: ${stdout.slice(0, 200)}`,
    );
  }
  if (typeof parsed !== "object" || parsed === null) {
    throw new Error(`claude ${model} output is not an object`);
  }
  const structured = Reflect.get(parsed, "structured_output");
  if (structured === undefined || structured === null) {
    throw new Error(
      `claude ${model} output missing structured_output field: ${JSON.stringify(parsed).slice(0, 200)}`,
    );
  }
  if (!isHaikuOutput(structured)) {
    throw new Error(
      `claude ${model} structured_output shape mismatch: ${JSON.stringify(structured).slice(0, 200)}`,
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
