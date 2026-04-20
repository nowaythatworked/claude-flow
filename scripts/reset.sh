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
SESSIONS_FILE="$FLOW_DIR/SESSIONS.json"

if [ ! -d "$FLOW_DIR" ]; then
  echo "ERROR: No .flow/ directory found in $CWD. Run /flow:init first." >&2
  exit 1
fi

if [ -z "$SESSION_ID" ]; then
  echo "ERROR: --session <ID> is required." >&2
  exit 1
fi

# --- Resolve task file ---
TASK_NAME=$("$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --get-task)
TASK_FILE=""
if [ -n "$TASK_NAME" ] && [ -f "$FLOW_DIR/$TASK_NAME" ]; then
  TASK_FILE="$FLOW_DIR/$TASK_NAME"
fi

# --- Collect all sibling sessions sharing the same task file ---
SIBLING_IDS=""
if [ -n "$TASK_NAME" ] && [ -f "$SESSIONS_FILE" ]; then
  SIBLING_IDS=$(jq -r --arg task "$TASK_NAME" \
    '[to_entries[] | select(.value.task_file == $task) | .key] | .[]' \
    "$SESSIONS_FILE")
fi

# --- Handle task file ---
if [ "$MODE" = "phase-only" ]; then
  "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --remove
  echo "Removed session entry"
  echo "Phase-only reset — task file unchanged"
  exit 0
fi

if [ -z "$TASK_FILE" ]; then
  # Remove all sibling sessions (or just the calling one if no siblings found)
  if [ -n "$SIBLING_IDS" ]; then
    while IFS= read -r sid; do
      "$SCRIPT_DIR/session.sh" "$CWD" "$sid" --remove
    done <<< "$SIBLING_IDS"
  else
    "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --remove
  fi
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
  # Write sessions.json with all sibling sessions and archived timestamp
  if [ -n "$SIBLING_IDS" ] && [ -f "$SESSIONS_FILE" ]; then
    ARCHIVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    # Build a keyed object with all sibling sessions, adding archived_at to each
    ARCHIVE_JSON="{}"
    while IFS= read -r sid; do
      SID_JSON=$("$SCRIPT_DIR/session.sh" "$CWD" "$sid" --get-json)
      if [ -n "$SID_JSON" ]; then
        ARCHIVE_JSON=$(echo "$ARCHIVE_JSON" | jq --arg sid "$sid" --argjson entry "$SID_JSON" --arg at "$ARCHIVED_AT" \
          '.[$sid] = ($entry + {"archived_at": $at})')
      fi
    done <<< "$SIBLING_IDS"
    echo "$ARCHIVE_JSON" > "$ARCHIVE_FOLDER/sessions.json"
  fi
  echo "Archived → .flow/archive/$(basename "$ARCHIVE_FOLDER")/"
elif [ "$MODE" = "delete" ]; then
  rm "$TASK_FILE"
  echo "Deleted $TASK_BASENAME"
fi

# --- Remove all sibling session entries ---
if [ -n "$SIBLING_IDS" ]; then
  while IFS= read -r sid; do
    "$SCRIPT_DIR/session.sh" "$CWD" "$sid" --remove
  done <<< "$SIBLING_IDS"
else
  "$SCRIPT_DIR/session.sh" "$CWD" "$SESSION_ID" --remove
fi
echo "Removed session entry"

# --- Auto-commit if inside a git repo ---
if git -C "$CWD" rev-parse --git-dir &>/dev/null 2>&1; then
  # Stage each path separately — some may not exist (moved/deleted)
  git -C "$CWD" add "$FLOW_DIR/archive/" 2>/dev/null || true
  git -C "$CWD" add "$SESSIONS_FILE" 2>/dev/null || true
  git -C "$CWD" add "$TASK_FILE" 2>/dev/null || true
  if [ "$MODE" = "archive" ]; then
    git -C "$CWD" commit --quiet -m "chore: archive $NAME_NO_EXT" 2>/dev/null || true
  else
    git -C "$CWD" commit --quiet -m "chore: reset $NAME_NO_EXT" 2>/dev/null || true
  fi
fi

echo ""
echo "Reset complete."
