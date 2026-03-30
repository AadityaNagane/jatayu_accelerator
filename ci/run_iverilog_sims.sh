#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Icarus Verilog =="
iverilog -V | sed -n '1p'
echo

declare -a TB_NAMES=()
declare -a TB_DURATIONS_MS=()
SUITE_START_MS=$(date +%s%3N)
TIMING_CSV="${GARUDA_TIMING_CSV:-ci/iverilog_timing.csv}"
MAX_TOTAL_MS="${GARUDA_MAX_TOTAL_MS:-}"
MAX_TEST_MS_CSV="${GARUDA_MAX_TEST_MS_CSV:-}"

run_tb() {
  local name="$1"
  local out="$2"
  shift 2
  local files=("$@")
  local log_file
  local start_ms
  local end_ms
  local duration_ms

  echo "== Running ${name} =="
  start_ms=$(date +%s%3N)
  log_file="ci/${name}.log"
  rm -f "$out"
  rm -f "$log_file"
  iverilog -g2012 -o "$out" "${files[@]}"
  vvp "$out" | tee "$log_file"
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

run_tb "tb_register_rename_table" "sim_rr.vvp" \
  "garuda/tb/tb_register_rename_table.sv" \
  "garuda/rtl/register_rename_table.sv"

run_tb "tb_systolic_array" "sim_sa.vvp" \
  "garuda/tb/tb_systolic_array.sv" \
  "garuda/rtl/systolic_array.sv" \
  "garuda/rtl/systolic_pe.sv"

run_tb "tb_multi_issue_rename_integration" "sim_mi_rr_int.vvp" \
  "garuda/tb/tb_multi_issue_rename_integration.sv" \
  "garuda/rtl/register_rename_table.sv"

run_tb "tb_attention_microkernel_latency" "sim_att_lat.vvp" \
  "garuda/rtl/attention_microkernel_engine.sv" \
  "garuda/tb/tb_attention_microkernel_latency.sv"

# NOTE: tb_matmul_ctrl_fsm instantiates the full coprocessor path and imports
# int8_mac_instr_pkg parameter arrays. Icarus does not fully support this package
# pattern yet; run this test with Verilator instead.
# run_tb "tb_matmul_ctrl_fsm" "sim_mm_fsm.vvp" \
#   "garuda/rtl/int8_mac_instr_pkg.sv" \
#   "garuda/rtl/int8_mac_decoder.sv" \
#   "garuda/rtl/int8_mac_unit.sv" \
#   "garuda/rtl/attention_microkernel_engine.sv" \
#   "garuda/rtl/systolic_array.sv" \
#   "garuda/rtl/systolic_pe.sv" \
#   "garuda/rtl/int8_mac_coprocessor.sv" \
#   "garuda/tb/tb_matmul_ctrl_fsm.sv"

# NOTE: tb_attention_microkernel_cvxif requires parameter arrays in packages,
# which Icarus Verilog doesn't fully support. Skip for Icarus; use Verilator instead.
# echo "== Skipping tb_attention_microkernel_cvxif (requires Verilator for full CVXIF test) =="
# run_tb "tb_attention_microkernel_cvxif" "sim_att_cvxif.vvp" \
#   "garuda/rtl/int8_mac_instr_pkg.sv" \
#   "garuda/rtl/int8_mac_decoder.sv" \
#   "garuda/rtl/int8_mac_unit.sv" \
#   "garuda/rtl/attention_microkernel_engine.sv" \
#   "garuda/rtl/int8_mac_coprocessor.sv" \
#   "garuda/tb/tb_attention_microkernel_cvxif.sv"

SUITE_END_MS=$(date +%s%3N)
SUITE_DURATION_MS=$((SUITE_END_MS - SUITE_START_MS))

echo "== Icarus Timing Summary =="
printf "%-36s %12s\n" "Testbench" "Duration (ms)"
printf "%-36s %12s\n" "------------------------------------" "------------"
for i in "${!TB_NAMES[@]}"; do
  printf "%-36s %12d\n" "${TB_NAMES[$i]}" "${TB_DURATIONS_MS[$i]}"
done
printf "%-36s %12d\n" "TOTAL" "${SUITE_DURATION_MS}"
echo

mkdir -p "$(dirname "${TIMING_CSV}")"
{
  echo "simulator,testbench,duration_ms"
  for i in "${!TB_NAMES[@]}"; do
    echo "iverilog,${TB_NAMES[$i]},${TB_DURATIONS_MS[$i]}"
  done
  echo "iverilog,TOTAL,${SUITE_DURATION_MS}"
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
        echo "  [INFO] Skipping threshold for ${tb_name} (not run in this suite)"
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

echo "All Icarus sims PASSED."
