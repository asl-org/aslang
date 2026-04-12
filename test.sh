#!/bin/bash
set -uo pipefail

PASS=0
FAIL=0
ERRORS=""

# Build
echo "Building..."
if ! nimble build 2>&1 | tail -1; then
  echo "Build failed."
  exit 1
fi
echo ""

# Positive examples — must exit 0
echo "=== Positive examples ==="
for f in examples/*.asl; do
  name=$(basename "$f")
  output=$(./asl build "$f" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  OK    $name"
    PASS=$((PASS + 1))
  else
    msg=$(echo "$output" | grep "ERROR" | head -1 | sed 's/.*\] - //')
    echo "  FAIL  $name  ->  $msg"
    ERRORS="$ERRORS\n  FAIL $name -> $msg"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

# Negative examples — must exit non-zero
echo "=== Negative examples ==="
for f in examples/errors/*.asl; do
  name=$(basename "$f")
  # Skip support files that aren't meant to be entry points
  case "$name" in
    dep.asl|cycle_b.asl) continue ;;
  esac
  output=$(./asl build "$f" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    msg=$(echo "$output" | grep "ERROR" | head -1 | sed 's/.*\] - //')
    echo "  OK    $name  ->  $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $name  (expected error but exit code was 0)"
    ERRORS="$ERRORS\n  FAIL $name (expected error but exit code was 0)"
    FAIL=$((FAIL + 1))
  fi
done
echo ""

# Summary
TOTAL=$((PASS + FAIL))
echo "=== Summary ==="
echo "  $PASS/$TOTAL passed"
if [ "$FAIL" -gt 0 ]; then
  echo "  $FAIL/$TOTAL FAILED"
  echo ""
  echo "Failures:"
  echo -e "$ERRORS"
  exit 1
else
  echo "  All tests passed."
  exit 0
fi
