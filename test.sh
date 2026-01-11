set -e

echo "🔨 Building..."
nimble build -d:release > /dev/null 2>&1
echo
echo "✅ Building complete"

for test in $(ls -f examples/ | grep asl | sort); do
  file="examples/$test"
  ./aslang $file -o:sample && ./sample
  status=$?
  if [ $status -ne 0 ]; then
    echo
    echo "❌ Testing $file Failed"
    exit 1
  else
    echo
    echo "✅ Testing $file Passed"
  fi
done

for test in $(ls -f examples/project-euler/ | grep asl | sort); do
  file="examples/project-euler/$test"
  ./aslang $file -o:sample && ./sample
  status=$?
  if [ $status -ne 0 ]; then
    echo
    echo "❌ Testing $file Failed"
    exit 1
  else
    echo
    echo "✅ Testing $file Passed"
  fi
done

rm sample