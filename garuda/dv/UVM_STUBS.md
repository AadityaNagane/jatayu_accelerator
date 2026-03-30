# UVM Stub Runner Framework

This directory and the subdirectories contain stub `run_uvm.sh` scripts for all planned UVM testbench environments. Each stub provides:

1. **Discovery**: Each runner is discoverable in the manifest and CI
2. **Guidance**: Clear [TODO] and [HINT] messages on what to implement next
3. **Placeholder status**: Disabled in manifest (`enabled=0`) so they don't block regression runs
4. **Reference implementation**: To activate a stub:
   - Set `enabled=1` in [garuda/dv/uvm_manifest.csv](../uvm_manifest.csv)
   - Copy the pattern from [garuda/dv/uvm_systolic/](../uvm_systolic/) or [garuda/dv/uvm_attention/](../uvm_attention/) 
   - Implement the interface, UVM package, and top-level testbench
   - Update the `run_uvm.sh` script to call the actual UVM simulation

## Activation order (priority tier)

### Tier P0: Core pipeline blocks (active)
- `uvm_systolic`: Systolic array (implementation: [run_uvm.sh](../uvm_systolic/run_uvm.sh))
- `uvm_attention`: Attention microkernel (implementation: [run_uvm.sh](../uvm_attention/run_uvm.sh))

### Tier P1: Data path and control (planned)
- `uvm_register_rename`: Register rename table (stub: [run_uvm.sh](../uvm_register_rename/run_uvm.sh))
- `uvm_dma`: DMA engine (stub: [run_uvm.sh](../uvm_dma/run_uvm.sh))
- `uvm_coprocessor`: INT8 MAC and CVXIF (stub: [run_uvm.sh](../uvm_coprocessor/run_uvm.sh))
- `uvm_matmul_ctrl`: Decoder/control FSM (stub: [run_uvm.sh](../uvm_matmul_ctrl/run_uvm.sh))

### Tier P2: Buffer/lane subsystems (planned)
- `uvm_multilane`: Multilane MAC + issue (stub: [run_uvm.sh](../uvm_multilane/run_uvm.sh))
- `uvm_buffers`: On-chip buffers (stub: [run_uvm.sh](../uvm_buffers/run_uvm.sh))

### Tier P3: Integration (planned)
- `uvm_integration`: Full CVA6+Garuda system (stub: [integration/uvm_system/run_uvm.sh](../../integration/uvm_system/run_uvm.sh))

## Manifest

The manifest source of truth is [garuda/dv/uvm_manifest.csv](../uvm_manifest.csv). Each row specifies:

- `suite`: UVM suite name (directory)
- `test`: default test to run (e.g., `sa_smoke_test`)
- `script`: path to `run_uvm.sh`
- `enabled`: `1` to include in regression, `0` to skip
- `priority`: `p0`–`p3` indicating activation tier
- `block`: target RTL module name
- `status`: `active` or `planned`

## Next steps

1. **Pick a priority tier**: Start with P1 to add the register rename table UVM environment
2. **Copy the pattern**: `cp -r ../uvm_systolic ../uvm_register_rename && sed -i 's/systolic/register_rename/g ../uvm_register_rename/*.sv`
3. **Implement the interface**: Replace placeholder signals with actual register rename table I/O
4. **Implement tests**: Add smoke (deterministic) and random test cases
5. **Enable in manifest**: Set `enabled=1` for the new suite row
6. **Run regression**: `bash garuda/dv/run_uvm_regression.sh` to include the new suite

See [garuda/dv/UVM_READINESS.md](../UVM_READINESS.md) for the full RTL block coverage plan.
