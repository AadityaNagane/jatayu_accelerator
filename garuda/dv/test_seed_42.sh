#!/bin/bash
# Test systolic random with seed 42
echo "======================================"
echo "Testing seed 42..."
echo "======================================"
SEED=42 TESTNAME=sa_random_test bash garuda/dv/uvm_systolic/run_uvm.sh 2>&1 | tail -30
