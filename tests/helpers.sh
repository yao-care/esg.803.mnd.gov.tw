#!/bin/bash
# tests/helpers.sh — Minimal shell test helper with assertion functions
# Usage: source tests/helpers.sh

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# assert_eq <actual> <expected> [message]
assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="${3:-assert_eq}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$actual" = "$expected" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg (expected '$expected', got '$actual')"
  fi
}

# assert_contains <haystack> <needle> [message]
assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-assert_contains}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -q "$needle"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg (expected to contain '$needle')"
  fi
}

# assert_file_exists <path> [message]
assert_file_exists() {
  local filepath="$1"
  local msg="${2:-assert_file_exists: $filepath}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$filepath" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg (file not found: $filepath)"
  fi
}

# assert_exit_code <expected_code> <command...>
assert_exit_code() {
  local expected="$1"
  shift
  local msg="assert_exit_code: $*"
  TESTS_RUN=$((TESTS_RUN + 1))
  "$@" >/dev/null 2>&1
  local actual=$?
  if [ "$actual" -eq "$expected" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $msg (expected exit $expected, got $actual)"
  fi
}

# test_summary — Print results and exit with appropriate code
test_summary() {
  echo ""
  echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
  [ "$TESTS_FAILED" -eq 0 ] && exit 0 || exit 1
}
