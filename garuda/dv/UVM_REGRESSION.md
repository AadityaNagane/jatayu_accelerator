# UVM Regression Runner

Manifest-driven UVM regression for Garuda block-level environments.

## Source of truth

- Manifest: `garuda/dv/uvm_manifest.csv`
- Readiness matrix: `garuda/dv/UVM_READINESS.md`

Only rows with `enabled=1` in the manifest are executed.

## Run

```bash
cd garuda-accelerator-personal-main
bash garuda/dv/run_uvm_regression.sh
```

UVM dependency resolution order is automatic:

1. `UVM_HOME` if valid
2. repo-local `third_party/uvm-1.2`
3. optional auto-fetch when `AUTO_FETCH_UVM=1`

## Options

- `UVM_VERBOSITY` (default `UVM_MEDIUM`)
- `UVM_REGRESS_DIR` (default `build/uvm_regression`)
- `UVM_WAVE_DIR` (default `waves/uvm_regression`)
- `UVM_RESULT_CSV` (default `build/uvm_regression/uvm_regression_results.csv`)
- `UVM_JUNIT_XML` (default `build/uvm_regression/uvm_regression_results.xml`)
- `UVM_MANIFEST` (default `garuda/dv/uvm_manifest.csv`)
- `KEEP_WAVES=1` to retain VCD files for all passing tests
- `AUTO_FETCH_UVM=1` to auto-clone UVM core if not found locally

Example:

```bash
KEEP_WAVES=1 UVM_VERBOSITY=UVM_LOW bash garuda/dv/run_uvm_regression.sh
```

## Machine-readable outputs

Each run emits:

- CSV summary (`suite,test,status,reason,duration_ms,log_file,wave_file,priority,block,declared_status`)
- JUnit XML (`testsuite/testcase`) for CI dashboards

Defaults:

- `build/uvm_regression/uvm_regression_results.csv`
- `build/uvm_regression/uvm_regression_results.xml`

## Pass/Fail policy

A test is marked FAIL if:

1. The suite run script exits non-zero, or
2. The log contains non-zero `UVM_ERROR` or `UVM_FATAL` counts, or
3. A manifest-enabled row points to a missing/non-executable script.

Summary table and totals (including `skipped` disabled manifest rows) are printed at the end.
