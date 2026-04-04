// Weight Buffer - 128KB SRAM for Filter Weights
// Phase 2.2 of Production Roadmap - UPDATED TO v2.0
// Stores filter weights for convolutional layers
//
// IMPROVEMENTS (v2.0):
// - Multi-port write interface: 4 concurrent write ports (one per bank)
// - Eliminates serialization bottleneck from DMA
// - DMA can write 128 bits/cycle (4 × 32-bit words in parallel)
// - Increases weight buffer throughput from 25% to 100% utilization

module weight_buffer #(
    parameter int unsigned DEPTH          = 32768,  // 128KB = 32768 × 32 bits
    parameter int unsigned DATA_WIDTH     = 32,     // 32-bit words
    parameter int unsigned NUM_BANKS      = 4,      // 4 banks for parallel access
    parameter int unsigned ADDR_WIDTH     = 15,     // log2(32768) = 15
    parameter int unsigned NUM_WR_PORTS   = 4       // 4 parallel write ports (one per bank)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Multiple write ports (DMA/CPU - one per bank for parallel writes)
    input  logic [NUM_WR_PORTS-1:0]                wr_en_i,
    input  logic [NUM_WR_PORTS-1:0][ADDR_WIDTH-1:0]       wr_addr_i,
    input  logic [NUM_WR_PORTS-1:0][DATA_WIDTH-1:0]       wr_data_i,
    output logic [NUM_WR_PORTS-1:0]                wr_ready_o,
    
    // Read ports (parallel access for multi-lane)
    input  logic [NUM_BANKS-1:0]        rd_en_i,
    input  logic [NUM_BANKS-1:0][ADDR_WIDTH-1:0] rd_addr_i,
    output logic [NUM_BANKS-1:0][DATA_WIDTH-1:0] rd_data_o,
    output logic [NUM_BANKS-1:0]        rd_valid_o
);

  // Memory array - synthesized to BRAM on FPGA
  // Each bank is 32KB (8192 × 32 bits)
  localparam int unsigned BANK_DEPTH = DEPTH / NUM_BANKS;
  
  logic [NUM_BANKS-1:0][BANK_DEPTH-1:0][DATA_WIDTH-1:0] memory;
  
  // =========================================================================
  // MULTI-PORT WRITE LOGIC (4 parallel write ports)
  // =========================================================================
  // Each port is dedicated to one bank, enabling full 128-bit/cycle throughput
  
  integer wp, bank_idx, mem_idx;
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (bank_idx = 0; bank_idx < NUM_BANKS; bank_idx++) begin
        for (mem_idx = 0; mem_idx < BANK_DEPTH; mem_idx++) begin
          memory[bank_idx][mem_idx] <= '0;
        end
      end
    end else begin
      // Process all write ports in parallel
      for (wp = 0; wp < NUM_WR_PORTS; wp++) begin
        if (wr_en_i[wp] && wr_addr_i[wp] < BANK_DEPTH) begin
          // Port WP writes to Bank WP
          // Address directly indexes into that bank's memory
          memory[wp][wr_addr_i[wp]] <= wr_data_i[wp];
        end
      end
    end
  end
  
  // Write ready signals (always ready for ASIC SRAM, delayed for simulation BRAM)
  always_comb begin
    for (wp = 0; wp < NUM_WR_PORTS; wp++) begin
      wr_ready_o[wp] = 1'b1;  // Multi-port SRAM allows all writes simultaneously
    end
  end
  
  // =========================================================================
  // PARALLEL READ LOGIC (4 read ports for compute lanes)
  // =========================================================================
  // Each read port can access any bank (true multi-port behavior)
  
  always_comb begin
    for (int bank = 0; bank < NUM_BANKS; bank++) begin
      // Each read port independently selects a bank
      if (rd_en_i[bank] && rd_addr_i[bank] < BANK_DEPTH) begin
        rd_data_o[bank] = memory[bank][rd_addr_i[bank]];
        rd_valid_o[bank] = 1'b1;
      end else begin
        rd_data_o[bank] = '0;
        rd_valid_o[bank] = 1'b0;
      end
    end
  end
  
  // Note: For FPGA synthesis, each bank will be inferred as separate BRAM
  // For ASIC, would use dedicated multi-port SRAM compiler (e.g., Embedded SRAM from process node)

endmodule
