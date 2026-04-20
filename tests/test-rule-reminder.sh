#!/bin/bash
# Tests for rule-reminder.sh
# Run: ./tests/test-rule-reminder.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

# ============================================================
echo "=== rule-reminder.sh ==="
# ============================================================

echo "-- no rules directories --"
setup
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/rule-reminder.sh")
assert_json_empty "no rules dirs = silent" "$RESULT"

echo "-- empty rules directory --"
setup
mkdir -p "$TEST_DIR/.flow/rules/always"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/rule-reminder.sh")
assert_json_empty "empty rules dir = silent" "$RESULT"

echo "-- always-on rules exist --"
setup
mkdir -p "$TEST_DIR/.flow/rules/always"
printf "# Test Rule\nDo the right thing.\n" > "$TEST_DIR/.flow/rules/always/test-rule.md"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/rule-reminder.sh")
assert_contains "reminder with always rules" "Quality rules are active" "$RESULT"

echo "-- dynamic rules exist --"
setup
mkdir -p "$TEST_DIR/.flow/rules/dynamic"
printf "# Dynamic Rule\nConditional guidance.\n" > "$TEST_DIR/.flow/rules/dynamic/test-rule.md"
RESULT=$(echo '{"cwd":"'"$TEST_DIR"'"}' | "$SCRIPT_DIR/rule-reminder.sh")
assert_contains "reminder with dynamic rules" "Quality rules are active" "$RESULT"

echo "-- empty input --"
setup
RESULT=$(echo '' | "$SCRIPT_DIR/rule-reminder.sh")
assert_json_empty "empty input = silent" "$RESULT"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

report
