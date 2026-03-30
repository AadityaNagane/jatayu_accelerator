#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TB_NAME="${1:-tb_systolic_array}"
WAVE_DIR="${2:-waves}"
VVP_OUT="${WAVE_DIR}/${TB_NAME}.vvp"
VCD_OUT="${WAVE_DIR}/${TB_NAME}.vcd"
PRESET_FILE="ci/gtkwave/${TB_NAME}.gtkw"

mkdir -p "$WAVE_DIR"

run_tb() {
  local tb="$1"
  shift
  local files=("$@")

  echo "[INFO] Compiling ${tb}"
  rm -f "$VVP_OUT" "$VCD_OUT"
  iverilog -g2012 -o "$VVP_OUT" "${files[@]}"

  echo "[INFO] Running ${tb} with VCD dump"
  vvp "$VVP_OUT" +dumpfile="$VCD_OUT"

  if [[ ! -f "$VCD_OUT" ]]; then
    echo "[ERROR] Expected waveform not found: $VCD_OUT"
    exit 1
  fi

  if [[ -f "$PRESET_FILE" ]]; then
    echo "[INFO] Opening GTKWave with preset: $PRESET_FILE"
    gtkwave -f "$VCD_OUT" -a "$PRESET_FILE" >/dev/null 2>&1 &
  else
    echo "[INFO] Opening GTKWave: $VCD_OUT"
    gtkwave "$VCD_OUT" >/dev/null 2>&1 &
  fi
  echo "[DONE] GTKWave launched"
}

case "$TB_NAME" in
  tb_register_rename_table)
    run_tb "$TB_NAME" \
      "garuda/tb/tb_register_rename_table.sv" \
      "garuda/rtl/register_rename_table.sv"
    ;;
  tb_systolic_array)
    run_tb "$TB_NAME" \
      "garuda/tb/tb_systolic_array.sv" \
      "garuda/rtl/systolic_array.sv" \
      "garuda/rtl/systolic_pe.sv"
    ;;
  tb_multi_issue_rename_integration)
    run_tb "$TB_NAME" \
      "garuda/tb/tb_multi_issue_rename_integration.sv" \
      "garuda/rtl/register_rename_table.sv"
    ;;
  tb_attention_microkernel_latency)
    run_tb "$TB_NAME" \
      "garuda/rtl/attention_microkernel_engine.sv" \
      "garuda/tb/tb_attention_microkernel_latency.sv"
    ;;
  *)
    echo "[ERROR] Unsupported testbench: ${TB_NAME}"
    echo "Supported:"
    echo "  tb_register_rename_table"
    echo "  tb_systolic_array"
    echo "  tb_multi_issue_rename_integration"
    echo "  tb_attention_microkernel_latency"
    echo
    echo "Note: tb_norm_act_ctrl is Verilator-only in this repo and is not wired into"
    echo "the Icarus+VCD GTKWave helper yet."
    exit 1
    ;;
esac
