// UVM Top-level testbench for register rename table

`timescale 1ns / 1ps

module tb_rr_uvm_top;
  import uvm_pkg::*;
  import rr_uvm_pkg::*;
  `include "uvm_macros.svh"

  parameter int unsigned ARCH_REGS = 32;
  parameter int unsigned PHYS_REGS = 64;
  parameter int unsigned ISSUE_WIDTH = 4;
  parameter int unsigned XLEN = 32;

  logic clk, rst_n;
  reg [1023:0] dumpfile_path;

  // Instantiate interface
  rr_if #(
    .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS),
    .ISSUE_WIDTH(ISSUE_WIDTH)
  ) dut_if (
    .clk(clk),
    .rst_n(rst_n)
  );

  // Instantiate DUT
  register_rename_table #(
    .ARCH_REGS(ARCH_REGS),
    .PHYS_REGS(PHYS_REGS),
    .XLEN(XLEN),
    .ISSUE_WIDTH(ISSUE_WIDTH)
  ) dut (
    .clk_i(dut_if.clk),
    .rst_ni(dut_if.rst_n),
    .rename_valid_i(dut_if.rename_valid),
    .arch_rs1_i(dut_if.arch_rs1),
    .arch_rs2_i(dut_if.arch_rs2),
    .arch_rd_i(dut_if.arch_rd),
    .rename_ready_o(dut_if.rename_ready),
    .phys_rs1_o(dut_if.phys_rs1),
    .phys_rs2_o(dut_if.phys_rs2),
    .phys_rd_o(dut_if.phys_rd),
    .old_phys_rd_o(dut_if.old_phys_rd),
    .commit_valid_i(dut_if.commit_valid),
    .commit_phys_rd_i(dut_if.commit_phys_rd),
    .commit_ready_o(dut_if.commit_ready),
    .free_list_empty_o(dut_if.free_list_empty),
    .free_count_o(dut_if.free_count)
  );

  // Clock and reset
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end

  // Optional waveform dump
  initial begin
    if ($value$plusargs("dumpfile=%s", dumpfile_path)) begin
      $display("[WAVE] Dumping to %0s", dumpfile_path);
      $dumpfile(dumpfile_path);
      $dumpvars(0, tb_rr_uvm_top);
    end
  end

  // UVM top-level run
  initial begin
    uvm_config_db #(virtual rr_if)::set(uvm_root::get(), "*.env.*", "vif", dut_if);
    run_test();
  end

endmodule : tb_rr_uvm_top
