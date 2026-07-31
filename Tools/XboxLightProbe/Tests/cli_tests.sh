#!/bin/sh
set -eu

probe="./build/xbox-light-probe"

make clean all >/tmp/xbox-light-probe-build.log

dry_run_output="$($probe)"
printf '%s\n' "$dry_run_output" | grep -F "DRY RUN: no USB access performed" >/dev/null
printf '%s\n' "$dry_run_output" | grep -F "packet: 0a 20 01 03 00 01 14" >/dev/null

set +e
$probe --visual-test >/tmp/xbox-light-probe-removed-visual-test.log 2>&1
removed_visual_test_status=$?
set -e
test "$removed_visual_test_status" -eq 64
grep -F "usage: xbox-light-probe" \
  /tmp/xbox-light-probe-removed-visual-test.log >/dev/null

set +e
$probe --execute >/tmp/xbox-light-probe-missing-ack.log 2>&1
missing_ack_status=$?
set -e
test "$missing_ack_status" -eq 64
grep -F -- "--acknowledge-temporary-disconnect is required" \
  /tmp/xbox-light-probe-missing-ack.log >/dev/null

set +e
$probe --execute --acknowledge-temporary-disconnect \
  >/tmp/xbox-light-probe-non-root.log 2>&1
non_root_status=$?
set -e
test "$non_root_status" -eq 77
grep -F "execution requires root" /tmp/xbox-light-probe-non-root.log >/dev/null

echo "cli tests passed"
