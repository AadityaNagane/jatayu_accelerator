// UVM top for INT8 MAC coprocessor

`timescale 1ns / 1ps

module tb_cvxif_uvm_top;
  import uvm_pkg::*;
  import cvxif_uvm_pkg::*;
  `include "uvm_macros.svh"

  logic clk, rst_n;
  reg [1023:0] dumpfile_path;

  cvxif_if dut_if (
    .clk(clk),
    .rst_n(rst_n)
  );

  // Simplified stub for coprocessor
  logic [31:0] result_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) result_q <= '0;
    else if (dut_if.issue_valid && dut_if.issue_ready)
      result_q <= dut_if.issue_instr + dut_if.issue_rd;
  end

  assign dut_if.issue_ready = ~dut_if.result_valid;
  assign dut_if.result_valid = (dut_if.issue_instr != 0);
  assign dut_if.result = result_q;
  assign dut_if.busy = 0;

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
      $dumpvars(0, tb_cvxif_uvm_top);
    end
  end

  initial begin
    uvm_config_db #(virtual cvxif_if)::set(uvm_root::get(), "*.env.*", "vif", dut_if);
    run_test();
  end

endmodule : tb_cvxif_uvm_top
