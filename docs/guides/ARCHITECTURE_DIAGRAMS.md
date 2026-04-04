# 📊 Architecture Diagrams & Visual Guides

**Purpose:** Visual representation of Jatayu hardware architecture  
**Format:** ASCII diagrams + Mermaid graphs + conversion instructions for PDF/PNG  
**Audience:** Visual learners, system architects, technical presentations

---

## Table of Contents

1. [System Overview Hierarchy](#system-overview-hierarchy)
2. [Module Connectivity](#module-connectivity)
3. [Data Flow Diagrams](#data-flow-diagrams)
4. [Execution Pipeline](#execution-pipeline)
5. [Memory Hierarchy](#memory-hierarchy)
6. [Converting Diagrams to PDF/PNG](#converting-diagrams-to-pdfdpng)

---

## System Overview Hierarchy

### Complete System Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Qwen 2.5 INFERENCE ENGINE (C)                     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │  Execution Layer:                                                   │   │
│  │  • Load INT8 weights (133 MB)                                       │   │
│  │  • Generate tokens (auto-regressive)                               │   │
│  │  • Manage KV cache (conversation history)                          │   │
│  │  • Measure latency (cycle counting)                                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │  C API Interface (garuda_qwen_runtime.h):                        │      │
│  │  • qwen_load_weights(weights_file)                               │      │
│  │  • qwen_attention_layer(ctx, layer_idx, data)                    │      │
│  │  • qwen_mlp_layer(ctx, layer_idx, data)                         │      │
│  │  • qwen_generate_token(ctx, prompt, &token_id)                  │      │
│  └──────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                 CVXIF Protocol (Custom-3 opcode)
                              │
        ┌─────────────────────┴─────────────────────┐
        ↓                                           ↓
┌──────────────────────┐            ┌───────────────────────────────┐
│ CVA6 Host RISC-V CPU │            │ Jatayu Coprocessor (RTL)      │
│                      │            │                               │
│ • Runs main firmware │            │ ┌─────────────────────────┐   │
│ • Dispatches to      │────────────→ │ INSTRUCTION DECODER     │   │
│   accelerator        │ Requests    │ & CONTROL FSM           │   │
│ • Retrieves results  │ ← Responses  │                         │   │
│                      │            │ Decodes opcodes:        │   │
│ • Manages DDR        │            │ • LOAD_W, LOAD_A        │   │
│   memory hierarchy   │            │ • MM_RUN, MM_DRAIN      │   │
└──────────────────────┘            │ • GELU8, LNORM8         │   │
        ↑ ↓                          │ • KV_UPDATE, KV_READ    │   │
        │ │                          └──────┬──────────────────┘   │
        │ │                                 │                       │
   ┌────┴─┴────────────────────────────────┴───────────────────┐   │
   │                                                             │   │
   │ ┌──────────────────────────────────────────────────────┐  │   │
   │ │ EXECUTION DATAPATH (Hardware)                       │  │   │
   │ │                                                      │  │   │
   │ │  ┌──────────────────┐  ┌──────────────────┐       │  │   │
   │ │  │ Systolic Array   │  │ Attention Engine │       │  │   │
   │ │  │ (8×8 MAC grid)   │  │                  │       │  │   │
   │ │  │ 64 INT8 MACs     │  │ • Q·K dot prod   │       │  │   │
   │ │  │ 383 cyc/layer    │  │ • Softmax        │       │  │   │
   │ │  │                  │  │ • Value agg      │       │  │   │
   │ │  └────────┬─────────┘  │ 34 cycles        │       │  │   │
   │ │           ↕            └────────┬─────────┘       │  │   │
   │ │  ┌─────────────────────────────────────────┐     │  │   │
   │ │  │ KV Cache Buffer (Sequence Memory)       │     │  │   │
   │ │  │ • 128 KB dual-port SRAM                 │     │  │   │
   │ │  │ • Stores K, V for all past tokens       │     │  │   │
   │ │  │ • Prevents O(n²) recomputation          │     │  │   │
   │ │  │ • 3-cycle access latency                │     │  │   │
   │ │  └─────────────────────────────────────────┘     │  │   │
   │ │                                                    │  │   │
   │ │  ┌──────────────┐  ┌──────────────────┐          │  │   │
   │ │  │ GELU ROM     │  │ LNORM8 Unit      │          │  │   │
   │ │  │ (256-entry)  │  │ (4-lane)         │          │  │   │
   │ │  │ Q0.8 LUT     │  │ Normalization    │          │  │   │
   │ │  │ 5 cycles     │  │ 15 cycles        │          │  │   │
   │ │  └──────────────┘  └──────────────────┘          │  │   │
   │ │                                                    │  │   │
   │ │  ┌────────────────────────────────────────────┐   │  │   │
   │ │  │ Register Rename Table (Out-of-Order)      │   │  │   │
   │ │  │ • 4-lane parallel rename/commit           │   │  │   │
   │ │  │ • 64 physical registers (2× logical)      │   │  │   │
   │ │  │ • Resolves WAR/WAW hazards                │   │  │   │
   │ │  └────────────────────────────────────────────┘   │  │   │
   │ │                                                    │  │   │
   │ │  ┌────────────────────────────────────────────┐   │  │   │
   │ │  │ DMA Engine                                 │   │  │   │
   │ │  │ • Memory transfers (W, A, results)        │   │  │   │
   │ │  │ • Burst mode (8/16/32 beats)              │   │  │   │
   │ │  │ • Stride support (2D patterns)            │   │  │   │
   │ │  │ • 4-16 GB/s bandwidth                     │   │  │   │
   │ │  └────────────────────────────────────────────┘   │  │   │
   │ │                                                    │  │   │
   │ └────────────────────────────────────────────────────┘  │   │
   │                                                          │   │
   │ ┌───────────────────────────────────────────────────┐  │   │
   │ │ ON-CHIP MEMORY (L0 Cache)                        │  │   │
   │ │                                                   │  │   │
   │ │ • Weight Buffer: 16 KB (stores quantized W)      │  │   │
   │ │ • Activation Buffer: 8 KB (layer activations)   │  │   │
   │ │ • Accumulator Buffer: 4 KB (MAC partial sums)   │  │   │
   │ │ • Instruction Queue: 32 entries → pending ops   │  │   │
   │ │ • KV Cache: 128 KB (K,V history)                │  │   │
   │ │                                                   │  │   │
   │ │ Total on-chip: ~160 KB                           │  │   │
   │ └───────────────────────────────────────────────────┘  │   │
   │                                                          │   │
   └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                   ┌──────────┴──────────┐
                   ↓                     ↓
          ┌─────────────────┐    ┌─────────────────┐
          │  Cache L1/L2    │    │  System Memory  │
          │  (CPU-managed)  │    │  (DDR RAM)      │
          ├─────────────────┤    ├─────────────────┤
          │ 32-64 KB L1/CPU │    │ 2-4 GB RAM      │
          │ 256 KB L2/CPU   │    │ (weights +      │
          └─────────────────┘    │  activations)   │
                                  └─────────────────┘
                                  ↑ 4-16 GB/s ↓
                                  Bandwidth
```

---

## Module Connectivity

### Datapath Signal Flow

```
                          INSTRUCTION PATH
                                │
                    ┌───────────┴───────────┐
                    ↓                       ↓
          ┌──────────────────┐    ┌──────────────────┐
          │ Decoder &        │    │ Register Rename  │
          │ Control FSM      │    │ Table            │
          └────────┬─────────┘    └────────┬─────────┘
                   │                       │
       ┌───────────┼───────────────────────┼═══════════════════┐
       │           │                       │                   │
       ↓           ↓                       ↓                   ↓
   ┌─────────┐ ┌────────────┐ ┌──────────────────┐ ┌──────────────┐
   │ Systolic│─│ Attention  │─│ KV Cache Access  │─│ GELU + LNORM8│
   │ Array   │ │ Engine     │ │ Control          │ │ Dispatch     │
   └────┬────┘ └─────┬──────┘ └────────┬─────────┘ └──────┬───────┘
        │            │                 │                  │
        └────────┬───┴─────────────────┴──────────────────┘
                 ↓
        ┌────────────────────┐
        │ Output Multiplexer │ (Select which unit output)
        │ & Result Buffer    │
        └────────┬───────────┘
                 ↓
        ┌────────────────────┐
        │ Result Writeabck   │ (To main memory or reg)
        └────────────────────┘
```

### Component Interconnection Matrix

```
                  SystolicArray  AttentionEngine  KVCache  GELU  LNORM8  DMA   RenameTable
──────────────────────────────────────────────────────────────────────────────────────
SystolicArray         ──            ← W_out         ──     ←in    ←in     ──      ──
AttentionEngine      ← W            ──              ← K,V  ←in    ←in     ──      ──
KVCache              ──             → K,V           ──     ──     ──      ← new   ──
GELU                 ──             ← softmax_in    ──     ──     ──      ──      ──
LNORM8               ← in_norm      ← attn_norm     ──     ──     ──      ──      ──
DMA                  ← weight_addr  ←addr, req      ←addr  ──     ──      ──      ──
RenameTable          ← phys_alloc   ← phys_alloc    ──     ──     ──      ──      ──

Legend: ← (input from), → (output to), ── (no connection)
```

---

## Data Flow Diagrams

### Token Generation Flow

```
┌────────────────────────────────────────────────────────────┐
│ TOKEN GENERATION (Single Token)                          │
└────────────────────────────────────────────────────────────┘

START: Prompt = "What is Garuda?"  (5 tokens)
       Generate = [] (to collect generated tokens)

LOOP (generate up to 10 tokens):

┌─ Iteration 1 (seq_len = 5) ─────────────────────────────────┐
│                                                              │
│ Input: [batch=1, seq_len=5, hidden=512]                    │
│        (prompt: "What", "is", "Garuda", "?", <pad>)       │
│                                                              │
│ ┌──────────────────────────────┐                            │
│ │ Layer 0:                     │                            │
│ │  Input [1, 5, 512] → hidden  │                            │
│ │  Compute attention (5×5)     │                            │
│ │  Compute MLP                 │                            │
│ │  Output [1, 5, 512]          │                            │
│ │  @ 575 cycles                │                            │
│ │  Collect only last token     │                            │
│ └──────────────────────────────┘                            │
│                   ↓                                          │
│ ┌──────────────────────────────┐                            │
│ │ Layers 1-7 (same process)    │                            │
│ │ @ 575 cycles each            │                            │
│ │ Pipeline forward through 8   │                            │
│ └──────────────────────────────┘                            │
│                   ↓                                          │
│ Output projection to vocab:                                 │
│  logits = [1, vocab_size=32000]                            │
│  @ 128 cycles                                              │
│                   ↓                                          │
│ Sample or greedy: argmax(logits) = token_id                │
│  token_id = 1234  ("the"?)                                │
│  @ 1 cycle                                                 │
│                                                              │
│ KV Cache Update:                                            │
│  • Store K,V for this token at position 5                 │
│  • @ 8 cycles                                             │
│                                                              │
│ Generate.append(token_id)                                  │
│ seq_len = 6 (for next iteration)                          │
│                                                              │
│                   ↓                                          │
│ TOTAL CYCLES:  4,600                                       │
│ @ 1 GHz:      4.6 µs                                       │
└──────────────────────────────────────────────────────────────┘

┌─ Iteration 2 (seq_len = 6) ─────────────────────────────────┐
│                                                              │
│ Input: [1, 6, 512]  (original 5 + 1 generated)            │
│                                                              │
│ Due to KV Cache:                                           │
│  • Use cached K,V from token 0-4                          │
│  • Compute new attention only for token 5                 │
│  • Re-use GELU results from previous layer                │
│  ← Still ~4.6 µs (KV cache doesn't reduce per-token      │
│                    latency, only reduces memory access)   │
│                                                              │
│ Generate token 2: token_id = 2456  ("accelerator"?)      │
│ Generate.append(token_id)                                 │
│ seq_len = 7 (for next iteration)                         │
└──────────────────────────────────────────────────────────────┘

... (iterations 3-10)

FINAL OUTPUT:
  "Garuda is a RISC-V INT8 accelerator..."
  Latency: 10 tokens × 4.6 µs = 46 µs total
  Throughput: ~217 tokens/sec

INPUT:  "What is Garuda?"        (user prompt)
        ↓ (through 8 layers RTL) ↓
OUTPUT: "Garuda is a RISC-V INT8 accelerator for LLM inference on edge devices."
```

---

## Execution Pipeline

### Cycle-Accurate Pipeline View (One Token Through Systolic Array)

```
              SYSTOLIC ARRAY MAC PIPELINE (8×8 Matrix Multiply)

Clock   Stage 0         Stage 1         Stage 2         Stage 3      ...    Output
Cycle   ───────         ───────         ───────         ───────             ──────
 0:     Active write    ---             ---             ---                  ---
        W[0,0]@PE[0,0]
        A[0,0]@PE[0,0]

 1:     W[0,1]@PE[0,1]  Compute         ---             ---                  ---
        W[1,0]@PE[1,0]  PS[0,0] =
        A[0,1]@PE[0,1]  W[0,0]*A[0,0]
        A[1,0]@PE[1,0]

 2:     W[0,2]@PE[0,2]  Compute         Forward         ---                  ---
        W[2,0]@PE[2,0]    PS[0,1]       PS[0,0]→PE[0,1]
        A[0,2]@PE[0,2]    PS[1,0]       PS[1,0]→PE[1,1]
        A[2,0]@PE[2,0]

 ...    (weights stream left-to-right, activations stream top-to-bottom)

 8:     W[7,7]@PE[7,7]  Compute         Forward         Forward             ---
        A[7,7]@PE[7,7]  PS[7,7]         PS[5,6]         PS[3,4]

 64:    Drain phase     Drain            Drain           Drain              Partial
        (all PEs done)  (propagate)      (propagate)     (propagate)         sums out

 Output: [8×8 partial sum matrix] from bottom-right corner
 Ready for next MAC array or accumulation stage

Per-token latency: 64 cycles base + 8 cycles init + 4 cycles drain = 76 cycles
(when combined with other layers)
```

---

## Memory Hierarchy

### Three-Tier Memory Access Pattern

```
┌─ TIER 1: On-Chip SRAM (L0 Cache) ─────────────────────────┐
│                                                            │
│  Access Time:  1-3 cycles                                 │
│  Capacity:     160 KB total                               │
│  Bandwidth:    256 GB/s (internal to accelerator)        │
│                                                            │
│  ┌─────────────────┐      ┌──────────────────┐           │
│  │ Weight Buffer   │      │ KV Cache Buffer  │           │
│  │ 16 KB           │      │ 128 KB           │           │
│  │                 │      │                  │           │
│  │ • 1 MB weights  │      │ • 256 tokens × 64│           │
│  │   loaded at     │      │ • Dual-port SRAM│           │
│  │   startup       │      │ • 50 GB/s I/O   │           │
│  │ • Refresh: 1x   │      │ • Refresh: 1x   │           │
│  │   per inference │      │   per token      │           │
│  └─────────────────┘      └──────────────────┘           │
│                                                            │
│  ┌──────────────────────┐                                │
│  │ Act/Acc Buffers      │                                │
│  │ 12 KB total          │                                │
│  │ • 8 KB Activations   │                                │
│  │ • 4 KB Accumulators  │                                │
│  │ • Refresh: 64x       │                                │
│  │   per layer          │                                │
│  └──────────────────────┘                                │
└────────────────────────────────────────────────────────────┘
                    ↕ (512 B/cyc)
┌─ TIER 2: L2 Cache (CPU-Managed) ──────────────────────────┐
│                                                            │
│  Access Time:  8-20 cycles                                │
│  Capacity:     256 KB - 4 MB                              │
│  Bandwidth:    64-128 GB/s                               │
│                                                            │
│  Typical Usage:                                            │
│  • CPU code (running firmware)                            │
│  • Frequently accessed weights                            │
│  • Attention results                                      │
└────────────────────────────────────────────────────────────┘
                    ↕ (64 B/cyc)
┌─ TIER 3: Main Memory (DDR DRAM) ──────────────────────────┐
│                                                            │
│  Access Time:  40-100 cycles                              │
│  Capacity:     2-8 GB                                    │
│  Bandwidth:    4-16 GB/s (depends on DDR generation)    │
│                                                            │
│  Stored:                                                   │
│  • Complete Qwen model (133 MB INT8)                     │
│  • Input data, intermediate outputs                       │
│  • Program code                                           │
└────────────────────────────────────────────────────────────┘

Memory Access Pattern (per token):
  • Weight load: 133 MB / token → L0 buffer (1x per inference)
  • Activation: 512 input → L0 buffer (8x per layer)
  • KV write: 8 bytes (K,V for 1 head) → KV cache (1x per token)
  • KV read: 256 × 64 bytes (all history) → Attention (1x per token)
  • Output: 512 bytes → main memory (1x per layer)
```

---

## Converting Diagrams to PDF/PNG

### Option 1: Mermaid Diagrams (Official)

**For professional PDF/PNG generation:**

```bash
# Install mermaid-cli
npm install -g @mermaid-js/mermaid-cli

# Save this as system_arch.mmd:
graph TD
    A["Qwen 2.5 Inference Engine<br/>(C Code)"]
    B["CVXIF Protocol<br/>(Custom-3 Opcode)"]
    C["Jatayu Coprocessor<br/>(RTL - Verilated)"]
    
    D["Systolic Array<br/>(8×8 MAC)"]
    E["Attention Engine"]
    F["KV Cache Buffer"]
    G["DMA Engine"]
    H["Reg Rename Table"]
    
    I["DDR Main Memory"]
    
    A -->|Instructions| B
    B -->|Decode| C
    C -->|Components| D
    C -->|Components| E
    C -->|Components| F
    C -->|Components| G
    C -->|Components| H
    C -->|Data| I

# Generate PDF
mmdc -i system_arch.mmd -o system_arch.pdf

# Generate PNG (high resolution)
mmdc -i system_arch.mmd -o system_arch.png -s 2
```

**Pro Diagrams to Create:**

1. **System Block Diagram** (`system_block.mmd`)
2. **Datapath Flow** (`datapath_flow.mmd`)
3. **Memory Hierarchy** (`memory_hierarchy.mmd`)
4. **Component Interconnect** (`interconnect.mmd`)

### Option 2: Draw.io / Lucidchart

**For drag-and-drop editing:**

1. Export this ASCII art to SVG
2. Import into Draw.io
3. Edit/beautify visually
4. Export as PDF/PNG

```bash
# ASCII to SVG converter
ditaa input.txt -o output.svg

# Then open in Draw.io for beautification
```

### Option 3: Graph Visualization (Graphviz)

**For automatic layout:**

```dot
digraph jatayu {
    rankdir=LR;
    
    node [shape=box, style=rounded];
    
    qwen [label="Qwen 2.5\nInference", fillcolor="#1E293B", fontcolor=white];
    cvxif [label="CVXIF\nProtocol"];
    
    coprocessor [label="Jatayu\nCoprocessor", fillcolor="#0F172A", fontcolor=white];
    
    systolic [label="Systolic Array\n8×8 MACs"];
    attention [label="Attention\nEngine"];
    kvcache [label="KV Cache\nBuffer"];
    dma [label="DMA\nEngine"];
    
    memory [label="Main Memory\n(DDR)"];
    
    qwen -> cvxif -> coprocessor;
    coprocessor -> systolic;
    coprocessor -> attention;
    coprocessor -> kvcache;
    coprocessor -> dma;
    coprocessor -> memory [style=dashed];
}

# Generate:
dot -Tpdf jatayu.dot -o jatayu_architecture.pdf
dot -Tpng jatayu.dot -o jatayu_architecture.png
```

**Commands:**
```bash
# Create DOT file
cat > jatayu.dot << 'EOF'
[paste diagram above]
EOF

# Convert to PDF
dot -Tpdf jatayu.dot -o jatayu_architecture.pdf

# Convert to PNG
dot -Tpng jatayu.dot -o jatayu_architecture.png
```

### Option 4: Automated Slide Deck (Markdown + Pandoc)

**Create presentation-ready PDF:**

```bash
# Install pandoc
sudo apt install pandoc texlive-latex-base

# Create architecture_slides.md with diagrams and content
# Then convert:
pandoc -t beamer architecture_slides.md -o architecture_presentation.pdf

# For speaker notes:
pandoc architecture_slides.md -o architecture_handout.pdf -V lang=en-US
```

**Example architecture_slides.md:**
```markdown
---
title: Jatayu RISC-V LLM Accelerator
author: SPIT VLSI Competition
date: April 2026
---

# System Architecture

## Overview

[ASCII diagram or image here]

## Key Components

- 8×8 Systolic Array (64 MACs)
- Attention Microkernel Engine
- KV Cache Buffer
- DMA Controller
- Register Rename Table

---

# Systolic Array Details

[More diagrams]

## Specifications

- Dimensions: 8×8
- Data type: INT8
- Throughput: 64 MACs/cycle
```

### Option 5: Interactive HTML Visualization

**For web-based exploration:**

```html
<!DOCTYPE html>
<html>
<head>
    <script src="https://d3js.org/d3.v6.min.js"></script>
    <style>
        .node { fill: #1E293B; stroke: #38BDF8; }
        .link { stroke: #666; stroke-width: 2px; }
    </style>
</head>
<body>
    <svg width="960" height="600"></svg>
    <script>
        // D3.js force-directed graph of Jatayu architecture
        // Nodes: components (systolic, attention, etc.)
        // Links: data flow connections
        
        const nodes = [
            {id: "CPU", type: "host"},
            {id: "Systolic", type: "compute"},
            {id: "Attention", type: "compute"},
            {id: "KVCache", type: "memory"},
            // ... more nodes
        ];
        
        const links = [
            {source: "CPU", target: "Systolic"},
            {source: "CPU", target: "Attention"},
            // ... more links
        ];
        
        // Render with D3.js
    </script>
</body>
</html>
```

---

## Recommended Diagram Set for Presentation

**If you're creating slides for judges/interviews, include:**

1. **System Overview** (one slide)
   - High-level block diagram
   - CPU + Accelerator boundary

2. **Systolic Array Detail** (one slide)
   - 8×8 MAC grid
   - Datapath illustration
   - Cycle timeline

3. **Memory Hierarchy** (one slide)
   - Three-tier SRAM/L2/DDR
   - Bandwidth/latency tradeoff

4. **Token Generation Flow** (one slide)
   - How prompt → tokens generated
   - KV cache benefit

5. **Performance Summary** (one slide)
   - Cycle breakdown per layer
   - Throughput/latency
   - Power estimates

**Total presentation: 5 professional diagrams → ~15 minutes talk**

---

## Quick Commands for PDF Generation

```bash
# All-in-one converter (ASCII → SVG → PDF)
cat > generate_diagrams.sh << 'EOF'
#!/bin/bash

# 1. Convert ASCII to SVG
ditaa architecture_diagram.txt -o arch_diagram.svg

# 2. Convert SVG to PDF
rsvg-convert -f pdf arch_diagram.svg > architecture_diagram.pdf

# 3. Merge all PDFs into presentation
pdftk page1.pdf page2.pdf page3.pdf cat output presentation.pdf

# 4. Open in viewer
xdg-open presentation.pdf
EOF

chmod +x generate_diagrams.sh
./generate_diagrams.sh
```

---

**For more details:**
- Mermaid docs: https://mermaid.js.org/
- Draw.io: https://draw.io/
- Graphviz: https://graphviz.org/
- For architecture deep dive, see [ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md)
