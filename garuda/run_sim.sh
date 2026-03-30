#!/bin/bash
# Simulation script for Garuda Accelerator
# Now supports multiple modules

set -e
cd "$(dirname "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Garuda Accelerator - Simulation Script"
echo "========================================="
echo

# Check if target module is specified
MODULE=${1:-int8_mac_unit}
SIMULATOR=${2:-iverilog}

echo -e "Target Module: ${YELLOW}${MODULE}${NC}"
echo -e "Simulator:     ${YELLOW}${SIMULATOR}${NC}"
echo

case $MODULE in
    int8_mac_unit)
        TOP_MODULE="tb_int8_mac_unit"
        RTL_FILES="rtl/int8_mac_instr_pkg.sv rtl/int8_mac_unit.sv"
        TB_FILES="tb/tb_int8_mac_unit.sv"
        ;;
    kv_cache_buffer)
        TOP_MODULE="tb_kv_cache_buffer"
        RTL_FILES="rtl/kv_cache_buffer.sv"
        TB_FILES="tb/tb_kv_cache_buffer.sv"
        ;;
    systolic_array)
        TOP_MODULE="tb_systolic_array"
        RTL_FILES="rtl/systolic_array.sv"
        TB_FILES="tb/tb_systolic_array.sv"
        ;;
    *)
        echo -e "${RED}Error: Unknown module '$MODULE'${NC}"
        echo "Supported modules: int8_mac_unit, kv_cache_buffer, systolic_array"
        exit 1
        ;;
esac

case $SIMULATOR in
    verilator)
        if ! command -v verilator &> /dev/null; then
            echo -e "${RED}Error: Verilator not found${NC}"
            exit 1
        fi
        rm -rf obj_dir
        
        echo "Compiling with Verilator..."
        verilator --cc --exe --build -Wall \
          --no-timing \
          --top-module $TOP_MODULE \
          -Irtl \
          $RTL_FILES \
          $TB_FILES \
          --binary \
          -Wno-WIDTH \
          -Wno-UNUSED \
          -Wno-TIMESCALEMOD \
          -Wno-REDEFMACRO
        
        echo
        echo "Running simulation..."
        echo "----------------------------------------"
        ./obj_dir/V${TOP_MODULE}
        SIM_RESULT=$?
        echo "----------------------------------------"
        ;;
    
    iverilog)
        if ! command -v iverilog &> /dev/null; then
            echo -e "${RED}Error: Icarus Verilog not found${NC}"
            exit 1
        fi
        
        rm -f ${TOP_MODULE}.vvp
        
        echo "Compiling with iverilog..."
        iverilog -g2012 -gno-assertions -DGARUDA_SIMPLE_PKG=1 -DSYNTHESIS=1 \
          -I rtl \
          -o ${TOP_MODULE}.vvp \
          $RTL_FILES \
          $TB_FILES
        
        echo
        echo "Running simulation..."
        echo "----------------------------------------"
        vvp ${TOP_MODULE}.vvp
        SIM_RESULT=$?
        echo "----------------------------------------"
        
        rm -f ${TOP_MODULE}.vvp
        ;;
    
    *)
        echo -e "${RED}Error: Unknown simulator '$SIMULATOR'${NC}"
        echo "Supported simulators: verilator, iverilog"
        exit 1
        ;;
esac

echo
if [ $SIM_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Simulation completed successfully!${NC}"
else
    echo -e "${RED}✗ Simulation failed with exit code $SIM_RESULT${NC}"
    exit $SIM_RESULT
fi
echo
