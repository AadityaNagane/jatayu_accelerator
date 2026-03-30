# UVM Attention Microkernel Verification

Reusable UVM environment for `attention_microkernel_engine`.

## Included

- `amk_if.sv`: interface with clocking blocks/modports
- `amk_uvm_pkg.sv`: seq item, sequencer, driver, monitor, scoreboard, env, tests
- `tb_amk_uvm_top.sv`: DUT+UVM top and optional VCD dump via `+dumpfile=...`
- `filelist.f`: compile list
- `run_uvm.sh`: launcher script

## Tests

- `amk_smoke_test`: deterministic transaction (no scale/clip)
- `amk_random_test`: randomized transactions (no scale/clip)

## Run

```bash
cd garuda-accelerator-personal-main

bash garuda/dv/uvm_attention/run_uvm.sh
TESTNAME=amk_random_test bash garuda/dv/uvm_attention/run_uvm.sh
```

UVM resolution is automatic (`UVM_HOME` -> `third_party/uvm-1.2` -> optional `AUTO_FETCH_UVM=1`).
Waveforms are saved by default under `waves/`.
