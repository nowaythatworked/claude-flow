import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { extractSinceWatermark } from "../src/transcript.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-test-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function writeJsonl(p: string, entries: object[]): void {
  fs.writeFileSync(p, entries.map((e) => JSON.stringify(e)).join("\n"));
}

describe("transcript", () => {
  test("missing transcript returns empty content", () => {
    const r = extractSinceWatermark(path.join(tmp, "nope.jsonl"), null);
    expect(r.filesInScope.reads.size).toBe(0);
    expect(r.recentUserText).toEqual([]);
  });

  test("extracts a Read tool result", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      {
        uuid: "u1",
        type: "assistant",
        message: {
          content: [
            {
              type: "tool_use",
              id: "tu1",
              name: "Read",
              input: { file_path: "/foo.ts" },
            },
          ],
        },
      },
      {
        uuid: "u2",
        type: "user",
        message: {
          content: [
            {
              type: "tool_result",
              tool_use_id: "tu1",
              content: "     1→hello\n     2→world",
            },
          ],
        },
      },
    ]);
    const r = extractSinceWatermark(p, null);
    expect(r.filesInScope.reads.get("/foo.ts")).toBe(
      "     1→hello\n     2→world",
    );
    expect(r.newWatermarkCandidate).toBe("u2");
  });

  test("extracts an Edit", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      {
        uuid: "u1",
        type: "assistant",
        message: {
          content: [
            {
              type: "tool_use",
              id: "tu1",
              name: "Edit",
              input: { file_path: "/foo.ts", old_string: "a", new_string: "b" },
            },
          ],
        },
      },
      {
        uuid: "u2",
        type: "user",
        message: {
          content: [
            { type: "tool_result", tool_use_id: "tu1", content: "ok" },
          ],
        },
      },
    ]);
    const r = extractSinceWatermark(p, null);
    expect(r.filesInScope.edits.get("/foo.ts")).toEqual([
      { old: "a", new: "b" },
    ]);
  });

  test("extracts user typed messages, skips command/system tags", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      { uuid: "u1", type: "user", message: { content: "hello world" } },
      {
        uuid: "u2",
        type: "user",
        message: { content: "<command-name>/foo</command-name>" },
      },
      {
        uuid: "u3",
        type: "user",
        message: { content: "<system-reminder>x</system-reminder>" },
      },
      { uuid: "u4", type: "user", message: { content: "second message" } },
    ]);
    const r = extractSinceWatermark(p, null);
    expect(r.recentUserText).toEqual(["hello world", "second message"]);
  });

  test("watermark: skips entries before and including watermark uuid", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      { uuid: "u1", type: "user", message: { content: "first" } },
      { uuid: "u2", type: "user", message: { content: "second" } },
      { uuid: "u3", type: "user", message: { content: "third" } },
    ]);
    const r = extractSinceWatermark(p, "u1");
    expect(r.recentUserText).toEqual(["second", "third"]);
    expect(r.newWatermarkCandidate).toBe("u3");
  });

  test("watermark unknown — nothing extracted", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      { uuid: "u1", type: "user", message: { content: "hello" } },
    ]);
    const r = extractSinceWatermark(p, "u999");
    expect(r.recentUserText).toEqual([]);
  });

  test("Glob result parsed as path list, header stripped", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      {
        uuid: "u1",
        type: "assistant",
        message: {
          content: [
            {
              type: "tool_use",
              id: "tu1",
              name: "Glob",
              input: { pattern: "**/*.ts" },
            },
          ],
        },
      },
      {
        uuid: "u2",
        type: "user",
        message: {
          content: [
            {
              type: "tool_result",
              tool_use_id: "tu1",
              content: "Found 2 files\nsrc/a.ts\nsrc/b.ts",
            },
          ],
        },
      },
    ]);
    const r = extractSinceWatermark(p, null);
    expect(r.globResults).toEqual([["src/a.ts", "src/b.ts"]]);
  });

  test("assistant text bursts captured", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      {
        uuid: "u1",
        type: "assistant",
        message: {
          content: [
            { type: "text", text: "thinking out loud" },
            { type: "text", text: "more text" },
          ],
        },
      },
    ]);
    const r = extractSinceWatermark(p, null);
    expect(r.recentAssistantText).toEqual(["thinking out loud\nmore text"]);
  });

  test("caps to last 5 user messages", () => {
    const p = path.join(tmp, "t.jsonl");
    const entries: object[] = [];
    for (let i = 0; i < 10; i++) {
      entries.push({
        uuid: `u${i}`,
        type: "user",
        message: { content: `msg ${i}` },
      });
    }
    writeJsonl(p, entries);
    const r = extractSinceWatermark(p, null);
    expect(r.recentUserText).toHaveLength(5);
    expect(r.recentUserText[0]).toBe("msg 5");
    expect(r.recentUserText[4]).toBe("msg 9");
  });

  test("user content as array with text only is captured if no tool_result", () => {
    const p = path.join(tmp, "t.jsonl");
    writeJsonl(p, [
      {
        uuid: "u1",
        type: "user",
        message: {
          content: [{ type: "text", text: "typed via array" }],
        },
      },
    ]);
    const r = extractSinceWatermark(p, null);
    expect(r.recentUserText).toEqual(["typed via array"]);
  });
});
