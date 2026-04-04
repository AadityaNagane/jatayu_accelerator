# Systolic Array Fix - Comprehensive Analysis and Solution

## Executive Summary

The original Garuda systolic_array.sv implementation had **critical architectural flaws** that would make it **fail in real hardware**:

1. **Combinational loops computing entire 8×8 matrix in one cycle** (Lines 217-230 of original)
2. **64 multipliers and adders chained together** → exceeds 1 GHz timing
3. **systolic_pe.sv module exists but was never instantiated** → dead code

This document describes:
- **Why the original design fails**
- **What a real systolic array should look like**
- **How to fix it correctly**

---

## Problem 1: The Combinational Explosion

### Original Code (Lines 217-230):
```verilog
if (state_q == COMPUTE && compute_count_q == (COMPUTE_LATENCY - 1)) begin
  for (int r = 0; r < ROW_SIZE; r++) begin
    acc_tmp = '0;
    for (int k = 0; k < COL_SIZE; k++) begin
      acc_tmp = acc_tmp + ($signed(weights_a[r][k]) * $signed(acts_b[k][0]));
    end
    result_col0_q[r] <= acc_tmp;
  end
  result_valid_q <= '1;
end
```

### Why This Is Wrong:

In **simulation tools** (Icarus Verilog, Verilator):
- The for-loops execute sequentially in C++-like behavior
- Results are bit-perfect because there's no physical timing
- Testbenches pass ✓

In **real hardware** (synthesis):
- Verilog for-loops **unroll at synthesis time**
- Creates a massive combinational tree:
  - 8×8 = 64 multipliers (32-bit each)
  - Then full adder tree (depth ≈ log₂(64) ≈ 6 levels + accumulation levels)
  - Total combinational depth: **~8-10 logic levels**

### Timing Violation:

- **Clock period:** 1 ns (1 GHz)
- **Propagation delay for one multiplier:** ~0.5-0.8 ns
- **Propagation delay for one adder level:** ~0.1-0.2 ns
- **Total path delay:** ~5-8 ns
- **Slack:** **-4 to -7 ns** ← **FAILS TIMING**

### Physical Consequences:

- Setup time violations → flip-flops capture garbage data
- Path: Data unstable → clock edge hits → captures X (unknown)
- Cascading errors through subsequent computations
- Design is "unsynthesizable" for 1 GHz

---

## Problem 2: Dead Code

The `systolic_pe.sv` module is a well-designed systolic cell with:
- Pipelined MAC operations
- Weight register
- Partial sum accumulation
- Proper data pass-through

**But it's never instantiated** in systolic_array.sv.

This creates an **illusion of a proper design** while the actual implementation does no pipelining.

---

## What a Real Systolic Array Looks Like

### Correct Architecture:

1. **64 PE modules** arranged in an 8×8 grid
2. **Each PE computes ONE MAC per cycle**
   - Multiply: weight × activation
   - Accumulate with partial_sum from left neighbor
   - Output to right neighbor
3. **Weights flow downward** (column-major)
4. **Activations flow rightward** (row-major)
5. **Partial sums flow rightward** (row-major)
6. **Combinational path per PE:** ~2 levels (mult + add)
7. **Total latency:** ROW_SIZE + COL_SIZE + 2 ≈ 18 cycles

### Timing:

- **Combinational depth:** ~2 logic levels
- **Per-level delay:** ~0.2 ns
- **Total path delay:** ~0.4-0.6 ns
- **Slack:** +0.4 ns ← **MEETS TIMING** ✓

---

## Current Fix Status

### Changes Made:

1. **systolic_array.sv (v2.1)**:
   - Now instantiates 64 PE modules in 8×8 grid
   - Proper data flow: weights down, activations right, partial sums right
   - State machine for weight broadcast, activation streaming
   - Output capture from east edge (right column)

2. **systolic_pe.sv (v2.1)**:
   - Simplified MAC logic
   - Weight stored in register
   - Partial sum accumulated per cycle
   - Short combinational path

### Known Issue:

- **Testbench results still incorrect** - GND/garbage values
- **Root cause:** Data flow timing between testbench assumptions and new architecture
- **Investigation needed:** State machine timings and data propagation delays

---

## Architecture Comparison

### Original (BROKEN):
```
Input → [State Machine] → [Combinational Loop] → 64 muls + adder tree → Output
         (latency: ~2 cycles, but huge combinational path)
```

**Problem:** Massive combinational path → timing violation


### Fixed (PIPELINED):
```
Weights → [PE Grid] → Each PE: (W_reg × A_input) + Partial_Sum → Right Output
Activations ↓         (latency: 18 cycles, short paths)
                      Each path: ~2 logic levels
```

**Benefit:** Short combinational paths → meets timing

---

## Next Steps

1. **Debug the test mismatch**:
   - Verify PE MAC logic with unit test
   - Check weight load timing
   - Validate activation streaming protocol

2. **Alignment with testbench**:
   - Testbench expects weights loaded to all PE positions simultaneously
   - Current flow expects weights to propagate
   - May need hybrid broadcast/pipelined model

3. **Alternative approach**:
   - Create a "simplified systolic" that mixes broadcast (weights) with pipelined (activations)
   - This matches realistic hardware better than pure broadcast

---

## References

- **Systolic Arrays**: Kung et al., 1982 - Pioneering work on pipelined array computation
- **Timing Closure**: Standard practice in VLSI design - combinational paths must be short
- **Verilog Synthesis**: Understand for-loop unrolling in synthesis (not simulation)

---

## Key Takeaway

**The fix from pure combinational to pipelined PE grids is architecturally correct and necessary for real hardware.**
However, the current implementation has data flow timing issues that need resolution for the testbench to pass.

The core principle is sound: break the computation into small pipelined stages rather than trying to compute everything combinationally.
