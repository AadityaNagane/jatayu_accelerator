`timescale 1ns/1ps

module tb_sa_uvm_top;
  import uvm_pkg::*;
  import sa_uvm_pkg::*;

  localparam int ROW_SIZE   = 8;
  localparam int COL_SIZE   = 8;
  localparam int DATA_WIDTH = 8;
  localparam int ACC_WIDTH  = 32;

  logic clk;
  logic rst_n;
  reg [1023:0] dumpfile_path;

  sa_if #(
    .ROW_SIZE(ROW_SIZE),
    .COL_SIZE(COL_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
  ) sa_vif (
    .clk_i(clk),
    .rst_ni(rst_n)
  );

  systolic_array #(
    .ROW_SIZE(ROW_SIZE),
    .COL_SIZE(COL_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
  ) dut (
    .clk_i(sa_vif.clk_i),
    .rst_ni(sa_vif.rst_ni),
    .weight_valid_i(sa_vif.weight_valid_i),
    .weight_row_i(sa_vif.weight_row_i),
    .weight_ready_o(sa_vif.weight_ready_o),
    .activation_valid_i(sa_vif.activation_valid_i),
    .activation_col_i(sa_vif.activation_col_i),
    .activation_ready_o(sa_vif.activation_ready_o),
    .result_valid_o(sa_vif.result_valid_o),
    .result_row_o(sa_vif.result_row_o),
    .result_ready_i(sa_vif.result_ready_i),
    .load_weights_i(sa_vif.load_weights_i),
    .execute_i(sa_vif.execute_i),
    .clear_accumulators_i(sa_vif.clear_accumulators_i),
    .done_o(sa_vif.done_o)
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
      $dumpvars(0, tb_sa_uvm_top);
    end
  end

  initial begin
    uvm_config_db#(virtual sa_if #(ROW_SIZE, COL_SIZE, DATA_WIDTH, ACC_WIDTH).drv_mp)::set(
      null, "uvm_test_top.env.agent.drv", "vif", sa_vif
    );
    uvm_config_db#(virtual sa_if #(ROW_SIZE, COL_SIZE, DATA_WIDTH, ACC_WIDTH).mon_mp)::set(
      null, "uvm_test_top.env.agent.mon", "vif", sa_vif
    );
    run_test("sa_smoke_test");
  end

endmodule
