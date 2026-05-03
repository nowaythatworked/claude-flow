import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { formatStatus } from "../src/status.ts";
import { writeState, initState } from "../src/cache.ts";
import {
  cacheDir,
  deriveCacheKey,
  deriveSessionCacheKey,
  evalLogPath,
  lockDirPath,
} from "../src/paths.ts";
import { appendInjected } from "../src/injected-ledger.ts";
import type { CacheState, EvalLogEntry, LockInfo } from "../src/types.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-status-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

const TASK = "task.md";
const FOCUS: string[] = ["x"];

function seedState(mut?: (s: CacheState) => void): void {
  const s = initState(TASK, FOCUS, tmp);
  s.task_type = "ui";
  s.trigger_reason = "user-prompt-submit-sync";
  s.last_eval_ts = new Date(Date.now() - 5_000).toISOString();
  s.last_eval_duration_ms = 42;
  if (mut) mut(s);
  const { key } = deriveCacheKey(TASK, FOCUS);
  writeState(key, s, tmp);
}

function writeLogEntries(n: number): void {
  fs.mkdirSync(cacheDir(tmp), { recursive: true });
  const lines: string[] = [];
  for (let i = 0; i < n; i++) {
    const entry: EvalLogEntry = {
      ts: new Date(Date.now() - (n - i) * 1000).toISOString(),
      trigger_reason: `r${i}`,
      task_type: "",
      selected_via_pattern: [],
      selected_via_keyword: [],
      selected_via_llm: [],
      duration_ms: i,
      digest_chars: 0,
      watermark_uuid: null,
    };
    lines.push(JSON.stringify(entry));
  }
  fs.writeFileSync(evalLogPath(tmp), `${lines.join("\n")}\n`);
}

describe("formatStatus", () => {
  test("empty state: returns (no state)", () => {
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out.trim()).toBe("(no state)");
  });

  test("empty state, brief: returns (no state)", () => {
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: true,
    });
    expect(out.trim()).toBe("(no state)");
  });

  test("default mode: all three selection arrays grouped under headings", () => {
    seedState((s) => {
      s.selected_via_pattern = ["rule-a.md", "rule-b.md"];
      s.selected_via_keyword = ["rule-c.md"];
      s.selected_via_llm = ["rule-d.md", "rule-e.md"];
    });
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out).toContain("Selected rules (5):");
    expect(out).toContain("via pattern: rule-a.md, rule-b.md");
    expect(out).toContain("via keyword: rule-c.md");
    expect(out).toContain("via llm:     rule-d.md, rule-e.md");
    expect(out).toContain("Task type: ui");
  });

  test("default mode: no rules selected → 'Selected rules: none'", () => {
    seedState();
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out).toContain("Selected rules: none");
  });

  test("brief: single line, counts add up", () => {
    seedState((s) => {
      s.selected_via_pattern = ["a.md", "b.md"];
      s.selected_via_keyword = ["c.md"];
      s.selected_via_llm = ["d.md"];
    });
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: true,
    });
    const trimmed = out.trim();
    expect(trimmed.split("\n").length).toBe(1);
    expect(trimmed).toContain("4 rules selected");
    expect(trimmed).toContain("2 pattern");
    expect(trimmed).toContain("1 keyword");
    expect(trimmed).toContain("1 llm");
    expect(trimmed).toContain("last eval");
    expect(trimmed).toContain("ago");
  });

  test("lock present: default output reports PID", () => {
    seedState();
    const { key } = deriveCacheKey(TASK, FOCUS);
    const dir = lockDirPath(key, tmp);
    fs.mkdirSync(dir, { recursive: true });
    const info: LockInfo = {
      pid: 12345,
      started_at: new Date(Date.now() - 3_000).toISOString(),
      trigger: "test",
      session_id: "s1",
      covers_up_to_uuid: "uuid-x",
    };
    fs.writeFileSync(path.join(dir, "info.json"), JSON.stringify(info));
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out).toContain("Lock: held by PID 12345");
    expect(out).toContain("uuid-x");
  });

  test("eval log with 7 entries: only last 5 shown", () => {
    seedState();
    writeLogEntries(7);
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out).toContain("Recent eval log");
    expect(out).toContain("r2");
    expect(out).toContain("r3");
    expect(out).toContain("r4");
    expect(out).toContain("r5");
    expect(out).toContain("r6");
    expect(out).not.toContain(" r0 ");
    expect(out).not.toContain(" r1 ");
  });

  test("empty eval log: 'Recent eval log: empty'", () => {
    seedState();
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out).toContain("Recent eval log: empty");
  });

  test("injected ledger with N entries: count reported", () => {
    seedState();
    appendInjected("sess-x", TASK, "deadbeef", ["r1.md", "r2.md"], tmp);
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: "sess-x",
      brief: false,
    });
    expect(out).toContain("Injected ledger (this session): 2 rule(s) already injected");
  });

  test("session id passed but no ledger file: 'Injected ledger: empty'", () => {
    seedState();
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: "sess-none",
      brief: false,
    });
    expect(out).toContain("Injected ledger: empty");
  });

  test("no session id: ledger section omitted", () => {
    seedState();
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out).not.toContain("Injected ledger");
  });

  test("default: 'Lock: not held' when no lock dir", () => {
    seedState();
    const out = formatStatus({
      cwd: tmp,
      taskFile: TASK,
      focus: FOCUS,
      sessionId: null,
      brief: false,
    });
    expect(out).toContain("Lock: not held");
  });

  test("vanilla session: empty taskFile/focus → uses session__<id> key", () => {
    const sid = "vanilla-status-1";
    // Seed state under session__-keyed cache.
    const s = initState("", [], tmp);
    s.task_type = "ad-hoc";
    s.trigger_reason = "user-prompt-submit-sync:vanilla";
    s.last_eval_ts = new Date(Date.now() - 5_000).toISOString();
    s.last_eval_duration_ms = 17;
    s.selected_via_keyword = ["foo.md"];
    const { key } = deriveSessionCacheKey(sid);
    writeState(key, s, tmp);

    const out = formatStatus({
      cwd: tmp,
      taskFile: "",
      focus: [],
      sessionId: sid,
      brief: false,
    });
    expect(out).toContain(`session__${sid}.json`);
    expect(out).toContain("via keyword: foo.md");
    expect(out).toContain("Task type: ad-hoc");
  });

  test("vanilla session: brief output uses session__<id> key", () => {
    const sid = "vanilla-status-brief";
    const s = initState("", [], tmp);
    s.last_eval_ts = new Date(Date.now() - 1_000).toISOString();
    s.selected_via_pattern = ["a.md"];
    const { key } = deriveSessionCacheKey(sid);
    writeState(key, s, tmp);

    const out = formatStatus({
      cwd: tmp,
      taskFile: "",
      focus: [],
      sessionId: sid,
      brief: true,
    });
    const trimmed = out.trim();
    expect(trimmed.split("\n").length).toBe(1);
    expect(trimmed).toContain("1 rules selected");
    expect(trimmed).toContain("1 pattern");
  });
});
