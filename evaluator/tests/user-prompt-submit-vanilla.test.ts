import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runUserPromptSubmit } from "../src/hooks/user-prompt-submit.ts";
import { readState } from "../src/cache.ts";
import { deriveSessionCacheKey, stateFilePath } from "../src/paths.ts";
import { readInjectedLedger } from "../src/injected-ledger.ts";

let tmp: string;
let origStdout: typeof process.stdout.write;
let captured: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-ups-vanilla-"));

  // No SESSIONS.json — this is a vanilla (non-flow) project.
  const dynamicDir = path.join(tmp, ".flow", "rules", "dynamic");
  fs.mkdirSync(dynamicDir, { recursive: true });
  fs.writeFileSync(
    path.join(dynamicDir, "kw-foo.md"),
    [
      "---",
      'keywords: ["FOO"]',
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

describe("runUserPromptSubmit vanilla session fallback", () => {
  test("no SESSIONS.json: uses session__<id> key, runs eval, injects rule", async () => {
    const sid = "vanilla-sess-1";
    const stdin = JSON.stringify({
      session_id: sid,
      cwd: tmp,
      transcript_path: "",
      prompt: "hello FOO world",
    });
    await runUserPromptSubmit(stdin);

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

    // State written under session__-prefixed key
    const { key } = deriveSessionCacheKey(sid);
    const fresh = readState(key, tmp);
    expect(fresh).not.toBeNull();
    expect(fresh?.selected_via_keyword).toContain("kw-foo.md");

    // Cache file actually lives at session__<id>.json
    const expectedPath = stateFilePath(key, tmp);
    expect(fs.existsSync(expectedPath)).toBe(true);

    // Ledger seeded
    expect(readInjectedLedger(sid, tmp)).toEqual(["kw-foo.md"]);
  });

  test("vanilla session: no keyword match → empty injection but state still written", async () => {
    const sid = "vanilla-sess-2";
    const stdin = JSON.stringify({
      session_id: sid,
      cwd: tmp,
      transcript_path: "",
      prompt: "noop without keywords",
    });
    await runUserPromptSubmit(stdin);

    expect(captured).toBe("{}");
    const { key } = deriveSessionCacheKey(sid);
    const fresh = readState(key, tmp);
    expect(fresh).not.toBeNull();
    // Empty selection — but state file exists (eval ran).
    expect(fresh?.selected_via_keyword).toEqual([]);
  });
});
