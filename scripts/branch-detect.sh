#!/bin/bash
# SessionStart hook: auto-register branched sessions.
# On source=resume, if SESSIONS.json exists but this session isn't in it,
# detect if this is a branched /flow:build session and register it.
#
# Detection strategy:
#   1. grep transcript for "flow:build" → confirms build session
#   2. grep transcript for parent session IDs from SESSIONS.json → identifies task
#   3. grep transcript for task filenames → fallback identification
#   4. LLM (sonnet) semantic check → last resort for compacted/ambiguous cases

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
if ! command -v jq &>/dev/null; then
  echo '{}'
  exit 0
fi

SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)

# Only act on resume (which includes branching)
if [ "$SOURCE" != "resume" ]; then
  echo '{}'
  exit 0
fi

if [ -z "$CWD" ] || [ -z "$SESSION_ID" ]; then
  echo '{}'
  exit 0
fi

SESSIONS_FILE="$CWD/.flow/SESSIONS.json"

# No active sessions = nothing to inherit
if [ ! -f "$SESSIONS_FILE" ]; then
  echo '{}'
  exit 0
fi

# Already registered = not a branch, just a normal resume
EXISTING=$(jq -r --arg id "$SESSION_ID" '.[$id] // empty' "$SESSIONS_FILE" 2>/dev/null || true)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
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
  local parent_id="$1" phase="$2" task="$3"
  "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --set "$phase" "$task"
  if [ -n "$parent_id" ]; then
    "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --set-parent "$parent_id"
  fi
  echo '{}'
  exit 0
}

# --- Get all session IDs and their data ---
SESSION_IDS=$(jq -r 'keys[]' "$SESSIONS_FILE" 2>/dev/null || true)
TOTAL=$(echo "$SESSION_IDS" | grep -c . 2>/dev/null || echo "0")

# --- Single task shortcut ---
if [ "$TOTAL" -eq 1 ]; then
  if grep -q "flow:build" "$TRANSCRIPT" 2>/dev/null; then
    PARENT_ID=$(echo "$SESSION_IDS" | head -1)
    PHASE=$(jq -r --arg id "$PARENT_ID" '.[$id].phase' "$SESSIONS_FILE")
    TASK=$(jq -r --arg id "$PARENT_ID" '.[$id].task_file' "$SESSIONS_FILE")
    register_and_exit "$PARENT_ID" "$PHASE" "$TASK"
  fi
fi

# --- Multi-task: identify which task via parent session ID ---
if grep -q "flow:build" "$TRANSCRIPT" 2>/dev/null; then

  # Strategy 1: grep for parent session IDs in transcript
  for PARENT_ID in $SESSION_IDS; do
    [ -z "$PARENT_ID" ] && continue
    if grep -q "$PARENT_ID" "$TRANSCRIPT" 2>/dev/null; then
      PHASE=$(jq -r --arg id "$PARENT_ID" '.[$id].phase' "$SESSIONS_FILE")
      TASK=$(jq -r --arg id "$PARENT_ID" '.[$id].task_file' "$SESSIONS_FILE")
      register_and_exit "$PARENT_ID" "$PHASE" "$TASK"
    fi
  done

  # Strategy 2: grep for task filenames in transcript
  MATCH_COUNT=0
  MATCHED_PARENT=""
  MATCHED_PHASE=""
  MATCHED_TASK=""
  for PARENT_ID in $SESSION_IDS; do
    [ -z "$PARENT_ID" ] && continue
    TASK=$(jq -r --arg id "$PARENT_ID" '.[$id].task_file' "$SESSIONS_FILE")
    [ -z "$TASK" ] && continue
    if grep -q "$TASK" "$TRANSCRIPT" 2>/dev/null; then
      MATCHED_PARENT="$PARENT_ID"
      MATCHED_PHASE=$(jq -r --arg id "$PARENT_ID" '.[$id].phase' "$SESSIONS_FILE")
      MATCHED_TASK="$TASK"
      MATCH_COUNT=$((MATCH_COUNT + 1))
    fi
  done

  if [ "$MATCH_COUNT" -eq 1 ]; then
    register_and_exit "$MATCHED_PARENT" "$MATCHED_PHASE" "$MATCHED_TASK"
  fi
fi

# --- LLM fallback: detect + disambiguate ---
if command -v claude &>/dev/null; then
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
  TASK_LIST=""
  for PARENT_ID in $SESSION_IDS; do
    [ -z "$PARENT_ID" ] && continue
    TASK=$(jq -r --arg id "$PARENT_ID" '.[$id].task_file' "$SESSIONS_FILE")
    [ -z "$TASK" ] && continue
    TASK_LIST="${TASK_LIST}${TASK}, "
    TASK_PATH="$CWD/.flow/$TASK"
    if [ -f "$TASK_PATH" ]; then
      CONTENT=$(head -80 "$TASK_PATH" 2>/dev/null || true)
      TASK_CONTEXT="${TASK_CONTEXT}
--- ${TASK} ---
${CONTENT}
"
    fi
  done
  TASK_LIST=$(echo "$TASK_LIST" | sed 's/, $//')

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
      # Find the parent session for this task
      for PARENT_ID in $SESSION_IDS; do
        TASK=$(jq -r --arg id "$PARENT_ID" '.[$id].task_file' "$SESSIONS_FILE")
        if [ "$TASK" = "$ANSWER" ]; then
          PHASE=$(jq -r --arg id "$PARENT_ID" '.[$id].phase' "$SESSIONS_FILE")
          register_and_exit "$PARENT_ID" "$PHASE" "$ANSWER"
        fi
      done
    fi
  fi
fi

echo '{}'
exit 0
