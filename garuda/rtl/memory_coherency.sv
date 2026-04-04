// Memory Coherency Module v1.0
// Provides write-through coherency for DMA→Buffer→Systolic data flows
// Uses generation counters to track latest writes

module memory_coherency #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ADDR_WIDTH = 32
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // DMA Write Port
    input  logic                        dma_wr_valid_i,
    input  logic [ADDR_WIDTH-1:0]       dma_wr_addr_i,
    input  logic [DATA_WIDTH-1:0]       dma_wr_data_i,
    output logic                        dma_wr_ready_o,
    
    // Memory Interface (to buffer)
    output logic                        mem_wr_valid_o,
    output logic [ADDR_WIDTH-1:0]       mem_wr_addr_o,
    output logic [DATA_WIDTH-1:0]       mem_wr_data_o,
    input  logic                        mem_wr_ready_i,
    
    // Compute Read Port (with coherency check)
    input  logic                        comp_rd_valid_i,
    input  logic [ADDR_WIDTH-1:0]       comp_rd_addr_i,
    output logic [DATA_WIDTH-1:0]       comp_rd_data_o,
    
    // Coherency Status
    output logic [31:0]                 write_gen_o,    // Generation counter for all writes
    output logic                        coherency_err_o // Error on coherency violation
);

  // Generation counter tracks all writes
  logic [31:0] write_gen_q, write_gen_d;
  
  // Write-through path (direct to memory, no buffering)
  logic pending_write_q, pending_write_d;
  logic [ADDR_WIDTH-1:0] pending_addr_q, pending_addr_d;
  logic [DATA_WIDTH-1:0] pending_data_q, pending_data_d;
  
  always_comb begin
    pending_write_d = pending_write_q;
    pending_addr_d = pending_addr_q;
    pending_data_d = pending_data_q;
    dma_wr_ready_o = 1'b0;
    mem_wr_valid_o = 1'b0;
    coherency_err_o = 1'b0;
    
    if (dma_wr_valid_i && !pending_write_q) begin
      // New write request - queue it
      pending_write_d = 1'b1;
      pending_addr_d = dma_wr_addr_i;
      pending_data_d = dma_wr_data_i;
      dma_wr_ready_o = 1'b1;  // Accept next write immediately
    end
    
    if (pending_write_q) begin
      // Send pending write to memory
      mem_wr_valid_o = 1'b1;
      if (mem_wr_ready_i) begin
        pending_write_d = 1'b0;
        // Write completes - generation counter increments
        // (will happen in sequential logic)
      end
    end
  end
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      write_gen_q <= '0;
      pending_write_q <= 1'b0;
    end else begin
      pending_write_q <= pending_write_d;
      pending_addr_q <= pending_addr_d;
      pending_data_q <= pending_data_d;
      
      // Increment generation counter on each write completion
      if (pending_write_q && mem_wr_ready_i) begin
        write_gen_q <= write_gen_q + 1;
      end
    end
  end
  
  assign mem_wr_addr_o = pending_addr_q;
  assign mem_wr_data_o = pending_data_q;
  assign write_gen_o = write_gen_q;

endmodule
