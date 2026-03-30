#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-dma_smoke_test}"
DUMPFILE="${DUMPFILE:-waves/dma_${TESTNAME}.vcd}"
BUILD_DIR="${BUILD_DIR:-build/dma_sim}"

mkdir -p "$BUILD_DIR" "$(dirname "$DUMPFILE")"

echo "[INFO] Compiling DMA smoke test with Icarus"
iverilog -g2012 -o "$BUILD_DIR/tb_dma.vvp" \
  garuda/tb/tb_dma_simple.sv

echo "[INFO] Running DMA smoke test: ${TESTNAME}"
timeout 20s vvp "$BUILD_DIR/tb_dma.vvp" | tee "$BUILD_DIR/${TESTNAME}.log"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]" "$BUILD_DIR/${TESTNAME}.log"; then
  echo "[ERROR] DMA smoke test reported failures"
  exit 1
fi

echo "[DONE] DMA smoke test passed"
echo "       Log: $BUILD_DIR/${TESTNAME}.log"
