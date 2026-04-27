import { test, expect, describe } from "bun:test";
import { buildClaudeArgs } from "../src/haiku.ts";

describe("buildClaudeArgs", () => {
  test("includes --max-turns 3", () => {
    const args = buildClaudeArgs();
    const idx = args.indexOf("--max-turns");
    expect(idx).toBeGreaterThanOrEqual(0);
    expect(args[idx + 1]).toBe("3");
  });

  test("uses haiku model", () => {
    const args = buildClaudeArgs();
    const idx = args.indexOf("--model");
    expect(args[idx + 1]).toBe("haiku");
  });

  test("includes --json-schema and --no-session-persistence", () => {
    const args = buildClaudeArgs();
    expect(args).toContain("--json-schema");
    expect(args).toContain("--no-session-persistence");
  });

  test("output format is json", () => {
    const args = buildClaudeArgs();
    const idx = args.indexOf("--output-format");
    expect(args[idx + 1]).toBe("json");
  });
});
