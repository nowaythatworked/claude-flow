---
name: init
description: "Initialize flow in the current project. Scaffolds .flow/ directory with rules, scripts, and installs agents to .claude/agents/."
disable-model-invocation: true
---

# Initialize Flow

Set up the flow quality framework in the current project.

## Steps

1. **Create directories:**
   ```bash
   !`mkdir -p .flow/rules/always .flow/rules/dynamic .flow/scripts .claude/agents && echo "Created directory structure"`
   ```

2. **Copy always-on rules** from the plugin:
   ```bash
   !`cp -n "${CLAUDE_PLUGIN_ROOT}/rules/always/"*.md .flow/rules/always/ 2>/dev/null; echo "Copied always-on rules to .flow/rules/always/"`
   ```
   Uses `-n` to not overwrite rules the team may have customized.

3. **Copy scripts** (used by agent hooks):
   ```bash
   !`cp -n "${CLAUDE_PLUGIN_ROOT}/scripts/stop-rule-check.sh" .flow/scripts/ 2>/dev/null; chmod +x .flow/scripts/*.sh 2>/dev/null; echo "Copied scripts to .flow/scripts/"`
   ```

4. **Install agents** to `.claude/agents/` (project-level, supports hooks):
   ```bash
   !`cp -n "${CLAUDE_PLUGIN_ROOT}/agents/installable/"*.md .claude/agents/ 2>/dev/null; echo "Installed agents to .claude/agents/"`
   ```

5. **Create `.flow/TASKS.md`** if it doesn't exist:
   ```bash
   !`[ ! -f .flow/TASKS.md ] && printf "# Tasks\n\n_No active tasks yet. Use /flow:build to start._\n" > .flow/TASKS.md && echo "Created .flow/TASKS.md" || echo ".flow/TASKS.md already exists"`
   ```

6. **Report what was done.** List the files created/copied. Remind the user to:
   - Commit `.flow/` and `.claude/agents/` to git so teammates get them
   - Add project-specific dynamic rules with `/flow:add-rule` as patterns emerge
