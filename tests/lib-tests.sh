#!/usr/bin/env bash
# Sourced by run-tests.sh. REPO_ROOT is set by the runner.
source "$REPO_ROOT/lib/exec.sh"

# run_mut in dry-run mode prints instead of executing
DRY_RUN=1
out=$(run_mut touch /tmp/manjaro-sl-should-never-exist)
assert_contains "$out" "+ touch /tmp/manjaro-sl-should-never-exist"
assert_fail test -e /tmp/manjaro-sl-should-never-exist

# run_mut executes when DRY_RUN=0
DRY_RUN=0
tmpf=$(mktemp -u)
run_mut touch "$tmpf" >/dev/null
assert_ok test -e "$tmpf"
rm -f "$tmpf"

# log_dir creates and echoes the state dir
d=$(XDG_STATE_HOME=$(mktemp -d) log_dir)
assert_ok test -d "$d"
assert_contains "$d" "manjaro-sl"

# run_step detects failure even without caller pipefail (regression)
step_fail() { return 7; }
# Test 1: failing step with "n" (abort) should return nonzero, not swallowed by pipeline
(
  set +o pipefail
  XDG_STATE_HOME=$(mktemp -d)
  RUN_LOG=""
  run_step "test_fail" step_fail <<< "n" >/dev/null 2>&1
)
assert_fail test "$?" -eq 0
# Test 2: failing step with "y" (continue) should return 0
(
  set +o pipefail
  XDG_STATE_HOME=$(mktemp -d)
  RUN_LOG=""
  run_step "test_fail" step_fail <<< "y" >/dev/null 2>&1
)
assert_ok test "$?" -eq 0
