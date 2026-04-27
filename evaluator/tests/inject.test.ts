import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { formatRulesInjection } from "../src/inject.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-test-"));
  fs.mkdirSync(path.join(tmp, ".flow", "rules", "dynamic"), { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function writeRule(name: string, content: string): void {
  fs.writeFileSync(path.join(tmp, ".flow", "rules", "dynamic", name), content);
}

describe("inject", () => {
  test("empty selection returns empty string", () => {
    expect(formatRulesInjection([], tmp)).toBe("");
  });

  test("strips frontmatter from injected body", () => {
    writeRule(
      "react.md",
      "---\nrelevance: React\npatterns: [\"**/*.tsx\"]\n---\nReact rule body here",
    );
    const out = formatRulesInjection(["react.md"], tmp);
    expect(out).toContain("# Dynamic Rules (auto-selected for this task)");
    expect(out).toContain("--- Dynamic Rule [react.md] (auto-selected) ---");
    expect(out).toContain("React rule body here");
    expect(out).not.toContain("relevance:");
    expect(out).not.toContain("patterns:");
  });

  test("missing rule file is skipped silently", () => {
    writeRule("a.md", "---\nrelevance: A\n---\nbody A");
    const out = formatRulesInjection(["a.md", "missing.md"], tmp);
    expect(out).toContain("body A");
    expect(out).not.toContain("missing.md");
  });

  test("all missing returns empty string", () => {
    expect(formatRulesInjection(["x.md"], tmp)).toBe("");
  });

  test("multiple rules joined", () => {
    writeRule("a.md", "---\nrelevance: A\n---\nbody A");
    writeRule("b.md", "---\nrelevance: B\n---\nbody B");
    const out = formatRulesInjection(["a.md", "b.md"], tmp);
    expect(out).toContain("body A");
    expect(out).toContain("body B");
    expect(out.indexOf("body A")).toBeLessThan(out.indexOf("body B"));
  });

  test("rule with no frontmatter still injected (full body)", () => {
    writeRule("plain.md", "Plain rule body");
    const out = formatRulesInjection(["plain.md"], tmp);
    expect(out).toContain("Plain rule body");
  });
});
