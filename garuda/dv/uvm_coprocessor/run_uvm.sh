#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-cvxif_smoke_test}"
BUILD_DIR="${BUILD_DIR:-obj_dir/tb_norm_act_ctrl}"
BUILD_JOBS="${GARUDA_BUILD_JOBS:-$(nproc)}"
LOG_FILE="build/uvm_coprocessor/${TESTNAME}.log"

mkdir -p "$BUILD_DIR" "$(dirname "$LOG_FILE")"

echo "[INFO] Building coprocessor/control-path smoke test with Verilator"
verilator --cc --exe --build \
  --top-module tb_norm_act_ctrl \
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
  garuda/tb/tb_norm_act_ctrl.sv \
  --binary \
  -o Vtb_norm_act_ctrl

echo "[INFO] Running coprocessor smoke test: ${TESTNAME}"
./"$BUILD_DIR"/Vtb_norm_act_ctrl | tee "$LOG_FILE"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]" "$LOG_FILE"; then
  echo "[ERROR] Coprocessor smoke test reported failures"
  exit 1
fi

echo "[DONE] Coprocessor smoke test passed"
echo "       Log: $LOG_FILE"
