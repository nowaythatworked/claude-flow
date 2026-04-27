import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { loadCatalog, buildLLMCatalog } from "../src/catalog.ts";

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

describe("catalog", () => {
  test("loadCatalog reads .md files with frontmatter", () => {
    writeRule(
      "react.md",
      "---\nrelevance: React work\npatterns: [\"**/*.tsx\"]\n---\nbody",
    );
    writeRule("other.md", "---\nkeywords: [foo]\n---\nbody");
    const c = loadCatalog(tmp);
    expect(c.size).toBe(2);
    expect(c.get("react.md")?.frontmatter.relevance).toBe("React work");
    expect(c.get("other.md")?.frontmatter.keywords).toEqual(["foo"]);
  });

  test("loadCatalog skips rules with no signal fields", () => {
    writeRule("dead.md", "---\ndescription: just a desc\n---\nbody");
    const c = loadCatalog(tmp);
    expect(c.size).toBe(0);
  });

  test("loadCatalog skips rules with no frontmatter", () => {
    writeRule("nofm.md", "no frontmatter here\njust text");
    const c = loadCatalog(tmp);
    expect(c.size).toBe(0);
  });

  test("loadCatalog returns empty when dir missing", () => {
    const tmp2 = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-test-"));
    expect(loadCatalog(tmp2).size).toBe(0);
    fs.rmSync(tmp2, { recursive: true, force: true });
  });

  test("buildLLMCatalog excludes already-selected", () => {
    writeRule("a.md", "---\nrelevance: A rule\n---\n");
    writeRule("b.md", "---\nrelevance: B rule\n---\n");
    const c = loadCatalog(tmp);
    const out = buildLLMCatalog(c, new Set(["a.md"]));
    expect(out).toHaveLength(1);
    expect(out[0]?.id).toBe("b.md");
  });

  test("buildLLMCatalog excludes rules without relevance", () => {
    writeRule("p.md", "---\npatterns: [\"**/*.ts\"]\n---\n");
    writeRule("k.md", "---\nrelevance: K rule\n---\n");
    const c = loadCatalog(tmp);
    const out = buildLLMCatalog(c, new Set());
    expect(out.map((e) => e.id)).toEqual(["k.md"]);
  });
});
