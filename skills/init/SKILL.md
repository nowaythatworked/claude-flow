---
name: init
description: "Initialize flow in the current project. Copies always-on rules to .claude/rules/ and scaffolds .flow/ directory."
disable-model-invocation: true
---

# Initialize Flow

Set up the flow quality framework in the current project.

## Steps

1. **Create directories:**
   - `.claude/rules/` (if it doesn't exist)
   - `.flow/rules/optional/`

2. **Copy always-on rules** from the plugin's `rules/always/` directory to `.claude/rules/`:
   ```bash
   !`cp -n "${CLAUDE_PLUGIN_ROOT}/rules/always/"*.md .claude/rules/ 2>/dev/null; echo "Copied always-on rules to .claude/rules/"`
   ```
   Use `-n` to not overwrite existing rules the team may have customized.

3. **Copy example optional rules** from the plugin's `rules/optional/` directory to `.flow/rules/optional/`:
   ```bash
   !`cp -n "${CLAUDE_PLUGIN_ROOT}/rules/optional/"*.md .flow/rules/optional/ 2>/dev/null; echo "Copied example optional rules to .flow/rules/optional/"`
   ```

4. **Create `.flow/TASKS.md`** if it doesn't exist:
   ```bash
   !`[ ! -f .flow/TASKS.md ] && echo "# Tasks\n\n_No active tasks yet. Use /flow:build to start._" > .flow/TASKS.md && echo "Created .flow/TASKS.md" || echo ".flow/TASKS.md already exists"`
   ```

5. **Report what was done.** List the files created/copied. Remind the user to:
   - Commit `.claude/rules/` and `.flow/` to git so teammates get them
   - Customize optional rules for their project (remove irrelevant ones, add project-specific ones)
   - Install the flow plugin project-wide: `claude plugin install flow@<marketplace> --scope project`
