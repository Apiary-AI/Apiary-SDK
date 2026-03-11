#!/usr/bin/env bash
# test_runner.sh — Tests for the run_tests.sh test runner itself.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test_harness.sh"

# ── Missing suite argument ───────────────────────────────────────

describe "Missing suite argument"

set +e
output=$(bash "${SCRIPT_DIR}/run_tests.sh" nonexistent_suite 2>&1)
rc=$?
set -e

assert_ne "$rc" "0" "exits non-zero for missing suite file"
assert_contains "$output" "ERROR" "prints ERROR for missing suite"
assert_contains "$output" "FAILED" "prints FAILED in summary"
assert_not_contains "$output" "ALL SUITES PASSED" "does not print ALL SUITES PASSED"

# ── Misspelled suite argument ────────────────────────────────────

describe "Misspelled suite argument"

set +e
output=$(bash "${SCRIPT_DIR}/run_tests.sh" clietn 2>&1)
rc=$?
set -e

assert_ne "$rc" "0" "exits non-zero for misspelled suite name"
assert_contains "$output" "Failed suites:" "reports failed suites"

# ── Mix of valid and missing suites ──────────────────────────────

describe "Mix of valid and missing suites"

set +e
output=$(bash "${SCRIPT_DIR}/run_tests.sh" client bogus 2>&1)
rc=$?
set -e

assert_ne "$rc" "0" "exits non-zero when any suite is missing"
assert_contains "$output" "bogus" "mentions missing suite in failure output"
assert_contains "$output" "FAILED" "prints FAILED when mix includes missing"

test_summary
