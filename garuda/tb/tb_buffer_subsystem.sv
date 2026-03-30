`timescale 1ns / 1ps

module tb_buffer_subsystem;

  localparam int unsigned NUM_LANES  = 16;
  localparam int unsigned LANE_WIDTH = 32;
  localparam int unsigned DATA_WIDTH = 32;
  localparam int unsigned ADDR_WIDTH = 32;

  logic clk, rst_n;

  logic dma_wr_valid;
  logic [ADDR_WIDTH-1:0] dma_wr_addr;
  logic [DATA_WIDTH-1:0] dma_wr_data;
  logic dma_wr_ready;

  logic [NUM_LANES-1:0] weight_rd_en;
  logic [NUM_LANES-1:0][$clog2(32768)-1:0] weight_rd_addr;
  logic [NUM_LANES-1:0][DATA_WIDTH-1:0] weight_rd_data;
  logic [NUM_LANES-1:0] weight_rd_valid;

  logic act_rd_en;
  logic [$clog2(16384)-1:0] act_rd_addr;
  logic [NUM_LANES*LANE_WIDTH-1:0] act_rd_data;
  logic act_rd_valid;

  logic acc_rmw_en;
  logic [$clog2(8192)-1:0] acc_rmw_addr;
  logic [DATA_WIDTH-1:0] acc_rmw_data;
  logic [DATA_WIDTH-1:0] acc_rmw_result;
  logic acc_rmw_ready;

  logic ping_pong_sel;

  int pass_count;
  int fail_count;

  buffer_subsystem #(
    .NUM_LANES(NUM_LANES),
    .LANE_WIDTH(LANE_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .dma_wr_valid_i(dma_wr_valid),
    .dma_wr_addr_i(dma_wr_addr),
    .dma_wr_data_i(dma_wr_data),
    .dma_wr_ready_o(dma_wr_ready),
    .weight_rd_en_i(weight_rd_en),
    .weight_rd_addr_i(weight_rd_addr),
    .weight_rd_data_o(weight_rd_data),
    .weight_rd_valid_o(weight_rd_valid),
    .act_rd_en_i(act_rd_en),
    .act_rd_addr_i(act_rd_addr),
    .act_rd_data_o(act_rd_data),
    .act_rd_valid_o(act_rd_valid),
    .acc_rmw_en_i(acc_rmw_en),
    .acc_rmw_addr_i(acc_rmw_addr),
    .acc_rmw_data_i(acc_rmw_data),
    .acc_rmw_result_o(acc_rmw_result),
    .acc_rmw_ready_o(acc_rmw_ready),
    .ping_pong_sel_i(ping_pong_sel)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  task automatic check(input string name, input logic cond);
    if (cond) begin
      pass_count++;
      $display("[PASS] %s", name);
    end else begin
      fail_count++;
      $display("[FAIL] %s", name);
    end
  endtask

  initial begin
    $display("========================================");
    $display("Buffer Subsystem Smoke Test");
    $display("========================================");

    pass_count = 0;
    fail_count = 0;

    rst_n = 0;
    dma_wr_valid = 0;
    dma_wr_addr = '0;
    dma_wr_data = '0;
    weight_rd_en = '0;
    weight_rd_addr = '0;
    act_rd_en = 0;
    act_rd_addr = '0;
    acc_rmw_en = 0;
    acc_rmw_addr = '0;
    acc_rmw_data = '0;
    ping_pong_sel = 0;

    repeat (3) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // Write and read a weight word (0x0000_0000 range)
    dma_wr_addr = 32'h0000_0000;
    dma_wr_data = 32'hDEADBEEF;
    dma_wr_valid = 1;
    @(posedge clk);
    dma_wr_valid = 0;
    @(posedge clk);

    weight_rd_en[0] = 1;
    weight_rd_addr[0] = '0;
    @(posedge clk);
    check("weight read valid", weight_rd_valid[0]);
    check("weight read data", weight_rd_data[0] == 32'hDEADBEEF);
    weight_rd_en[0] = 0;

    // Write activation ping and wide-read from opposite bank after bank swap
    dma_wr_addr = 32'h0002_0000;
    dma_wr_data = 32'h12345678;
    dma_wr_valid = 1;
    @(posedge clk);
    dma_wr_valid = 0;
    @(posedge clk);

    // Switch ping-pong so read bank points to written bank
    ping_pong_sel = 1;
    act_rd_en = 1;
    act_rd_addr = '0;
    @(posedge clk);
    check("activation wide read valid", act_rd_valid);
    check("activation lane0 data", act_rd_data[31:0] == 32'h12345678);
    act_rd_en = 0;

    // Accumulator RMW twice at same location
    acc_rmw_addr = '0;
    acc_rmw_data = 32'd10;
    acc_rmw_en = 1;
    @(posedge clk);
    check("acc rmw ready #1", acc_rmw_ready);
    check("acc rmw old value #1", acc_rmw_result == 32'd0);

    acc_rmw_data = 32'd7;
    @(posedge clk);
    check("acc rmw ready #2", acc_rmw_ready);
    check("acc rmw old value #2", acc_rmw_result == 32'd10);
    acc_rmw_en = 0;

    $display("========================================");
    $display("Summary: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");

    if (fail_count == 0) $display("ALL TESTS PASSED");
    else $display("SOME TESTS FAILED");

    #20;
    $finish;
  end

endmodule
