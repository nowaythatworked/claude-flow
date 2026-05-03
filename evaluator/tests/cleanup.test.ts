import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { runCleanup } from "../src/cleanup.ts";
import {
  cacheDir,
  evalLogPath,
  lockDirPath,
  deriveCacheKey,
} from "../src/paths.ts";
import { injectedLedgerDir } from "../src/injected-ledger.ts";
import { pendingSignalsPath } from "../src/pending-signals.ts";
import type { SessionRecord } from "../src/sessions.ts";
import type { LockInfo } from "../src/types.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-cleanup-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function writeSessions(sessions: Record<string, SessionRecord>): void {
  fs.mkdirSync(path.join(tmp, ".flow"), { recursive: true });
  fs.writeFileSync(
    path.join(tmp, ".flow", "SESSIONS.json"),
    JSON.stringify(sessions),
  );
}

function liveSession(taskFile: string, focus: string[]): SessionRecord {
  return {
    phase: "implementing",
    task_file: taskFile,
    focus,
    parent: null,
  };
}

function writeSubagentCache(
  parentId: string,
  agentId: string,
): string {
  fs.mkdirSync(cacheDir(tmp), { recursive: true });
  const p = path.join(cacheDir(tmp), `sub__${parentId}__${agentId}.json`);
  fs.writeFileSync(p, "{}");
  return p;
}

function writeInjectedLedger(sessionId: string): string {
  fs.mkdirSync(injectedLedgerDir(tmp), { recursive: true });
  const p = path.join(injectedLedgerDir(tmp), `${sessionId}.json`);
  fs.writeFileSync(p, "{}");
  return p;
}

function writeLockDir(
  taskFile: string,
  focus: string[],
  ageSeconds: number,
  pid: number,
): string {
  const { key } = deriveCacheKey(taskFile, focus);
  const dir = lockDirPath(key, tmp);
  fs.mkdirSync(dir, { recursive: true });
  const info: LockInfo = {
    pid,
    started_at: new Date(Date.now() - ageSeconds * 1000).toISOString(),
    trigger: "test",
    session_id: "s",
    covers_up_to_uuid: null,
  };
  fs.writeFileSync(path.join(dir, "info.json"), JSON.stringify(info));
  return dir;
}

function writeEvalLog(numLines: number): void {
  fs.mkdirSync(cacheDir(tmp), { recursive: true });
  const lines: string[] = [];
  for (let i = 0; i < numLines; i++) {
    lines.push(JSON.stringify({ idx: i }));
  }
  fs.writeFileSync(evalLogPath(tmp), `${lines.join("\n")}\n`);
}

function writePendingSignals(numLines: number): void {
  fs.mkdirSync(cacheDir(tmp), { recursive: true });
  const lines: string[] = [];
  for (let i = 0; i < numLines; i++) {
    lines.push(JSON.stringify({ idx: i }));
  }
  fs.writeFileSync(pendingSignalsPath(tmp), `${lines.join("\n")}\n`);
}

const DEFAULTS = {
  maxEvalLog: 1000,
  maxPendingSignals: 100,
  maxVanillaCacheAgeDays: 5,
};

function writeVanillaCache(sessionId: string, ageDays: number): string {
  fs.mkdirSync(cacheDir(tmp), { recursive: true });
  const p = path.join(cacheDir(tmp), `session__${sessionId}.json`);
  fs.writeFileSync(p, "{}");
  if (ageDays > 0) {
    const past = Date.now() - ageDays * 24 * 60 * 60 * 1000;
    const seconds = past / 1000;
    fs.utimesSync(p, seconds, seconds);
  }
  return p;
}

describe("runCleanup", () => {
  test("orphan subagent cache (parent not in SESSIONS.json) is deleted", () => {
    writeSessions({ "live-parent": liveSession("t.md", []) });
    const orphan = writeSubagentCache("dead-parent", "agent-1");
    const live = writeSubagentCache("live-parent", "agent-1");

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.subagentCachesDeleted).toContain(
      "sub__dead-parent__agent-1.json",
    );
    expect(report.subagentCachesDeleted).not.toContain(
      "sub__live-parent__agent-1.json",
    );
    expect(fs.existsSync(orphan)).toBe(false);
    expect(fs.existsSync(live)).toBe(true);
  });

  test("orphan injected ledger is deleted, live one kept", () => {
    writeSessions({ "live-sess": liveSession("t.md", []) });
    const orphan = writeInjectedLedger("dead-sess");
    const live = writeInjectedLedger("live-sess");

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.injectedLedgersDeleted).toContain("dead-sess.json");
    expect(report.injectedLedgersDeleted).not.toContain("live-sess.json");
    expect(fs.existsSync(orphan)).toBe(false);
    expect(fs.existsSync(live)).toBe(true);
  });

  test("fresh lock dir (<90s) is kept, stale dead-pid lock is reaped", () => {
    writeSessions({});
    const fresh = writeLockDir("fresh.md", [], 5, process.pid);
    // dead pid + old timestamp → stale
    const stale = writeLockDir("stale.md", [], 200, 999_999);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.staleLocksReaped.length).toBe(1);
    expect(report.staleLocksReaped[0]).toContain("stale");
    expect(fs.existsSync(fresh)).toBe(true);
    expect(fs.existsSync(stale)).toBe(false);
  });

  test("eval log over limit is truncated to last N lines", () => {
    writeSessions({});
    writeEvalLog(1500);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.evalLogTruncated.from).toBe(1500);
    expect(report.evalLogTruncated.to).toBe(1000);
    const after = fs
      .readFileSync(evalLogPath(tmp), "utf8")
      .split("\n")
      .filter((l) => l !== "");
    expect(after.length).toBe(1000);
    // first line is original idx=500
    const first: unknown = JSON.parse(after[0] ?? "{}");
    if (typeof first !== "object" || first === null) {
      throw new Error("expected object");
    }
    expect(Reflect.get(first, "idx")).toBe(500);
  });

  test("eval log under limit is untouched", () => {
    writeSessions({});
    writeEvalLog(50);
    const before = fs.readFileSync(evalLogPath(tmp), "utf8");

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.evalLogTruncated.from).toBe(50);
    expect(report.evalLogTruncated.to).toBe(50);
    expect(fs.readFileSync(evalLogPath(tmp), "utf8")).toBe(before);
  });

  test("pending signals over limit is truncated", () => {
    writeSessions({});
    writePendingSignals(500);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.pendingSignalsTruncated.from).toBe(500);
    expect(report.pendingSignalsTruncated.to).toBe(100);
    const after = fs
      .readFileSync(pendingSignalsPath(tmp), "utf8")
      .split("\n")
      .filter((l) => l !== "");
    expect(after.length).toBe(100);
  });

  test("missing SESSIONS.json: no orphans, everything kept", () => {
    // No writeSessions call
    const sub = writeSubagentCache("any-parent", "a1");
    const ledger = writeInjectedLedger("any-sess");

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.subagentCachesDeleted).toEqual([]);
    expect(report.injectedLedgersDeleted).toEqual([]);
    expect(fs.existsSync(sub)).toBe(true);
    expect(fs.existsSync(ledger)).toBe(true);
  });

  test("dry run: report shape matches but no files modified", () => {
    writeSessions({ "live-sess": liveSession("t.md", []) });
    const orphanSub = writeSubagentCache("dead-parent", "agent-1");
    const orphanLedger = writeInjectedLedger("dead-sess");
    const stale = writeLockDir("stale.md", [], 200, 999_999);
    writeEvalLog(1500);
    writePendingSignals(500);

    const report = runCleanup({
      cwd: tmp,
      dryRun: true,
      ...DEFAULTS,
    });

    expect(report.subagentCachesDeleted).toContain(
      "sub__dead-parent__agent-1.json",
    );
    expect(report.injectedLedgersDeleted).toContain("dead-sess.json");
    expect(report.staleLocksReaped.length).toBe(1);
    expect(report.evalLogTruncated.from).toBe(1500);
    expect(report.evalLogTruncated.to).toBe(1000);
    expect(report.pendingSignalsTruncated.from).toBe(500);
    expect(report.pendingSignalsTruncated.to).toBe(100);

    // Verify no file modifications
    expect(fs.existsSync(orphanSub)).toBe(true);
    expect(fs.existsSync(orphanLedger)).toBe(true);
    expect(fs.existsSync(stale)).toBe(true);
    const evalLines = fs
      .readFileSync(evalLogPath(tmp), "utf8")
      .split("\n")
      .filter((l) => l !== "");
    expect(evalLines.length).toBe(1500);
    const sigLines = fs
      .readFileSync(pendingSignalsPath(tmp), "utf8")
      .split("\n")
      .filter((l) => l !== "");
    expect(sigLines.length).toBe(500);
  });

  test("malformed subagent file name (no parent id parseable) is skipped", () => {
    writeSessions({ "live-sess": liveSession("t.md", []) });
    fs.mkdirSync(cacheDir(tmp), { recursive: true });
    const weird = path.join(cacheDir(tmp), "sub__only-one-segment.json");
    fs.writeFileSync(weird, "{}");

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    // Should NOT delete files we can't parse the parent from
    expect(report.subagentCachesDeleted).not.toContain(
      "sub__only-one-segment.json",
    );
    expect(fs.existsSync(weird)).toBe(true);
  });

  test("stale vanilla cache (mtime > N days) is reaped", () => {
    writeSessions({});
    const stale = writeVanillaCache("dead-vanilla", 6);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.vanillaCachesDeleted).toContain(
      "session__dead-vanilla.json",
    );
    expect(fs.existsSync(stale)).toBe(false);
  });

  test("fresh vanilla cache (recent mtime) is kept", () => {
    writeSessions({});
    const fresh = writeVanillaCache("live-vanilla", 0);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.vanillaCachesDeleted).toEqual([]);
    expect(fs.existsSync(fresh)).toBe(true);
  });

  test("active lock on stale vanilla cache prevents reap", () => {
    writeSessions({});
    const sid = "locked-vanilla";
    const stale = writeVanillaCache(sid, 6);
    // Active lock with current PID + recent timestamp.
    const lockDir = path.join(
      cacheDir(tmp),
      `session__${sid}.json.lock`,
    );
    fs.mkdirSync(lockDir, { recursive: true });
    const info: LockInfo = {
      pid: process.pid,
      started_at: new Date().toISOString(),
      trigger: "test",
      session_id: sid,
      covers_up_to_uuid: null,
    };
    fs.writeFileSync(path.join(lockDir, "info.json"), JSON.stringify(info));

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.vanillaCachesDeleted).not.toContain(
      `session__${sid}.json`,
    );
    expect(fs.existsSync(stale)).toBe(true);
  });

  test("vanilla ledger paired with fresh cache is kept", () => {
    writeSessions({});
    const sid = "live-vanilla-ledger";
    writeVanillaCache(sid, 0);
    const ledger = writeInjectedLedger(sid);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.injectedLedgersDeleted).not.toContain(`${sid}.json`);
    expect(fs.existsSync(ledger)).toBe(true);
  });

  test("vanilla ledger paired with stale cache: both reaped together", () => {
    writeSessions({});
    const sid = "stale-vanilla-pair";
    const cache = writeVanillaCache(sid, 6);
    const ledger = writeInjectedLedger(sid);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.vanillaCachesDeleted).toContain(`session__${sid}.json`);
    expect(report.injectedLedgersDeleted).toContain(`${sid}.json`);
    expect(fs.existsSync(cache)).toBe(false);
    expect(fs.existsSync(ledger)).toBe(false);
  });

  test("dry-run vanilla cache: report mentions it but file remains", () => {
    writeSessions({});
    const stale = writeVanillaCache("would-die", 7);

    const report = runCleanup({
      cwd: tmp,
      dryRun: true,
      ...DEFAULTS,
    });

    expect(report.vanillaCachesDeleted).toContain(
      "session__would-die.json",
    );
    expect(fs.existsSync(stale)).toBe(true);
  });

  test("missing SESSIONS.json: vanilla caches still swept by mtime", () => {
    // No writeSessions call; vanilla cleanup is mtime-driven and runs
    // independent of SESSIONS.json (which only gates flow-orphan logic).
    const stale = writeVanillaCache("orphan-vanilla", 6);

    const report = runCleanup({
      cwd: tmp,
      dryRun: false,
      ...DEFAULTS,
    });

    expect(report.vanillaCachesDeleted).toContain(
      "session__orphan-vanilla.json",
    );
    expect(fs.existsSync(stale)).toBe(false);
  });
});
