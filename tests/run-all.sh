#!/bin/bash
# Run all unit tests (skips integration tests that need Claude CLI).
# Exit code 0 = all passed, 1 = failures.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_FILES=""

for test_file in "$DIR"/test-*.sh; do
  name=$(basename "$test_file")

  # Skip integration tests — they require a live Claude CLI session
  if [ "$name" = "test-integration.sh" ]; then
    echo "SKIP: $name (requires Claude CLI)"
    echo ""
    continue
  fi

  echo "=== $name ==="
  if bash "$test_file" 2>&1; then
    : # test prints its own results
  else
    FAILED_FILES="$FAILED_FILES $name"
  fi
  echo ""
done

echo "==============================="
if [ -n "$FAILED_FILES" ]; then
  echo "FAILED:$FAILED_FILES"
  exit 1
else
  echo "All test files passed."
  exit 0
fi
