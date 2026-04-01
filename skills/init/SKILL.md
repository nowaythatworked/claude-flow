---
name: init
description: "Initialize flow in the current project. Scaffolds .flow/ directory with always-on rules and empty dynamic rules folder."
disable-model-invocation: true
---

# Initialize Flow

Set up the flow quality framework in the current project.

## Steps

1. **Create directories:**
   ```bash
   !`mkdir -p .flow/rules/always .flow/rules/dynamic && echo "Created .flow/ directory structure"`
   ```

2. **Copy always-on rules** from the plugin:
   ```bash
   !`cp -n "${CLAUDE_PLUGIN_ROOT}/rules/always/"*.md .flow/rules/always/ 2>/dev/null; echo "Copied always-on rules to .flow/rules/always/"`
   ```
   Uses `-n` to not overwrite rules the team may have customized.

3. **Create `.flow/TASKS.md`** if it doesn't exist:
   ```bash
   !`[ ! -f .flow/TASKS.md ] && printf "# Tasks\n\n_No active tasks yet. Use /flow:build to start._\n" > .flow/TASKS.md && echo "Created .flow/TASKS.md" || echo ".flow/TASKS.md already exists"`
   ```

4. **Report what was done.** List the files created/copied. Remind the user to:
   - Commit `.flow/` to git so teammates get the rules
   - Add project-specific dynamic rules with `/flow:add-rule` as patterns emerge
   - `.flow/rules/dynamic/` is intentionally empty — dynamic rules are project-specific
