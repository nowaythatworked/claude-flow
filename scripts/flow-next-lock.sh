#!/bin/bash
# UserPromptSubmit hook: enforce phase lock when /flow:next is invoked.
# When /flow:next is called (without --no-lock) in implementing phase,
# pre-emptively locks the phase to planned and clears focus in shell —
# so the lock is enforced before the skill runs, not by the LLM.

set -euo pipefail

# --- Stdin guard ---
if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat 2>/dev/null) || INPUT=""
fi

if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo '{}'
  exit 0
fi

PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)

# Only trigger for /flow:next (with or without trailing args)
case "$PROMPT" in
  /flow:next*) ;;
  *) echo '{}'; exit 0 ;;
esac

# Respect --no-lock flag
case "$PROMPT" in
  *--no-lock*) echo '{}'; exit 0 ;;
esac

if [ -z "$SESSION_ID" ] || [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

SESSIONS_FILE="${CWD}/.flow/SESSIONS.json"
if [ ! -f "$SESSIONS_FILE" ]; then
  echo '{}'
  exit 0
fi

# Get current phase from SESSIONS.json directly (no session.sh dependency)
PHASE=$(jq -r --arg id "$SESSION_ID" '.[$id].phase // empty' "$SESSIONS_FILE" 2>/dev/null || true)

if [ "$PHASE" != "implementing" ]; then
  echo '{}'
  exit 0
fi

# Lock: clear focus and set phase to planned
SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/session.sh"
if [ ! -f "$SCRIPT" ]; then
  echo '{}'
  exit 0
fi

"$SCRIPT" "$CWD" "$SESSION_ID" --clear-focus 2>/dev/null || true
"$SCRIPT" "$CWD" "$SESSION_ID" --set-phase planned 2>/dev/null || true

# Inject context so the skill knows the lock already happened
jq -n '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: "**[flow-next-lock hook]** Phase pre-locked by shell hook: `implementing → planned`. Focus cleared. When you reach step 1 of the skill, `--get` will return `planned` — confirm this in your step 1 output to the user."
  }
}'

exit 0
