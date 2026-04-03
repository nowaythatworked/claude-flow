#!/bin/bash
# SessionStart hook: auto-register branched sessions.
# On source=resume, if SESSIONS exists but this session isn't in it,
# detect if this is a branched /flow:build session and register it.
#
# Detection strategy:
#   1. grep transcript for "flow:build" → confirms build session
#   2. grep transcript for parent session IDs from SESSIONS → identifies task
#   3. grep transcript for task filenames → fallback identification
#   4. LLM (haiku) semantic check → last resort for compacted/ambiguous cases

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
  SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
else
  SOURCE=$(echo "$INPUT" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  TRANSCRIPT=$(echo "$INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

# Only act on resume (which includes branching)
if [ "$SOURCE" != "resume" ]; then
  echo '{}'
  exit 0
fi

if [ -z "$CWD" ] || [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

SESSIONS_FILE="$CWD/.flow/SESSIONS"

# No active sessions = nothing to inherit
if [ ! -f "$SESSIONS_FILE" ]; then
  echo '{}'
  exit 0
fi

# Already registered = not a branch, just a normal resume
if grep -q "^${SESSION_ID} " "$SESSIONS_FILE" 2>/dev/null; then
  echo '{}'
  exit 0
fi

# --- Need transcript from here ---
if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
  echo '{}'
  exit 0
fi

# --- Helper: register and exit ---
register_and_exit() {
  local phase="$1" task="$2"
  "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --set "$phase" "$task"
  echo '{}'
  exit 0
}

# --- Single task shortcut ---
TOTAL=$(wc -l < "$SESSIONS_FILE" | tr -d ' ')
if [ "$TOTAL" -eq 1 ]; then
  # Only one task — check if this is a build session at all
  if grep -q "flow:build" "$TRANSCRIPT" 2>/dev/null; then
    PHASE=$(awk '{print $2}' "$SESSIONS_FILE")
    TASK=$(awk '{print $3}' "$SESSIONS_FILE")
    register_and_exit "$PHASE" "$TASK"
  fi
  # Fall through to LLM check
fi

# --- Multi-task: identify which task via parent session ID ---
if grep -q "flow:build" "$TRANSCRIPT" 2>/dev/null; then

  # Strategy 1: grep for parent session IDs in transcript
  while IFS= read -r line; do
    PARENT_ID=$(echo "$line" | awk '{print $1}')
    [ -z "$PARENT_ID" ] && continue
    if grep -q "$PARENT_ID" "$TRANSCRIPT" 2>/dev/null; then
      PHASE=$(echo "$line" | awk '{print $2}')
      TASK=$(echo "$line" | awk '{print $3}')
      register_and_exit "$PHASE" "$TASK"
    fi
  done < "$SESSIONS_FILE"

  # Strategy 2: grep for task filenames in transcript
  MATCH_COUNT=0
  MATCHED_PHASE=""
  MATCHED_TASK=""
  while IFS= read -r line; do
    TASK=$(echo "$line" | awk '{print $3}')
    [ -z "$TASK" ] && continue
    if grep -q "$TASK" "$TRANSCRIPT" 2>/dev/null; then
      MATCHED_PHASE=$(echo "$line" | awk '{print $2}')
      MATCHED_TASK="$TASK"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
  done < "$SESSIONS_FILE"

  if [ "$MATCH_COUNT" -eq 1 ]; then
    register_and_exit "$MATCHED_PHASE" "$MATCHED_TASK"
  fi
fi

# --- LLM fallback: detect + disambiguate ---
if command -v claude &>/dev/null; then
  # Read beginning + end of transcript for full picture
  TOTAL_LINES=$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
  if [ "$TOTAL_LINES" -le 100 ]; then
    CONVERSATION=$(cat "$TRANSCRIPT" 2>/dev/null | head -c 8000)
  else
    CONV_HEAD=$(head -30 "$TRANSCRIPT" 2>/dev/null | head -c 3000)
    CONV_TAIL=$(tail -50 "$TRANSCRIPT" 2>/dev/null | head -c 5000)
    CONVERSATION="${CONV_HEAD}

... (middle of conversation omitted) ...

${CONV_TAIL}"
  fi

  # Read task file contents for matching
  TASK_CONTEXT=""
  while IFS= read -r line; do
    TASK=$(echo "$line" | awk '{print $3}')
    [ -z "$TASK" ] && continue
    TASK_PATH="$CWD/.flow/$TASK"
    if [ -f "$TASK_PATH" ]; then
      CONTENT=$(head -80 "$TASK_PATH" 2>/dev/null || true)
      TASK_CONTEXT="${TASK_CONTEXT}
--- ${TASK} ---
${CONTENT}
"
    fi
  done < "$SESSIONS_FILE"

  TASK_LIST=$(awk '{print $3}' "$SESSIONS_FILE" | sort -u | tr '\n' ', ' | sed 's/,$//')

  if [ -n "$CONVERSATION" ] && [ -n "$TASK_LIST" ]; then
    PROMPT="You are checking if this conversation is part of a /flow:build workflow session.

Active task files: ${TASK_LIST}

Task file contents:
${TASK_CONTEXT}

Look for evidence: /flow:build invocation, planning/implementation discussion, task file references, phase commands (/flow:approve, /flow:lock), session registration commands.

Conversation transcript:
${CONVERSATION}

If this IS a build session, respond with ONLY the matching task filename (e.g. \"my-task.md\").
If this is NOT a build session, respond with ONLY \"no\"."

    ANSWER=$(echo "$PROMPT" | claude -p --model sonnet --output-format json 2>/dev/null | jq -r '.result // empty' 2>/dev/null || true)

    if [ -n "$ANSWER" ] && [ "$ANSWER" != "no" ]; then
      MATCH_LINE=$(grep " ${ANSWER}$" "$SESSIONS_FILE" 2>/dev/null | tail -1)
      if [ -n "$MATCH_LINE" ]; then
        PHASE=$(echo "$MATCH_LINE" | awk '{print $2}')
        register_and_exit "$PHASE" "$ANSWER"
      fi
    fi
  fi
fi

echo '{}'
exit 0
