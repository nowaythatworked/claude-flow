#!/bin/bash
# Manage per-session state in .flow/SESSIONS.json
#
# Format: JSON object keyed by session ID
#   { "sess-abc": { "phase": "planning", "task_file": "my-task.md", "focus": [], "parent": null } }
#
# Usage:
#   session.sh <CWD> <SESSION_ID> --get                          → print "phase task_file"
#   session.sh <CWD> <SESSION_ID> --get-phase                    → print phase only
#   session.sh <CWD> <SESSION_ID> --get-task                     → print task_file only
#   session.sh <CWD> <SESSION_ID> --get-focus                    → print focus as JSON array
#   session.sh <CWD> <SESSION_ID> --get-json                     → print full session entry as JSON
#   session.sh <CWD> <SESSION_ID> --set <phase> <task_file>      → create/update entry
#   session.sh <CWD> <SESSION_ID> --set-phase <phase>            → update phase only
#   session.sh <CWD> <SESSION_ID> --set-focus <item> [<item>...] → set focus array
#   session.sh <CWD> <SESSION_ID> --clear-focus                  → clear focus array
#   session.sh <CWD> <SESSION_ID> --remove                       → remove entry
#   session.sh <CWD> --dump                                      → print entire file
#   session.sh <CWD> --list                                      → print all session IDs

set -euo pipefail

CWD="${1:-.}"
SESSION_ID="${2:-}"
ACTION="${3:-}"

SESSIONS_FILE="$CWD/.flow/SESSIONS.json"

# --- jq check ---
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required for session management" >&2
  exit 1
fi

# --- Ensure file exists ---
ensure_file() {
  mkdir -p "$CWD/.flow"
  if [ ! -f "$SESSIONS_FILE" ]; then
    echo '{}' > "$SESSIONS_FILE"
  fi
}

# --- Read session entry ---
read_entry() {
  if [ -f "$SESSIONS_FILE" ]; then
    jq -r --arg id "$SESSION_ID" '.[$id] // empty' "$SESSIONS_FILE" 2>/dev/null || true
  fi
}

# --- Atomic write helper ---
write_json() {
  local new_content="$1"
  echo "$new_content" > "${SESSIONS_FILE}.tmp"
  mv "${SESSIONS_FILE}.tmp" "$SESSIONS_FILE"
  # Remove file if empty object
  if [ "$(jq 'length' "$SESSIONS_FILE" 2>/dev/null)" = "0" ]; then
    rm -f "$SESSIONS_FILE"
  fi
}

# --- Handle global commands (no session ID needed) ---
if [ "$SESSION_ID" = "--dump" ]; then
  if [ -f "$SESSIONS_FILE" ]; then
    cat "$SESSIONS_FILE"
  else
    echo '{}'
  fi
  exit 0
fi

if [ "$SESSION_ID" = "--list" ]; then
  if [ -f "$SESSIONS_FILE" ]; then
    jq -r 'keys[]' "$SESSIONS_FILE" 2>/dev/null || true
  fi
  exit 0
fi

# --- Validate args ---
if [ -z "$SESSION_ID" ] || [ -z "$ACTION" ]; then
  echo "Usage: session.sh <CWD> <SESSION_ID> <action> [args...]" >&2
  echo "       session.sh <CWD> --dump" >&2
  echo "       session.sh <CWD> --list" >&2
  exit 1
fi

case "$ACTION" in
  --get)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ] && [ "$ENTRY" != "null" ]; then
      PHASE=$(echo "$ENTRY" | jq -r '.phase')
      TASK=$(echo "$ENTRY" | jq -r '.task_file')
      echo "$PHASE $TASK"
    fi
    ;;
  --get-phase)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ] && [ "$ENTRY" != "null" ]; then
      echo "$ENTRY" | jq -r '.phase'
    fi
    ;;
  --get-task)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ] && [ "$ENTRY" != "null" ]; then
      echo "$ENTRY" | jq -r '.task_file'
    fi
    ;;
  --get-focus)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ] && [ "$ENTRY" != "null" ]; then
      echo "$ENTRY" | jq -c '.focus // []'
    else
      echo '[]'
    fi
    ;;
  --get-json)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ] && [ "$ENTRY" != "null" ]; then
      echo "$ENTRY" | jq -c '.'
    fi
    ;;
  --set)
    PHASE="${4:-}"
    TASK_FILE="${5:-}"
    if [ -z "$PHASE" ] || [ -z "$TASK_FILE" ]; then
      echo "Usage: session.sh <CWD> <SESSION_ID> --set <phase> <task_file>" >&2
      exit 1
    fi
    ensure_file
    NEW=$(jq --arg id "$SESSION_ID" --arg phase "$PHASE" --arg task "$TASK_FILE" \
      '.[$id] = {"phase": $phase, "task_file": $task, "focus": [], "parent": null}' \
      "$SESSIONS_FILE")
    write_json "$NEW"
    ;;
  --set-phase)
    PHASE="${4:-}"
    if [ -z "$PHASE" ]; then
      echo "Usage: session.sh <CWD> <SESSION_ID> --set-phase <phase>" >&2
      exit 1
    fi
    ENTRY=$(read_entry)
    if [ -z "$ENTRY" ] || [ "$ENTRY" = "null" ]; then
      echo "No session entry found for ${SESSION_ID}" >&2
      exit 1
    fi
    ensure_file
    NEW=$(jq --arg id "$SESSION_ID" --arg phase "$PHASE" \
      '.[$id].phase = $phase' "$SESSIONS_FILE")
    write_json "$NEW"
    ;;
  --set-focus)
    shift 3  # past CWD, SESSION_ID, --set-focus
    if [ $# -eq 0 ]; then
      echo "Usage: session.sh <CWD> <SESSION_ID> --set-focus <item> [<item>...]" >&2
      exit 1
    fi
    ENTRY=$(read_entry)
    if [ -z "$ENTRY" ] || [ "$ENTRY" = "null" ]; then
      echo "No session entry found for ${SESSION_ID}" >&2
      exit 1
    fi
    # Build JSON array from args
    FOCUS_JSON=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
    ensure_file
    NEW=$(jq --arg id "$SESSION_ID" --argjson focus "$FOCUS_JSON" \
      '.[$id].focus = $focus' "$SESSIONS_FILE")
    write_json "$NEW"
    ;;
  --clear-focus)
    ENTRY=$(read_entry)
    if [ -z "$ENTRY" ] || [ "$ENTRY" = "null" ]; then
      echo "No session entry found for ${SESSION_ID}" >&2
      exit 1
    fi
    ensure_file
    NEW=$(jq --arg id "$SESSION_ID" \
      '.[$id].focus = []' "$SESSIONS_FILE")
    write_json "$NEW"
    ;;
  --set-parent)
    PARENT="${4:-}"
    if [ -z "$PARENT" ]; then
      echo "Usage: session.sh <CWD> <SESSION_ID> --set-parent <parent_session_id>" >&2
      exit 1
    fi
    ENTRY=$(read_entry)
    if [ -z "$ENTRY" ] || [ "$ENTRY" = "null" ]; then
      echo "No session entry found for ${SESSION_ID}" >&2
      exit 1
    fi
    ensure_file
    NEW=$(jq --arg id "$SESSION_ID" --arg parent "$PARENT" \
      '.[$id].parent = $parent' "$SESSIONS_FILE")
    write_json "$NEW"
    ;;
  --remove)
    if [ -f "$SESSIONS_FILE" ]; then
      NEW=$(jq --arg id "$SESSION_ID" 'del(.[$id])' "$SESSIONS_FILE")
      write_json "$NEW"
    fi
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    exit 1
    ;;
esac
