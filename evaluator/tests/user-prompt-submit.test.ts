import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runUserPromptSubmit } from "../src/hooks/user-prompt-submit.ts";
import { writeState, initState } from "../src/cache.ts";
import { deriveCacheKey } from "../src/paths.ts";
import { readInjectedLedger } from "../src/injected-ledger.ts";
import type { CacheState } from "../src/types.ts";

let tmp: string;
let origStdout: typeof process.stdout.write;
let captured: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-ups-"));

  const dynamicDir = path.join(tmp, ".flow", "rules", "dynamic");
  fs.mkdirSync(dynamicDir, { recursive: true });
  fs.writeFileSync(
    path.join(dynamicDir, "tsx-rule.md"),
    ["---", 'patterns: ["**/*.tsx"]', "---", "Tsx rule body."].join("\n"),
  );
  fs.writeFileSync(
    path.join(dynamicDir, "ts-rule.md"),
    ["---", 'patterns: ["**/*.ts"]', "---", "Ts rule body."].join("\n"),
  );

  fs.writeFileSync(
    path.join(tmp, ".flow", "SESSIONS.json"),
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

describe("runUserPromptSubmit delta injection", () => {
  function seedSelection(ids: string[]): void {
    const { key } = deriveCacheKey("task.md", ["x"]);
    const seeded: CacheState = initState("task.md", ["x"], tmp);
    seeded.selected_via_pattern = ids;
    writeState(key, seeded, tmp);
  }

  function stdin(): string {
    return JSON.stringify({
      session_id: "sess-x",
      cwd: tmp,
      transcript_path: "",
      // benign prompt — no keyword matches against test rules
      prompt: "noop",
    });
  }

  test("first call: initial header + ledger seeded with selection", async () => {
    seedSelection(["tsx-rule.md"]);
    captured = "";
    await runUserPromptSubmit(stdin());
    const out: unknown = JSON.parse(captured);
    if (typeof out !== "object" || out === null) {
      throw new Error("expected object");
    }
    const hookOut = Reflect.get(out, "hookSpecificOutput");
    if (typeof hookOut !== "object" || hookOut === null) {
      throw new Error("expected hookSpecificOutput");
    }
    expect(Reflect.get(hookOut, "hookEventName")).toBe("UserPromptSubmit");
    const ctx = Reflect.get(hookOut, "additionalContext");
    expect(typeof ctx).toBe("string");
    if (typeof ctx !== "string") return;
    expect(ctx).toContain("# Dynamic Rules (initial set for this task)");
    expect(ctx).toContain("Tsx rule body.");
    expect(readInjectedLedger("sess-x", tmp)).toEqual(["tsx-rule.md"]);
  });

  test("second call same selection: empty output, ledger unchanged", async () => {
    seedSelection(["tsx-rule.md"]);
    captured = "";
    await runUserPromptSubmit(stdin());
    captured = "";
    await runUserPromptSubmit(stdin());
    expect(captured).toBe("{}");
    expect(readInjectedLedger("sess-x", tmp)).toEqual(["tsx-rule.md"]);
  });

  test("selection grows: only new rule injected with delta header", async () => {
    seedSelection(["tsx-rule.md"]);
    captured = "";
    await runUserPromptSubmit(stdin());
    seedSelection(["tsx-rule.md", "ts-rule.md"]);
    captured = "";
    await runUserPromptSubmit(stdin());
    const out: unknown = JSON.parse(captured);
    if (typeof out !== "object" || out === null) {
      throw new Error("expected object");
    }
    const hookOut = Reflect.get(out, "hookSpecificOutput");
    if (typeof hookOut !== "object" || hookOut === null) {
      throw new Error("expected hookSpecificOutput");
    }
    const ctx = Reflect.get(hookOut, "additionalContext");
    if (typeof ctx !== "string") {
      throw new Error("expected ctx string");
    }
    expect(ctx).toContain("# New Dynamic Rules (just added)");
    expect(ctx).toContain("**IMPORTANT:**");
    expect(ctx).toContain("Ts rule body.");
    expect(ctx).not.toContain("Tsx rule body.");
    expect(readInjectedLedger("sess-x", tmp)).toEqual([
      "tsx-rule.md",
      "ts-rule.md",
    ]);
  });

  test("selection shrinks: empty output, ledger preserves both", async () => {
    seedSelection(["tsx-rule.md"]);
    captured = "";
    await runUserPromptSubmit(stdin());
    seedSelection(["tsx-rule.md", "ts-rule.md"]);
    captured = "";
    await runUserPromptSubmit(stdin());
    seedSelection(["tsx-rule.md"]);
    captured = "";
    await runUserPromptSubmit(stdin());
    expect(captured).toBe("{}");
    expect(readInjectedLedger("sess-x", tmp)).toEqual([
      "tsx-rule.md",
      "ts-rule.md",
    ]);
  });
});
