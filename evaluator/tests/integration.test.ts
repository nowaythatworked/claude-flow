import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runFullEval, unionAllSelected } from "../src/eval.ts";
import { readState } from "../src/cache.ts";
import { deriveCacheKey, evalLogPath, lockDirPath } from "../src/paths.ts";

let tmp: string;
let mockBinDir: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-test-"));
  mockBinDir = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-mock-"));

  const dynamicDir = path.join(tmp, ".flow", "rules", "dynamic");
  fs.mkdirSync(dynamicDir, { recursive: true });

  fs.writeFileSync(
    path.join(dynamicDir, "react-tsx.md"),
    [
      "---",
      'patterns: ["**/*.tsx"]',
      "---",
      "Use proper React+TS conventions.",
    ].join("\n"),
  );
  fs.writeFileSync(
    path.join(dynamicDir, "kw-component.md"),
    [
      "---",
      'keywords: ["component", "JSX"]',
      "---",
      "Component conventions apply.",
    ].join("\n"),
  );
  fs.writeFileSync(
    path.join(dynamicDir, "llm-rule.md"),
    [
      "---",
      'relevance: "When the user mentions cleanup work."',
      "---",
      "LLM-only rule body.",
    ].join("\n"),
  );
  fs.writeFileSync(
    path.join(dynamicDir, "no-signal.md"),
    "---\ndescription: bare\n---\nbody",
  );

  const mockClaude = path.join(mockBinDir, "claude");
  fs.writeFileSync(
    mockClaude,
    `#!/bin/sh
cat > /dev/null
echo '{"result":null,"structured_output":{"task_type":"test","selected_rules":["llm-rule.md"],"reason":"fixture"}}'
`,
  );
  fs.chmodSync(mockClaude, 0o755);
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.rmSync(mockBinDir, { recursive: true, force: true });
});

describe("integration", () => {
  test("full eval: pattern + keyword + LLM-mock all merge into state", async () => {
    const transcriptPath = path.join(__dirname, "fixtures", "sample-transcript.jsonl");
    expect(fs.existsSync(transcriptPath)).toBe(true);

    const origPath = process.env.PATH ?? "";
    process.env.PATH = `${mockBinDir}:${origPath}`;
    try {
      const result = await runFullEval({
        cwd: tmp,
        taskFile: "task.md",
        focus: ["something"],
        sessionId: "sess1",
        transcriptPath,
        triggerReason: "integration-test",
      });
      expect(result.kind).toBe("ok");
      if (result.kind !== "ok") return;
      const ids = unionAllSelected(result.state);
      expect(ids).toContain("react-tsx.md");
      expect(ids).toContain("kw-component.md");
      expect(ids).toContain("llm-rule.md");

      const { key } = deriveCacheKey("task.md", ["something"]);
      const persisted = readState(key, tmp);
      expect(persisted).not.toBeNull();
      expect(persisted?.task_type).toBe("test");
      expect(persisted?.per_session.sess1?.watermark_uuid).toBe("u8");
      expect(persisted?.selected_via_pattern).toContain("react-tsx.md");
      expect(persisted?.selected_via_keyword).toContain("kw-component.md");
      expect(persisted?.selected_via_llm).toContain("llm-rule.md");

      const log = fs.readFileSync(evalLogPath(tmp), "utf8").trim().split("\n");
      expect(log.length).toBeGreaterThanOrEqual(1);
      const last: unknown = JSON.parse(log[log.length - 1] ?? "{}");
      expect(typeof last).toBe("object");

      expect(fs.existsSync(lockDirPath(key, tmp))).toBe(false);
    } finally {
      process.env.PATH = origPath;
    }
  });

  test("haiku failure does not advance watermark or update llm selection", async () => {
    const transcriptPath = path.join(__dirname, "fixtures", "sample-transcript.jsonl");
    const failingMockDir = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-mock-"));
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
      const result = await runFullEval({
        cwd: tmp,
        taskFile: "task.md",
        focus: [],
        sessionId: "sess1",
        transcriptPath,
        triggerReason: "integration-test-fail",
      });
      expect(result.kind).toBe("ok");
      if (result.kind !== "ok") return;
      // pattern + keyword still ran
      expect(result.state.selected_via_pattern).toContain("react-tsx.md");
      expect(result.state.selected_via_keyword).toContain("kw-component.md");
      // llm should be empty since haiku failed
      expect(result.state.selected_via_llm).toEqual([]);
      // watermark NOT advanced
      expect(result.state.per_session.sess1).toBeUndefined();
    } finally {
      process.env.PATH = origPath;
      fs.rmSync(failingMockDir, { recursive: true, force: true });
    }
  });
});
