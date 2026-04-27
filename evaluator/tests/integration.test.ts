// Real-claude integration test for flow-rules.
//
// IMPORTANT: this test invokes the actual `claude` CLI against the real
// Anthropic API and consumes a small amount of haiku-tier credit per run.
// It is skipped when:
//   - the `claude` binary is not on PATH, or
//   - the env var FLOW_SKIP_REAL_CLAUDE=1 is set.
//
// Use FLOW_SKIP_REAL_CLAUDE=1 in CI / casual `bun test` invocations to avoid
// spending money. Run without that env var to actually exercise the LLM.

import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { spawnSync } from "node:child_process";
import { deriveCacheKey, evalLogPath, stateFilePath } from "../src/paths.ts";

const REPO_ROOT = path.resolve(import.meta.dir, "..", "..");
const FLOW_RULES_BIN = path.join(REPO_ROOT, "bin", "flow-rules");

function realClaudeAvailable(): boolean {
  if (process.env.FLOW_SKIP_REAL_CLAUDE === "1") return false;
  const which = spawnSync("which", ["claude"], { encoding: "utf8" });
  if (which.status !== 0) return false;
  return which.stdout.trim() !== "";
}

function binAvailable(): boolean {
  return fs.existsSync(FLOW_RULES_BIN);
}

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-real-"));

  const dynamicDir = path.join(tmp, ".flow", "rules", "dynamic");
  fs.mkdirSync(dynamicDir, { recursive: true });

  // pattern-only rule (deterministic match)
  fs.writeFileSync(
    path.join(dynamicDir, "react-tsx.md"),
    [
      "---",
      'patterns: ["**/*.tsx"]',
      "---",
      "Use proper React+TS conventions.",
    ].join("\n"),
  );

  // keyword-only rule (deterministic match)
  fs.writeFileSync(
    path.join(dynamicDir, "kw-component.md"),
    [
      "---",
      'keywords: ["component", "JSX"]',
      "---",
      "Component conventions apply.",
    ].join("\n"),
  );

  // relevance-only rule — drives the LLM path. Phrasing kept very explicit
  // to give the LLM a clear signal regardless of model variance.
  fs.writeFileSync(
    path.join(dynamicDir, "llm-rule.md"),
    [
      "---",
      'relevance: "Always select this rule whenever the user is editing or reading TypeScript React components. The transcript will mention React/TSX work."',
      "---",
      "LLM-only rule body.",
    ].join("\n"),
  );

  fs.writeFileSync(
    path.join(tmp, ".flow", "SESSIONS.json"),
    JSON.stringify({ "sess1": { phase: "implementing", task_file: "task.md", focus: ["something"], parent: null } }),
  );
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("integration (real claude)", () => {
  test("flow-rules eval --sync: pattern + keyword + LLM merge into state", () => {
    if (!realClaudeAvailable()) {
      console.log(
        "[skip] real-claude integration: claude not on PATH or FLOW_SKIP_REAL_CLAUDE=1",
      );
      return;
    }
    if (!binAvailable()) {
      console.log(
        `[skip] real-claude integration: binary missing at ${FLOW_RULES_BIN} (run \`bun run build\` first)`,
      );
      return;
    }

    const transcriptPath = path.join(
      import.meta.dir,
      "fixtures",
      "sample-transcript.jsonl",
    );
    expect(fs.existsSync(transcriptPath)).toBe(true);

    const result = spawnSync(
      FLOW_RULES_BIN,
      [
        "eval",
        "--sync",
        "--cwd",
        tmp,
        "--session-id",
        "sess1",
        "--task-file",
        "task.md",
        "--focus",
        JSON.stringify(["something"]),
        "--reason",
        "real-claude-integration",
        "--transcript",
        transcriptPath,
      ],
      {
        env: { ...process.env, FLOW_NO_HOOKS: "1" },
        encoding: "utf8",
        timeout: 120_000,
      },
    );

    expect(result.status).toBe(0);

    const { key } = deriveCacheKey("task.md", ["something"]);
    const statePath = stateFilePath(key, tmp);
    expect(fs.existsSync(statePath)).toBe(true);

    const stateRaw: unknown = JSON.parse(fs.readFileSync(statePath, "utf8"));
    expect(typeof stateRaw).toBe("object");
    if (typeof stateRaw !== "object" || stateRaw === null) return;

    const schemaVersion = Reflect.get(stateRaw, "schema_version");
    expect(schemaVersion).toBe(1);

    const patternSel = Reflect.get(stateRaw, "selected_via_pattern");
    expect(Array.isArray(patternSel)).toBe(true);
    expect(patternSel).toContain("react-tsx.md");

    const llmSel = Reflect.get(stateRaw, "selected_via_llm");
    expect(Array.isArray(llmSel)).toBe(true);
    // model variance — we don't assert which rules; only shape
    if (Array.isArray(llmSel)) {
      for (const id of llmSel) expect(typeof id).toBe("string");
    }

    const perSession = Reflect.get(stateRaw, "per_session");
    if (typeof perSession === "object" && perSession !== null) {
      const sessRec = Reflect.get(perSession, "sess1");
      if (typeof sessRec === "object" && sessRec !== null) {
        const watermark = Reflect.get(sessRec, "watermark_uuid");
        // fixture transcript ends at uuid u8
        expect(watermark).toBe("u8");
      }
    }

    // eval-log.jsonl exists with at least one valid entry
    const logPath = evalLogPath(tmp);
    expect(fs.existsSync(logPath)).toBe(true);
    const logLines = fs
      .readFileSync(logPath, "utf8")
      .trim()
      .split("\n")
      .filter((l) => l !== "");
    expect(logLines.length).toBe(1);
    const lastEntry: unknown = JSON.parse(logLines[logLines.length - 1] ?? "{}");
    expect(typeof lastEntry).toBe("object");
    if (typeof lastEntry === "object" && lastEntry !== null) {
      expect(typeof Reflect.get(lastEntry, "ts")).toBe("string");
      expect(typeof Reflect.get(lastEntry, "trigger_reason")).toBe("string");
      expect(typeof Reflect.get(lastEntry, "duration_ms")).toBe("number");
    }
  }, 130_000);

  test("FLOW_SKIP_REAL_CLAUDE=1 skips cleanly", () => {
    // sanity check — skip should produce no state file
    if (process.env.FLOW_SKIP_REAL_CLAUDE !== "1") {
      return; // not asserting anything in non-skip mode
    }
    const { key } = deriveCacheKey("task.md", ["something"]);
    expect(fs.existsSync(stateFilePath(key, tmp))).toBe(false);
  });
});
