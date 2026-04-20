#!/bin/bash
# Tests for stop-rule-check.sh
# Run: ./tests/test-stop-rule-check.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

# ============================================================
echo "=== stop-rule-check.sh ==="
# ============================================================

echo "-- first stop (stop_hook_active=false) blocks --"
setup
RESULT=$(echo '{"stop_hook_active": false}' | "$SCRIPT_DIR/stop-rule-check.sh")
assert_contains "decision is block" '"block"' "$RESULT"
assert_contains "reason mentions compliance check" "quality rules" "$RESULT"

echo "-- first stop (stop_hook_active missing) blocks --"
setup
RESULT=$(echo '{}' | "$SCRIPT_DIR/stop-rule-check.sh")
assert_contains "decision is block when key missing" '"block"' "$RESULT"

echo "-- second stop (stop_hook_active=true) allows --"
setup
RESULT=$(echo '{"stop_hook_active": true}' | "$SCRIPT_DIR/stop-rule-check.sh")
assert_empty "second stop produces no output" "$RESULT"

echo "-- empty input exits silently --"
setup
RESULT=$(echo '' | "$SCRIPT_DIR/stop-rule-check.sh")
assert_empty "empty input produces no output" "$RESULT"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

report
