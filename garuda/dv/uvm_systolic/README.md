# UVM Systolic Verification

This directory contains a reusable UVM baseline for the Garuda systolic array.

## What is included

- UVM agent (driver, monitor, sequencer)
- Scoreboard with matrix-based expected checks
- Handshake coverage sampling in monitor
- Two tests:
  - `sa_smoke_test` (deterministic identity-style sanity)
  - `sa_random_test` (randomized matrices)
- Top-level TB with optional VCD dump via `+dumpfile=...`

## Files

- `sa_if.sv`: Interface + clocking blocks + modports
- `sa_uvm_pkg.sv`: UVM transaction/env/tests
- `tb_sa_uvm_top.sv`: UVM top TB + DUT instantiation
- `filelist.f`: Compile list (repo-relative)
- `run_uvm.sh`: Convenience launcher

## Run

```bash
cd garuda-accelerator-personal-main

# Smoke
bash garuda/dv/uvm_systolic/run_uvm.sh

# Random
TESTNAME=sa_random_test bash garuda/dv/uvm_systolic/run_uvm.sh
```

UVM resolution is automatic (`UVM_HOME` -> `third_party/uvm-1.2` -> optional `AUTO_FETCH_UVM=1`).

## Waveform

By default the run script emits waveforms to:

- `waves/uvm_systolic_sa_smoke_test.vcd`
- `waves/uvm_systolic_sa_random_test.vcd`

Open with:

```bash
gtkwave waves/uvm_systolic_sa_smoke_test.vcd
```

## Extending to complete Garuda RTL

Use this pattern for each subsystem:

1. Create a dedicated interface in `garuda/dv/uvm_<block>/`.
2. Reuse sequence/scoreboard structure from `sa_uvm_pkg.sv`.
3. Add one deterministic test + one randomized test per block.
4. Connect block-level scoreboards into a system-level virtual sequence later.

Suggested next UVM targets:

- `attention_microkernel_engine`
- `int8_mac_coprocessor`
- `register_rename_table`
- `matmul_ctrl_fsm` path
