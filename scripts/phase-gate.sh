#!/bin/bash
# UserPromptSubmit hook: inject phase-appropriate reminders.
# Reads .flow/SESSIONS for the current session's phase.
# Pure bash — no LLM calls.

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

# --- Parse input ---
if command -v jq &>/dev/null; then
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
else
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$CWD" ] || [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

SESSIONS_FILE="${CWD}/.flow/SESSIONS"

if [ ! -f "$SESSIONS_FILE" ]; then
  echo '{}'
  exit 0
fi

# --- Look up this session's phase ---
PHASE=$(grep "^${SESSION_ID} " "$SESSIONS_FILE" 2>/dev/null | awk '{print $2}' || true)

if [ -z "$PHASE" ]; then
  echo '{}'
  exit 0
fi

# --- Build phase reminder ---
case "$PHASE" in
  planning)
    CONTEXT="**Phase: planning.** Follow the /flow:build skill rules for steps 1-4. No implementation until the user runs /flow:approve. If you can't recall the rules, re-read the skill."
    ;;
  implementing)
    CONTEXT="**Phase: implementing.** Follow the /flow:build skill rules for steps 5-6. Delegate where it makes sense. If you can't recall the rules, re-read the skill."
    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

# --- Output ---
if command -v jq &>/dev/null; then
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$CONTEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$CONTEXT")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
