#!/bin/bash
set -e

# Add Nim to PATH if not already available
if ! command -v nimble &> /dev/null; then
  export PATH="/tmp/Nim-2.2.2/bin:$PATH"
fi

echo "🔨 Building..."
nimble build -d:release > /dev/null 2>&1
echo
echo "✅ Building complete"

for test in $(ls -f examples/docs | grep asl | sort); do
  file="examples/docs/$test"
  ./aslang $file -o:sample && ./sample > /dev/null
  status=$?
  if [ $status -ne 0 ]; then
    echo "❌ Failed $file"
    exit 1
  else
    echo
    echo "✅ Passed $file"
  fi
done

for test in $(ls -f examples/project-euler/ | grep asl | sort); do
  file="examples/project-euler/$test"
  ./aslang $file -o:sample && ./sample > /dev/null
  status=$?
  if [ $status -ne 0 ]; then
    echo
    echo "❌ Failed $file"
    exit 1
  else
    echo
    echo "✅ Passed $file"
  fi
done

rm sample