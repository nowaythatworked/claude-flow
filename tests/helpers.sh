#!/bin/bash
# Shared test helpers for flow plugin tests.
# Source this file from test scripts:
#   source "$(dirname "$0")/helpers.sh"

PASS=0
FAIL=0

# --- Setup / Teardown ---
setup() {
  rm -rf "$TEST_DIR"
  mkdir -p "$TEST_DIR/.flow"
}

# --- Assertions ---
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (file not found: $path)"
  fi
}

assert_file_not_exists() {
  local label="$1" path="$2"
  if [ ! -f "$path" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (file should not exist: $path)"
  fi
}

assert_contains() {
  local label="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label"
    echo "    expected to contain: $expected"
    echo "    actual: $actual"
  fi
}

assert_not_contains() {
  local label="$1" unexpected="$2" actual="$3"
  if ! echo "$actual" | grep -q "$unexpected"; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label"
    echo "    should NOT contain: $unexpected"
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (expected empty, got: $actual)"
  fi
}

assert_not_empty() {
  local label="$1" actual="$2"
  if [ -n "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (expected non-empty, got empty)"
  fi
}

assert_dir_not_exists() {
  local label="$1" path="$2"
  if [ ! -d "$path" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (directory exists: $path)"
  fi
}

assert_json_empty() {
  local label="$1" actual="$2"
  if [ "$actual" = "{}" ] || [ -z "$actual" ]; then
    PASS=$((PASS + 1))
    echo "  ✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "  ✗ $label (expected {}, got: $actual)"
  fi
}

# --- Report ---
report() {
  echo ""
  echo "================================"
  echo "Results: $PASS passed, $FAIL failed"
  echo "================================"

  if [ "$FAIL" -gt 0 ]; then
    exit 1
  fi
}
