import { test, expect, describe } from "bun:test";
import {
  cacheDir,
  dynamicRulesDir,
  evalLogPath,
  focusHash,
  deriveCacheKey,
  stateFilePath,
  lockDirPath,
} from "../src/paths.ts";

describe("paths", () => {
  test("cacheDir resolves under .flow/rule-cache", () => {
    expect(cacheDir("/tmp/proj")).toBe("/tmp/proj/.flow/rule-cache");
  });

  test("dynamicRulesDir resolves under .flow/rules/dynamic", () => {
    expect(dynamicRulesDir("/tmp/proj")).toBe("/tmp/proj/.flow/rules/dynamic");
  });

  test("evalLogPath", () => {
    expect(evalLogPath("/tmp/proj")).toBe(
      "/tmp/proj/.flow/rule-cache/eval-log.jsonl",
    );
  });

  test("focusHash is order-independent", () => {
    expect(focusHash(["a", "b"])).toBe(focusHash(["b", "a"]));
  });

  test("focusHash empty list", () => {
    const h = focusHash([]);
    expect(h).toMatch(/^[0-9a-f]{16}$/);
  });

  test("deriveCacheKey strips .md and joins with hash", () => {
    const { key, focusHash: fh } = deriveCacheKey("rebuild.md", ["x"]);
    expect(key).toBe(`rebuild__${fh}`);
    expect(fh).toMatch(/^[0-9a-f]{16}$/);
  });

  test("deriveCacheKey handles basename with path", () => {
    const { key } = deriveCacheKey("/abs/path/foo.md", []);
    expect(key.startsWith("foo__")).toBe(true);
  });

  test("stateFilePath", () => {
    expect(stateFilePath("k", "/tmp/proj")).toBe(
      "/tmp/proj/.flow/rule-cache/k.json",
    );
  });

  test("lockDirPath", () => {
    expect(lockDirPath("k", "/tmp/proj")).toBe(
      "/tmp/proj/.flow/rule-cache/k.json.lock",
    );
  });
});
