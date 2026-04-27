import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { buildDigest } from "../src/digest.ts";
import type { ExtractedContent } from "../src/types.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-test-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function emptyExtracted(): ExtractedContent {
  return {
    filesInScope: { reads: new Map(), edits: new Map() },
    globResults: [],
    recentUserText: [],
    recentAssistantText: [],
    newWatermarkCandidate: "",
  };
}

describe("digest", () => {
  test("empty extracted produces minimal digest with selection+catalog", () => {
    const d = buildDigest(emptyExtracted(), [], []);
    expect(d).toContain("## Currently selected rules");
    expect(d).toContain("(none)");
    expect(d).toContain("## LLM rule catalog");
    expect(d).toContain("(empty)");
    expect(d).toContain("## Instructions");
  });

  test("includes Read content under threshold full", () => {
    const e = emptyExtracted();
    e.filesInScope.reads.set("/foo.ts", "line1\nline2");
    const d = buildDigest(e, [], []);
    expect(d).toContain("### Read: /foo.ts");
    expect(d).toContain("line1");
    expect(d).toContain("line2");
  });

  test("truncates large file (>30KB) to head+tail", () => {
    const e = emptyExtracted();
    const lines: string[] = [];
    for (let i = 0; i < 1000; i++) lines.push(`line ${i} ` + "x".repeat(80));
    const big = lines.join("\n");
    expect(Buffer.byteLength(big, "utf8")).toBeGreaterThan(30000);
    e.filesInScope.reads.set("/big.ts", big);
    const d = buildDigest(e, [], []);
    expect(d).toContain("[truncated");
    expect(d).toContain("line 0 ");
    expect(d).toContain("line 999 ");
    expect(d).not.toContain("line 500 ");
  });

  test("file just under 30KB is full", () => {
    const e = emptyExtracted();
    const content = "x".repeat(29_000);
    e.filesInScope.reads.set("/m.ts", content);
    const d = buildDigest(e, [], []);
    expect(d).not.toContain("[truncated");
    expect(d).toContain(content);
  });

  test("Edit-only file falls back to disk read (head 100 lines)", () => {
    const fp = path.join(tmp, "real.ts");
    const lines: string[] = [];
    for (let i = 0; i < 200; i++) lines.push(`real line ${i}`);
    fs.writeFileSync(fp, lines.join("\n"));
    const e = emptyExtracted();
    e.filesInScope.edits.set(fp, [{ old: "a", new: "b" }]);
    const d = buildDigest(e, [], []);
    expect(d).toContain("real line 0");
    expect(d).toContain("real line 99");
    expect(d).not.toContain("real line 150");
  });

  test("edit fallback gracefully handles missing file", () => {
    const e = emptyExtracted();
    e.filesInScope.edits.set("/nonexistent.ts", [{ old: "a", new: "b" }]);
    const d = buildDigest(e, [], []);
    expect(d).toContain("### Edit: /nonexistent.ts");
    expect(d).toContain("OLD:");
    expect(d).toContain("NEW:");
  });

  test("includes recent user and assistant text", () => {
    const e = emptyExtracted();
    e.recentUserText = ["hello"];
    e.recentAssistantText = ["world"];
    const d = buildDigest(e, [], []);
    expect(d).toContain("## Recent user messages");
    expect(d).toContain("hello");
    expect(d).toContain("## Recent assistant text");
    expect(d).toContain("world");
  });

  test("lists current selection and LLM catalog", () => {
    const d = buildDigest(emptyExtracted(), ["a.md", "b.md"], [
      { id: "c.md", relevance: "C is relevant when..." },
    ]);
    expect(d).toContain("- a.md");
    expect(d).toContain("- b.md");
    expect(d).toContain("- c.md: C is relevant when...");
  });

  test("glob results listed", () => {
    const e = emptyExtracted();
    e.globResults = [["src/a.ts", "src/b.ts"]];
    const d = buildDigest(e, [], []);
    expect(d).toContain("## Glob/Grep results");
    expect(d).toContain("- src/a.ts");
  });
});
