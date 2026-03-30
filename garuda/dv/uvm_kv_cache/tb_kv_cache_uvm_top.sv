// UVM Top-Level Testbench for kv_cache_buffer
`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import kv_cache_uvm_pkg::*;

module tb_kv_cache_uvm_top;

  localparam int unsigned NUM_LAYERS  = kv_cache_uvm_pkg::KV_LAYERS;
  localparam int unsigned MAX_SEQ_LEN = kv_cache_uvm_pkg::KV_SEQ_LEN;
  localparam int unsigned HEAD_DIM    = kv_cache_uvm_pkg::KV_HEAD_DIM;

  // -----------------------------------------------------------------------
  // Clock and reset
  // -----------------------------------------------------------------------
  logic clk, rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
  end

  // -----------------------------------------------------------------------
  // Interface bind
  // -----------------------------------------------------------------------
  kv_cache_if #(NUM_LAYERS, MAX_SEQ_LEN, HEAD_DIM) vif (.clk_i(clk), .rst_ni(rst_n));

  // -----------------------------------------------------------------------
  // DUT instantiation
  // -----------------------------------------------------------------------
  kv_cache_buffer #(
    .NUM_LAYERS (NUM_LAYERS),
    .MAX_SEQ_LEN(MAX_SEQ_LEN),
    .HEAD_DIM   (HEAD_DIM)
  ) dut (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .wr_en_i       (vif.wr_en),
    .wr_type_i     (vif.wr_type),
    .wr_layer_i    (vif.wr_layer),
    .wr_pos_i      (vif.wr_pos),
    .wr_word_i     (vif.wr_word),
    .wr_data_i     (vif.wr_data),
    .rd_en_i       (vif.rd_en),
    .rd_type_i     (vif.rd_type),
    .rd_layer_i    (vif.rd_layer),
    .rd_pos_i      (vif.rd_pos),
    .rd_word_i     (vif.rd_word),
    .rd_data_o     (vif.rd_data),
    .rd_valid_o    (vif.rd_valid),
    .seq_advance_i (vif.seq_advance),
    .seq_reset_i   (vif.seq_reset),
    .seq_len_o     (vif.seq_len),
    .full_o        (vif.full)
  );

  // -----------------------------------------------------------------------
  // UVM kick-off
  // -----------------------------------------------------------------------
  initial begin
    uvm_config_db #(
      virtual kv_cache_if #(NUM_LAYERS, MAX_SEQ_LEN, HEAD_DIM).drv_mp
    )::set(null, "uvm_test_top.env.agent.drv", "vif", vif.drv_mp);

    uvm_config_db #(
      virtual kv_cache_if #(NUM_LAYERS, MAX_SEQ_LEN, HEAD_DIM).mon_mp
    )::set(null, "uvm_test_top.env.agent.mon", "vif", vif.mon_mp);

    run_test();
  end

  // -----------------------------------------------------------------------
  // Optional waveform dump
  // -----------------------------------------------------------------------
  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("waves/uvm_regression/kv_cache_uvm.vcd");
      $dumpvars(0, tb_kv_cache_uvm_top);
    end
  end

endmodule
