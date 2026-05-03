import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runPreToolUse } from "../src/hooks/pre-tool-use.ts";
import { readState } from "../src/cache.ts";
import { deriveSessionCacheKey, stateFilePath } from "../src/paths.ts";
import { readInjectedLedger } from "../src/injected-ledger.ts";

let tmp: string;
let origStdout: typeof process.stdout.write;
let captured: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-ptu-vanilla-"));
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

describe("runPreToolUse vanilla session fallback", () => {
  test("no SESSIONS.json: pattern match on Read input → state written under session__-key, rule injected", () => {
    const sid = "vanilla-ptu-1";
    const stdin = JSON.stringify({
      session_id: sid,
      cwd: tmp,
      tool_name: "Read",
      tool_input: { file_path: "/proj/Button.tsx" },
    });
    runPreToolUse(stdin);

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
    expect(ctx).toContain("Tsx pattern rule body.");

    const { key } = deriveSessionCacheKey(sid);
    const fresh = readState(key, tmp);
    expect(fresh).not.toBeNull();
    expect(fresh?.selected_via_pattern).toContain("tsx-rule.md");

    const expectedPath = stateFilePath(key, tmp);
    expect(fs.existsSync(expectedPath)).toBe(true);

    expect(readInjectedLedger(sid, tmp)).toEqual(["tsx-rule.md"]);
  });
});
