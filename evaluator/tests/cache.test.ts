import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  readState,
  writeState,
  initState,
  ensureCacheDir,
  subagentCachePath,
} from "../src/cache.ts";
import { deriveCacheKey, stateFilePath } from "../src/paths.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-test-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("cache", () => {
  test("readState returns null when missing", () => {
    expect(readState("nokey", tmp)).toBeNull();
  });

  test("initState creates fresh state with focus_hash", () => {
    const s = initState("task.md", ["focus1"], tmp);
    expect(s.schema_version).toBe(1);
    expect(s.task_file).toBe("task.md");
    expect(s.focus).toEqual(["focus1"]);
    expect(s.focus_hash).toMatch(/^[0-9a-f]{16}$/);
    expect(s.selected_via_pattern).toEqual([]);
    expect(s.selected_via_keyword).toEqual([]);
    expect(s.selected_via_llm).toEqual([]);
    expect(s.per_session).toEqual({});
  });

  test("write then read roundtrip", () => {
    const s = initState("task.md", [], tmp);
    s.selected_via_pattern = ["a.md"];
    s.task_type = "ui";
    const { key } = deriveCacheKey("task.md", []);
    ensureCacheDir(tmp);
    writeState(key, s, tmp);
    const r = readState(key, tmp);
    expect(r).not.toBeNull();
    expect(r?.selected_via_pattern).toEqual(["a.md"]);
    expect(r?.task_type).toBe("ui");
  });

  test("schema_version mismatch returns null", () => {
    const { key } = deriveCacheKey("task.md", []);
    ensureCacheDir(tmp);
    fs.writeFileSync(
      stateFilePath(key, tmp),
      JSON.stringify({
        schema_version: 999,
        task_file: "task.md",
        focus: [],
        focus_hash: "x",
        selected_via_pattern: [],
        selected_via_keyword: [],
        selected_via_llm: [],
        task_type: "",
        trigger_reason: "",
        last_eval_ts: "",
        last_eval_duration_ms: 0,
        per_session: {},
      }),
    );
    expect(readState(key, tmp)).toBeNull();
  });

  test("invalid JSON returns null", () => {
    const { key } = deriveCacheKey("task.md", []);
    ensureCacheDir(tmp);
    fs.writeFileSync(stateFilePath(key, tmp), "not json{");
    expect(readState(key, tmp)).toBeNull();
  });

  test("missing fields returns null", () => {
    const { key } = deriveCacheKey("task.md", []);
    ensureCacheDir(tmp);
    fs.writeFileSync(stateFilePath(key, tmp), "{}");
    expect(readState(key, tmp)).toBeNull();
  });

  test("write is atomic — no .tmp file leftover", () => {
    const s = initState("task.md", [], tmp);
    const { key } = deriveCacheKey("task.md", []);
    ensureCacheDir(tmp);
    writeState(key, s, tmp);
    const dir = path.join(tmp, ".flow", "rule-cache");
    const entries = fs.readdirSync(dir).filter((f) => f.includes(".tmp."));
    expect(entries).toEqual([]);
  });

  test("subagentCachePath", () => {
    expect(subagentCachePath("p1", "a1", tmp)).toBe(
      path.join(tmp, ".flow", "rule-cache", "sub__p1__a1.json"),
    );
  });
});
