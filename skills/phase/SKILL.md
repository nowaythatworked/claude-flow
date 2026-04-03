---
name: phase
description: "Show the current workflow phase (planning or implementing). Auto-detects branched sessions."
---

Invoked as `/flow:phase`.

## Instructions

1. Get state: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`

2. **If registered**, report the phase and task file:
   - `planning` — "Planning mode. Discussing and refining the plan. No implementation until `/flow:approve`."
   - `implementing` — "Implementation mode. Plan approved. Delegating code changes to subagents."

3. **If NOT registered**, attempt self-heal:

   a. Run branch detection: `"${CLAUDE_PLUGIN_ROOT}/scripts/branch-detect.sh"` — pipe the following JSON to stdin:
      ```json
      {"source":"resume","cwd":".","session_id":"${CLAUDE_SESSION_ID}","transcript_path":"<transcript path>"}
      ```
      Note: you may not have the transcript path. If so, skip to step (b).

   b. Check again: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --get`
      - If now registered → detection succeeded. **Ask the user to confirm**: show the detected phase and task file, ask "Is this correct?" via `AskUserQuestion`.
        - If confirmed → report the phase.
        - If denied → remove the entry: `"${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" . "${CLAUDE_SESSION_ID}" --remove` and continue to (c).

   c. If still not registered — list all task files from `.flow/SESSIONS` and any `.md` files in `.flow/` (excluding rules, archive). Use `AskUserQuestion` to ask the user which task they are working on and which phase they are in. Register with their answer.

4. If no `.flow/SESSIONS` exists and no task files found, say: "No active workflow. Use `/flow:build` to start."
