#!/bin/bash
# PostToolUse hook for Write|Edit: warn on code writes during planning/planned phases.
# Session-aware — only fires for sessions with an active planning or planned phase.
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

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

if [ -z "$CWD" ] || [ -z "$FILE_PATH" ] || [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

SESSIONS_FILE="${CWD}/.flow/SESSIONS.json"

if [ ! -f "$SESSIONS_FILE" ]; then
  echo '{}'
  exit 0
fi

# --- Look up this session's phase ---
PHASE=$(jq -r --arg id "$SESSION_ID" '.[$id].phase // empty' "$SESSIONS_FILE" 2>/dev/null || true)

# Only enforce during planning and planned — implementing allows writes
if [ "$PHASE" != "planning" ] && [ "$PHASE" != "planned" ]; then
  echo '{}'
  exit 0
fi

# --- Check if file is inside .flow/ ---
FLOW_DIR="${CWD}/.flow/"
case "$FILE_PATH" in
  ${FLOW_DIR}*|.flow/*)
    echo '{}'
    exit 0
    ;;
esac

# --- Warn ---
if [ "$PHASE" = "planning" ]; then
  WARNING="You wrote to \`${FILE_PATH}\` during **planning** phase. No code changes until the plan is approved. Re-read /flow:build rules."
else
  WARNING="You wrote to \`${FILE_PATH}\` during **planned** phase (deep-dive). No code changes until /flow:implement. Re-read /flow:next rules."
fi

jq -n --arg ctx "$WARNING" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $ctx
  }
}'

exit 0
