import * as fs from "node:fs";
import { evalLogPath, cacheDir } from "./paths.ts";
import type { EvalLogEntry } from "./types.ts";

export function appendLog(cwd: string, entry: EvalLogEntry): void {
  fs.mkdirSync(cacheDir(cwd), { recursive: true });
  fs.appendFileSync(evalLogPath(cwd), `${JSON.stringify(entry)}\n`);
}
