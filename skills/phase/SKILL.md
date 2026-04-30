---
name: phase
description: "Show the current workflow phase, focus, and available commands. Auto-detects branched sessions."
---

Invoked as `/flow:phase`.

## Instructions

1. Get state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get`

2. **If registered**, get details and report:
   - Phase: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-phase`
   - Focus: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-focus`
   - Task file: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-task`

   Report based on phase:
   - `planning` — "**Planning.** Discussing and refining the plan in conversation. → `/flow:approve` when ready."
   - `planned` (no focus) — "**Planned.** Plan written to `<file>`. → `/flow:next` to pick tasks."
   - `planned` (with focus) — "**Planned | Focus: [tasks].** Deep-diving. → `/flow:implement` when ready."
   - `implementing` (with focus) — "**Implementing: [tasks].** Code writes unlocked. → `/flow:next` when done."

   Then append a brief rule-status line. Capture the output of:
   ```bash
   TASK=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-task)
   FOCUS=$("${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get-focus)
   "${CLAUDE_PLUGIN_ROOT}/bin/flow-rules" state status --cwd . --task-file "$TASK" --focus "$FOCUS" --brief 2>/dev/null || true
   ```
   If the brief output is non-empty, append it as a second line under the phase report. If empty or errored, skip silently — telemetry is best-effort.

3. **If NOT registered**, attempt self-heal:

   a. Run branch detection: `"${CLAUDE_PLUGIN_ROOT}/scripts/branch-detect.sh"` — pipe the following JSON to stdin:
      ```json
      {"source":"resume","cwd":".","session_id":"$CURRENT_SESSION_ID","transcript_path":"<transcript path>"}
      ```
      Note: you may not have the transcript path. If so, skip to step (b).

   b. Check again: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --get`
      - If now registered → detection succeeded. **Ask the user to confirm**: show the detected phase and task file, ask "Is this correct?" via `AskUserQuestion`.
        - If confirmed → report the phase.
        - If denied → remove the entry: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "$CURRENT_SESSION_ID" --remove` and continue to (c).

   c. If still not registered — list all task files from SESSIONS.json (`"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . --dump`) and any `.md` files in `.flow/` (excluding rules, archive). Use `AskUserQuestion` to ask the user which task they are working on and which phase they are in. Register with their answer.

4. If no SESSIONS.json exists and no task files found, say: "No active workflow. Use `/flow:build` to start."
