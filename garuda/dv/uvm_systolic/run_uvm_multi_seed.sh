#!/usr/bin/env bash
# Multi-seed test runner for Systolic Array
# Usage:
#   bash garuda/dv/uvm_systolic/run_uvm_multi_seed.sh [test_name] [seed_start] [seed_end]
# Examples:
#   bash garuda/dv/uvm_systolic/run_uvm_multi_seed.sh sa_random_test 1 10
#   bash garuda/dv/uvm_systolic/run_uvm_multi_seed.sh sa_smoke_test 1 5

set -euo pipefail

TESTNAME="${1:-sa_random_test}"
SEED_START="${2:-1}"
SEED_END="${3:-10}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

PASS_COUNT=0
FAIL_COUNT=0

echo "╔════════════════════════════════════════════════════╗"
echo "║  Multi-Seed Test Runner: ${TESTNAME}             ║"
echo "║  Seeds: ${SEED_START} to ${SEED_END}                              ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

for seed in $(seq $SEED_START $SEED_END); do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "▶ Testing seed ${seed}/${SEED_END}..."  
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Run test and save output for debugging
    TEST_OUTPUT=$(SEED=$seed TESTNAME="$TESTNAME" bash garuda/dv/uvm_systolic/run_uvm.sh 2>&1)
    
    # Check if test passed
    if echo "$TEST_OUTPUT" | grep -q "ALL TESTS PASSED"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "✅ Seed $seed: PASSED"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "❌ Seed $seed: FAILED"
        # Debug: show last few lines
        echo "$TEST_OUTPUT" | tail -5
    fi
    echo ""
done

echo "╔════════════════════════════════════════════════════╗"
echo "║  Test Results                                      ║"
echo "╠════════════════════════════════════════════════════╣"
echo "│ Total seeds: $((SEED_END - SEED_START + 1))                           │"
echo "│ Passed:      ${PASS_COUNT}                                  │"
echo "│ Failed:      ${FAIL_COUNT}                                  │"
echo "╚════════════════════════════════════════════════════╝"

if [ $FAIL_COUNT -eq 0 ]; then
    echo ""
    echo "🎉 All seeds passed!"
    exit 0
else
    echo ""
    echo "❌ Some seeds failed"
    exit 1
fi
