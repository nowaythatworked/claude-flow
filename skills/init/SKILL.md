---
name: init
description: "Initialize flow in the current project. Scaffolds .flow/ directory with rules and installs agents to .claude/agents/."
disable-model-invocation: true
---

# Initialize Flow

Set up the flow quality framework in the current project.

## Steps

1. **Create directories:**
   ```bash
   !`mkdir -p .flow/rules/always .flow/rules/dynamic .claude/agents && echo "Created directory structure"`
   ```

2. **Copy always-on rules** from the plugin:
   ```bash
   !`cp -n "${CLAUDE_PLUGIN_ROOT}/rules/always/"*.md .flow/rules/always/ 2>/dev/null; echo "Copied always-on rules to .flow/rules/always/"`
   ```
   Uses `-n` to not overwrite rules the team may have customized.

3. **Install agents** to `.claude/agents/` with resolved plugin paths:
   ```bash
   !`for f in "${CLAUDE_PLUGIN_ROOT}/agents/installable/"*.md; do [ -f "$f" ] || continue; name=$(basename "$f"); target=".claude/agents/$name"; if [ ! -f "$target" ]; then sed "s|__FLOW_PLUGIN_ROOT__|${CLAUDE_PLUGIN_ROOT}|g" "$f" > "$target"; echo "Installed $name"; else echo "$name already exists, skipping"; fi; done`
   ```
   Replaces `__FLOW_PLUGIN_ROOT__` with the actual plugin cache path so agent hooks can reference plugin scripts.

4. **Create `.flow/TASKS.md`** if it doesn't exist:
   ```bash
   !`[ ! -f .flow/TASKS.md ] && printf "# Tasks\n\n_No active tasks yet. Use /flow:build to start._\n" > .flow/TASKS.md && echo "Created .flow/TASKS.md" || echo ".flow/TASKS.md already exists"`
   ```

5. **Report what was done.** List the files created/copied. Remind the user to:
   - Commit `.flow/` and `.claude/agents/` to git so teammates get them
   - Add project-specific dynamic rules with `/flow:add-rule` as patterns emerge
   - After a plugin update, re-run `/flow:init` to update agent paths (existing agents won't be overwritten unless deleted first)
