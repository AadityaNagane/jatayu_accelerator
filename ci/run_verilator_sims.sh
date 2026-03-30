#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SIM_MODE="${GARUDA_SIM_MODE:-nightly}"

case "${1:-}" in
  --quick|--smoke)
    SIM_MODE="smoke"
    ;;
  --premerge)
    SIM_MODE="premerge"
    ;;
  --full|--nightly)
    SIM_MODE="nightly"
    ;;
  --help|-h)
    echo "Usage: bash ci/run_verilator_sims.sh [--smoke|--premerge|--nightly]"
    echo "  --smoke    Fast subset (former --quick)"
    echo "  --premerge Balanced regression for PR checks"
    echo "  --nightly  Full regression (former full/default)"
    exit 0
    ;;
esac

BUILD_JOBS="${GARUDA_BUILD_JOBS:-$(nproc)}"
TIMING_CSV="${GARUDA_TIMING_CSV:-ci/verilator_timing.csv}"
MAX_TOTAL_MS="${GARUDA_MAX_TOTAL_MS:-}"
MAX_TEST_MS_CSV="${GARUDA_MAX_TEST_MS_CSV:-}"
declare -a TB_NAMES=()
declare -a TB_DURATIONS_MS=()
SUITE_START_MS=$(date +%s%3N)

echo "== Verilator =="
verilator --version | head -n 1
echo "Mode: ${SIM_MODE}"
echo "Build jobs: ${BUILD_JOBS}"
echo

run_tb() {
  local name="$1"
  local top="$2"
  shift 2
  local files=("$@")
  local mdir="obj_dir/${top}"
  local log_file
  local start_ms
  local end_ms
  local duration_ms

  echo "== Running ${name} =="
  start_ms=$(date +%s%3N)
  log_file="ci/${name}.log"
  rm -f "$log_file"
  mkdir -p "$mdir"
  
  verilator --cc --exe --build \
    --top-module "${top}" \
    --Mdir "$mdir" \
    --build-jobs "${BUILD_JOBS}" \
    -Igaruda/rtl \
    -Wno-fatal \
    -Wno-WIDTH \
    -Wno-UNUSED \
    -Wno-TIMESCALEMOD \
    -Wno-REDEFMACRO \
    -Wno-PINCONNECTEMPTY \
    -Wno-SELRANGE \
    -Wno-SYMRSVDWORD \
    "${files[@]}" \
    --binary \
    -o "V${top}"
  
  ./${mdir}/V"${top}" | tee "$log_file"
  if grep -Eq "SOME TESTS FAILED|Failed:[[:space:]]*[1-9][0-9]*" "$log_file"; then
    echo "[ERROR] ${name} reported failures in testbench output"
    return 1
  fi
  end_ms=$(date +%s%3N)
  duration_ms=$((end_ms - start_ms))
  TB_NAMES+=("${name}")
  TB_DURATIONS_MS+=("${duration_ms}")
  printf "Duration: %d ms\n" "${duration_ms}"
  echo
}

if [[ "$SIM_MODE" == "smoke" ]]; then
  echo "== SMOKE MODE: running fast subset =="
  echo

  run_tb "tb_attention_microkernel_latency" "tb_attention_microkernel_latency" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/tb/tb_attention_microkernel_latency.sv"

  run_tb "tb_norm_act_ctrl" "tb_norm_act_ctrl" \
    "garuda/rtl/int8_mac_instr_pkg.sv" \
    "garuda/rtl/int8_mac_decoder.sv" \
    "garuda/rtl/int8_mac_unit.sv" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv" \
    "garuda/rtl/gelu8_rom.sv" \
    "garuda/rtl/int8_mac_coprocessor.sv" \
    "garuda/tb/tb_norm_act_ctrl.sv"
elif [[ "$SIM_MODE" == "premerge" ]]; then
  echo "== PREMERGE MODE: running balanced regression =="
  echo

  run_tb "tb_register_rename_table" "tb_register_rename_table" \
    "garuda/tb/tb_register_rename_table.sv" \
    "garuda/rtl/register_rename_table.sv"

  run_tb "tb_systolic_array" "tb_systolic_array" \
    "garuda/tb/tb_systolic_array.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv"

  run_tb "tb_multi_issue_rename_integration" "tb_multi_issue_rename_integration" \
    "garuda/tb/tb_multi_issue_rename_integration.sv" \
    "garuda/rtl/register_rename_table.sv"

  run_tb "tb_attention_microkernel_latency" "tb_attention_microkernel_latency" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/tb/tb_attention_microkernel_latency.sv"

  run_tb "tb_matmul_ctrl_fsm" "tb_matmul_ctrl_fsm" \
    "garuda/rtl/int8_mac_instr_pkg.sv" \
    "garuda/rtl/int8_mac_decoder.sv" \
    "garuda/rtl/int8_mac_unit.sv" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv" \
    "garuda/rtl/gelu8_rom.sv" \
    "garuda/rtl/int8_mac_coprocessor.sv" \
    "garuda/tb/tb_matmul_ctrl_fsm.sv"

  run_tb "tb_norm_act_ctrl" "tb_norm_act_ctrl" \
    "garuda/rtl/int8_mac_instr_pkg.sv" \
    "garuda/rtl/int8_mac_decoder.sv" \
    "garuda/rtl/int8_mac_unit.sv" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv" \
    "garuda/rtl/gelu8_rom.sv" \
    "garuda/rtl/int8_mac_coprocessor.sv" \
    "garuda/tb/tb_norm_act_ctrl.sv"
else
  echo "== NIGHTLY MODE: running full regression =="
  echo

  # Testbenches that work with Verilator
  run_tb "tb_register_rename_table" "tb_register_rename_table" \
    "garuda/tb/tb_register_rename_table.sv" \
    "garuda/rtl/register_rename_table.sv"

  run_tb "tb_systolic_array" "tb_systolic_array" \
    "garuda/tb/tb_systolic_array.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv"

  run_tb "tb_multi_issue_rename_integration" "tb_multi_issue_rename_integration" \
    "garuda/tb/tb_multi_issue_rename_integration.sv" \
    "garuda/rtl/register_rename_table.sv"

  run_tb "tb_attention_microkernel_latency" "tb_attention_microkernel_latency" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/tb/tb_attention_microkernel_latency.sv"

  # CVXIF integration testbench (Verilator only)
  run_tb "tb_attention_microkernel_cvxif" "tb_attention_microkernel_cvxif" \
    "garuda/rtl/int8_mac_instr_pkg.sv" \
    "garuda/rtl/int8_mac_decoder.sv" \
    "garuda/rtl/int8_mac_unit.sv" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/rtl/gelu8_rom.sv" \
    "garuda/rtl/int8_mac_coprocessor.sv" \
    "garuda/tb/tb_attention_microkernel_cvxif.sv"

  # MATMUL control-path FSM + tag-latching testbench (Verilator only)
  run_tb "tb_matmul_ctrl_fsm" "tb_matmul_ctrl_fsm" \
    "garuda/rtl/int8_mac_instr_pkg.sv" \
    "garuda/rtl/int8_mac_decoder.sv" \
    "garuda/rtl/int8_mac_unit.sv" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv" \
    "garuda/rtl/gelu8_rom.sv" \
    "garuda/rtl/int8_mac_coprocessor.sv" \
    "garuda/tb/tb_matmul_ctrl_fsm.sv"

  # NORM_ACT control-path FSM + tag-latching testbench (Verilator only)
  run_tb "tb_norm_act_ctrl" "tb_norm_act_ctrl" \
    "garuda/rtl/int8_mac_instr_pkg.sv" \
    "garuda/rtl/int8_mac_decoder.sv" \
    "garuda/rtl/int8_mac_unit.sv" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv" \
    "garuda/rtl/gelu8_rom.sv" \
    "garuda/rtl/int8_mac_coprocessor.sv" \
    "garuda/tb/tb_norm_act_ctrl.sv"

  # End-to-end MATMUL -> GELU sandwich testbench (Verilator only)
  run_tb "tb_matmul_gelu_sandwich" "tb_matmul_gelu_sandwich" \
    "garuda/rtl/int8_mac_instr_pkg.sv" \
    "garuda/rtl/int8_mac_decoder.sv" \
    "garuda/rtl/int8_mac_unit.sv" \
    "garuda/rtl/attention_microkernel_engine.sv" \
    "garuda/rtl/systolic_array.sv" \
    "garuda/rtl/systolic_pe.sv" \
    "garuda/rtl/gelu8_rom.sv" \
    "garuda/rtl/int8_mac_coprocessor.sv" \
    "garuda/tb/tb_matmul_gelu_sandwich.sv"
fi

SUITE_END_MS=$(date +%s%3N)
SUITE_DURATION_MS=$((SUITE_END_MS - SUITE_START_MS))

echo "== Verilator Timing Summary =="
printf "%-36s %12s\n" "Testbench" "Duration (ms)"
printf "%-36s %12s\n" "------------------------------------" "------------"
for i in "${!TB_NAMES[@]}"; do
  printf "%-36s %12d\n" "${TB_NAMES[$i]}" "${TB_DURATIONS_MS[$i]}"
done
printf "%-36s %12d\n" "TOTAL" "${SUITE_DURATION_MS}"
echo

mkdir -p "$(dirname "${TIMING_CSV}")"
{
  echo "mode,testbench,duration_ms"
  for i in "${!TB_NAMES[@]}"; do
    echo "${SIM_MODE},${TB_NAMES[$i]},${TB_DURATIONS_MS[$i]}"
  done
  echo "${SIM_MODE},TOTAL,${SUITE_DURATION_MS}"
} > "${TIMING_CSV}"
echo "Timing CSV: ${TIMING_CSV}"
echo

if [[ -n "${MAX_TEST_MS_CSV}" ]]; then
  if [[ ! -f "${MAX_TEST_MS_CSV}" ]]; then
    echo "[ERROR] Per-test threshold policy file not found: ${MAX_TEST_MS_CSV}"
    exit 1
  fi

  echo "Per-test performance policy: ${MAX_TEST_MS_CSV}"
  while IFS=, read -r tb_name tb_limit; do
    local_duration=""
    if [[ -z "${tb_name}" || "${tb_name}" == "testbench" || "${tb_name:0:1}" == "#" ]]; then
      continue
    fi

    if [[ "${tb_name}" == "TOTAL" ]]; then
      local_duration="${SUITE_DURATION_MS}"
    else
      for i in "${!TB_NAMES[@]}"; do
        if [[ "${TB_NAMES[$i]}" == "${tb_name}" ]]; then
          local_duration="${TB_DURATIONS_MS[$i]}"
          break
        fi
      done
      if [[ -z "${local_duration}" ]]; then
        echo "  [INFO] Skipping threshold for ${tb_name} (not run in ${SIM_MODE} mode)"
        continue
      fi
    fi

    if (( local_duration > tb_limit )); then
      echo "[ERROR] Performance regression for ${tb_name}: ${local_duration} ms exceeds ${tb_limit} ms"
      exit 1
    fi
    echo "  [PASS] ${tb_name}: ${local_duration} ms <= ${tb_limit} ms"
  done < "${MAX_TEST_MS_CSV}"
  echo
fi

if [[ -n "${MAX_TOTAL_MS}" ]]; then
  echo "Performance guard: total <= ${MAX_TOTAL_MS} ms"
  if (( SUITE_DURATION_MS > MAX_TOTAL_MS )); then
    echo "[ERROR] Performance regression: total ${SUITE_DURATION_MS} ms exceeds ${MAX_TOTAL_MS} ms"
    exit 1
  fi
  echo "Performance guard: PASS (${SUITE_DURATION_MS} ms)"
  echo
fi

echo "All Verilator sims PASSED."
