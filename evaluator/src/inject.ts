import * as fs from "node:fs";
import * as path from "node:path";
import { dynamicRulesDir } from "./paths.ts";
import { stripFrontmatter } from "./frontmatter.ts";

const INITIAL_HEADER = `# Dynamic Rules (initial set for this task)
These rules were loaded because they are relevant to your current task context.
Follow them. Adjust your approach where needed.
If you already have a plan, re-evaluate it.
When encountering ambiguity that cannot be resolved by reading the codebase, raise it before proceeding.
`;

const DELTA_HEADER = `# New Dynamic Rules (just added)
These rules just became relevant and are being added to your context now.
**IMPORTANT:** Earlier \`Dynamic Rule [...]\` blocks injected previously in this conversation remain active. When judging which rules apply, scan ALL such blocks throughout conversation history, not only this latest set. Follow them alongside the rules already loaded.
`;

export function formatRulesInjection(
  selectedRuleIds: string[],
  cwd: string,
  opts: { isInitial: boolean },
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
  const header = opts.isInitial ? INITIAL_HEADER : DELTA_HEADER;
  return `${header}\n${blocks.join("\n")}`;
}
