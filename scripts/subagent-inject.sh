#!/bin/bash
# SubagentStart hook: inject quality rules into subagent context
# Reads always-on rules from .flow/rules/always/ and optional rules
# from .flow/rules/optional/ to give subagents the necessary context.

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
else
  # Fallback: crude extraction without jq
  CWD=$(echo "$INPUT" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
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

# Optional rules from .flow/rules/optional/
OPTIONAL_DIR="${CWD}/.flow/rules/optional"
if [ -d "$OPTIONAL_DIR" ]; then
  for f in "$OPTIONAL_DIR"/*.md; do
    [ -f "$f" ] || continue
    RULE_NAME=$(basename "$f")
    CONTENT=$(cat "$f" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      RULES="${RULES}--- Optional Rule [${RULE_NAME}] ---
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
      additionalContext: $ctx
    }
  }'
else
  # Fallback: escape for JSON manually
  ESCAPED=$(printf '%s' "$RULES" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$RULES")
  echo "{\"hookSpecificOutput\":{\"additionalContext\":${ESCAPED}}}"
fi

exit 0
