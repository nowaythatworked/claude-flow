import * as fs from "node:fs";
import type { ExtractedContent, ExtractedEditEntry } from "./types.ts";

interface ToolUseRef {
  id: string;
  name: string;
  input: ToolInput;
}

interface ToolInput {
  file_path?: string;
  old_string?: string;
  new_string?: string;
}

export function extractSinceWatermark(
  transcriptPath: string,
  watermarkUuid: string | null,
): ExtractedContent {
  const reads = new Map<string, string>();
  const edits = new Map<string, ExtractedEditEntry[]>();
  const globResults: string[][] = [];
  const recentUserText: string[] = [];
  const recentAssistantText: string[] = [];
  let newWatermarkCandidate = "";

  if (!fs.existsSync(transcriptPath)) {
    return {
      filesInScope: { reads, edits },
      globResults,
      recentUserText,
      recentAssistantText,
      newWatermarkCandidate: watermarkUuid ?? "",
    };
  }

  const raw = fs.readFileSync(transcriptPath, "utf8");
  const lines = raw.split("\n");
  const toolUseById = new Map<string, ToolUseRef>();

  let pastWatermark = watermarkUuid === null;

  for (const line of lines) {
    if (line.trim() === "") continue;
    let entry: unknown;
    try {
      entry = JSON.parse(line);
    } catch {
      continue;
    }
    if (typeof entry !== "object" || entry === null) continue;

    const uuid = getString(entry, "uuid");
    if (uuid === undefined) continue;

    if (!pastWatermark) {
      if (uuid === watermarkUuid) {
        pastWatermark = true;
      }
      continue;
    }

    newWatermarkCandidate = uuid;
    const type = getString(entry, "type");
    if (type === "assistant") {
      processAssistant(entry, toolUseById, recentAssistantText);
    } else if (type === "user") {
      processUser(
        entry,
        toolUseById,
        reads,
        edits,
        globResults,
        recentUserText,
      );
    }
  }

  capLast(recentUserText, 5);
  capLast(recentAssistantText, 5);

  return {
    filesInScope: { reads, edits },
    globResults,
    recentUserText,
    recentAssistantText,
    newWatermarkCandidate: newWatermarkCandidate || (watermarkUuid ?? ""),
  };
}

function processAssistant(
  entry: object,
  toolUseById: Map<string, ToolUseRef>,
  recentAssistantText: string[],
): void {
  const message = Reflect.get(entry, "message");
  if (typeof message !== "object" || message === null) return;
  const content = Reflect.get(message, "content");
  if (!Array.isArray(content)) return;
  const textParts: string[] = [];
  for (const part of content) {
    if (typeof part !== "object" || part === null) continue;
    const ptype = Reflect.get(part, "type");
    if (ptype === "text") {
      const t = Reflect.get(part, "text");
      if (typeof t === "string") textParts.push(t);
    } else if (ptype === "tool_use") {
      const id = Reflect.get(part, "id");
      const name = Reflect.get(part, "name");
      const inputRaw = Reflect.get(part, "input");
      if (typeof id !== "string" || typeof name !== "string") continue;
      const input: ToolInput = {};
      if (typeof inputRaw === "object" && inputRaw !== null) {
        const fp = Reflect.get(inputRaw, "file_path");
        const os = Reflect.get(inputRaw, "old_string");
        const ns = Reflect.get(inputRaw, "new_string");
        if (typeof fp === "string") input.file_path = fp;
        if (typeof os === "string") input.old_string = os;
        if (typeof ns === "string") input.new_string = ns;
      }
      toolUseById.set(id, { id, name, input });
    }
  }
  if (textParts.length > 0) {
    recentAssistantText.push(textParts.join("\n"));
  }
}

function processUser(
  entry: object,
  toolUseById: Map<string, ToolUseRef>,
  reads: Map<string, string>,
  edits: Map<string, ExtractedEditEntry[]>,
  globResults: string[][],
  recentUserText: string[],
): void {
  const message = Reflect.get(entry, "message");
  if (typeof message !== "object" || message === null) return;
  const content = Reflect.get(message, "content");
  if (typeof content === "string") {
    if (isUserTypedString(content)) {
      recentUserText.push(content);
    }
    return;
  }
  if (!Array.isArray(content)) return;

  let sawToolResult = false;
  const textChunks: string[] = [];
  for (const part of content) {
    if (typeof part !== "object" || part === null) continue;
    const ptype = Reflect.get(part, "type");
    if (ptype === "tool_result") {
      sawToolResult = true;
      const toolUseId = Reflect.get(part, "tool_use_id");
      const resultContent = Reflect.get(part, "content");
      if (typeof toolUseId !== "string") continue;
      const ref = toolUseById.get(toolUseId);
      if (!ref) continue;
      const resultStr = stringifyResultContent(resultContent);
      if (ref.name === "Read") {
        if (ref.input.file_path !== undefined && resultStr !== null) {
          reads.set(ref.input.file_path, resultStr);
        }
      } else if (ref.name === "Edit") {
        if (
          ref.input.file_path !== undefined &&
          ref.input.old_string !== undefined &&
          ref.input.new_string !== undefined
        ) {
          const arr = edits.get(ref.input.file_path) ?? [];
          arr.push({
            old: ref.input.old_string,
            new: ref.input.new_string,
          });
          edits.set(ref.input.file_path, arr);
        }
      } else if (ref.name === "Glob" || ref.name === "Grep") {
        if (resultStr !== null) {
          globResults.push(parseGlobResult(resultStr));
        }
      }
    } else if (ptype === "text") {
      const t = Reflect.get(part, "text");
      if (typeof t === "string") textChunks.push(t);
    }
  }
  if (!sawToolResult && textChunks.length > 0) {
    const joined = textChunks.join("\n");
    if (isUserTypedString(joined)) recentUserText.push(joined);
  }
}

function isUserTypedString(s: string): boolean {
  if (s.includes("<command-name>")) return false;
  if (s.includes("<local-command-")) return false;
  if (s.includes("<system-reminder>")) return false;
  if (s.trim() === "") return false;
  return true;
}

function stringifyResultContent(c: unknown): string | null {
  if (typeof c === "string") return c;
  if (Array.isArray(c)) {
    const parts: string[] = [];
    for (const p of c) {
      if (typeof p === "object" && p !== null) {
        const t = Reflect.get(p, "text");
        if (typeof t === "string") parts.push(t);
      }
    }
    return parts.join("\n");
  }
  return null;
}

function parseGlobResult(s: string): string[] {
  const lines = s.split("\n").map((l) => l.trim()).filter((l) => l !== "");
  return lines.filter((l) => !/^Found \d+ /i.test(l) && !/^No files/i.test(l));
}

function getString(v: unknown, key: string): string | undefined {
  if (typeof v !== "object" || v === null) return undefined;
  const x = Reflect.get(v, key);
  return typeof x === "string" ? x : undefined;
}

function capLast<T>(arr: T[], n: number): void {
  if (arr.length > n) {
    arr.splice(0, arr.length - n);
  }
}
