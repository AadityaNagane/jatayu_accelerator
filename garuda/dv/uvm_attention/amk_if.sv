interface amk_if #(parameter int XLEN = 32,
                   parameter int MAX_K = 256,
                   parameter int WORD_ELEMS = 4)
                  (input logic clk_i, input logic rst_ni);

  localparam int MAX_WORDS = (MAX_K + WORD_ELEMS - 1) / WORD_ELEMS;
  localparam int WORD_W = $clog2(MAX_WORDS);

  logic cfg_valid_i;
  logic [$clog2(MAX_K+1)-1:0] cfg_k_i;
  logic signed [15:0] cfg_scale_i;
  logic [3:0] cfg_shift_i;
  logic signed [31:0] cfg_clip_min_i;
  logic signed [31:0] cfg_clip_max_i;
  logic cfg_enable_scale_i;
  logic cfg_enable_clip_i;

  logic load_q_valid_i;
  logic [WORD_W-1:0] load_q_idx_i;
  logic [31:0] load_q_word_i;

  logic load_k_valid_i;
  logic [WORD_W-1:0] load_k_idx_i;
  logic [31:0] load_k_word_i;

  logic start_i;
  logic busy_o;
  logic done_o;

  logic result_valid_o;
  logic signed [31:0] result_o;

  clocking drv_cb @(posedge clk_i);
    default input #1step output #1step;
    output cfg_valid_i;
    output cfg_k_i;
    output cfg_scale_i;
    output cfg_shift_i;
    output cfg_clip_min_i;
    output cfg_clip_max_i;
    output cfg_enable_scale_i;
    output cfg_enable_clip_i;

    output load_q_valid_i;
    output load_q_idx_i;
    output load_q_word_i;

    output load_k_valid_i;
    output load_k_idx_i;
    output load_k_word_i;

    output start_i;
    input busy_o;
    input done_o;
    input result_valid_o;
    input result_o;
  endclocking

  clocking mon_cb @(posedge clk_i);
    default input #1step;
    input cfg_valid_i;
    input cfg_k_i;
    input cfg_scale_i;
    input cfg_shift_i;
    input cfg_clip_min_i;
    input cfg_clip_max_i;
    input cfg_enable_scale_i;
    input cfg_enable_clip_i;

    input load_q_valid_i;
    input load_q_idx_i;
    input load_q_word_i;

    input load_k_valid_i;
    input load_k_idx_i;
    input load_k_word_i;

    input start_i;
    input busy_o;
    input done_o;
    input result_valid_o;
    input result_o;
  endclocking

  modport drv_mp (clocking drv_cb, input rst_ni, input clk_i);
  modport mon_mp (clocking mon_cb, input rst_ni, input clk_i);

endinterface
