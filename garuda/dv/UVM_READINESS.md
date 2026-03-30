# UVM Readiness Matrix

This matrix tracks UVM status across the Garuda RTL codebase.

## Status legend

- `active`: UVM environment implemented and included in regression
- `planned`: target identified, environment not implemented yet
- `n/a`: not a UVM target (helper/package/ROM)

## Block status

| RTL Module | UVM Status | Suite | Priority | Notes |
|---|---|---|---|---|
| `systolic_array.sv` | active | `uvm_systolic` | p0 | Smoke + random tests in regression |
| `attention_microkernel_engine.sv` | active | `uvm_attention` | p0 | Smoke + random tests in regression |
| `register_rename_table.sv` | planned | `uvm_register_rename` | p1 | Functional model from existing TB |
| `dma_engine.sv` | planned | `uvm_dma` | p1 | Backpressure + burst coverage |
| `int8_mac_coprocessor.sv` | planned | `uvm_coprocessor` | p1 | CVXIF handshake + result ordering |
| `int8_mac_decoder.sv` | planned | `uvm_matmul_ctrl` | p1 | Instruction decode legality |
| `int8_mac_unit.sv` | planned | `uvm_coprocessor` | p1 | Low-level op functional checks |
| `int8_mac_multilane_unit.sv` | planned | `uvm_multilane` | p2 | Multilane contention/throughput |
| `int8_mac_multilane_decoder.sv` | planned | `uvm_multilane` | p2 | Decode consistency |
| `int8_mac_multilane_wrapper.sv` | planned | `uvm_multilane` | p2 | Wrapper integration checks |
| `multilane_with_dma.sv` | planned | `uvm_multilane` | p2 | DMA + multilane integration |
| `multi_issue_decoder.sv` | planned | `uvm_multilane` | p2 | Issue legality |
| `multi_issue_execution_unit.sv` | planned | `uvm_multilane` | p2 | Scheduling/commit checks |
| `buffer_subsystem.sv` | planned | `uvm_buffers` | p2 | Arbitration + data integrity |
| `buffer_controller.sv` | planned | `uvm_buffers` | p2 | State machine robustness |
| `activation_buffer.sv` | planned | `uvm_buffers` | p2 | Data retention checks |
| `weight_buffer.sv` | planned | `uvm_buffers` | p2 | Load/store checks |
| `accumulator_buffer.sv` | planned | `uvm_buffers` | p2 | Saturation/overflow checks |
| `onchip_buffer.sv` | planned | `uvm_buffers` | p2 | Interface contract checks |
| `prefetch_buffer.sv` | planned | `uvm_buffers` | p2 | Prefetch ordering checks |
| `instruction_buffer.sv` | planned | `uvm_buffers` | p2 | Instruction queue checks |
| `memory_coalescing_unit.sv` | planned | `uvm_dma` | p2 | Coalescing correctness |
| `dma_engine_stride.sv` | planned | `uvm_dma` | p2 | Stride correctness |
| `dma_engine_advanced.sv` | planned | `uvm_dma` | p2 | Advanced mode corner cases |
| `address_generation_unit.sv` | planned | `uvm_dma` | p2 | Address math + bounds |
| `systolic_pe.sv` | n/a | — | — | Verified via systolic_array UVM/TB |
| `gelu8_rom.sv` | n/a | — | — | ROM LUT; covered through higher-level tests |
| `int8_mac_instr_pkg.sv` | n/a | — | — | Package/constants |
| `system_top.sv` (integration dir) | planned | `uvm_integration` | p3 | Full-system CVA6 + Garuda UVM |

## Regression source of truth

- Manifest file: `garuda/dv/uvm_manifest.csv`
- Runner: `garuda/dv/run_uvm_regression.sh`

Only rows with `enabled=1` in the manifest are executed.
