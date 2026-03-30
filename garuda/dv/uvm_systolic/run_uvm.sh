#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-sa_smoke_test}"
DUMPFILE="${DUMPFILE:-waves/systolic_${TESTNAME}.vcd}"
BUILD_DIR="${BUILD_DIR:-build/uvm_systolic}"

mkdir -p "$BUILD_DIR" "$(dirname "$DUMPFILE")"

echo "[INFO] Compiling systolic smoke test with Icarus"
iverilog -g2012 -o "$BUILD_DIR/tb_sa.vvp" \
  garuda/tb/tb_systolic_array.sv \
  garuda/rtl/systolic_array.sv \
  garuda/rtl/systolic_pe.sv

echo "[INFO] Running systolic smoke test: ${TESTNAME}"
vvp "$BUILD_DIR/tb_sa.vvp" | tee "$BUILD_DIR/${TESTNAME}.log"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]" "$BUILD_DIR/${TESTNAME}.log"; then
  echo "[ERROR] Systolic smoke test reported failures"
  exit 1
fi

echo "[DONE] Systolic smoke test passed"
echo "       Test: ${TESTNAME}"
echo "       Log: $BUILD_DIR/${TESTNAME}.log"
