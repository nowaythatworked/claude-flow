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
    expect(formatRulesInjection([], tmp, { isInitial: true })).toBe("");
  });

  test("strips frontmatter from injected body", () => {
    writeRule(
      "react.md",
      "---\nrelevance: React\npatterns: [\"**/*.tsx\"]\n---\nReact rule body here",
    );
    const out = formatRulesInjection(["react.md"], tmp, { isInitial: true });
    expect(out).toContain("# Dynamic Rules (initial set for this task)");
    expect(out).toContain("--- Dynamic Rule [react.md] (auto-selected) ---");
    expect(out).toContain("React rule body here");
    expect(out).not.toContain("relevance:");
    expect(out).not.toContain("patterns:");
  });

  test("missing rule file is skipped silently", () => {
    writeRule("a.md", "---\nrelevance: A\n---\nbody A");
    const out = formatRulesInjection(["a.md", "missing.md"], tmp, {
      isInitial: true,
    });
    expect(out).toContain("body A");
    expect(out).not.toContain("missing.md");
  });

  test("all missing returns empty string", () => {
    expect(formatRulesInjection(["x.md"], tmp, { isInitial: true })).toBe("");
  });

  test("multiple rules joined", () => {
    writeRule("a.md", "---\nrelevance: A\n---\nbody A");
    writeRule("b.md", "---\nrelevance: B\n---\nbody B");
    const out = formatRulesInjection(["a.md", "b.md"], tmp, {
      isInitial: true,
    });
    expect(out).toContain("body A");
    expect(out).toContain("body B");
    expect(out.indexOf("body A")).toBeLessThan(out.indexOf("body B"));
  });

  test("rule with no frontmatter still injected (full body)", () => {
    writeRule("plain.md", "Plain rule body");
    const out = formatRulesInjection(["plain.md"], tmp, { isInitial: true });
    expect(out).toContain("Plain rule body");
  });

  test("isInitial=false produces delta header with bold IMPORTANT line", () => {
    writeRule("a.md", "---\nrelevance: A\n---\nbody A");
    const out = formatRulesInjection(["a.md"], tmp, { isInitial: false });
    expect(out).toContain("# New Dynamic Rules (just added)");
    expect(out).toContain("**IMPORTANT:**");
    expect(out).toContain("Earlier `Dynamic Rule [...]` blocks");
    expect(out).toContain("scan ALL such blocks throughout conversation history");
    expect(out).toContain("body A");
  });

  test("isInitial=false does NOT contain 'initial set'", () => {
    writeRule("a.md", "---\nrelevance: A\n---\nbody A");
    const out = formatRulesInjection(["a.md"], tmp, { isInitial: false });
    expect(out).not.toContain("initial set");
  });
});
