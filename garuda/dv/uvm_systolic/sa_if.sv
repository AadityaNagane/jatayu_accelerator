interface sa_if #(parameter int ROW_SIZE = 8,
                  parameter int COL_SIZE = 8,
                  parameter int DATA_WIDTH = 8,
                  parameter int ACC_WIDTH = 32)
                 (input logic clk_i, input logic rst_ni);

  logic weight_valid_i;
  logic [ROW_SIZE*DATA_WIDTH-1:0] weight_row_i;
  logic weight_ready_o;

  logic activation_valid_i;
  logic [COL_SIZE*DATA_WIDTH-1:0] activation_col_i;
  logic activation_ready_o;

  logic result_valid_o;
  logic [ROW_SIZE*ACC_WIDTH-1:0] result_row_o;
  logic result_ready_i;

  logic load_weights_i;
  logic execute_i;
  logic clear_accumulators_i;
  logic done_o;

  // Driver-facing clocking block to avoid race conditions.
  clocking drv_cb @(posedge clk_i);
    default input #1step output #1step;
    output weight_valid_i;
    output weight_row_i;
    input  weight_ready_o;

    output activation_valid_i;
    output activation_col_i;
    input  activation_ready_o;

    input  result_valid_o;
    input  result_row_o;
    output result_ready_i;

    output load_weights_i;
    output execute_i;
    output clear_accumulators_i;
    input  done_o;
  endclocking

  // Monitor-facing clocking block.
  clocking mon_cb @(posedge clk_i);
    default input #1step;
    input weight_valid_i;
    input weight_row_i;
    input weight_ready_o;

    input activation_valid_i;
    input activation_col_i;
    input activation_ready_o;

    input result_valid_o;
    input result_row_o;
    input result_ready_i;

    input load_weights_i;
    input execute_i;
    input clear_accumulators_i;
    input done_o;
  endclocking

  modport drv_mp (clocking drv_cb, input rst_ni, input clk_i);
  modport mon_mp (clocking mon_cb, input rst_ni, input clk_i);

endinterface
