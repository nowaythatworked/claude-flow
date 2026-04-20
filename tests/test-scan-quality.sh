#!/bin/bash
# Tests for scan-quality.sh
# Run: ./tests/test-scan-quality.sh
# Exit code 0 = all passed, 1 = failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"
TEST_DIR=$(mktemp -d)

source "$(dirname "$0")/helpers.sh"

# ============================================================
echo "=== scan-quality.sh ==="
# ============================================================

echo "-- clean TS content (silent) --"
FILE="$TEST_DIR/clean.ts"
echo 'const x: string = "hello"' > "$FILE"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$FILE"'","content":"const x: string = \"hello\""}}' | "$SCRIPT_DIR/scan-quality.sh")
assert_json_empty "clean TS = silent" "$RESULT"

echo "-- any type violation --"
FILE="$TEST_DIR/any-type.ts"
echo 'const x: any = 5' > "$FILE"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$FILE"'","content":"const x: any = 5"}}' | "$SCRIPT_DIR/scan-quality.sh")
assert_contains "any type flagged" "any" "$RESULT"
assert_contains "any type is violation" "violation" "$RESULT"

echo "-- as any violation --"
FILE="$TEST_DIR/as-any.ts"
echo 'const x = foo as any' > "$FILE"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$FILE"'","content":"const x = foo as any"}}' | "$SCRIPT_DIR/scan-quality.sh")
assert_contains "as any flagged" "as any" "$RESULT"
assert_contains "as any is violation" "violation" "$RESULT"

echo "-- as unknown violation --"
FILE="$TEST_DIR/as-unknown.tsx"
echo 'const x = foo as unknown' > "$FILE"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$FILE"'","content":"const x = foo as unknown"}}' | "$SCRIPT_DIR/scan-quality.sh")
assert_contains "as unknown flagged" "as unknown" "$RESULT"
assert_contains "as unknown is violation" "violation" "$RESULT"

echo "-- @ts-ignore without explanation --"
FILE="$TEST_DIR/ts-ignore.ts"
printf '// @ts-ignore\nconst x = 1\n' > "$FILE"
RESULT=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"// @ts-ignore\\nconst x = 1"}}' "$FILE" | "$SCRIPT_DIR/scan-quality.sh")
assert_contains "ts-ignore flagged" "ts-ignore" "$RESULT"
assert_contains "ts-ignore is violation" "violation" "$RESULT"

echo "-- @ts-ignore with explanation (no violation) --"
FILE="$TEST_DIR/ts-ignore-ok.ts"
echo '// @ts-ignore - legacy API returns untyped data' > "$FILE"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$FILE"'","content":"// @ts-ignore - legacy API returns untyped data"}}' | "$SCRIPT_DIR/scan-quality.sh")
assert_json_empty "ts-ignore with explanation = silent" "$RESULT"

echo "-- non-TS file (silent) --"
FILE="$TEST_DIR/script.py"
echo 'x: any = 5' > "$FILE"
RESULT=$(echo '{"tool_name":"Write","tool_input":{"file_path":"'"$FILE"'","content":"x: any = 5"}}' | "$SCRIPT_DIR/scan-quality.sh")
assert_json_empty "non-TS file = silent" "$RESULT"

echo "-- empty input (silent) --"
RESULT=$(echo '' | "$SCRIPT_DIR/scan-quality.sh")
assert_json_empty "empty input = silent" "$RESULT"

echo "-- Edit tool new_string --"
FILE="$TEST_DIR/edit-test.ts"
echo 'const x: any = 5' > "$FILE"
RESULT=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$FILE"'","new_string":"const x: any = 5"}}' | "$SCRIPT_DIR/scan-quality.sh")
assert_contains "Edit new_string any flagged" "any" "$RESULT"
assert_contains "Edit new_string is violation" "violation" "$RESULT"

# ============================================================
# Cleanup & Report
# ============================================================
rm -rf "$TEST_DIR"

report
