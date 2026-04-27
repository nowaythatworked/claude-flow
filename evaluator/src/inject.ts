import * as fs from "node:fs";
import * as path from "node:path";
import { dynamicRulesDir } from "./paths.ts";
import { stripFrontmatter } from "./frontmatter.ts";

const HEADER = `# Dynamic Rules (auto-selected for this task)
These rules were loaded because they are relevant to your current task context.
Follow them. Adjust your approach where needed.
If you already have a plan, re-evaluate it against these rules and adjust where needed.
When encountering ambiguity that cannot be resolved by reading the codebase, raise it before proceeding.
`;

export function formatRulesInjection(
  selectedRuleIds: string[],
  cwd: string,
): string {
  if (selectedRuleIds.length === 0) return "";
  const dir = dynamicRulesDir(cwd);
  const blocks: string[] = [];
  for (const id of selectedRuleIds) {
    const full = path.join(dir, id);
    let raw: string;
    try {
      raw = fs.readFileSync(full, "utf8");
    } catch {
      continue;
    }
    const body = stripFrontmatter(raw).replace(/^\n+/, "");
    blocks.push(`--- Dynamic Rule [${id}] (auto-selected) ---\n${body}\n`);
  }
  if (blocks.length === 0) return "";
  return `${HEADER}\n${blocks.join("\n")}`;
}
