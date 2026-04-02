---
name: init
description: "Initialize flow in the current project. Scaffolds .flow/ directory with rules and installs agents to .claude/agents/."
disable-model-invocation: true
---

# Initialize Flow

Set up the flow quality framework in the current project.

## Steps

1. **Run the init script:**
   ```bash
   !`"${CLAUDE_PLUGIN_ROOT}/scripts/init.sh"`
   ```

2. **Report what was done.** Remind the user to:
   - Commit `.flow/` and `.claude/agents/` to git so teammates get them
   - Add project-specific dynamic rules with `/flow:add-rule` as patterns emerge
   - After a plugin update, re-run `/flow:init` to update agent paths (existing agents won't be overwritten unless deleted first)
