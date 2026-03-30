`timescale 1ns/1ps

module tb_amk_uvm_top;
  import uvm_pkg::*;
  import amk_uvm_pkg::*;

  localparam int XLEN = 32;
  localparam int MAX_K = 256;
  localparam int WORD_ELEMS = 4;

  logic clk;
  logic rst_n;
  reg [1023:0] dumpfile_path;

  amk_if #(
    .XLEN(XLEN),
    .MAX_K(MAX_K),
    .WORD_ELEMS(WORD_ELEMS)
  ) amk_vif (
    .clk_i(clk),
    .rst_ni(rst_n)
  );

  attention_microkernel_engine #(
    .XLEN(XLEN),
    .MAX_K(MAX_K),
    .WORD_ELEMS(WORD_ELEMS)
  ) dut (
    .clk_i(amk_vif.clk_i),
    .rst_ni(amk_vif.rst_ni),
    .cfg_valid_i(amk_vif.cfg_valid_i),
    .cfg_k_i(amk_vif.cfg_k_i),
    .cfg_scale_i(amk_vif.cfg_scale_i),
    .cfg_shift_i(amk_vif.cfg_shift_i),
    .cfg_clip_min_i(amk_vif.cfg_clip_min_i),
    .cfg_clip_max_i(amk_vif.cfg_clip_max_i),
    .cfg_enable_scale_i(amk_vif.cfg_enable_scale_i),
    .cfg_enable_clip_i(amk_vif.cfg_enable_clip_i),
    .load_q_valid_i(amk_vif.load_q_valid_i),
    .load_q_idx_i(amk_vif.load_q_idx_i),
    .load_q_word_i(amk_vif.load_q_word_i),
    .load_k_valid_i(amk_vif.load_k_valid_i),
    .load_k_idx_i(amk_vif.load_k_idx_i),
    .load_k_word_i(amk_vif.load_k_word_i),
    .start_i(amk_vif.start_i),
    .busy_o(amk_vif.busy_o),
    .done_o(amk_vif.done_o),
    .result_valid_o(amk_vif.result_valid_o),
    .result_o(amk_vif.result_o)
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
      $display("[UVM WAVE] Dumping VCD to %0s", dumpfile_path);
      $dumpfile(dumpfile_path);
      $dumpvars(0, tb_amk_uvm_top);
    end
  end

  initial begin
    uvm_config_db#(virtual amk_if #(XLEN, MAX_K, WORD_ELEMS).drv_mp)::set(
      null, "uvm_test_top.env.agent.drv", "vif", amk_vif
    );
    uvm_config_db#(virtual amk_if #(XLEN, MAX_K, WORD_ELEMS).mon_mp)::set(
      null, "uvm_test_top.env.agent.mon", "vif", amk_vif
    );
    run_test("amk_smoke_test");
  end

endmodule
