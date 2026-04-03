#!/bin/bash
# PostToolUse hook for Write|Edit: warn on code writes during planning phase.
# Session-aware — only fires for the session that has an active planning phase.
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
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
else
  FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$CWD" ] || [ -z "$FILE_PATH" ] || [ -z "$SESSION_ID" ]; then
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

# Only enforce during planning
if [ "$PHASE" != "planning" ]; then
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
WARNING="You wrote to \`${FILE_PATH}\` during **planning** phase. No code changes until /flow:approve. Re-read the /flow:build skill if needed."

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$WARNING" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$WARNING" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$WARNING")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
