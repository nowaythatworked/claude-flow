import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runSubagentStart } from "../src/hooks/subagent-start.ts";
import { writeState, initState, subagentCachePath } from "../src/cache.ts";
import {
  deriveCacheKey,
  deriveSessionCacheKey,
} from "../src/paths.ts";
import type { CacheState } from "../src/types.ts";

let tmp: string;
let origStdout: typeof process.stdout.write;
let captured: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-subagent-"));
  const dynamicDir = path.join(tmp, ".flow", "rules", "dynamic");
  fs.mkdirSync(dynamicDir, { recursive: true });
  fs.writeFileSync(
    path.join(dynamicDir, "tsx-rule.md"),
    [
      "---",
      'patterns: ["**/*.tsx"]',
      "---",
      "Tsx pattern rule body.",
    ].join("\n"),
  );
  fs.writeFileSync(
    path.join(dynamicDir, "kw-foo.md"),
    [
      "---",
      'keywords: ["foo"]',
      "---",
      "Foo keyword rule body.",
    ].join("\n"),
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

function writeFlowParent(parentId: string): void {
  fs.writeFileSync(
    path.join(tmp, ".flow", "SESSIONS.json"),
    JSON.stringify({
      [parentId]: {
        phase: "implementing",
        task_file: "task.md",
        focus: ["x"],
        parent: null,
      },
    }),
  );
  const seeded: CacheState = initState("task.md", ["x"], tmp);
  seeded.selected_via_pattern = ["tsx-rule.md"];
  const { key } = deriveCacheKey("task.md", ["x"]);
  writeState(key, seeded, tmp);
}

function writeVanillaParent(parentId: string): void {
  // No SESSIONS.json: parent has only a session__-keyed cache.
  const { key } = deriveSessionCacheKey(parentId);
  const seeded: CacheState = initState("", [], tmp);
  seeded.selected_via_keyword = ["kw-foo.md"];
  writeState(key, seeded, tmp);
}

function stdinJson(parentId: string, agentId: string): string {
  return JSON.stringify({
    session_id: "sub-sess",
    parent_session_id: parentId,
    agent_id: agentId,
    cwd: tmp,
  });
}

describe("runSubagentStart", () => {
  test("flow parent: subagent warm-starts from flow cache", () => {
    writeFlowParent("flow-parent");
    runSubagentStart(stdinJson("flow-parent", "agent-1"));

    const subPath = subagentCachePath("flow-parent", "agent-1", tmp);
    expect(fs.existsSync(subPath)).toBe(true);
    const subState: unknown = JSON.parse(fs.readFileSync(subPath, "utf8"));
    if (typeof subState !== "object" || subState === null) {
      throw new Error("expected object");
    }
    expect(Reflect.get(subState, "selected_via_pattern")).toEqual([
      "tsx-rule.md",
    ]);

    // Injection should fire — first time for sub session
    const out: unknown = JSON.parse(captured);
    if (typeof out !== "object" || out === null) {
      throw new Error("expected object");
    }
    const hookOut = Reflect.get(out, "hookSpecificOutput");
    expect(typeof hookOut).toBe("object");
  });

  test("vanilla parent: subagent warm-starts from session__-keyed cache", () => {
    writeVanillaParent("vanilla-parent");
    runSubagentStart(stdinJson("vanilla-parent", "agent-2"));

    const subPath = subagentCachePath("vanilla-parent", "agent-2", tmp);
    expect(fs.existsSync(subPath)).toBe(true);
    const subState: unknown = JSON.parse(fs.readFileSync(subPath, "utf8"));
    if (typeof subState !== "object" || subState === null) {
      throw new Error("expected object");
    }
    expect(Reflect.get(subState, "selected_via_keyword")).toEqual([
      "kw-foo.md",
    ]);

    const out: unknown = JSON.parse(captured);
    if (typeof out !== "object" || out === null) {
      throw new Error("expected object");
    }
    const hookOut = Reflect.get(out, "hookSpecificOutput");
    if (typeof hookOut !== "object" || hookOut === null) {
      throw new Error("expected hookSpecificOutput");
    }
    const ctx = Reflect.get(hookOut, "additionalContext");
    expect(typeof ctx).toBe("string");
    if (typeof ctx !== "string") return;
    expect(ctx).toContain("Foo keyword rule body.");
  });

  test("no parent cache (neither flow nor vanilla): cold-starts → returns {}", () => {
    runSubagentStart(stdinJson("nonexistent-parent", "agent-3"));
    expect(captured).toBe("{}");
    const subPath = subagentCachePath("nonexistent-parent", "agent-3", tmp);
    expect(fs.existsSync(subPath)).toBe(false);
  });

  test("flow parent in SESSIONS.json but no cache state yet: cold-starts → {}", () => {
    fs.writeFileSync(
      path.join(tmp, ".flow", "SESSIONS.json"),
      JSON.stringify({
        "flow-parent-no-cache": {
          phase: "implementing",
          task_file: "task.md",
          focus: ["x"],
          parent: null,
        },
      }),
    );
    runSubagentStart(stdinJson("flow-parent-no-cache", "agent-4"));
    expect(captured).toBe("{}");
  });

  test("FLOW_NO_HOOKS=1: short-circuits to {}", () => {
    process.env.FLOW_NO_HOOKS = "1";
    writeFlowParent("flow-parent-2");
    runSubagentStart(stdinJson("flow-parent-2", "agent-5"));
    expect(captured).toBe("{}");
    const subPath = subagentCachePath("flow-parent-2", "agent-5", tmp);
    expect(fs.existsSync(subPath)).toBe(false);
  });
});
