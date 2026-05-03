import { createHash } from "node:crypto";
import * as path from "node:path";

export function resolvePluginRoot(args: string[]): string {
  const flagIdx = args.indexOf("--plugin-root");
  if (flagIdx >= 0 && flagIdx + 1 < args.length) {
    const v = args[flagIdx + 1];
    if (v) return path.resolve(v);
  }
  const env = process.env.CLAUDE_PLUGIN_ROOT;
  if (env) return path.resolve(env);
  return path.resolve(import.meta.dir, "..");
}

export function cacheDir(cwd: string): string {
  return path.join(cwd, ".flow", "rule-cache");
}

export function dynamicRulesDir(cwd: string): string {
  return path.join(cwd, ".flow", "rules", "dynamic");
}

export function evalLogPath(cwd: string): string {
  return path.join(cacheDir(cwd), "eval-log.jsonl");
}

export function focusHash(focus: string[]): string {
  const sorted = [...focus].sort();
  return createHash("sha1").update(sorted.join("\n")).digest("hex").slice(0, 16);
}

export function deriveCacheKey(
  taskFile: string,
  focus: string[],
): { key: string; focusHash: string } {
  const base = path.basename(taskFile, path.extname(taskFile));
  const fh = focusHash(focus);
  return { key: `${base}__${fh}`, focusHash: fh };
}

/**
 * Derive a cache key for vanilla (non-flow) Claude Code sessions where
 * SESSIONS.json has no entry for the current session. Each vanilla session
 * gets its own cache file keyed by full session id, preventing cross-session
 * leak of rule selections within the same project.
 */
export function deriveSessionCacheKey(sessionId: string): { key: string } {
  return { key: `session__${sessionId}` };
}

export function stateFilePath(cacheKey: string, cwd: string): string {
  return path.join(cacheDir(cwd), `${cacheKey}.json`);
}

export function lockDirPath(cacheKey: string, cwd: string): string {
  return path.join(cacheDir(cwd), `${cacheKey}.json.lock`);
}
