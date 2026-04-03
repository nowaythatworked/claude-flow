---
name: approve
description: "Approve the plan and write it to the task file. Transitions from planning to planned phase."
---

Invoked as `/flow:approve`.

## What this does

Transitions the workflow from **planning** to **planned**. The plan discussed in conversation gets written to the task file as the approved artifact.

## Instructions

1. Check current state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`
   - If empty, tell the user there's no active workflow. Suggest `/flow:build`.
   - If phase isn't `planning`, tell the user the current phase and what commands are available.

2. **Write the plan to the task file.**
   - Get the task filename: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get-task`
   - Create or update the file at `.flow/<task-filename>.md`
   - If the file already exists (re-approval after `/flow:lock`): preserve any completed items and execution notes, update the plan sections with the revised plan
   - Write the mid-level plan as discussed — areas with key points, NOT granular task lists
   - Format as a checklist with section headings:
     ```markdown
     # <Task Title>

     ## <Area 1>
     - [ ] Key item
     - [ ] Key item

     ## <Area 2>
     - [ ] Key item
     ```

3. **Reflect on scope** (if not already discussed during planning):
   - Assess the overall size and complexity
   - If large: mention that the user might want to consider splitting into separate `/flow:build` sessions
   - If small: note that the deep-dive phase can be brief

4. Transition: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --set-phase planned`

5. Confirm: "Plan approved and written to `.flow/<filename>`. Run `/flow:next` to pick tasks and deep-dive."
