#!/bin/bash
# Tests for flow-next-lock.sh
# Run: ./tests/test-flow-next-lock.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

export CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ============================================================
echo "=== flow-next-lock.sh ==="
# ============================================================

echo "-- non-/flow:next prompt = silent --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set implementing task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"hello"}' | "$SCRIPT_DIR/flow-next-lock.sh")
assert_json_empty "non-flow:next = silent" "$RESULT"

echo "-- no SESSIONS.json = silent --"
setup
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"/flow:next"}' | "$SCRIPT_DIR/flow-next-lock.sh")
assert_json_empty "no SESSIONS.json = silent" "$RESULT"

echo "-- non-implementing phase = silent --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set planned task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"/flow:next"}' | "$SCRIPT_DIR/flow-next-lock.sh")
assert_json_empty "planned phase = silent" "$RESULT"

echo "-- /flow:next in implementing = locks phase --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set implementing task.md
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set-focus "Auth Middleware" "Rate Limiting"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"/flow:next"}' | "$SCRIPT_DIR/flow-next-lock.sh")
assert_contains "output has additionalContext" "additionalContext" "$RESULT"
assert_contains "output has lock message" "Phase pre-locked" "$RESULT"
PHASE=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --get-phase)
assert_eq "phase changed to planned" "planned" "$PHASE"
FOCUS=$("$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --get-focus)
assert_eq "focus cleared" "[]" "$FOCUS"

echo "-- /flow:next --no-lock = silent --"
setup
"$SCRIPT_DIR/session.sh" "$TEST_DIR" s1 --set implementing task.md
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'","session_id":"s1","prompt":"/flow:next --no-lock"}' | "$SCRIPT_DIR/flow-next-lock.sh")
assert_json_empty "--no-lock = silent" "$RESULT"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

report
