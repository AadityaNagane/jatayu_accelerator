#!/bin/bash
set -e

echo "Testing all components..."

echo ""
echo "=== Full UVM Regression ==="
bash garuda/dv/run_uvm_regression.sh 2>&1 | tail -10

echo ""
echo "=== Multi-Seed Test (seeds 1-5) ==="
bash garuda/dv/uvm_systolic/run_uvm_multi_seed.sh sa_random_test 1 5 2>&1 | tail -20

echo ""
echo "=== All Tests Complete ==="
