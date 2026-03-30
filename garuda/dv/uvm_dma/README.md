# UVM DMA Engine Verification

Reusable UVM environment for `dma_engine.sv`.

## Included

- `dma_if.sv`: AXI4-lite config + AXI4 read + data output interface
- `dma_uvm_pkg.sv`: Driver, monitor, scoreboard, smoke + random tests
- `tb_dma_uvm_top.sv`: DUT + UVM top
- `filelist.f` and `run_uvm.sh`

## Tests

- `dma_smoke_test`: Sequential aligned transfers

## Run

```bash
cd garuda-accelerator-personal-main
bash garuda/dv/uvm_dma/run_uvm.sh
```

To activate in regression, set `enabled=1` in `garuda/dv/uvm_manifest.csv`.
