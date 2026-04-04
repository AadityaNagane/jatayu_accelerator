# 📊 Architecture Diagrams & Visual Reference

Professional system architecture, component interactions, and dataflow illustrations for the Jatayu accelerator.

---

## 1️⃣ System-Level Architecture

### 1.1 Overall System Block Diagram

```mermaid
graph TB
    subgraph Host["🖥️ Host System"]
        CPU["CVA6 RISC-V CPU"]
        Mem["DDR Main Memory"]
    end
    
    subgraph Jatayu["⚡ Jatayu Accelerator (RTL)"]
        CVXIF["CVXIF Interface<br/>(custom-3 opcode)"]
        
        subgraph Compute["Computation Engines"]
            SA["8×8 Systolic Array<br/>INT8 MACs"]
            ATT["Attention Microkernel<br/>Q·K·V Operations"]
            GELU["GELU ROM<br/>256-entry LUT"]
            NORM["LNORM8<br/>4-lane Normalization"]
        end
        
        subgraph Memory["Memory & Caching"]
            KVC["KV Cache Buffer<br/>Sequence History"]
            WB["Weight Buffer<br/>Quantized Weights"]
            AB["Activation Buffer<br/>Layer Outputs"]
        end
        
        DMA["DMA Engine<br/>Data Movement"]
        REG["Register Rename<br/>Out-of-order"]
        MULTI["Multilane MAC<br/>Parallel Lanes"]
    end
    
    CPU -->|CVXIF Dispatch| CVXIF
    CPU -->|DDR Reads/Writes| Mem
    
    CVXIF --> Compute
    CVXIF --> Memory
    CVXIF --> DMA
    
    Compute -->|Uses| Memory
    DMA -->|Transfers| Memory
    DMA -->|Feeds| Compute
    
    style Host fill:#1E293B,stroke:#38BDF8,stroke-width:2px,color:#fff
    style Jatayu fill:#0F172A,stroke:#F59E0B,stroke-width:2px,color:#fff
    style Compute fill:#1E40AF,stroke:#3B82F6,stroke-width:2px,color:#fff
    style Memory fill:#064E3B,stroke:#10B981,stroke-width:2px,color:#fff
```

---

## 2️⃣ Computation Pipeline

### 2.1 Transformer Layer Execution Flow

```mermaid
graph LR
    INPUT["Input<br/>[seq,embed]"]
    
    subgraph ATT["Attention Layer (383 cycles)"]
        QKV["Proj Q,K,V"]
        SA1["Systolic Array<br/>Q·K compute"]
        SM["Softmax"]
        AV["Attention@V"]
    end
    
    subgraph MLP["MLP Layer (177 cycles)"]
        UP["Up-Projection"]
        SA2["Systolic Array<br/>Matrix">"]
        GELU_OP["GELU"]
        DOWN["Down-Projection"]
    end
    
    subgraph NORM["Normalization (15 cycles)"]
        LN["LayerNorm"]
        ADD["Add Residual"]
    end
    
    OUTPUT["Output<br/>[seq,embed]"]
    
    INPUT --> QKV
    QKV --> SA1
    SA1 --> SM
    SM --> AV
    AV --> LN
    
    LN --> UP
    UP --> SA2
    SA2 --> GELU_OP
    GELU_OP --> DOWN
    DOWN --> ADD
    ADD --> OUTPUT
    
    style ATT fill:#1E40AF,stroke:#3B82F6,stroke-width:2px,color:#fff
    style MLP fill:#7C2D12,stroke:#EA580C,stroke-width:2px,color:#fff
    style NORM fill:#064E3B,stroke:#10B981,stroke-width:2px,color:#fff
```

### 2.2 Systolic Array Operation

```mermaid
graph TB
    subgraph PE["Processing Element (PE)"]
        MUL["×<br/>Multiplier"]
        ACC["Accumulator<br/>Register"]
        REG["Pipeline<br/>Register"]
    end
    
    D_IN["Data In<br/>(activation)"]
    W_IN["Weight In<br/>(from row)"]
    D_OUT["Data Out<br/>(to next)"]
    P_OUT["Partial Sum<br/>(diagonal)"]
    
    D_IN --> D_OUT
    W_IN --> MUL
    D_IN --> MUL
    MUL --> ACC
    ACC --> REG
    REG --> P_OUT
    
    style PE fill:#1E40AF,stroke:#3B82F6,stroke-width:2px,color:#fff
    style MUL fill:#DC2626,stroke:#F87171,stroke-width:1px,color:#fff
    style ACC fill:#059669,stroke:#34D399,stroke-width:1px,color:#fff
```

---

## 3️⃣ Data Flow Diagrams

### 3.1 Token Generation Loop

```mermaid
graph LR
    START["🟢 START"]
    
    LOAD["1️⃣ Load Weights<br/>INT8 from Memory"]
    INIT["2️⃣ Initialize Context<br/>KV Cache, Buffers"]
    TOKEN["3️⃣ Input Token<br/>Current Position"]
    
    subgraph LAYERS["4️⃣ For Each Layer"]
        L1["Attention (RTL)"]
        L2["MLP (RTL)"]
        L3["Normalization"]
    end
    
    KV["5️⃣ Update KV Cache<br/>Store K,V for next"]
    NEXT["6️⃣ Next Token<br/>Output Logits"]
    
    LOOP{"More Tokens?"}
    
    OUTPUT["🟢 Done<br/>Output Sequence"]
    
    START --> LOAD
    LOAD --> INIT
    INIT --> TOKEN
    TOKEN --> LAYERS
    LAYERS --> KV
    KV --> NEXT
    NEXT --> LOOP
    LOOP -->|Yes| TOKEN
    LOOP -->|No| OUTPUT
    
    style START fill:#059669,stroke:#34D399,stroke-width:2px,color:#fff
    style OUTPUT fill:#059669,stroke:#34D399,stroke-width:2px,color:#fff
    style LAYERS fill:#1E40AF,stroke:#3B82F6,stroke-width:2px,color:#fff
    style LOOP fill:#DC2626,stroke:#F87171,stroke-width:2px,color:#fff
```

### 3.2 Memory Access Patterns

```mermaid
graph TB
    subgraph DDR["🏢 DDR Main Memory"]
        WEIGHTS["Weight Tensors<br/>133 MB"]
        ACTIVATIONS["Activation Tensors<br/>Layer Buffers"]
    end
    
    subgraph ONCHIP["⚡ On-Chip Storage"]
        WB["Weight Buffer<br/>16 KB"]
        AB["Activation Buffer<br/>8 KB"]
        ACC["Accumulator Buffer<br/>4 KB"]
        INSTR["Instruction Queue<br/>32 entries"]
    end
    
    DMA["DMA Engine<br/>Burst Mode"]
    
    WEIGHTS -->|Load via DMA| WB
    WB -->|Stream| SA["8×8 Systolic"]
    SA -->|Results| ACC
    ACC -->|Writeback| ACTIVATIONS
    
    ACTIVATIONS -->|Feedback| AB
    AB -->|Feed| SA
    
    INSTR -->|Control| DMA
    INSTR -->|Dispatch| SA
    
    style DDR fill:#334155,stroke:#64748B,stroke-width:2px,color:#fff
    style ONCHIP fill:#1E40AF,stroke:#3B82F6,stroke-width:2px,color:#fff
    style DMA fill:#EA580C,stroke:#F97316,stroke-width:2px,color:#fff
```

---

## 4️⃣ Timing Diagrams

### 4.1 Attention Layer Timing

```
Clock Cycle:  0    10    20    30    40    50    60    70
            │────────────────────────────────────────────│

Load Q,K,V  │███│
            
Compute Q·K │    │████████ (50 cycles)
            
Softmax     │              │███ (10 cycles)
            
Load V      │                    │███ (10 cycles)
            
Compute A·V │                        │████████ (40 cycles)
            
Output Ready│                                    ▼ (at ~105 cycles)
            
Legend: ███ = Active computation | ▼ = Result Ready
```

### 4.2 Systolic Array Wave Propagation

```
Time:        0  1  2  3  4  5  6  7  8
           ┌──────────────────────────┐
Input Row0 │█ · · · · · · · ·          │ (PE index 0-7)
Input Row1 │· █ · · · · · · ·          │
Input Row2 │· · █ · · · · · ·          │
Input Row3 │· · · █ · · · · ·          │
Input Row4 │· · · · █ · · · ·          │
Input Row5 │· · · · · █ · · ·          │
Input Row6 │· · · · · · █ · ·          │
Input Row7 │· · · · · · · █ ·          │
           └──────────────────────────┘

█ = Data flowing through PE
· = PE empty/waiting

Result emerges after 8 cycles (when reaches opposite corner)
Plus accumulation pipeline = 8-16 cycles total
```

---

## 5️⃣ Component Hierarchy

### 5.1 Hardware Subsystems

```mermaid
graph TB
    TOP["Jatayu Coprocessor Top"]
    
    TOP --> CVXIF_M["CVXIF Manager<br/>Instruction decode"]
    
    CVXIF_M --> SA["Systolic Array<br/>8×8 MAC grid"]
    CVXIF_M --> ATT["Attention Engine<br/>Q·K·V"]
    CVXIF_M --> DMA["DMA Controller<br/>Memory I/F"]
    CVXIF_M --> BUF["Buffer Control<br/>W/A/Acc"]
    CVXIF_M --> REG["Register Pipeline<br/>Data staging"]
    
    SA --> SA_PE["Array of PE"]
    SA_PE --> MUL["Multiplier"]
    SA_PE --> ACC["Accumulator"]
    
    ATT --> DOT["Dot Product<br/>Unit"]
    ATT --> SM["Softmax<br/>Unit"]
    
    style TOP fill:#1E40AF,color:#fff
    style SA fill:#DC2626,color:#fff
    style ATT fill:#EA580C,color:#fff
    style DMA fill:#059669,color:#fff
```

---

## 6️⃣ Signal Flow: One MAC Operation

```mermaid
graph LR
    A["Activation<br/>Input"] 
    W["Weight"]
    
    A -->|Select Lane| MUX1["Mux<br/>Select Partial"]
    W -->|8-bit| MUL["MAC<br/>× Unit"]
    
    A -->|8-bit| MUL
    MUL -->|16-bit| ACC["Accumulator<br/>Register"]
    
    MUX1 -->|Previous| ACC
    ACC -->|Saturation| SAT["Clamp<br/>[-128,127]"]
    SAT -->|Next Cycle| MUX1
    
    SAT -->|Output| OUT["Result Out<br/>8-bit"]
    OUT -->|To Next PE| NEXT["→ PE[i+1]"]
    
    style MUL fill:#DC2626,color:#fff,stroke-width:2px
    style ACC fill:#059669,color:#fff,stroke-width:2px
    style SAT fill:#EA580C,color:#fff,stroke-width:2px
```

---

## 7️⃣ Memory Map (On-Chip)

```
┌────────────────────────────────────────┐
│     Jatayu On-Chip Storage (32 KB)     │
├────────────────────────────────────────┤
│                                        │
│  ┌────────────────────────────────┐  │
│  │  Weight Buffer (16 KB)         │  │
│  │  [0x0000 - 0x3FFF]            │  │
│  │  INT8 quantized weights        │  │
│  └────────────────────────────────┘  │
│                                        │
│  ┌────────────────────────────────┐  │
│  │  Activation Buffer (8 KB)      │  │
│  │  [0x4000 - 0x5FFF]            │  │
│  │  Layer inputs/outputs          │  │
│  └────────────────────────────────┘  │
│                                        │
│  ┌────────────────────────────────┐  │
│  │  Accumulator Buffer (4 KB)     │  │
│  │  [0x6000 - 0x6FFF]            │  │
│  │  MAC partial sums              │  │
│  └────────────────────────────────┘  │
│                                        │
│  ┌────────────────────────────────┐  │
│  │  Instruction Queue (4 KB)     │  │
│  │  [0x7000 - 0x7FFF]            │  │
│  │  32 × 128-bit instructions    │  │
│  └────────────────────────────────┘  │
│                                        │
└────────────────────────────────────────┘

Access patterns:
• Weight: Sequential (row + column streaming)
• Activation: Random (depends on attention)
• Accumulator: FIFO + random write
• Instruction: FIFO queue
```

---

## 8️⃣ Bus Protocol: CVXIF Interaction

```mermaid
sequenceDiagram
    participant CPU as CVA6 CPU
    participant CVXIF as CVXIF Manager
    participant SA as Systolic Array
    participant MEM as Memory
    
    CPU->>CVXIF: Issue LOAD_W<br/>(addr, size)
    activate CVXIF
    
    CVXIF->>MEM: Read weights<br/>(DMA)
    activate MEM
    MEM-->>CVXIF: Weight data
    deactivate MEM
    
    CVXIF->>SA: Store weights<br/>in buffer
    activate SA
    
    CPU->>CVXIF: Issue MM_RUN<br/>(start compute)
    CVXIF->>SA: Execute MAC<br/>operations
    
    Note over SA: Systolic Array<br/>Computing...
    
    SA-->>CVXIF: Result ready
    CVXIF->>MEM: Write results<br/>(DMA writeback)
    
    CPU->>CVXIF: Issue DRAIN<br/>(end transaction)
    CVXIF-->>CPU: Transaction done
    deactivate SA
    deactivate CVXIF
```

---

## 9️⃣ UVM Test Architecture

### 9.1 Test Hierarchy

```mermaid
graph TB
    TB["SystemVerilog Testbench<br/>tb_*_uvm_top.sv"]
    
    TB --> UVM["UVM Testbench Base"]
    
    UVM --> AGT["UVM Agent<br/>Drives DUT"]
    UVM --> MON["UVM Monitor<br/>Observes"]
    UVM --> SB["Scoreboard<br/>Compares"]
    
    AGT --> DRV["Driver<br/>Stimulus"]
    AGT --> SEQ["Sequencer<br/>Test Sequences"]
    
    DRV --> DUT["DUT<br/>(RTL Block)"]
    DUT --> MON
    MON --> SB
    
    SB --> RESULT["Pass/Fail"]
    
    style TB fill:#1E40AF,color:#fff
    style UVM fill:#EA580C,color:#fff
    style DUT fill:#DC2626,color:#fff
    style RESULT fill:#059669,color:#fff
```

---

## 🔟 Performance Comparison

### 10.1 Software vs Hardware Execution

```mermaid
graph BarChart
    title["Cycle Count Comparison: Single Layer"]
    
    SW["Software Only<br/>C Implementation"] : 2400
    HW["Hardware RTL<br/>Systolic Array"] : 400
    HWOV["Hardware + Overhead<br/>(SW + RTL)"] : 430
```

**Key Insight:**
- Software only: ~2400 cycles (sequential computation)
- Hardware: ~400 cycles (parallel 8×8 array)
- **6× speedup with RTL acceleration**

---

## 📐 Detailed Component Specs

### Systolic Array (8×8)
```
Dimensions:       8 rows × 8 columns = 64 MACs
Data Type:        INT8 (8-bit signed integers)
Throughput:       64 MACs per cycle (peak)
Latency:          8-16 cycles (pipeline + accumulation)
Power:            ~50 mW @ 1 GHz (estimated)
Area:             ~2,000 µm² (normalized)
```

### Attention Engine
```
Input:            Q, K, V tensors (INT8)
Operations:       Q·K dot product, softmax, V aggregation
Throughput:       1 head per 34 cycles
Sequence Len:     Supports up to 2048 tokens (parameterized)
Heads:            Multi-head capable (sequential)
```

### KV Cache
```
Capacity:         Parameterized (default: 256 × 64 × 8 bytes)
Access Ports:     1 write (new tokens), 2 read (queries)
Latency:          1 cycle (SRAM)
Overflow Detect:  Yes (prevents sequence wrap)
```

---

## 📚 References

See [ARCHITECTURE_GUIDE.md](ARCHITECTURE_GUIDE.md) for detailed component specifications.

See [COMPLETE_TESTING_GUIDE.md](../../COMPLETE_TESTING_GUIDE.md) for testing procedures.
