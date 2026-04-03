#!/bin/bash
# UserPromptSubmit hook: inject phase-appropriate reminders.
# Reads .flow/SESSIONS.json for the current session's phase and focus.
# Pure bash + jq — no LLM calls.

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
if ! command -v jq &>/dev/null; then
  echo '{}'
  exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)

if [ -z "$CWD" ] || [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

# Skip injection for /flow: commands — they manage their own state
case "$PROMPT" in
  /flow:*) echo '{}'; exit 0 ;;
esac

SESSIONS_FILE="${CWD}/.flow/SESSIONS.json"

if [ ! -f "$SESSIONS_FILE" ]; then
  echo '{}'
  exit 0
fi

# --- Look up this session ---
ENTRY=$(jq -r --arg id "$SESSION_ID" '.[$id] // empty' "$SESSIONS_FILE" 2>/dev/null || true)

if [ -z "$ENTRY" ] || [ "$ENTRY" = "null" ]; then
  echo '{}'
  exit 0
fi

PHASE=$(echo "$ENTRY" | jq -r '.phase' 2>/dev/null || true)
FOCUS=$(echo "$ENTRY" | jq -r '.focus // [] | if length > 0 then join(", ") else "" end' 2>/dev/null || true)

# --- Build phase reminder ---
case "$PHASE" in
  planning)
    CONTEXT="**Phase: planning.** Follow /flow:build planning rules — understand deeply, plan in conversation. No code writes. Keep questioning yourself: Do you understand enough? Have you searched for side-effects, affected areas, and new possibilities? Is the plan solid enough to approve? If not, keep iterating. When genuinely confident, suggest the user runs /flow:approve."
    ;;
  planned)
    if [ -n "$FOCUS" ]; then
      CONTEXT="**Phase: planned | Focus: ${FOCUS}.** Follow /flow:next deep-dive rules — research thoroughly, think through edge cases. No code writes. Keep iterating: ask yourself if you are confident enough to implement this correctly. If not, dig deeper or ask. When confident, suggest the user runs /flow:implement."
    else
      CONTEXT="**Phase: planned.** Follow /flow:build planned-phase rules. Suggest the user runs /flow:next or tells you which tasks to focus on. Deep-dive before implementing."
    fi
    ;;
  implementing)
    CONTEXT="**Phase: implementing.** Follow /flow:build implementation rules — delegate substantial work, verify results. When tasks are complete, suggest the user runs /flow:next for the next task."
    ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

# --- Output ---
jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

exit 0
