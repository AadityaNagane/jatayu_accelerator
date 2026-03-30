# INT8 MAC Coprocessor UVM Environment

## Overview
UVM environment for the INT8 MAC coprocessor unit (CVXIF interface). Targets:
- `garuda/rtl/int8_mac_coprocessor.sv` (main coprocessor)
- `garuda/rtl/int8_mac_unit.sv` (execution unit)

## Components

- **cvxif_if.sv**: CVXIF protocol interface (simplified)
  - `issue_valid`, `issue_instr`, `issue_rd` (instruction issue)
  - `issue_ready` (coprocessor handshake)
  - `result_valid`, `result` (result generation)
  
- **cvxif_uvm_pkg.sv**: UVM testbench package
  - `cvxif_driver`: Issues instructions over CVXIF
  - `cvxif_monitor`: Observes instruction issue and result
  - `cvxif_scoreboard`: Tracks instruction completion
  - `cvxif_smoke_test`: Basic smoke test with 10 instructions
  
- **tb_cvxif_uvm_top.sv**: Top-level testbench with simplified DUT stub

## Running Tests

```bash
cd /path/to/garuda-accelerator
bash garuda/dv/uvm_coprocessor/run_uvm.sh
```

**Supported env vars:**
- `TESTNAME`: Test name (default: `cvxif_smoke_test`)
- `SIM`: Simulator choice (default: `iverilog`)
- `DUMPFILE`: Wave dump file (default: `waves/uvm_cvxif_${TESTNAME}.vcd`)

**Example (custom test):**
```bash
TESTNAME=cvxif_smoke_test SIM=iverilog bash garuda/dv/uvm_coprocessor/run_uvm.sh
```

## Status
- ✓ Smoke test implemented
- ✓ CVXIF protocol covered
- ○ Stress/random tests (future)
- ○ Real DUT integration (future)
