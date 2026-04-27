import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runFullEval } from "../src/eval.ts";
import { readState } from "../src/cache.ts";
import { deriveCacheKey } from "../src/paths.ts";
import {
  appendPendingSignal,
  pendingSignalsPath,
  drainPendingSignals,
} from "../src/pending-signals.ts";

let tmp: string;
let mockBinDir: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-evalsig-"));
  mockBinDir = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-mock-"));

  const dynamicDir = path.join(tmp, ".flow", "rules", "dynamic");
  fs.mkdirSync(dynamicDir, { recursive: true });
  fs.writeFileSync(
    path.join(dynamicDir, "tsx-rule.md"),
    [
      "---",
      'patterns: ["**/*.tsx"]',
      "---",
      "Tsx rule body.",
    ].join("\n"),
  );
  fs.writeFileSync(
    path.join(dynamicDir, "py-rule.md"),
    [
      "---",
      'patterns: ["**/*.py"]',
      "---",
      "Py rule body.",
    ].join("\n"),
  );
  // rule with relevance so haiku is actually invoked
  fs.writeFileSync(
    path.join(dynamicDir, "llm-rule.md"),
    [
      "---",
      'relevance: "When the user touches anything."',
      "---",
      "Llm rule body.",
    ].join("\n"),
  );

  // mock claude that returns no LLM rules
  const mockClaude = path.join(mockBinDir, "claude");
  fs.writeFileSync(
    mockClaude,
    `#!/bin/sh
cat > /dev/null
echo '{"result":null,"structured_output":{"task_type":"none","selected_rules":[],"reason":"none"}}'
`,
  );
  fs.chmodSync(mockClaude, 0o755);
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.rmSync(mockBinDir, { recursive: true, force: true });
});

describe("runFullEval drains pending-signals", () => {
  test("pending-signal paths are included in pattern matching", async () => {
    appendPendingSignal(tmp, {
      ts: new Date().toISOString(),
      path: "/proj/Foo.tsx",
      tool: "Edit",
      session_id: "sess1",
    });
    const origPath = process.env.PATH ?? "";
    process.env.PATH = `${mockBinDir}:${origPath}`;
    try {
      const result = await runFullEval({
        cwd: tmp,
        taskFile: "task.md",
        focus: ["x"],
        sessionId: "sess1",
        transcriptPath: null,
        triggerReason: "test-drain",
      });
      expect(result.kind).toBe("ok");
      if (result.kind !== "ok") return;
      expect(result.state.selected_via_pattern).toContain("tsx-rule.md");
      // py-rule.md should not match — no .py path
      expect(result.state.selected_via_pattern).not.toContain("py-rule.md");
    } finally {
      process.env.PATH = origPath;
    }
  });

  test("pending-signals are truncated after a successful eval", async () => {
    appendPendingSignal(tmp, {
      ts: new Date().toISOString(),
      path: "/proj/X.tsx",
      tool: "Read",
      session_id: "sess1",
    });
    expect(fs.existsSync(pendingSignalsPath(tmp))).toBe(true);
    const origPath = process.env.PATH ?? "";
    process.env.PATH = `${mockBinDir}:${origPath}`;
    try {
      const result = await runFullEval({
        cwd: tmp,
        taskFile: "task.md",
        focus: [],
        sessionId: "sess1",
        transcriptPath: null,
        triggerReason: "test-truncate",
      });
      expect(result.kind).toBe("ok");
      const remaining = drainPendingSignals(tmp);
      expect(remaining).toEqual([]);
    } finally {
      process.env.PATH = origPath;
    }
  });

  test("pending-signals NOT truncated if haiku failed", async () => {
    appendPendingSignal(tmp, {
      ts: new Date().toISOString(),
      path: "/proj/X.tsx",
      tool: "Read",
      session_id: "sess1",
    });
    const failingMockDir = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-mockfail-"));
    fs.writeFileSync(
      path.join(failingMockDir, "claude"),
      `#!/bin/sh
cat > /dev/null
exit 1
`,
    );
    fs.chmodSync(path.join(failingMockDir, "claude"), 0o755);
    const origPath = process.env.PATH ?? "";
    process.env.PATH = `${failingMockDir}:${origPath}`;
    try {
      await runFullEval({
        cwd: tmp,
        taskFile: "task.md",
        focus: [],
        sessionId: "sess1",
        transcriptPath: null,
        triggerReason: "test-fail-no-truncate",
      });
      // signals should remain so the next eval picks them up
      const remaining = drainPendingSignals(tmp);
      expect(remaining.length).toBe(1);
    } finally {
      process.env.PATH = origPath;
      fs.rmSync(failingMockDir, { recursive: true, force: true });
    }
  });

  test("eval works with no pending-signals file", async () => {
    const origPath = process.env.PATH ?? "";
    process.env.PATH = `${mockBinDir}:${origPath}`;
    try {
      const result = await runFullEval({
        cwd: tmp,
        taskFile: "task.md",
        focus: [],
        sessionId: "sess1",
        transcriptPath: null,
        triggerReason: "test-empty",
      });
      expect(result.kind).toBe("ok");
    } finally {
      process.env.PATH = origPath;
    }
  });
});
