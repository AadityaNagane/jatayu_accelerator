#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OBJ_DIR="obj_dir/rtl_runtime"

echo "== Generating Verilated systolic model =="
mkdir -p "$OBJ_DIR"
verilator --cc \
  --Mdir "$OBJ_DIR" \
  --top-module systolic_array \
  -Igaruda/rtl \
  -Wno-fatal \
  -Wno-WIDTH \
  -Wno-UNUSED \
  -Wno-TIMESCALEMOD \
  -Wno-REDEFMACRO \
  -Wno-PINCONNECTEMPTY \
  -Wno-SELRANGE \
  garuda/rtl/systolic_array.sv \
  garuda/rtl/systolic_pe.sv

echo "== Building Verilated objects =="
make -C "$OBJ_DIR" -f Vsystolic_array.mk

echo "== Building inference objects =="
gcc -O2 -std=c11 -DGARUDA_ENABLE_RTL_BACKEND \
  -Igaruda/include \
  -c garuda/examples/garuda_qwen_inference.c \
  -o "$OBJ_DIR"/garuda_qwen_inference.o

g++ -O2 -std=c++17 -DGARUDA_ENABLE_RTL_BACKEND \
  -Igaruda/include \
  -I"$OBJ_DIR" \
  -I/usr/share/verilator/include \
  -I/usr/share/verilator/include/vltstd \
  -c garuda/examples/garuda_rtl_backend.cpp \
  -o "$OBJ_DIR"/garuda_rtl_backend.o

echo "== Linking garuda_inference_rtl =="
g++ -O2 \
  "$OBJ_DIR"/garuda_qwen_inference.o \
  "$OBJ_DIR"/garuda_rtl_backend.o \
  "$OBJ_DIR"/verilated.o \
  "$OBJ_DIR"/verilated_threads.o \
  "$OBJ_DIR"/Vsystolic_array__ALL.a \
  -lpthread -latomic -lm \
  -o garuda_inference_rtl

echo
echo "Build complete: ./garuda_inference_rtl"
echo "Run with RTL backend enabled: GARUDA_USE_RTL=1 ./garuda_inference_rtl"
