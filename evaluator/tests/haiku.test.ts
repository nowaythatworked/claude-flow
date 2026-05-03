import { test, expect, describe } from "bun:test";
import { buildClaudeArgs, resolveEvalModel } from "../src/haiku.ts";

describe("buildClaudeArgs", () => {
  test("includes --max-turns 3", () => {
    const args = buildClaudeArgs();
    const idx = args.indexOf("--max-turns");
    expect(idx).toBeGreaterThanOrEqual(0);
    expect(args[idx + 1]).toBe("3");
  });

  test("defaults to haiku model", () => {
    const args = buildClaudeArgs();
    const idx = args.indexOf("--model");
    expect(args[idx + 1]).toBe("haiku");
  });

  test("uses sonnet when explicitly requested", () => {
    const args = buildClaudeArgs("sonnet");
    const idx = args.indexOf("--model");
    expect(args[idx + 1]).toBe("sonnet");
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

describe("resolveEvalModel", () => {
  test("returns sonnet for pre-approve-checkpoint", () => {
    expect(resolveEvalModel("pre-approve-checkpoint")).toBe("sonnet");
  });

  test("returns sonnet for pre-implement-checkpoint", () => {
    expect(resolveEvalModel("pre-implement-checkpoint")).toBe("sonnet");
  });

  test("returns haiku for routine async reasons", () => {
    expect(resolveEvalModel("user-prompt-submit-async")).toBe("haiku");
    expect(resolveEvalModel("pre-tool-use-async:Read")).toBe("haiku");
  });

  test("returns haiku for unknown reasons", () => {
    expect(resolveEvalModel("manual")).toBe("haiku");
    expect(resolveEvalModel("")).toBe("haiku");
    expect(resolveEvalModel("user-reload")).toBe("haiku");
  });
});
