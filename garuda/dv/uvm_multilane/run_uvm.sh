#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-multilane_smoke_test}"
BUILD_DIR="${BUILD_DIR:-obj_dir/tb_multilane_mac_unit}"
BUILD_JOBS="${GARUDA_BUILD_JOBS:-$(nproc)}"
LOG_FILE="${BUILD_DIR}/${TESTNAME}.log"

mkdir -p "$BUILD_DIR"

echo "[INFO] Building multilane smoke test with Verilator"
verilator --cc --exe --build \
	--top-module tb_multilane_mac_unit \
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
	garuda/rtl/int8_mac_multilane_unit.sv \
	garuda/rtl/int8_mac_multilane_wrapper.sv \
	garuda/tb/tb_multilane_mac_unit.sv \
	--binary \
	-o Vtb_multilane_mac_unit

echo "[INFO] Running multilane smoke test: ${TESTNAME}"
./"$BUILD_DIR"/Vtb_multilane_mac_unit | tee "$LOG_FILE"

if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|\[FAIL\]|(^|[[:space:]])FAIL:" "$LOG_FILE"; then
	echo "[ERROR] Multilane smoke test reported failures"
	exit 1
fi

if ! grep -Eq "ALL TESTS PASSED|PASSED" "$LOG_FILE"; then
	echo "[ERROR] Multilane smoke test missing explicit pass marker"
	exit 1
fi

echo "[DONE] Multilane smoke test passed"
echo "       Log: $LOG_FILE"
