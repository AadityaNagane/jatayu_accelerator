// UVM top for DMA engine

`timescale 1ns / 1ps

module tb_dma_uvm_top;
  import uvm_pkg::*;
  import dma_uvm_pkg::*;
  `include "uvm_macros.svh"

  logic clk, rst_n;
  reg [1023:0] dumpfile_path;

  dma_if dut_if (
    .clk(clk),
    .rst_n(rst_n)
  );

  dma_engine #(
    .DATA_WIDTH(32),
    .ADDR_WIDTH(32),
    .NUM_LANES(16),
    .LANE_WIDTH(32)
  ) dut (
    .clk_i(dut_if.clk),
    .rst_ni(dut_if.rst_n),
    .cfg_valid_i(dut_if.cfg_valid),
    .cfg_src_addr_i(dut_if.cfg_src_addr),
    .cfg_dst_addr_i(dut_if.cfg_dst_addr),
    .cfg_size_i(dut_if.cfg_size),
    .cfg_start_i(dut_if.cfg_start),
    .cfg_ready_o(dut_if.cfg_ready),
    .cfg_done_o(dut_if.cfg_done),
    .cfg_error_o(dut_if.cfg_error),
    .axi_arvalid_o(dut_if.axi_arvalid),
    .axi_arready_i(dut_if.axi_arready),
    .axi_araddr_o(dut_if.axi_araddr),
    .axi_arlen_o(dut_if.axi_arlen),
    .axi_arsize_o(dut_if.axi_arsize),
    .axi_arburst_o(dut_if.axi_arburst),
    .axi_rvalid_i(dut_if.axi_rvalid),
    .axi_rready_o(dut_if.axi_rready),
    .axi_rdata_i(dut_if.axi_rdata),
    .axi_rlast_i(dut_if.axi_rlast),
    .data_valid_o(dut_if.data_valid),
    .data_o(dut_if.data),
    .data_ready_i(dut_if.data_ready),
    .busy_o(dut_if.busy)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end

  initial begin
    if ($value$plusargs("dumpfile=%s", dumpfile_path)) begin
      $display("[WAVE] Dumping to %0s", dumpfile_path);
      $dumpfile(dumpfile_path);
      $dumpvars(0, tb_dma_uvm_top);
    end
  end

  initial begin
    uvm_config_db #(virtual dma_if)::set(uvm_root::get(), "*.env.*", "vif", dut_if);
    run_test();
  end

endmodule : tb_dma_uvm_top
