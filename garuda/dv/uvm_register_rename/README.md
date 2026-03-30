# UVM Register Rename Table Verification

Reusable UVM environment for `register_rename_table.sv` (4-lane parallel rename).

## Included

- `rr_if.sv`: clocking-based interface with parallel rename + commit ports
- `rr_uvm_pkg.sv`: UVM agent, monitor, scoreboard, base test, smoke + random tests
- `tb_rr_uvm_top.sv`: DUT + UVM top + optional +dumpfile support
- `filelist.f`: compile list
- `run_uvm.sh`: launcher script

## Tests

- `rr_smoke_test`: deterministic parallel rename sequence (low traffic)
- `rr_random_test`: randomized multi-lane rename transactions

## Run

```bash
cd garuda-accelerator-personal-main

bash garuda/dv/uvm_register_rename/run_uvm.sh
TESTNAME=rr_random_test bash garuda/dv/uvm_register_rename/run_uvm.sh
```

UVM resolution is automatic (`UVM_HOME` → `third_party/uvm-1.2` → optional `AUTO_FETCH_UVM=1`).

Waveforms are saved by default to `waves/uvm_rr_*.vcd`.

## Design verification approach

- **Smoke test**: Validates basic rename pipeline (one lane active per cycle)
- **Random test**: Drives full 4-lane parallelism + cross-lane dependencies
- **Scoreboard**: Tracks rename table state + free list; validates phys_rd allocation sequences and old_phys_rd mapping recovery
- **Monitor**: Captures rename transactions for analysis

## Next steps

To activate this suite in the regression:
1. Set `enabled=1` in [garuda/dv/uvm_manifest.csv](../uvm_manifest.csv) for the `uvm_register_rename` row
2. Run: `bash garuda/dv/run_uvm_regression.sh`
