#!/bin/bash
# SessionStart hook: inject always-on rules and list available dynamic rules
# Runs on startup and compact to ensure rules survive context compaction.

set -euo pipefail

# --- Stdin timeout guard (3 seconds) ---
if [ -t 0 ]; then
  INPUT=""
else
  INPUT=$(cat 2>/dev/null) || INPUT=""
fi

if [ -z "$INPUT" ]; then
  echo '{}'
  exit 0
fi

# --- Parse input JSON ---
if command -v jq &>/dev/null; then
  SOURCE=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null || true)
  CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
else
  SOURCE=$(echo "$INPUT" | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$CWD" ]; then
  echo '{}'
  exit 0
fi

# Only run on startup and compact
case "$SOURCE" in
  startup|compact) ;;
  *)
    echo '{}'
    exit 0
    ;;
esac

CONTEXT=""

# --- Always-on rules from .flow/rules/always/ ---
RULES_DIR="${CWD}/.flow/rules/always"
if [ -d "$RULES_DIR" ]; then
  ALWAYS_RULES=""
  for f in "$RULES_DIR"/*.md; do
    [ -f "$f" ] || continue
    RULE_NAME=$(basename "$f")
    CONTENT=$(cat "$f" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      ALWAYS_RULES="${ALWAYS_RULES}--- Rule [${RULE_NAME}] ---
${CONTENT}

"
    fi
  done

  if [ -n "$ALWAYS_RULES" ]; then
    CONTEXT="${CONTEXT}# Active Quality Rules
Follow these rules. If a rule is clear, apply it — no discussion needed.
Only ask the user when you encounter genuine ambiguity that you cannot resolve by reading the codebase.

${ALWAYS_RULES}"
  fi
fi

# --- List available dynamic rules ---
OPTIONAL_DIR="${CWD}/.flow/rules/dynamic"
if [ -d "$OPTIONAL_DIR" ]; then
  OPTIONAL_LIST=""
  for f in "$OPTIONAL_DIR"/*.md; do
    [ -f "$f" ] || continue
    RULE_NAME=$(basename "$f")
    OPTIONAL_LIST="${OPTIONAL_LIST}  - ${RULE_NAME}\n"
  done

  if [ -n "$OPTIONAL_LIST" ]; then
    CONTEXT="${CONTEXT}
# Available Dynamic Rules
The following dynamic rules can be auto-activated based on task context:
${OPTIONAL_LIST}
These are selected automatically when your prompt matches relevant keywords."
  fi
fi

# --- Output ---
if [ -z "$CONTEXT" ]; then
  echo '{}'
  exit 0
fi

if command -v jq &>/dev/null; then
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: $ctx
    }
  }'
else
  ESCAPED=$(printf '%s' "$CONTEXT" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$CONTEXT")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
