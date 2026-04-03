#!/bin/bash
# Initialize flow in the current project.
# Copies always-on rules and installs agents.
# Called from the /flow:init skill.

set -euo pipefail

# --- Resolve plugin root ---
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  echo "ERROR: CLAUDE_PLUGIN_ROOT is not set. Cannot locate plugin files." >&2
  exit 1
fi

if [ ! -d "$CLAUDE_PLUGIN_ROOT" ]; then
  echo "ERROR: CLAUDE_PLUGIN_ROOT ($CLAUDE_PLUGIN_ROOT) does not exist." >&2
  exit 1
fi

# Use CWD from argument or current directory
CWD="${1:-.}"

# --- 1. Create directories ---
mkdir -p "$CWD/.flow/rules/always" "$CWD/.flow/rules/dynamic" "$CWD/.claude/agents"
echo "Created directory structure"

# --- 2. Copy always-on rules ---
SRC_RULES="$CLAUDE_PLUGIN_ROOT/rules/always"
DST_RULES="$CWD/.flow/rules/always"

if [ ! -d "$SRC_RULES" ]; then
  echo "WARNING: Source rules directory not found at $SRC_RULES"
else
  copied=0
  skipped=0
  failed=0
  for f in "$SRC_RULES"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    target="$DST_RULES/$name"
    if [ -f "$target" ]; then
      skipped=$((skipped + 1))
    else
      if cp "$f" "$target"; then
        copied=$((copied + 1))
      else
        echo "ERROR: Failed to copy $name" >&2
        failed=$((failed + 1))
      fi
    fi
  done
  echo "Always-on rules: $copied copied, $skipped already existed, $failed failed"
  if [ "$failed" -gt 0 ]; then
    exit 1
  fi
fi

# --- 3. Install agents ---
SRC_AGENTS="$CLAUDE_PLUGIN_ROOT/agents/installable"
DST_AGENTS="$CWD/.claude/agents"

if [ ! -d "$SRC_AGENTS" ]; then
  echo "No installable agents found (directory missing)"
else
  installed=0
  skipped=0
  for f in "$SRC_AGENTS"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    target="$DST_AGENTS/$name"
    if [ -f "$target" ]; then
      echo "$name already exists, skipping"
      skipped=$((skipped + 1))
    else
      sed "s|__FLOW_PLUGIN_ROOT__|${CLAUDE_PLUGIN_ROOT}|g" "$f" > "$target"
      echo "Installed $name"
      installed=$((installed + 1))
    fi
  done
  echo "Agents: $installed installed, $skipped already existed"
fi

# --- 4. Create archive directory ---
mkdir -p "$CWD/.flow/archive"

# --- 5. Clean up stale state files ---
# SESSIONS.json is managed by /flow:build, not by init.
for f in SESSIONS SESSIONS.json PHASE ACTIVE_TASK; do
  if [ -f "$CWD/.flow/$f" ]; then
    rm "$CWD/.flow/$f"
    echo "Removed stale .flow/$f"
  fi
done

echo ""
echo "Init complete. Commit .flow/ and .claude/agents/ to share with your team."
