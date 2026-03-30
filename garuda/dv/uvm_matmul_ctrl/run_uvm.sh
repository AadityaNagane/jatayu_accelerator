#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-mm_ctrl_smoke_test}"
BUILD_DIR="${BUILD_DIR:-obj_dir/tb_matmul_ctrl_fsm}"
BUILD_JOBS="${GARUDA_BUILD_JOBS:-$(nproc)}"
LOG_FILE="build/uvm_matmul_ctrl/${TESTNAME}.log"

mkdir -p "$BUILD_DIR" "$(dirname "$LOG_FILE")"

echo "[INFO] Building matmul control smoke test with Verilator"
verilator --cc --exe --build \
  --top-module tb_matmul_ctrl_fsm \
  --Mdir "$BUILD_DIR" \
  --build-jobs "$BUILD_JOBS" \
  -Igaruda/rtl \
  -Wno-fatal \
  -Wno-WIDTH \
  -Wno-UNUSED \
  -Wno-TIMESCALEMOD \
  -Wno-REDEFMACRO \
  -Wno-PINCONNECTEMPTY \
  -Wno-SELRANGE \
  -Wno-SYMRSVDWORD \
  garuda/rtl/int8_mac_instr_pkg.sv \
  garuda/rtl/int8_mac_decoder.sv \
  garuda/rtl/int8_mac_unit.sv \
  garuda/rtl/attention_microkernel_engine.sv \
  garuda/rtl/systolic_array.sv \
  garuda/rtl/systolic_pe.sv \
  garuda/rtl/gelu8_rom.sv \
  garuda/rtl/int8_mac_coprocessor.sv \
  garuda/tb/tb_matmul_ctrl_fsm.sv \
  --binary \
  -o Vtb_matmul_ctrl_fsm

echo "[INFO] Running matmul control smoke test: ${TESTNAME}"
./"$BUILD_DIR"/Vtb_matmul_ctrl_fsm | tee "$LOG_FILE"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]" "$LOG_FILE"; then
  echo "[ERROR] Matmul control smoke test reported failures"
  exit 1
fi

echo "[DONE] Matmul control smoke test passed"
echo "       Log: $LOG_FILE"
