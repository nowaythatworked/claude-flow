#!/bin/bash
# Manage per-session state in .flow/SESSIONS
#
# Format: one line per session
#   <session_id> <phase> <task_file>
#
# Usage:
#   session.sh <CWD> <SESSION_ID> --get                          → print "phase task_file"
#   session.sh <CWD> <SESSION_ID> --get-phase                    → print phase only
#   session.sh <CWD> <SESSION_ID> --get-task                     → print task_file only
#   session.sh <CWD> <SESSION_ID> --set <phase> <task_file>      → create/update entry
#   session.sh <CWD> <SESSION_ID> --set-phase <phase>            → update phase only
#   session.sh <CWD> <SESSION_ID> --remove                       → remove entry

set -euo pipefail

CWD="${1:-.}"
SESSION_ID="${2:-}"
ACTION="${3:-}"

if [ -z "$SESSION_ID" ] || [ -z "$ACTION" ]; then
  echo "Usage: session.sh <CWD> <SESSION_ID> <--get|--get-phase|--get-task|--set|--set-phase|--remove> [args...]" >&2
  exit 1
fi

SESSIONS_FILE="$CWD/.flow/SESSIONS"

# --- Read current entry ---
read_entry() {
  if [ -f "$SESSIONS_FILE" ]; then
    grep "^${SESSION_ID} " "$SESSIONS_FILE" 2>/dev/null || true
  fi
}

# --- Remove current entry ---
remove_entry() {
  if [ -f "$SESSIONS_FILE" ]; then
    grep -v "^${SESSION_ID} " "$SESSIONS_FILE" 2>/dev/null > "${SESSIONS_FILE}.tmp" || true
    mv "${SESSIONS_FILE}.tmp" "$SESSIONS_FILE"
    # Remove file if empty
    if [ ! -s "$SESSIONS_FILE" ]; then
      rm -f "$SESSIONS_FILE"
    fi
  fi
}

case "$ACTION" in
  --get)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ]; then
      echo "$ENTRY" | awk '{print $2, $3}'
    fi
    ;;
  --get-phase)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ]; then
      echo "$ENTRY" | awk '{print $2}'
    fi
    ;;
  --get-task)
    ENTRY=$(read_entry)
    if [ -n "$ENTRY" ]; then
      echo "$ENTRY" | awk '{print $3}'
    fi
    ;;
  --set)
    PHASE="${4:-}"
    TASK_FILE="${5:-}"
    if [ -z "$PHASE" ] || [ -z "$TASK_FILE" ]; then
      echo "Usage: session.sh <CWD> <SESSION_ID> --set <phase> <task_file>" >&2
      exit 1
    fi
    mkdir -p "$CWD/.flow"
    remove_entry
    echo "${SESSION_ID} ${PHASE} ${TASK_FILE}" >> "$SESSIONS_FILE"
    ;;
  --set-phase)
    PHASE="${4:-}"
    if [ -z "$PHASE" ]; then
      echo "Usage: session.sh <CWD> <SESSION_ID> --set-phase <phase>" >&2
      exit 1
    fi
    ENTRY=$(read_entry)
    if [ -z "$ENTRY" ]; then
      echo "No session entry found for ${SESSION_ID}" >&2
      exit 1
    fi
    TASK_FILE=$(echo "$ENTRY" | awk '{print $3}')
    remove_entry
    echo "${SESSION_ID} ${PHASE} ${TASK_FILE}" >> "$SESSIONS_FILE"
    ;;
  --remove)
    remove_entry
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    exit 1
    ;;
esac
