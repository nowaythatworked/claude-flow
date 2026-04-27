import { test, expect, describe } from "bun:test";
import { parseRuleFile, stripFrontmatter } from "../src/frontmatter.ts";

describe("frontmatter", () => {
  test("no frontmatter returns null + full body", () => {
    const r = parseRuleFile("# Hello\nworld");
    expect(r.frontmatter).toBeNull();
    expect(r.body).toBe("# Hello\nworld");
  });

  test("unterminated frontmatter returns null", () => {
    const r = parseRuleFile("---\nrelevance: x\nno closing fence");
    expect(r.frontmatter).toBeNull();
  });

  test("simple relevance string unquoted", () => {
    const r = parseRuleFile(
      "---\nrelevance: When working on React\n---\nbody here",
    );
    expect(r.frontmatter?.relevance).toBe("When working on React");
    expect(r.body).toBe("body here");
  });

  test("relevance with double quotes", () => {
    const r = parseRuleFile(
      '---\nrelevance: "When working on React"\n---\nbody',
    );
    expect(r.frontmatter?.relevance).toBe("When working on React");
  });

  test("relevance with single quotes", () => {
    const r = parseRuleFile(
      "---\nrelevance: 'use TSX'\n---\n",
    );
    expect(r.frontmatter?.relevance).toBe("use TSX");
  });

  test("inline patterns list", () => {
    const r = parseRuleFile(
      '---\npatterns: ["**/*.tsx", "**/*.ts"]\n---\nx',
    );
    expect(r.frontmatter?.patterns).toEqual(["**/*.tsx", "**/*.ts"]);
  });

  test("inline patterns list unquoted", () => {
    const r = parseRuleFile("---\npatterns: [a, b, c]\n---\n");
    expect(r.frontmatter?.patterns).toEqual(["a", "b", "c"]);
  });

  test("block list of keywords", () => {
    const r = parseRuleFile(
      "---\nkeywords:\n  - hook\n  - useEffect\n  - 'state'\n---\nbody",
    );
    expect(r.frontmatter?.keywords).toEqual(["hook", "useEffect", "state"]);
  });

  test("multiple fields", () => {
    const r = parseRuleFile(
      [
        "---",
        'relevance: "React work"',
        'patterns: ["**/*.tsx"]',
        "keywords:",
        "  - component",
        "  - useEffect",
        "---",
        "Body content",
      ].join("\n"),
    );
    expect(r.frontmatter?.relevance).toBe("React work");
    expect(r.frontmatter?.patterns).toEqual(["**/*.tsx"]);
    expect(r.frontmatter?.keywords).toEqual(["component", "useEffect"]);
    expect(r.body).toBe("Body content");
  });

  test("empty frontmatter block", () => {
    const r = parseRuleFile("---\n---\nbody");
    expect(r.frontmatter).toEqual({});
    expect(r.body).toBe("body");
  });

  test("unknown fields ignored", () => {
    const r = parseRuleFile("---\ndescription: foo\nrelevance: bar\n---\nb");
    expect(r.frontmatter?.relevance).toBe("bar");
  });

  test("stripFrontmatter returns body only", () => {
    const txt = "---\nrelevance: x\n---\nactual body";
    expect(stripFrontmatter(txt)).toBe("actual body");
  });

  test("stripFrontmatter with no frontmatter returns input", () => {
    expect(stripFrontmatter("just body")).toBe("just body");
  });
});
