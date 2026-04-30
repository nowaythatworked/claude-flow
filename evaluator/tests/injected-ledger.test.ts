import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  appendInjected,
  clearInjectedLedger,
  injectedLedgerDir,
  injectedLedgerPath,
  readInjectedLedger,
} from "../src/injected-ledger.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-ledger-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("injected-ledger", () => {
  test("readInjectedLedger returns [] when missing", () => {
    expect(readInjectedLedger("sess-x", tmp)).toEqual([]);
  });

  test("injectedLedgerDir is .flow/rule-cache/injected", () => {
    expect(injectedLedgerDir(tmp)).toBe(
      path.join(tmp, ".flow", "rule-cache", "injected"),
    );
  });

  test("injectedLedgerPath includes session id", () => {
    expect(injectedLedgerPath("sess-x", tmp)).toBe(
      path.join(tmp, ".flow", "rule-cache", "injected", "sess-x.json"),
    );
  });

  test("append + read roundtrip", () => {
    appendInjected("sess-x", "task.md", "fh1", ["a.md", "b.md"], tmp);
    expect(readInjectedLedger("sess-x", tmp)).toEqual(["a.md", "b.md"]);
  });

  test("append is idempotent: appending same IDs twice does not change file content", () => {
    appendInjected("sess-x", "task.md", "fh1", ["a.md", "b.md"], tmp);
    const before = fs.readFileSync(
      injectedLedgerPath("sess-x", tmp),
      "utf8",
    );
    appendInjected("sess-x", "task.md", "fh1", ["a.md", "b.md"], tmp);
    const after = fs.readFileSync(
      injectedLedgerPath("sess-x", tmp),
      "utf8",
    );
    expect(after).toBe(before);
  });

  test("preserves order: existing IDs come first, new appended", () => {
    appendInjected("sess-x", "task.md", "fh1", ["a.md", "b.md"], tmp);
    appendInjected("sess-x", "task.md", "fh1", ["b.md", "c.md", "a.md", "d.md"], tmp);
    expect(readInjectedLedger("sess-x", tmp)).toEqual([
      "a.md",
      "b.md",
      "c.md",
      "d.md",
    ]);
  });

  test("atomic write: no .tmp.* leftover in injected/", () => {
    appendInjected("sess-x", "task.md", "fh1", ["a.md"], tmp);
    const dir = injectedLedgerDir(tmp);
    const entries = fs.readdirSync(dir).filter((f) => f.includes(".tmp."));
    expect(entries).toEqual([]);
  });

  test("clearInjectedLedger removes file", () => {
    appendInjected("sess-x", "task.md", "fh1", ["a.md"], tmp);
    expect(fs.existsSync(injectedLedgerPath("sess-x", tmp))).toBe(true);
    clearInjectedLedger("sess-x", tmp);
    expect(fs.existsSync(injectedLedgerPath("sess-x", tmp))).toBe(false);
  });

  test("clearInjectedLedger no-op on missing file", () => {
    expect(() => clearInjectedLedger("sess-x", tmp)).not.toThrow();
  });

  test("invalid JSON returns []", () => {
    fs.mkdirSync(injectedLedgerDir(tmp), { recursive: true });
    fs.writeFileSync(injectedLedgerPath("sess-x", tmp), "not json{");
    expect(readInjectedLedger("sess-x", tmp)).toEqual([]);
  });

  test("schema_version mismatch returns []", () => {
    fs.mkdirSync(injectedLedgerDir(tmp), { recursive: true });
    fs.writeFileSync(
      injectedLedgerPath("sess-x", tmp),
      JSON.stringify({
        schema_version: 999,
        session_id: "sess-x",
        task_file: "task.md",
        focus_hash: "fh1",
        injected_rule_ids: ["a.md"],
        last_injection_ts: "2026-01-01T00:00:00Z",
      }),
    );
    expect(readInjectedLedger("sess-x", tmp)).toEqual([]);
  });

  test("missing fields returns []", () => {
    fs.mkdirSync(injectedLedgerDir(tmp), { recursive: true });
    fs.writeFileSync(injectedLedgerPath("sess-x", tmp), "{}");
    expect(readInjectedLedger("sess-x", tmp)).toEqual([]);
  });

  test("appendInjected with no actually-new IDs is a no-op (no file written)", () => {
    appendInjected("sess-x", "task.md", "fh1", [], tmp);
    expect(fs.existsSync(injectedLedgerPath("sess-x", tmp))).toBe(false);
  });

  test("creates injected/ dir on first append", () => {
    expect(fs.existsSync(injectedLedgerDir(tmp))).toBe(false);
    appendInjected("sess-x", "task.md", "fh1", ["a.md"], tmp);
    expect(fs.existsSync(injectedLedgerDir(tmp))).toBe(true);
  });
});
