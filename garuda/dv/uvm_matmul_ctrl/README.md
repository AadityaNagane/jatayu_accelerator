# Matmul Control (Decoder) UVM Environment

## Overview
UVM environment for matmul control and instruction decoder. Targets:
- `garuda/rtl/int8_mac_decoder.sv` (instruction decoder)
- `garuda/rtl/multi_issue_decoder.sv` (multi-issue decoder)

## Components

- **mm_ctrl_if.sv**: Decoder control interface
  - `instr`, `instr_valid`, `instr_ready` (instruction input)
  - `m`, `n`, `k` (matrix dimensions from decode)
  - `decode_valid`, `decode_error` (status)
  - `opcode` (instruction type)
  
- **mm_ctrl_uvm_pkg.sv**: UVM testbench package
  - `mm_ctrl_driver`: Issues instructions to decoder
  - `mm_ctrl_monitor`: Observes decode results
  - `mm_ctrl_scoreboard`: Counts decoded instructions
  - `mm_ctrl_smoke_test`: Basic smoke test with 10 instructions
  
- **tb_mm_ctrl_uvm_top.sv**: Top-level testbench with simplified decoder stub

## Running Tests

```bash
cd /path/to/garuda-accelerator
bash garuda/dv/uvm_matmul_ctrl/run_uvm.sh
```

**Supported env vars:**
- `TESTNAME`: Test name (default: `mm_ctrl_smoke_test`)
- `SIM`: Simulator choice (default: `iverilog`)
- `DUMPFILE`: Wave dump file (default: `waves/uvm_mm_ctrl_${TESTNAME}.vcd`)

**Example (custom test):**
```bash
TESTNAME=mm_ctrl_smoke_test SIM=iverilog bash garuda/dv/uvm_matmul_ctrl/run_uvm.sh
```

## Status
- ✓ Smoke test implemented
- ✓ Decoder interface covered
- ○ Instruction legality checks (future)
- ○ FSM state validation (future)
