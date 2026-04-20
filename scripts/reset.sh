#!/bin/bash
# Reset flow state: archive/delete the active task file and remove session entry.
# Called from the /flow:reset skill.
#
# Usage: reset.sh [--archive|--delete|--phase-only] --session <ID> [CWD]
#   --archive    (default) move task file to .flow/archive/
#   --delete     remove task file without archiving
#   --phase-only only remove session entry, keep task file as-is
#   --session ID the session to reset (required)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODE="archive"
CWD=""
SESSION_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --archive) MODE="archive" ;;
    --delete) MODE="delete" ;;
    --phase-only) MODE="phase-only" ;;
    --session) SESSION_ID="$2"; shift ;;
    *) CWD="$1" ;;
  esac
  shift
done

CWD="${CWD:-.}"
FLOW_DIR="$CWD/.flow"

if [ ! -d "$FLOW_DIR" ]; then
  echo "ERROR: No .flow/ directory found in $CWD. Run /flow:init first." >&2
  exit 1
fi

if [ -z "$SESSION_ID" ]; then
  echo "ERROR: --session <ID> is required." >&2
  exit 1
fi

# --- Resolve task file and capture session JSON ---
TASK_NAME=$("$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --get-task)
SESSION_JSON=$("$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --get-json)
TASK_FILE=""
if [ -n "$TASK_NAME" ] && [ -f "$FLOW_DIR/$TASK_NAME" ]; then
  TASK_FILE="$FLOW_DIR/$TASK_NAME"
fi

# --- Handle task file ---
if [ "$MODE" = "phase-only" ]; then
  "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --remove
  echo "Removed session entry"
  echo "Phase-only reset — task file unchanged"
  exit 0
fi

if [ -z "$TASK_FILE" ]; then
  "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --remove
  echo "Removed session entry"
  echo "No active task file to reset"
  exit 0
fi

TASK_BASENAME=$(basename "$TASK_FILE")
NAME_NO_EXT="${TASK_BASENAME%.md}"

if [ "$MODE" = "archive" ]; then
  ARCHIVE_DIR="$FLOW_DIR/archive"
  ARCHIVE_FOLDER="$ARCHIVE_DIR/$NAME_NO_EXT"
  if [ -d "$ARCHIVE_FOLDER" ]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    ARCHIVE_FOLDER="$ARCHIVE_DIR/${NAME_NO_EXT}-${TIMESTAMP}"
  fi
  mkdir -p "$ARCHIVE_FOLDER"
  mv "$TASK_FILE" "$ARCHIVE_FOLDER/$TASK_BASENAME"
  # Write session.json with session ID and archived timestamp
  if [ -n "$SESSION_JSON" ]; then
    ARCHIVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    echo "$SESSION_JSON" | jq --arg sid "$SESSION_ID" --arg at "$ARCHIVED_AT" \
      '. + {"session_id": $sid, "archived_at": $at}' \
      > "$ARCHIVE_FOLDER/session.json"
  fi
  echo "Archived → .flow/archive/$(basename "$ARCHIVE_FOLDER")/"
elif [ "$MODE" = "delete" ]; then
  rm "$TASK_FILE"
  echo "Deleted $TASK_BASENAME"
fi

# --- Remove session entry ---
"$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --remove
echo "Removed session entry"

echo ""
echo "Reset complete."
