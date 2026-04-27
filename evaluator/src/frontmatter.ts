import type { ParsedRule, RuleFrontmatter } from "./types.ts";

const FENCE = "---";

export function parseRuleFile(text: string): ParsedRule {
  const lines = text.split("\n");
  if (lines.length === 0 || lines[0]?.trim() !== FENCE) {
    return { frontmatter: null, body: text };
  }
  let endIdx = -1;
  for (let i = 1; i < lines.length; i++) {
    if (lines[i]?.trim() === FENCE) {
      endIdx = i;
      break;
    }
  }
  if (endIdx === -1) {
    return { frontmatter: null, body: text };
  }
  const fmLines = lines.slice(1, endIdx);
  const bodyLines = lines.slice(endIdx + 1);
  const frontmatter = parseYaml(fmLines);
  const body = bodyLines.join("\n");
  return { frontmatter, body };
}

export function stripFrontmatter(text: string): string {
  return parseRuleFile(text).body;
}

function parseYaml(lines: string[]): RuleFrontmatter {
  const fm: RuleFrontmatter = {};
  let i = 0;
  while (i < lines.length) {
    const raw = lines[i];
    if (raw === undefined) {
      i++;
      continue;
    }
    const line = raw;
    if (line.trim() === "" || line.trim().startsWith("#")) {
      i++;
      continue;
    }
    const m = /^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$/.exec(line);
    if (!m) {
      i++;
      continue;
    }
    const key = m[1];
    const rest = (m[2] ?? "").trimEnd();
    if (key !== "relevance" && key !== "patterns" && key !== "keywords") {
      i++;
      continue;
    }
    if (rest === "") {
      const items: string[] = [];
      i++;
      while (i < lines.length) {
        const next = lines[i];
        if (next === undefined) break;
        if (next.trim() === "") {
          i++;
          continue;
        }
        const itemMatch = /^\s*-\s*(.*)$/.exec(next);
        if (!itemMatch) break;
        items.push(unquote((itemMatch[1] ?? "").trim()));
        i++;
      }
      if (key === "patterns" || key === "keywords") {
        fm[key] = items;
      }
      continue;
    }
    if (rest.startsWith("[")) {
      const arr = parseInlineList(rest);
      if (key === "patterns" || key === "keywords") {
        fm[key] = arr;
      }
      i++;
      continue;
    }
    if (key === "relevance") {
      fm.relevance = unquote(rest);
    } else {
      fm[key] = [unquote(rest)];
    }
    i++;
  }
  return fm;
}

function parseInlineList(s: string): string[] {
  const trimmed = s.trim();
  if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) {
    return [];
  }
  const inner = trimmed.slice(1, -1).trim();
  if (inner === "") return [];
  const out: string[] = [];
  let i = 0;
  let buf = "";
  let inStr: '"' | "'" | null = null;
  while (i < inner.length) {
    const ch = inner[i];
    if (ch === undefined) break;
    if (inStr) {
      if (ch === "\\" && i + 1 < inner.length) {
        buf += inner[i + 1] ?? "";
        i += 2;
        continue;
      }
      if (ch === inStr) {
        inStr = null;
        i++;
        continue;
      }
      buf += ch;
      i++;
      continue;
    }
    if (ch === '"' || ch === "'") {
      inStr = ch;
      i++;
      continue;
    }
    if (ch === ",") {
      const v = buf.trim();
      if (v !== "") out.push(unquote(v));
      buf = "";
      i++;
      continue;
    }
    buf += ch;
    i++;
  }
  const last = buf.trim();
  if (last !== "") out.push(unquote(last));
  return out;
}

function unquote(s: string): string {
  const t = s.trim();
  if (t.length >= 2) {
    const first = t[0];
    const last = t[t.length - 1];
    if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
      return t.slice(1, -1);
    }
  }
  return t;
}
