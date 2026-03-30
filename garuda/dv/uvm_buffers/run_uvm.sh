#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-buffer_smoke_test}"
BUILD_DIR="${BUILD_DIR:-obj_dir/tb_buffer_subsystem}"
BUILD_JOBS="${GARUDA_BUILD_JOBS:-$(nproc)}"
LOG_FILE="${BUILD_DIR}/${TESTNAME}.log"

mkdir -p "$BUILD_DIR"

echo "[INFO] Building buffer subsystem smoke test with Verilator"
verilator --cc --exe --build \
	--top-module tb_buffer_subsystem \
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
	garuda/rtl/weight_buffer.sv \
	garuda/rtl/activation_buffer.sv \
	garuda/rtl/accumulator_buffer.sv \
	garuda/rtl/buffer_subsystem.sv \
	garuda/tb/tb_buffer_subsystem.sv \
	--binary \
	-o Vtb_buffer_subsystem

echo "[INFO] Running buffer subsystem smoke test: ${TESTNAME}"
./"$BUILD_DIR"/Vtb_buffer_subsystem | tee "$LOG_FILE"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]" "$LOG_FILE"; then
	echo "[ERROR] Buffer subsystem smoke test reported failures"
	exit 1
fi

echo "[DONE] Buffer subsystem smoke test passed"
echo "       Log: $LOG_FILE"
