#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

TESTNAME="${TESTNAME:-system_smoke_test}"
BUILD_JOBS="${GARUDA_BUILD_JOBS:-$(nproc)}"
SIM="${GARUDA_INTEGRATION_SIM:-verilator}"
LOG_DIR="${GARUDA_INTEGRATION_LOG_DIR:-build/uvm_regression/uvm_integration}"
LOG_FILE="${LOG_DIR}/${TESTNAME}.log"

mkdir -p "$LOG_DIR"
if [[ ! -f "integration/Makefile.commercial" ]]; then
	echo "[ERROR] Missing integration/Makefile.commercial"
	exit 1
fi

if [[ ! -d "cva6" || -z "$(find cva6 -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
	echo "[ERROR] Missing CVA6 sources: cva6/ is empty"
	echo "[HINT]   Populate cva6 sources (submodule/checkout) before enabling uvm_integration"
	exit 1
fi

echo "[INFO] Running system integration smoke: ${TESTNAME}"
echo "[INFO] Simulator: ${SIM}"
echo "[INFO] Build jobs: ${BUILD_JOBS}"
echo "[INFO] Log: ${LOG_FILE}"

# Use the established integration flow that already resolves CVA6 file lists and include paths.
if [[ "$SIM" != "verilator" ]]; then
	echo "[ERROR] Unsupported GARUDA_INTEGRATION_SIM=${SIM}; expected 'verilator'"
	exit 1
fi

{
	make -C integration -f Makefile.commercial SIM=verilator BUILD_JOBS="$BUILD_JOBS" run
} 2>&1 | tee "$LOG_FILE"

if grep -Eq "\[ERROR\]|SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*|(^|[[:space:]])FAIL:" "$LOG_FILE"; then
	echo "[ERROR] System integration smoke reported failures"
	exit 1
fi

if ! grep -Eq "ALL TESTS PASSED|PASSED|Test completed" "$LOG_FILE"; then
	echo "[ERROR] System integration smoke missing explicit completion marker"
	exit 1
fi

echo "[DONE] System integration smoke test passed"
echo "       Log: ${LOG_FILE}"

exit 0
