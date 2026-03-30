#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OBJ_DIR="obj_dir/systolic_cosim"
BIN="${OBJ_DIR}/Vsystolic_array_cosim"

echo "== Building systolic RTL co-sim (Verilator) =="
rm -rf "$OBJ_DIR"
mkdir -p "$OBJ_DIR"

verilator --cc --exe --build \
  --top-module systolic_array \
  --Mdir "$OBJ_DIR" \
  -Igaruda/rtl \
  -Wno-fatal \
  -Wno-WIDTH \
  -Wno-UNUSED \
  -Wno-TIMESCALEMOD \
  -Wno-REDEFMACRO \
  -Wno-PINCONNECTEMPTY \
  -Wno-SELRANGE \
  garuda/rtl/systolic_array.sv \
  garuda/rtl/systolic_pe.sv \
  garuda/examples/systolic_rtl_cosim.cpp \
  -o Vsystolic_array_cosim

echo
echo "== Running systolic RTL co-sim =="
"$BIN"

echo
echo "Systolic RTL co-simulation completed."
