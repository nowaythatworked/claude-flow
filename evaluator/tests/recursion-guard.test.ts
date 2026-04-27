import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runUserPromptSubmit } from "../src/hooks/user-prompt-submit.ts";
import { runSubagentStart } from "../src/hooks/subagent-start.ts";
import { evaluate } from "../src/haiku.ts";

// These tests verify the recursion guard that prevents the original 60s
// hang. The bug: hook calls `claude -p`, that inner claude triggers its own
// UserPromptSubmit hook, which spawns another `claude -p`, ad infinitum.
// Fix: every hook short-circuits on FLOW_NO_HOOKS=1, and every spawn of
// claude from inside the binary sets FLOW_NO_HOOKS=1 in the child env.

let tmp: string;
let originalPath: string | undefined;
let originalNoHooks: string | undefined;
let stdoutCapture: string;
let originalWrite: typeof process.stdout.write;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-recursion-"));
  originalPath = process.env.PATH;
  originalNoHooks = process.env.FLOW_NO_HOOKS;
  stdoutCapture = "";
  originalWrite = process.stdout.write.bind(process.stdout);
  process.stdout.write = ((chunk: string | Uint8Array): boolean => {
    stdoutCapture += typeof chunk === "string" ? chunk : Buffer.from(chunk).toString();
    return true;
  }) as typeof process.stdout.write;
});

afterEach(() => {
  process.stdout.write = originalWrite;
  if (originalPath !== undefined) process.env.PATH = originalPath;
  if (originalNoHooks === undefined) delete process.env.FLOW_NO_HOOKS;
  else process.env.FLOW_NO_HOOKS = originalNoHooks;
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("recursion guard — hook short-circuits", () => {
  test("user-prompt-submit returns {} immediately when FLOW_NO_HOOKS=1", async () => {
    process.env.FLOW_NO_HOOKS = "1";
    const stdin = JSON.stringify({
      session_id: "s",
      transcript_path: "/dev/null",
      prompt: "hi",
      cwd: tmp,
    });
    const exit = await runUserPromptSubmit(stdin);
    expect(exit).toBe(0);
    expect(stdoutCapture).toBe("{}");
  });

  test("subagent-start returns {} immediately when FLOW_NO_HOOKS=1", () => {
    process.env.FLOW_NO_HOOKS = "1";
    const stdin = JSON.stringify({
      session_id: "child",
      parent_session_id: "parent",
      agent_id: "a1",
      cwd: tmp,
    });
    const exit = runSubagentStart(stdin);
    expect(exit).toBe(0);
    expect(stdoutCapture).toBe("{}");
  });
});

describe("recursion guard — haiku spawn propagates FLOW_NO_HOOKS=1", () => {
  test("evaluate() sets FLOW_NO_HOOKS=1 in spawned claude's env", async () => {
    // Stub claude that writes its env to a file, returns canned JSON.
    const binDir = path.join(tmp, "bin");
    fs.mkdirSync(binDir, { recursive: true });
    const envRecord = path.join(tmp, "env-record.txt");
    const stubPath = path.join(binDir, "claude");
    fs.writeFileSync(
      stubPath,
      `#!/bin/sh
# drain stdin so the parent's pipe.write doesn't block
cat > /dev/null
env > "${envRecord}"
cat <<'JSON'
{"structured_output":{"task_type":"test","selected_rules":[],"reason":"stub"}}
JSON
`,
      { mode: 0o755 },
    );
    process.env.PATH = `${binDir}:${originalPath ?? ""}`;

    const result = await evaluate("digest");
    expect(result.task_type).toBe("test");

    const recorded = fs.readFileSync(envRecord, "utf8");
    // Recorded env from the stub must show FLOW_NO_HOOKS=1 — proving the
    // outer process injected it before spawning claude. If this assertion
    // ever fails, the recursion bug is back.
    expect(recorded).toMatch(/^FLOW_NO_HOOKS=1$/m);
  });
});
