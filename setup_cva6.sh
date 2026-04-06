#!/bin/bash
# Setup CVA6 with all submodules for jatayu_accelerator
# Usage: bash setup_cva6.sh

set -e  # Exit on error

echo "================================================"
echo "CVA6 Setup Script for jatayu_accelerator"
echo "================================================"

# Clone CVA6 if not present
if [ ! -d cva6 ]; then
    echo "[INFO] Cloning CVA6 with initial submodules..."
    git clone --recurse-submodules https://github.com/openhwgroup/cva6.git cva6
    echo "[DONE] CVA6 cloned"
else
    echo "[INFO] CVA6 directory already exists, skipping clone"
fi

# ALWAYS ensure all CVA6 nested submodules are initialized
# (This works whether we just cloned or directory already existed)
echo "[INFO] Initializing all CVA6 submodules including nested dependencies..."
cd cva6 && git submodule update --init --recursive && cd ..
echo "[DONE] CVA6 submodules initialized"

# Verify critical submodules are present
echo ""
echo "[INFO] Verifying critical submodules..."
if [ -d cva6/core/cvfpu/src ] && [ "$(ls -A cva6/core/cvfpu/src)" ]; then
    echo "✓ cvfpu/src: OK"
else
    echo "✗ cvfpu/src: MISSING or empty!"
    exit 1
fi

if [ -d cva6/core/cache_subsystem/hpdcache/rtl/src ] && [ "$(ls -A cva6/core/cache_subsystem/hpdcache/rtl/src)" ]; then
    echo "✓ hpdcache/rtl/src: OK"
else
    echo "✗ hpdcache/rtl/src: MISSING or empty!"
    exit 1
fi

echo ""
echo "================================================"
echo "[SUCCESS] CVA6 fully initialized with all submodules!"
echo "================================================"
echo ""
echo "Next steps:"
echo "  1. Run: export JATAYU_ROOT=\$(pwd)"
echo "  2. Run: export UVM_HOME=\$(pwd)/third_party/uvm-1.2"
echo "  3. Run: bash integration/uvm_system/run_uvm.sh"
echo ""
