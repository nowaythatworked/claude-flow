import { test, expect, describe, beforeEach, afterEach } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  acquireLock,
  inspectLock,
  waitForRelease,
} from "../src/lock.ts";
import { lockDirPath } from "../src/paths.ts";
import type { LockInfo } from "../src/types.ts";

let tmp: string;

beforeEach(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "flow-rules-test-"));
});

afterEach(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

function info(): LockInfo {
  return {
    pid: process.pid,
    started_at: new Date().toISOString(),
    trigger: "test",
    session_id: "s1",
    covers_up_to_uuid: null,
  };
}

describe("lock", () => {
  test("acquire then release", () => {
    const h = acquireLock("k", tmp, info());
    expect(h).not.toBeNull();
    h?.release();
    expect(fs.existsSync(lockDirPath("k", tmp))).toBe(false);
  });

  test("contention: second acquire returns null", () => {
    const a = acquireLock("k", tmp, info());
    expect(a).not.toBeNull();
    const b = acquireLock("k", tmp, info());
    expect(b).toBeNull();
    a?.release();
  });

  test("inspectLock returns null when no lock", () => {
    expect(inspectLock("k", tmp)).toBeNull();
  });

  test("inspectLock reads info.json fields", () => {
    const i = info();
    i.covers_up_to_uuid = "uuid-1";
    const a = acquireLock("k", tmp, i);
    expect(a).not.toBeNull();
    const insp = inspectLock("k", tmp);
    expect(insp?.pid).toBe(process.pid);
    expect(insp?.coversUpToUuid).toBe("uuid-1");
    expect(insp?.fresh).toBe(true);
    a?.release();
  });

  test("stale lock (old timestamp + dead pid) is reaped on next acquire", () => {
    const dir = lockDirPath("k", tmp);
    fs.mkdirSync(dir, { recursive: true });
    const stale: LockInfo = {
      pid: 999999, // unlikely to exist
      started_at: new Date(Date.now() - 200_000).toISOString(),
      trigger: "test",
      session_id: "s1",
      covers_up_to_uuid: null,
    };
    fs.writeFileSync(path.join(dir, "info.json"), JSON.stringify(stale));
    const insp = inspectLock("k", tmp);
    expect(insp?.fresh).toBe(false);
    const h = acquireLock("k", tmp, info());
    expect(h).not.toBeNull();
    h?.release();
  });

  test("waitForRelease returns true once lock is released", async () => {
    const a = acquireLock("k", tmp, info());
    expect(a).not.toBeNull();
    setTimeout(() => a?.release(), 150);
    const ok = await waitForRelease("k", tmp, 2000);
    expect(ok).toBe(true);
  });

  test("waitForRelease times out", async () => {
    const a = acquireLock("k", tmp, info());
    expect(a).not.toBeNull();
    const ok = await waitForRelease("k", tmp, 250);
    expect(ok).toBe(false);
    a?.release();
  });

  test("release is idempotent", () => {
    const h = acquireLock("k", tmp, info());
    expect(h).not.toBeNull();
    h?.release();
    h?.release();
    expect(fs.existsSync(lockDirPath("k", tmp))).toBe(false);
  });
});
