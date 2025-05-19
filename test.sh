#!/usr/bin/env bash

set -euo pipefail

echo "Bootstrapping compiler..."
if ! ./bootstrap.sh > /dev/null 2>&1; then
    echo "❌ Failed to bootstrap compiler"
    exit 1
fi

echo "Starting tests..."
echo

# Track failures
failures=0
passed=0
skipped=0

for dir in project-euler/*/; do
    solution_asl="${dir}solution.asl"
    solution_c="${dir}solution.c"

    if [[ ! -f "$solution_asl" ]]; then
        echo "⚠️  Skipping $dir — no solution.asl found"
        ((skipped++))
        continue
    fi

    echo "▶️  Testing ${dir}"

    # Step 1: Run ASLang
    if ! ./asl "$solution_asl"; then
        echo "❌ ASLang compilation failed for $solution_asl"
        ((failures++))
        continue
    fi

    if [[ ! -x example ]]; then
        echo "❌ ASLang output binary not found or not executable"
        ((failures++))
        continue
    fi

    if ! output_asl=$(./example | tail -n1); then
        echo "❌ ASLang program crashed or failed to produce output"
        ((failures++))
        continue
    fi

    # Step 2: Compile and run C
    if ! gcc "$solution_c" -o example_c; then
        echo "❌ C compilation failed for $solution_c"
        ((failures++))
        continue
    fi

    if [[ ! -x example_c ]]; then
        echo "❌ Compiled C binary not found or not executable"
        ((failures++))
        continue
    fi

    if ! output_c=$(./example_c | tail -n1); then
        echo "❌ C program crashed or failed to produce output"
        ((failures++))
        continue
    fi

    # Step 3: Compare outputs
    if [[ "$output_asl" != "$output_c" ]]; then
        echo "❌ Output mismatch in $dir"
        echo "    ASLang: $output_asl"
        echo "    C Code: $output_c"
        diff <(echo "$output_asl") <(echo "$output_c") || true
        ((failures++))
        continue
    fi

    # Clean up
    rm -f example example_c
    echo "✅ Output matches for $dir"
    ((passed++))
    echo
done

echo
echo "Test Summary:  ✅ Passed: $passed  ❌ Failed: $failures  ⚠️ Skipped: $skipped"
echo

if [[ $failures -gt 0 ]]; then
    echo "❌ Some tests failed."
    exit 1
else
    echo "🎉 All tests passed!"
    exit 0
fi
