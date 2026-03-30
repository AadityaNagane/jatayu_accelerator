#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-rr_smoke_test}"
DUMPFILE="${DUMPFILE:-waves/rr_${TESTNAME}.vcd}"
BUILD_DIR="${BUILD_DIR:-build/uvm_register_rename}"

mkdir -p "$BUILD_DIR" "$(dirname "$DUMPFILE")"

echo "[INFO] Compiling register-rename smoke test with Icarus"
iverilog -g2012 -o "$BUILD_DIR/tb_rr.vvp" \
  garuda/tb/tb_register_rename_table.sv \
  garuda/rtl/register_rename_table.sv

echo "[INFO] Running register-rename smoke test: ${TESTNAME}"
vvp "$BUILD_DIR/tb_rr.vvp" | tee "$BUILD_DIR/${TESTNAME}.log"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]" "$BUILD_DIR/${TESTNAME}.log"; then
  echo "[ERROR] Register-rename smoke test reported failures"
  exit 1
fi

echo "[DONE] Register-rename smoke test passed"
echo "       Test: ${TESTNAME}"
echo "       Log: $BUILD_DIR/${TESTNAME}.log"
