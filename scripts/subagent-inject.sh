#!/bin/bash
# SubagentStart hook: inject quality rules into subagent context
# Reads always-on rules from .flow/rules/always/ and dynamic rules
# from .flow/rules/dynamic/ to give subagents the necessary context.
# Dynamic rules are filtered to only those selected by the parent session's
# rule evaluator (cached in /tmp/flow-rule-cache/last-selection-{session_id}.json).
# Falls back to loading ALL dynamic rules if no cache exists.

set -euo pipefail

# --- Stdin timeout guard (3 seconds) ---
INPUT=""
if read -t 3 -r INPUT; then
  # Read any remaining lines
  while IFS= read -t 1 -r line; do
    INPUT="${INPUT}${line}"
  done
fi

# If no input, exit cleanly
if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

# --- Parse input JSON ---
if command -v jq &>/dev/null; then
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null || true)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
else
  # Fallback: crude extraction without jq
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=$(echo "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

# --- Collect rules ---
RULES=""

# Always-on rules from .flow/rules/always/
RULES_DIR="${CWD}/.flow/rules/always"
if [ -d "$RULES_DIR" ]; then
  for f in "$RULES_DIR"/*.md; do
    [ -f "$f" ] || continue
    RULE_NAME=$(basename "$f")
    CONTENT=$(cat "$f" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      RULES="${RULES}--- Rule [${RULE_NAME}] ---
${CONTENT}

"
    fi
  done
fi

# Dynamic rules from .flow/rules/dynamic/
# If the parent session cached its rule selection, only inject those rules.
# Otherwise fall back to loading all dynamic rules.
OPTIONAL_DIR="${CWD}/.flow/rules/dynamic"
CACHE_FILE=""
SELECTED_RULES=""

if [ -n "$SESSION_ID" ]; then
  CACHE_FILE="/tmp/flow-rule-cache/last-selection-${SESSION_ID}.json"
fi

if [ -n "$CACHE_FILE" ] && [ -f "$CACHE_FILE" ]; then
  # Extract selected rule filenames from the cache
  if command -v jq &>/dev/null; then
    SELECTED_RULES=$(jq -r '.selected[].rule // empty' "$CACHE_FILE" 2>/dev/null || true)
  fi

  if [ -n "$SELECTED_RULES" ]; then
    # Load only the selected dynamic rules
    while IFS= read -r RULE_NAME; do
      [ -n "$RULE_NAME" ] || continue
      f="${OPTIONAL_DIR}/${RULE_NAME}"
      [ -f "$f" ] || continue
      CONTENT=$(cat "$f" 2>/dev/null || true)
      if [ -n "$CONTENT" ]; then
        RULES="${RULES}--- Dynamic Rule [${RULE_NAME}] ---
${CONTENT}

"
      fi
    done <<< "$SELECTED_RULES"
  fi
  # If SELECTED_RULES is empty (cache exists but no selections), inject nothing
  # from dynamic — this is intentional (parent evaluated and chose none)
elif [ -d "$OPTIONAL_DIR" ]; then
  # No cache — fall back to loading ALL dynamic rules
  for f in "$OPTIONAL_DIR"/*.md; do
    [ -f "$f" ] || continue
    RULE_NAME=$(basename "$f")
    CONTENT=$(cat "$f" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      RULES="${RULES}--- Dynamic Rule [${RULE_NAME}] ---
${CONTENT}

"
    fi
  done
fi

# --- Output ---
if [ -z "$RULES" ]; then
  echo '{}'
  exit 0
fi

# Add instruction header and trim
RULES="# Quality Rules (auto-loaded by flow)
Follow these rules. Adjust your approach where needed.
When encountering ambiguity that cannot be resolved by reading the codebase, raise it before proceeding.

${RULES}"
RULES=$(echo "$RULES" | sed '/^$/N;/^\n$/d')

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$RULES" '{
    hookSpecificOutput: {
      hookEventName: "SubagentStart",
      additionalContext: $ctx
    }
  }'
else
  # Fallback: escape for JSON manually
  ESCAPED=$(printf '%s' "$RULES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$RULES")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
