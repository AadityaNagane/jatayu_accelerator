// KV Cache Buffer — Virtual Interface for UVM (v2.0)
// Added: seq_reset signal (matching new kv_cache_buffer seq_reset_i port)

`timescale 1ns / 1ps

interface kv_cache_if #(
  parameter int unsigned NUM_LAYERS  = 4,
  parameter int unsigned MAX_SEQ_LEN = 8,
  parameter int unsigned HEAD_DIM    = 16
) (
  input logic clk_i,
  input logic rst_ni
);

  localparam int unsigned HEAD_WORDS = HEAD_DIM / 4;

  // DUT ports
  logic                               wr_en;
  logic                               wr_type;
  logic [$clog2(NUM_LAYERS)-1:0]      wr_layer;
  logic [$clog2(MAX_SEQ_LEN)-1:0]     wr_pos;
  logic [$clog2(HEAD_DIM/4)-1:0]      wr_word;
  logic [31:0]                        wr_data;

  logic                               rd_en;
  logic                               rd_type;
  logic [$clog2(NUM_LAYERS)-1:0]      rd_layer;
  logic [$clog2(MAX_SEQ_LEN)-1:0]     rd_pos;
  logic [$clog2(HEAD_DIM/4)-1:0]      rd_word;
  logic [31:0]                        rd_data;
  logic                               rd_valid;

  logic                               seq_advance;
  logic                               seq_reset;      // NEW
  logic [$clog2(MAX_SEQ_LEN+1):0]    seq_len;
  logic                               full;

  // Driver clocking block
  clocking drv_cb @(posedge clk_i);
    default input #1 output #1;
    output wr_en, wr_type, wr_layer, wr_pos, wr_word, wr_data;
    output rd_en, rd_type, rd_layer, rd_pos, rd_word;
    output seq_advance, seq_reset;
    input  rd_data, rd_valid, seq_len, full;
  endclocking

  // Monitor clocking block
  clocking mon_cb @(posedge clk_i);
    default input #1;
    input wr_en, wr_type, wr_layer, wr_pos, wr_word, wr_data;
    input rd_en, rd_type, rd_layer, rd_pos, rd_word;
    input rd_data, rd_valid, seq_advance, seq_reset, seq_len, full;
  endclocking

  modport drv_mp (clocking drv_cb, input clk_i, rst_ni);
  modport mon_mp (clocking mon_cb, input clk_i, rst_ni);

endinterface
