#!/bin/bash
set -e

# Add Nim to PATH if not already available
if ! command -v nimble &> /dev/null; then
  export PATH="/tmp/Nim-2.2.2/bin:$PATH"
fi

echo "Building..."
nimble build -d:release > /dev/null 2>&1
echo
echo "Building complete"
echo

# Detect platform
OS="$(uname -s)"

# Timeout wrapper (macOS lacks `timeout`)
run_with_timeout() {
  local seconds="$1"
  shift
  "$@" &
  local pid=$!
  (sleep $seconds && kill $pid 2>/dev/null) &
  local watcher=$!
  wait $pid 2>/dev/null
  local status=$?
  kill $watcher 2>/dev/null
  wait $watcher 2>/dev/null
  return $status
}

failed=0
passed=0

check_memory() {
  local file="$1"

  # Phase 1: AddressSanitizer (use-after-free, buffer overflow, double-free)
  export CC=gcc
  export CFLAGS="-O1 -g -fsanitize=address -fno-omit-frame-pointer"
  ./aslang $file -o:sample_asan 2>/dev/null
  ./sample_asan > /dev/null 2>/tmp/asan_output || true
  if grep -q "ERROR: AddressSanitizer" /tmp/asan_output 2>/dev/null; then
    echo "Memory error in $file"
    grep -A 20 "ERROR: AddressSanitizer" /tmp/asan_output
    echo
    rm -f sample_asan
    return 1
  fi
  rm -f sample_asan

  # Phase 2: Leak detection (platform-specific)
  case "$OS" in
    Darwin)
      # macOS: recompile without ASan for accurate leak detection
      export CFLAGS="-O1 -g"
      ./aslang $file -o:sample_leak 2>/dev/null
      run_with_timeout 30 leaks --atExit -- ./sample_leak > /tmp/leak_output 2>&1 || true
      if grep -q "0 leaks for 0 total leaked bytes" /tmp/leak_output 2>/dev/null; then
        rm -f sample_leak
        return 0
      elif grep -q "leaks for" /tmp/leak_output 2>/dev/null; then
        local leak_summary=$(grep "leaks for" /tmp/leak_output)
        echo "Memory leak in $file"
        echo "  $leak_summary"
        rm -f sample_leak
        return 1
      fi
      rm -f sample_leak
      ;;
    Linux)
      # Linux: LeakSanitizer runs with ASan binary
      export CFLAGS="-O1 -g -fsanitize=address -fno-omit-frame-pointer"
      ./aslang $file -o:sample_leak 2>/dev/null
      ASAN_OPTIONS="detect_leaks=1" ./sample_leak > /dev/null 2>/tmp/leak_output || true
      if grep -q "ERROR: LeakSanitizer" /tmp/leak_output 2>/dev/null; then
        echo "Memory leak in $file"
        grep "SUMMARY" /tmp/leak_output 2>/dev/null || true
        rm -f sample_leak
        return 1
      fi
      rm -f sample_leak
      ;;
  esac
  return 0
}

echo "Running memory sanitization ($OS)..."
echo

for test in $(ls -f examples/docs | grep asl | sort); do
  file="examples/docs/$test"
  if check_memory "$file"; then
    echo "Clean $file"
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

for test in $(ls -f examples/project-euler/ | grep asl | sort); do
  file="examples/project-euler/$test"
  if check_memory "$file"; then
    echo "Clean $file"
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

rm -f /tmp/asan_output /tmp/leak_output

echo
echo "Results: $passed passed, $failed failed"
[ $failed -eq 0 ] || exit 1
