import * as path from "node:path";
import { runFullEval, unionAllSelected } from "./eval.ts";
import { readState } from "./cache.ts";
import { deriveCacheKey, stateFilePath } from "./paths.ts";
import { runUserPromptSubmit } from "./hooks/user-prompt-submit.ts";
import { runPreToolUse } from "./hooks/pre-tool-use.ts";
import { runSubagentStart } from "./hooks/subagent-start.ts";
import { formatStatus } from "./status.ts";

interface ParsedArgs {
  positionals: string[];
  flags: Map<string, string>;
  bools: Set<string>;
}

function parseArgs(argv: string[]): ParsedArgs {
  const positionals: string[] = [];
  const flags = new Map<string, string>();
  const bools = new Set<string>();
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === undefined) continue;
    if (a.startsWith("--")) {
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith("--")) {
        flags.set(a.slice(2), next);
        i++;
      } else {
        bools.add(a.slice(2));
      }
    } else {
      positionals.push(a);
    }
  }
  return { positionals, flags, bools };
}

function parseFocus(json: string | undefined): string[] {
  if (!json) return [];
  try {
    const parsed: unknown = JSON.parse(json);
    if (!Array.isArray(parsed)) return [];
    if (!parsed.every((x): x is string => typeof x === "string")) return [];
    return parsed;
  } catch {
    return [];
  }
}

async function main(): Promise<number> {
  const argv = process.argv.slice(2);
  const parsed = parseArgs(argv);
  const cmd = parsed.positionals[0];

  if (cmd === undefined || cmd === "--help" || cmd === "-h") {
    printHelp();
    return cmd === undefined ? 1 : 0;
  }

  if (cmd === "eval") {
    return cmdEval(parsed);
  }
  if (cmd === "hook") {
    return cmdHook(parsed);
  }
  if (cmd === "state") {
    return cmdState(parsed);
  }

  process.stderr.write(`unknown command: ${cmd}\n`);
  printHelp();
  return 1;
}

async function cmdEval(parsed: ParsedArgs): Promise<number> {
  const cwd = parsed.flags.get("cwd") ?? process.cwd();
  const sessionId = parsed.flags.get("session-id");
  const reason = parsed.flags.get("reason") ?? "manual";
  const transcript = parsed.flags.get("transcript") ?? null;
  const taskFile = parsed.flags.get("task-file") ?? "unknown.md";
  const focus = parseFocus(parsed.flags.get("focus"));
  const sync = parsed.bools.has("sync") || !parsed.bools.has("async");

  if (!sessionId) {
    process.stderr.write("flow-rules eval: --session-id is required\n");
    return 2;
  }

  if (!sync) {
    spawnDetachedAsyncEval({
      cwd,
      sessionId,
      taskFile,
      focus,
      transcript,
      reason,
    });
    return 0;
  }

  const result = await runFullEval({
    cwd: path.resolve(cwd),
    taskFile,
    focus,
    sessionId,
    transcriptPath: transcript,
    triggerReason: reason,
  });

  if (result.kind === "lock_held") {
    process.stderr.write("[flow-rules] lock held, skipping\n");
    return 0;
  }
  if (result.kind === "skipped") {
    process.stderr.write(`[flow-rules] skipped: ${result.reason}\n`);
    return 0;
  }
  const ids = unionAllSelected(result.state);
  process.stderr.write(
    `[flow-rules] refreshed: ${ids.length} rules selected (task_type=${result.state.task_type})\n`,
  );
  return 0;
}

function spawnDetachedAsyncEval(args: {
  cwd: string;
  sessionId: string;
  taskFile: string;
  focus: string[];
  transcript: string | null;
  reason: string;
}): void {
  const cmdArgs = [
    "eval",
    "--sync",
    "--cwd",
    args.cwd,
    "--session-id",
    args.sessionId,
    "--task-file",
    args.taskFile,
    "--focus",
    JSON.stringify(args.focus),
    "--reason",
    args.reason,
  ];
  if (args.transcript) {
    cmdArgs.push("--transcript", args.transcript);
  }
  Bun.spawn({
    cmd: [process.execPath, ...cmdArgs],
    env: { ...process.env, FLOW_NO_HOOKS: "1" },
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
  });
}

async function cmdHook(parsed: ParsedArgs): Promise<number> {
  const name = parsed.positionals[1];
  if (name === undefined) {
    process.stderr.write("flow-rules hook: hook name required\n");
    return 2;
  }
  const stdinText = await readStdin();
  if (name === "user-prompt-submit") {
    return runUserPromptSubmit(stdinText);
  }
  if (name === "pre-tool-use") {
    return runPreToolUse(stdinText);
  }
  if (name === "subagent-start") {
    return runSubagentStart(stdinText);
  }
  process.stderr.write(`unknown hook: ${name}\n`);
  return 1;
}

async function cmdState(parsed: ParsedArgs): Promise<number> {
  const sub = parsed.positionals[1];
  if (sub !== "show" && sub !== "path" && sub !== "status") {
    process.stderr.write(
      "flow-rules state: subcommand must be 'show', 'path', or 'status'\n",
    );
    return 2;
  }
  const cwd = path.resolve(parsed.flags.get("cwd") ?? process.cwd());
  const taskFile = parsed.flags.get("task-file") ?? "unknown.md";
  const focus = parseFocus(parsed.flags.get("focus"));
  const { key } = deriveCacheKey(taskFile, focus);

  if (sub === "path") {
    process.stdout.write(`${stateFilePath(key, cwd)}\n`);
    return 0;
  }
  if (sub === "status") {
    const sessionIdRaw = parsed.flags.get("session-id");
    const sessionId =
      sessionIdRaw !== undefined && sessionIdRaw !== "" ? sessionIdRaw : null;
    const out = formatStatus({
      cwd,
      taskFile,
      focus,
      sessionId,
      brief: parsed.bools.has("brief"),
    });
    process.stdout.write(out);
    return 0;
  }
  const state = readState(key, cwd);
  if (!state) {
    process.stdout.write("(no state)\n");
    return 0;
  }
  process.stdout.write(`${JSON.stringify(state, null, 2)}\n`);
  return 0;
}

async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) return "";
  const chunks: Buffer[] = [];
  for await (const chunk of process.stdin) {
    if (typeof chunk === "string") chunks.push(Buffer.from(chunk));
    else chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf8");
}

function printHelp(): void {
  process.stderr.write(`flow-rules — dynamic rule evaluator

Usage:
  flow-rules eval [--sync|--async] --reason <r> --cwd <p> --session-id <id>
                  [--transcript <path>] [--task-file <name>] [--focus <json>]
  flow-rules hook <user-prompt-submit|pre-tool-use|subagent-start>
                  (reads JSON payload from stdin)
  flow-rules state show [--cwd <p>] [--task-file <name>] [--focus <json>]
  flow-rules state path [--cwd <p>] [--task-file <name>] [--focus <json>]
  flow-rules state status [--cwd <p>] [--task-file <name>] [--focus <json>]
                          [--session-id <id>] [--brief]
`);
}

const exitCode = await main();
process.exit(exitCode);
