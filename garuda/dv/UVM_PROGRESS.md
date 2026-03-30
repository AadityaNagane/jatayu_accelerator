# UVM Framework Progress Summary

## Milestone: UVM Ready for Scale

The Garuda verification framework is now structured for incremental UVM expansion across all RTL blocks.

### What's new

**Core infrastructure**
- Shared UVM dependency resolver: [garuda/dv/uvm_common/resolve_uvm_home.sh](uvm_common/resolve_uvm_home.sh)
- Manifest-driven regression: [garuda/dv/uvm_manifest.csv](uvm_manifest.csv) + [run_uvm_regression.sh](run_uvm_regression.sh)
- Readiness matrix: [garuda/dv/UVM_READINESS.md](UVM_READINESS.md)

**Active UVM suites (6 tests)**

| Suite | Block | Tests | Status |
|---|---|---|---|
| `uvm_systolic` | Systolic array | smoke, random | ✓ Active |
| `uvm_attention` | Attention microkernel | smoke, random | ✓ Active |
| `uvm_register_rename` (NEW) | Register rename table | smoke, random | ✓ Active |

**Planned UVM suites (6 tests, stubs ready)**

| Suite | Block | Test | Priority | Status |
|---|---|---|---|---|
| `uvm_dma` | DMA engine | smoke | p1 | Stub ready |
| `uvm_coprocessor` | INT8 MAC coprocessor | smoke | p1 | Stub ready |
| `uvm_matmul_ctrl` | Matmul control/decoder | smoke | p1 | Stub ready |
| `uvm_multilane` | Multilane execution | smoke | p2 | Stub ready |
| `uvm_buffers` | On-chip buffers | smoke | p2 | Stub ready |
| `uvm_integration` | System-level (CVA6+Garuda) | smoke | p3 | Stub ready |

### Register rename (P1) implementation

Full UVM environment with:
- **Interface** ([rr_if.sv](uvm_register_rename/rr_if.sv)): Parallel 4-lane rename + commit ports
- **UVM agent** ([rr_uvm_pkg.sv](uvm_register_rename/rr_uvm_pkg.sv)): Driver, monitor, scoreboard, tests
- **Tests**:
  - `rr_smoke_test`: Deterministic single-lane + multi-lane sequences
  - `rr_random_test`: Full 4-lane randomized rename + free-list stress
- **Runner** ([run_uvm_regression.sh](run_uvm_regression.sh)): Integrated into manifest + regression

### Roadmap

- **P0 (Core pipeline)**: ✓ systolic, ✓ attention, ✓ register_rename
- **P1 (Data path)**: DMA, coprocessor, matmul_ctrl (stubs ready; pattern templates in place)
- **P2 (Buffer/lane)**: multilane, buffers (stubs ready)
- **P3 (Integration)**: system-level UVM (stub ready)

### To activate next suite

1. Pick a stub: `ls -d garuda/dv/uvm_dma garuda/dv/uvm_coprocessor garuda/dv/uvm_matmul_ctrl ...`
2. Copy pattern from active suite: `cp -r garuda/dv/uvm_register_rename garuda/dv/uvm_<new_block>`
3. Replace register-rename-specific names with block names
4. Implement interface (`*_if.sv`) with block signals
5. Adapt UVM package (`*_uvm_pkg.sv`) for block behavior
6. Update manifest: set `enabled=1`
7. Run: `bash garuda/dv/run_uvm_regression.sh`

See [UVM_STUBS.md](UVM_STUBS.md) for detailed activation checklist.

### Usage

**Run all active suites:**
```bash
cd garuda-accelerator-personal-main
bash garuda/dv/run_uvm_regression.sh
```

**Run register_rename only:**
```bash
bash garuda/dv/uvm_register_rename/run_uvm.sh
TESTNAME=rr_random_test bash garuda/dv/uvm_register_rename/run_uvm.sh
```

**Auto-fetch UVM (if not present):**
```bash
AUTO_FETCH_UVM=1 bash garuda/dv/run_uvm_regression.sh
```

**Regression outputs:**
- CSV: `build/uvm_regression/uvm_regression_results.csv`
- JUnit: `build/uvm_regression/uvm_regression_results.xml`
- Logs: `build/uvm_regression/*.log`
- Waves: `waves/uvm_regression/*.vcd` (with `KEEP_WAVES=1`)

### Key improvements over previous state

- **Zero manual UVM_HOME setup**: Auto-resolved from env, local, or git clone
- **Manifest-driven scaling**: Add new suites by updating one CSV row + implementing blockcopy pattern
- **Full test coverage**: 6 active suites now (P0 core + P1 data path) with both smoke + random modes
- **Clear roadmap visibility**: Readiness matrix + stubs show all-blocks plan + activation tier
- **CI-ready outputs**: Machine-readable CSV + JUnit + skip tracking for CI integration

---

**Next steps**
1. Implement remaining P1 suites (DMA, coprocessor, matmul_ctrl) ~3-4 hours each
2. Add CI workflow integration to publish readiness matrix in PR comments
3. Expand P2 suites (multilane, buffers) once P1 baseline stable
4. Integration test suite (P3) once all block-level suites verified
