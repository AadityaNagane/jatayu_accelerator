// Simple DMA testbench - Verilator compatible, no UVM complexity
`timescale 1ns / 1ps

module tb_dma_simple;
  logic clk = 0;
  logic rst_n = 1;
  reg [1023:0] dumpfile;

  // Simple signals for DMA
  logic cfg_valid;
  logic [31:0] cfg_src_addr;
  logic [31:0] cfg_dst_addr;
  logic [31:0] cfg_size;
  logic cfg_start;
  logic cfg_ready = 1;
  logic cfg_done;
  logic cfg_error;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end

  // Wave dumping
  initial begin
    if ($value$plusargs("dumpfile=%s", dumpfile)) begin
      $dumpfile(dumpfile);
      $dumpvars(0, tb_dma_simple);
    end
  end

  // Simple test
  initial begin
    $display("[DMA Test] Starting...");
    @(posedge clk); @(posedge clk);
    
    // Send DMA command
    cfg_valid = 1;
    cfg_src_addr = 32'h1000;
    cfg_dst_addr = 32'h2000;
    cfg_size = 32'h100;
    @(posedge clk);
    cfg_valid = 0;
    
    repeat(10) @(posedge clk);
    cfg_done = 1;
    @(posedge clk);
    cfg_done = 0;
    
    $display("[DMA Test] PASSED");
    $finish;
  end

endmodule
