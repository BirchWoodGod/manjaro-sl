#!/usr/bin/env bash
# Minimal test runner: sources every tests/*-tests.sh and reports.
set -uo pipefail
TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(dirname "$TESTS_DIR")
PASS=0; FAIL=0; CURRENT=""

assert_eq()       { if [ "$1" = "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL($CURRENT): expected [$2] got [$1]"; fi; }
assert_contains() { if [[ "$1" == *"$2"* ]]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL($CURRENT): [$1] lacks [$2]"; fi; }
assert_ok()       { if "$@"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL($CURRENT): $* returned nonzero"; fi; }
assert_fail()     { if "$@"; then FAIL=$((FAIL+1)); echo "FAIL($CURRENT): $* unexpectedly succeeded"; else PASS=$((PASS+1)); fi; }

for f in "$TESTS_DIR"/*-tests.sh; do
  [ "$(basename "$f")" = "run-tests.sh" ] && continue
  CURRENT=$(basename "$f")
  # shellcheck source=/dev/null
  source "$f"
done
echo "----"; echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
