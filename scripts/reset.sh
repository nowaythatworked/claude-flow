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

# --- Resolve task file from session ---
TASK_NAME=$("$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --get-task)
TASK_FILE=""
if [ -n "$TASK_NAME" ] && [ -f "$FLOW_DIR/$TASK_NAME" ]; then
  TASK_FILE="$FLOW_DIR/$TASK_NAME"
fi

# --- Remove session entry ---
"$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --remove
echo "Removed session entry"

# --- Handle task file ---
if [ "$MODE" = "phase-only" ]; then
  echo "Phase-only reset — task file unchanged"
  exit 0
fi

if [ -z "$TASK_FILE" ]; then
  echo "No active task file to reset"
  exit 0
fi

TASK_BASENAME=$(basename "$TASK_FILE")

if [ "$MODE" = "archive" ]; then
  ARCHIVE_DIR="$FLOW_DIR/archive"
  mkdir -p "$ARCHIVE_DIR"
  ARCHIVE_PATH="$ARCHIVE_DIR/$TASK_BASENAME"
  if [ -f "$ARCHIVE_PATH" ]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    NAME_NO_EXT="${TASK_BASENAME%.md}"
    ARCHIVE_PATH="$ARCHIVE_DIR/${NAME_NO_EXT}-${TIMESTAMP}.md"
  fi
  mv "$TASK_FILE" "$ARCHIVE_PATH"
  echo "Archived → .flow/archive/$(basename "$ARCHIVE_PATH")"
elif [ "$MODE" = "delete" ]; then
  rm "$TASK_FILE"
  echo "Deleted $TASK_BASENAME"
fi

echo ""
echo "Reset complete."
