#!/bin/bash
# PostToolUse hook: periodically prompt re-evaluation of optional rules
# Debounced — only fires every N tool uses.
# When it fires, reads the available optional rules catalog and injects it
# as additionalContext, asking the main agent to re-evaluate which rules
# should be active. No external LLM call — the main agent does the reasoning.

set -euo pipefail

DEBOUNCE_INTERVAL=15  # Re-evaluate every N tool uses
CACHE_DIR="/tmp/flow-rule-cache"

# --- Stdin timeout guard ---
INPUT=""
if read -t 3 -r INPUT; then
  while IFS= read -t 1 -r line; do
    INPUT="${INPUT}${line}"
  done
fi

if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

# --- Parse input ---
if command -v jq &>/dev/null; then
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
else
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  SESSION_ID=""
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

OPTIONAL_DIR="${CWD}/.flow/rules/optional"
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

# --- Build rule catalog with summaries ---
RULE_CATALOG=""
for rule_file in "$OPTIONAL_DIR"/*.md; do
  [ -f "$rule_file" ] || continue
  RULE_ID=$(basename "$rule_file")
  SUMMARY=$(head -5 "$rule_file" 2>/dev/null | tr '\n' ' ')
  RULE_CATALOG="${RULE_CATALOG}  - ${RULE_ID}: ${SUMMARY}
"
done

if [ -z "$RULE_CATALOG" ]; then
  echo '{}'
  exit 0
fi

# --- Inject catalog + re-evaluation prompt ---
CONTEXT="# Periodic Rule Re-evaluation
Based on your recent work, check if additional optional rules should be active.
Available optional rules in .flow/rules/optional/:
${RULE_CATALOG}
If any of these are relevant to what you're currently working on and not yet loaded, read and apply them.
If rules you previously loaded are no longer relevant, you can deprioritize them."

CONTEXT=$(echo "$CONTEXT" | sed '/^$/N;/^\n$/d')

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$CONTEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$CONTEXT")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
