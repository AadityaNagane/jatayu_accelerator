// UVM top for matmul control

`timescale 1ns / 1ps

module tb_mm_ctrl_uvm_top;
  import uvm_pkg::*;
  import mm_ctrl_uvm_pkg::*;
  `include "uvm_macros.svh"

  logic clk, rst_n;
  reg [1023:0] dumpfile_path;

  mm_ctrl_if dut_if (
    .clk(clk),
    .rst_n(rst_n)
  );

  // Simplified decoder stub
  assign dut_if.instr_ready = 1;
  assign dut_if.decode_valid = dut_if.instr_valid;
  assign dut_if.decode_error = 0;
  assign dut_if.m = 8;
  assign dut_if.n = 8;
  assign dut_if.k = 32;
  assign dut_if.opcode = 3'b000;

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
      $dumpvars(0, tb_mm_ctrl_uvm_top);
    end
  end

  initial begin
    uvm_config_db #(virtual mm_ctrl_if)::set(uvm_root::get(), "*.env.*", "vif", dut_if);
    run_test();
  end

endmodule : tb_mm_ctrl_uvm_top
