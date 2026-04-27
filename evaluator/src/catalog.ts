import * as fs from "node:fs";
import * as path from "node:path";
import { dynamicRulesDir } from "./paths.ts";
import { parseRuleFile } from "./frontmatter.ts";
import type { RuleCatalog, LLMCatalogEntry } from "./types.ts";

export function loadCatalog(cwd: string): RuleCatalog {
  const dir = dynamicRulesDir(cwd);
  const out: RuleCatalog = new Map();
  if (!fs.existsSync(dir)) return out;
  let entries: string[];
  try {
    entries = fs.readdirSync(dir);
  } catch {
    return out;
  }
  for (const name of entries) {
    if (!name.endsWith(".md")) continue;
    const full = path.join(dir, name);
    let raw: string;
    try {
      raw = fs.readFileSync(full, "utf8");
    } catch {
      continue;
    }
    const parsed = parseRuleFile(raw);
    const fm = parsed.frontmatter;
    if (!fm) {
      process.stderr.write(
        `[flow-rules] skip rule ${name}: no frontmatter (${full})\n`,
      );
      continue;
    }
    const hasSignal =
      (fm.relevance !== undefined && fm.relevance !== "") ||
      (fm.patterns !== undefined && fm.patterns.length > 0) ||
      (fm.keywords !== undefined && fm.keywords.length > 0);
    if (!hasSignal) {
      process.stderr.write(
        `[flow-rules] skip rule ${name}: no signal fields (${full})\n`,
      );
      continue;
    }
    out.set(name, { id: name, frontmatter: fm, body: parsed.body });
  }
  return out;
}

export function buildLLMCatalog(
  catalog: RuleCatalog,
  alreadySelected: Set<string>,
): LLMCatalogEntry[] {
  const out: LLMCatalogEntry[] = [];
  for (const [id, entry] of catalog) {
    if (alreadySelected.has(id)) continue;
    const r = entry.frontmatter.relevance;
    if (r === undefined || r === "") continue;
    out.push({ id, relevance: r });
  }
  return out;
}
