#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-amk_smoke_test}"
DUMPFILE="${DUMPFILE:-waves/attention_${TESTNAME}.vcd}"
BUILD_DIR="${BUILD_DIR:-build/uvm_attention}"

mkdir -p "$BUILD_DIR" "$(dirname "$DUMPFILE")"

echo "[INFO] Compiling attention smoke test with Icarus"
iverilog -g2012 -o "$BUILD_DIR/tb_attention.vvp" \
  garuda/rtl/attention_microkernel_engine.sv \
  garuda/tb/tb_attention_microkernel_latency.sv

echo "[INFO] Running attention smoke test: ${TESTNAME}"
vvp "$BUILD_DIR/tb_attention.vvp" | tee "$BUILD_DIR/${TESTNAME}.log"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]" "$BUILD_DIR/${TESTNAME}.log"; then
  echo "[ERROR] Attention smoke test reported failures"
  exit 1
fi

echo "[DONE] Attention smoke test passed"
echo "       Test: ${TESTNAME}"
echo "       Log: $BUILD_DIR/${TESTNAME}.log"
