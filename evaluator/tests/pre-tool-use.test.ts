import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  extractToolPaths,
  runPreToolUse,
} from "../src/hooks/pre-tool-use.ts";
import { drainPendingSignals } from "../src/pending-signals.ts";
import { readState, writeState, initState } from "../src/cache.ts";
import { deriveCacheKey } from "../src/paths.ts";
import type { CacheState } from "../src/types.ts";

let tmp: string;
let origStdout: typeof process.stdout.write;
let captured: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-pretool-"));

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
    path.join(dynamicDir, "ts-rule.md"),
    [
      "---",
      'patterns: ["**/*.ts"]',
      "---",
      "Ts rule body.",
    ].join("\n"),
  );

  const sessionsPath = path.join(tmp, ".flow", "SESSIONS.json");
  fs.writeFileSync(
    sessionsPath,
    JSON.stringify({
      "sess-x": {
        phase: "implementing",
        task_file: "task.md",
        focus: ["x"],
        parent: null,
      },
    }),
  );

  captured = "";
  origStdout = process.stdout.write.bind(process.stdout);
  process.stdout.write = ((chunk: unknown): boolean => {
    if (typeof chunk === "string") captured += chunk;
    return true;
  }) as typeof process.stdout.write;
});

afterEach(() => {
  process.stdout.write = origStdout;
  fs.rmSync(tmp, { recursive: true, force: true });
  delete process.env.FLOW_NO_HOOKS;
});

describe("extractToolPaths", () => {
  test("Read uses file_path", () => {
    expect(extractToolPaths("Read", { file_path: "/proj/a.ts" })).toEqual([
      "/proj/a.ts",
    ]);
  });

  test("Edit uses file_path", () => {
    expect(
      extractToolPaths("Edit", {
        file_path: "/proj/a.ts",
        old_string: "x",
        new_string: "y",
      }),
    ).toEqual(["/proj/a.ts"]);
  });

  test("Write uses file_path", () => {
    expect(
      extractToolPaths("Write", { file_path: "/proj/b.ts", content: "ok" }),
    ).toEqual(["/proj/b.ts"]);
  });

  test("Glob uses pattern", () => {
    expect(extractToolPaths("Glob", { pattern: "**/*.tsx" })).toEqual([
      "**/*.tsx",
    ]);
  });

  test("Grep uses pattern and path", () => {
    const out = extractToolPaths("Grep", {
      pattern: "useState",
      path: "/proj/src",
    });
    expect(out).toContain("/proj/src");
    expect(out).toContain("useState");
  });

  test("ignores non-string fields", () => {
    expect(extractToolPaths("Read", { file_path: 123 })).toEqual([]);
  });

  test("returns [] for unknown tool", () => {
    expect(extractToolPaths("Bash", { command: "ls" })).toEqual([]);
  });

  test("returns [] when tool_input is null", () => {
    expect(extractToolPaths("Read", null)).toEqual([]);
  });
});

describe("runPreToolUse signals + additive selection", () => {
  test("appends a pending signal for the tool path", () => {
    const stdin = JSON.stringify({
      session_id: "sess-x",
      cwd: tmp,
      tool_name: "Read",
      tool_input: { file_path: "/proj/foo.tsx" },
    });
    runPreToolUse(stdin);
    const sigs = drainPendingSignals(tmp);
    expect(sigs.length).toBe(1);
    expect(sigs[0]?.path).toBe("/proj/foo.tsx");
    expect(sigs[0]?.tool).toBe("Read");
    expect(sigs[0]?.session_id).toBe("sess-x");
  });

  test("pattern hit on the tool path adds rule (additive)", () => {
    const { key } = deriveCacheKey("task.md", ["x"]);
    const seeded: CacheState = initState("task.md", ["x"], tmp);
    seeded.selected_via_pattern = ["pre-existing.md"];
    writeState(key, seeded, tmp);

    const stdin = JSON.stringify({
      session_id: "sess-x",
      cwd: tmp,
      tool_name: "Edit",
      tool_input: {
        file_path: "/proj/Button.tsx",
        old_string: "x",
        new_string: "y",
      },
    });
    runPreToolUse(stdin);

    const fresh = readState(key, tmp);
    expect(fresh).not.toBeNull();
    expect(fresh?.selected_via_pattern).toContain("pre-existing.md");
    expect(fresh?.selected_via_pattern).toContain("tsx-rule.md");
  });

  test("FLOW_NO_HOOKS=1 short-circuits without writing signals or state", () => {
    process.env.FLOW_NO_HOOKS = "1";
    const stdin = JSON.stringify({
      session_id: "sess-x",
      cwd: tmp,
      tool_name: "Read",
      tool_input: { file_path: "/proj/x.tsx" },
    });
    runPreToolUse(stdin);
    expect(drainPendingSignals(tmp)).toEqual([]);
  });
});
