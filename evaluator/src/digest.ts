import * as fs from "node:fs";
import type { ExtractedContent, LLMCatalogEntry } from "./types.ts";

const LARGE_BYTES = 30_000;
const HEAD_LINES = 300;
const TAIL_LINES = 50;
const FALLBACK_HEAD_LINES = 100;

export function buildDigest(
  extracted: ExtractedContent,
  currentSelection: string[],
  llmCatalog: LLMCatalogEntry[],
): string {
  const sections: string[] = [];
  sections.push(formatFilesSection(extracted));
  sections.push(formatGlobSection(extracted.globResults));
  sections.push(formatRecentUser(extracted.recentUserText));
  sections.push(formatRecentAssistant(extracted.recentAssistantText));
  sections.push(formatCurrentSelection(currentSelection));
  sections.push(formatLLMCatalog(llmCatalog));
  sections.push(
    "## Instructions\nBased on the activity above, select which rules from the LLM catalog should now apply. Return strict JSON matching the schema.",
  );
  return sections.filter((s) => s !== "").join("\n\n");
}

function formatFilesSection(extracted: ExtractedContent): string {
  const reads = extracted.filesInScope.reads;
  const edits = extracted.filesInScope.edits;
  if (reads.size === 0 && edits.size === 0) return "";
  const lines: string[] = ["## Files in scope"];

  for (const [filePath, content] of reads) {
    lines.push(`### Read: ${filePath}`);
    lines.push("```");
    lines.push(truncateContent(content));
    lines.push("```");
  }

  for (const [filePath, editList] of edits) {
    lines.push(`### Edit: ${filePath}`);
    if (!reads.has(filePath)) {
      const fallback = readFallback(filePath);
      if (fallback !== null) {
        lines.push(`(fallback read from disk, head ${FALLBACK_HEAD_LINES} lines)`);
        lines.push("```");
        lines.push(fallback);
        lines.push("```");
      }
    }
    for (const e of editList) {
      lines.push("Edit diff:");
      lines.push("```");
      lines.push(`OLD:\n${e.old}`);
      lines.push(`NEW:\n${e.new}`);
      lines.push("```");
    }
  }
  return lines.join("\n");
}

function truncateContent(content: string): string {
  const bytes = Buffer.byteLength(content, "utf8");
  if (bytes < LARGE_BYTES) return content;
  const lines = content.split("\n");
  if (lines.length <= HEAD_LINES + TAIL_LINES) return content;
  const head = lines.slice(0, HEAD_LINES);
  const tail = lines.slice(lines.length - TAIL_LINES);
  return [
    ...head,
    `... [truncated ${lines.length - HEAD_LINES - TAIL_LINES} lines] ...`,
    ...tail,
  ].join("\n");
}

function readFallback(filePath: string): string | null {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    const lines = raw.split("\n").slice(0, FALLBACK_HEAD_LINES);
    return lines.join("\n");
  } catch {
    return null;
  }
}

function formatGlobSection(globResults: string[][]): string {
  if (globResults.length === 0) return "";
  const lines: string[] = ["## Glob/Grep results"];
  for (let i = 0; i < globResults.length; i++) {
    const results = globResults[i];
    if (!results) continue;
    lines.push(`### Result ${i + 1}`);
    for (const path of results) lines.push(`- ${path}`);
  }
  return lines.join("\n");
}

function formatRecentUser(messages: string[]): string {
  if (messages.length === 0) return "";
  const lines: string[] = ["## Recent user messages"];
  for (const m of messages) {
    lines.push("---");
    lines.push(m);
  }
  return lines.join("\n");
}

function formatRecentAssistant(messages: string[]): string {
  if (messages.length === 0) return "";
  const lines: string[] = ["## Recent assistant text"];
  for (const m of messages) {
    lines.push("---");
    lines.push(m);
  }
  return lines.join("\n");
}

function formatCurrentSelection(selection: string[]): string {
  const lines: string[] = ["## Currently selected rules"];
  if (selection.length === 0) {
    lines.push("(none)");
  } else {
    for (const id of selection) lines.push(`- ${id}`);
  }
  return lines.join("\n");
}

function formatLLMCatalog(catalog: LLMCatalogEntry[]): string {
  const lines: string[] = ["## LLM rule catalog"];
  if (catalog.length === 0) {
    lines.push("(empty)");
  } else {
    for (const e of catalog) lines.push(`- ${e.id}: ${e.relevance}`);
  }
  return lines.join("\n");
}
