#!/bin/bash
# Test systolic random with multiple seeds (1-10)
echo "======================================"
echo "Testing seeds 1-10..."
echo "======================================"
for seed in {1..10}; do
  echo -e "\n>>> Testing seed $seed..."
  SEED=$seed TESTNAME=sa_random_test bash garuda/dv/uvm_systolic/run_uvm.sh 2>&1 | grep -E "PASS|FAIL|Mismatch"
done
