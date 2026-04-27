import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  appendPendingSignal,
  drainPendingSignals,
  truncatePendingSignals,
  pendingSignalsPath,
} from "../src/pending-signals.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-signals-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("pending-signals", () => {
  test("append creates file with valid JSONL line", () => {
    appendPendingSignal(tmp, {
      ts: "2026-04-25T00:00:00.000Z",
      path: "/proj/src/a.ts",
      tool: "Read",
      session_id: "sess1",
    });
    const raw = fs.readFileSync(pendingSignalsPath(tmp), "utf8");
    expect(raw).toBe(
      `{"ts":"2026-04-25T00:00:00.000Z","path":"/proj/src/a.ts","tool":"Read","session_id":"sess1"}\n`,
    );
  });

  test("multiple appends accumulate", () => {
    appendPendingSignal(tmp, {
      ts: "1",
      path: "/p/a.ts",
      tool: "Read",
      session_id: "s",
    });
    appendPendingSignal(tmp, {
      ts: "2",
      path: "/p/b.ts",
      tool: "Edit",
      session_id: "s",
    });
    const lines = fs
      .readFileSync(pendingSignalsPath(tmp), "utf8")
      .trim()
      .split("\n");
    expect(lines).toHaveLength(2);
  });

  test("drain reads parsed entries; tolerates malformed lines", () => {
    const p = pendingSignalsPath(tmp);
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(
      p,
      [
        `{"ts":"1","path":"/p/a.ts","tool":"Read","session_id":"s"}`,
        `not json`,
        `{"ts":"2","path":"/p/b.ts","tool":"Edit","session_id":"s"}`,
        ``,
      ].join("\n"),
    );
    const drained = drainPendingSignals(tmp);
    expect(drained.map((d) => d.path)).toEqual(["/p/a.ts", "/p/b.ts"]);
    expect(drained[0]?.tool).toBe("Read");
    expect(drained[1]?.tool).toBe("Edit");
  });

  test("drain returns [] when file does not exist", () => {
    expect(drainPendingSignals(tmp)).toEqual([]);
  });

  test("truncate atomically clears the file", () => {
    appendPendingSignal(tmp, {
      ts: "1",
      path: "/p/a.ts",
      tool: "Read",
      session_id: "s",
    });
    truncatePendingSignals(tmp);
    expect(fs.existsSync(pendingSignalsPath(tmp))).toBe(true);
    expect(fs.readFileSync(pendingSignalsPath(tmp), "utf8")).toBe("");
  });

  test("path is under .flow/rule-cache/", () => {
    expect(pendingSignalsPath(tmp)).toBe(
      path.join(tmp, ".flow", "rule-cache", "pending-signals.jsonl"),
    );
  });
});
