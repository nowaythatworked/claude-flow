#!/bin/bash
# PostToolUse hook: periodically re-evaluate dynamic rules
# Debounced — only fires every N tool uses.
# When it fires, calls eval-rules-core.sh to re-evaluate which dynamic
# rules are relevant, reading the conversation transcript for full context.
# Only injects new rules if the selection changed.

set -euo pipefail

DEBOUNCE_INTERVAL=15
CACHE_DIR="/tmp/flow-rule-cache"

# --- Stdin timeout guard ---
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
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
else
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=""
  TRANSCRIPT=""
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

OPTIONAL_DIR="${CWD}/.flow/rules/dynamic"
if [ ! -d "$OPTIONAL_DIR" ]; then
  echo '{}'
  exit 0
fi

# --- Debounce ---
mkdir -p "$CACHE_DIR" 2>/dev/null || true
COUNTER_FILE="${CACHE_DIR}/tool-counter-${SESSION_ID:-default}.txt"

COUNTER=0
if [ -f "$COUNTER_FILE" ]; then
  COUNTER=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
fi
COUNTER=$((COUNTER + 1))
echo "$COUNTER" > "$COUNTER_FILE" 2>/dev/null || true

if [ $((COUNTER % DEBOUNCE_INTERVAL)) -ne 0 ]; then
  echo '{}'
  exit 0
fi

# --- Read previous selection from cache (before core overwrites it) ---
PREV_CACHE_FILE="${CACHE_DIR}/last-selection-${SESSION_ID:-default}.json"
PREV_RULES=""
if [ -f "$PREV_CACHE_FILE" ]; then
  PREV_RULES=$(jq -r '[.selected[].rule] | sort | .[]' "$PREV_CACHE_FILE" 2>/dev/null || true)
fi

# --- Call eval-rules-core.sh ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

CORE_ARGS=(--cwd "$CWD" --session-id "${SESSION_ID:-default}")
if [ -n "$TRANSCRIPT" ]; then
  CORE_ARGS+=(--transcript "$TRANSCRIPT")
fi

SELECTED=$("$SCRIPT_DIR/eval-rules-core.sh" "${CORE_ARGS[@]}" 2>/dev/null || true)

# --- Read new selection from cache (core just wrote it) ---
NEW_RULES=""
if [ -f "$PREV_CACHE_FILE" ]; then
  NEW_RULES=$(jq -r '[.selected[].rule] | sort | .[]' "$PREV_CACHE_FILE" 2>/dev/null || true)
fi

# --- Change detection: compare sorted rule filenames ---
if [ "$NEW_RULES" = "$PREV_RULES" ]; then
  echo '{}'
  exit 0
fi

# --- Load selected rules from core stdout ---
SELECTED_FILES="$SELECTED"

if [ -z "$SELECTED_FILES" ]; then
  echo '{}'
  exit 0
fi

MATCHED_RULES=""
while IFS= read -r rule_id; do
  [ -z "$rule_id" ] && continue
  rule_path="${OPTIONAL_DIR}/${rule_id}"
  if [ -f "$rule_path" ]; then
    CONTENT=$(cat "$rule_path" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      MATCHED_RULES="${MATCHED_RULES}--- Dynamic Rule [${rule_id}] (auto-selected) ---
${CONTENT}

"
    fi
  fi
done <<< "$SELECTED_FILES"

if [ -z "$MATCHED_RULES" ]; then
  echo '{}'
  exit 0
fi

MATCHED_RULES="# Dynamic Rules Updated (periodic re-evaluation)
Rules were re-evaluated based on your recent activity.
Follow them. Adjust your approach where needed.
If you already have a plan, re-evaluate it against these rules and adjust where needed.
When encountering ambiguity that cannot be resolved by reading the codebase, raise it before proceeding.

${MATCHED_RULES}"
MATCHED_RULES=$(echo "$MATCHED_RULES" | sed '/^$/N;/^\n$/d')

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$MATCHED_RULES" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$MATCHED_RULES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$MATCHED_RULES")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"additionalContext\":${ESCAPED}}}"
fi

exit 0
