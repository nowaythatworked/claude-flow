import { test, expect, describe } from "bun:test";
import { matchPatterns, matchKeywords } from "../src/matcher.ts";
import type { RuleCatalog } from "../src/types.ts";

function cat(
  entries: Array<[string, { patterns?: string[]; keywords?: string[] }]>,
): RuleCatalog {
  const m: RuleCatalog = new Map();
  for (const [id, fm] of entries) {
    m.set(id, { id, frontmatter: fm, body: "" });
  }
  return m;
}

describe("matcher", () => {
  test("matchPatterns: nested glob hits", () => {
    const c = cat([
      ["react.md", { patterns: ["**/*.tsx"] }],
      ["other.md", { patterns: ["**/*.py"] }],
    ]);
    expect(matchPatterns(["src/components/Foo.tsx"], c)).toEqual(["react.md"]);
  });

  test("matchPatterns: top-level file with **/*", () => {
    const c = cat([["all-tsx.md", { patterns: ["**/*.tsx"] }]]);
    expect(matchPatterns(["Foo.tsx"], c)).toEqual(["all-tsx.md"]);
  });

  test("matchPatterns: no patterns means no match", () => {
    const c = cat([["bare.md", {}]]);
    expect(matchPatterns(["x.tsx"], c)).toEqual([]);
  });

  test("matchPatterns: dotfiles match with dot:true", () => {
    const c = cat([["dot.md", { patterns: ["**/.env*"] }]]);
    expect(matchPatterns(["src/.env.local"], c)).toEqual(["dot.md"]);
  });

  test("matchPatterns: empty file list", () => {
    const c = cat([["a.md", { patterns: ["**/*"] }]]);
    expect(matchPatterns([], c)).toEqual([]);
  });

  test("matchPatterns: multi-pattern OR", () => {
    const c = cat([["multi.md", { patterns: ["**/*.tsx", "**/*.ts"] }]]);
    expect(matchPatterns(["a.ts"], c)).toEqual(["multi.md"]);
    expect(matchPatterns(["a.tsx"], c)).toEqual(["multi.md"]);
    expect(matchPatterns(["a.js"], c)).toEqual([]);
  });

  test("matchKeywords: case-insensitive", () => {
    const c = cat([["k.md", { keywords: ["Hook"] }]]);
    expect(matchKeywords("using a hook here", c)).toEqual(["k.md"]);
  });

  test("matchKeywords: substring", () => {
    const c = cat([["k.md", { keywords: ["useEffect"] }]]);
    expect(matchKeywords("we call useEffect()", c)).toEqual(["k.md"]);
  });

  test("matchKeywords: no keyword field, no match", () => {
    const c = cat([["bare.md", {}]]);
    expect(matchKeywords("anything", c)).toEqual([]);
  });

  test("matchKeywords: empty text matches nothing", () => {
    const c = cat([["k.md", { keywords: ["x"] }]]);
    expect(matchKeywords("", c)).toEqual([]);
  });

  test("matchKeywords: empty keyword string is ignored", () => {
    const c = cat([["k.md", { keywords: [""] }]]);
    expect(matchKeywords("anything", c)).toEqual([]);
  });
});
