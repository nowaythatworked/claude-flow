import { minimatch } from "minimatch";
import type { RuleCatalog } from "./types.ts";

export function matchPatterns(
  filePaths: string[],
  catalog: RuleCatalog,
): string[] {
  const matched: string[] = [];
  for (const [id, entry] of catalog) {
    const patterns = entry.frontmatter.patterns;
    if (!patterns || patterns.length === 0) continue;
    const hit = filePaths.some((p) =>
      patterns.some((pat) => minimatch(p, pat, { dot: true })),
    );
    if (hit) matched.push(id);
  }
  return matched;
}

export function matchKeywords(text: string, catalog: RuleCatalog): string[] {
  const lower = text.toLowerCase();
  const matched: string[] = [];
  for (const [id, entry] of catalog) {
    const keywords = entry.frontmatter.keywords;
    if (!keywords || keywords.length === 0) continue;
    const hit = keywords.some(
      (k) => k !== "" && lower.includes(k.toLowerCase()),
    );
    if (hit) matched.push(id);
  }
  return matched;
}
