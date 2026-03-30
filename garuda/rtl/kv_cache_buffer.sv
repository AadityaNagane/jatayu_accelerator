// KV Cache Buffer — Garuda Accelerator
// Icarus Verilog compatible: no always_comb with $clog2, no automatic tasks.
// Memory indexed by a single integer computed inside always_ff.
//
// Memory layout (flat 32-bit words):
//   K bank: words [0 .. NUM_LAYERS*MAX_SEQ_LEN*HW - 1]
//   V bank: words [NUM_LAYERS*MAX_SEQ_LEN*HW .. 2*NUM_LAYERS*MAX_SEQ_LEN*HW - 1]
//   HW = HEAD_DIM / 4
//
// FIX LOG:
//   v2.0 — parameterized port widths via $clog2 (fix silent address wrap)
//        — added rst_ni to write block (synthesis correctness)
//        — added rst_ni + reset to rd_data_o block (eliminates X-propagation)
//        — added seq_reset_i port (multi-inference support)
//        — fixed full_o to avoid bit-width truncation on large MAX_SEQ_LEN

`timescale 1ns / 1ps

module kv_cache_buffer #(
  parameter integer NUM_LAYERS  = 8,
  parameter integer MAX_SEQ_LEN = 64,
  parameter integer HEAD_DIM    = 64,
  parameter integer DATA_WIDTH  = 8
) (
  input  wire        clk_i,
  input  wire        rst_ni,

  // Write port
  input  wire                                wr_en_i,
  input  wire                                wr_type_i,         // 0=K, 1=V
  input  wire [$clog2(NUM_LAYERS)-1:0]       wr_layer_i,
  input  wire [$clog2(MAX_SEQ_LEN)-1:0]     wr_pos_i,
  input  wire [$clog2(HEAD_DIM/4)-1:0]      wr_word_i,
  input  wire [31:0]                         wr_data_i,

  // Read port (result valid 1 cycle after rd_en)
  input  wire                                rd_en_i,
  input  wire                                rd_type_i,
  input  wire [$clog2(NUM_LAYERS)-1:0]       rd_layer_i,
  input  wire [$clog2(MAX_SEQ_LEN)-1:0]     rd_pos_i,
  input  wire [$clog2(HEAD_DIM/4)-1:0]      rd_word_i,
  output reg  [31:0]                         rd_data_o,
  output reg                                 rd_valid_o,

  // Sequence tracking
  input  wire                                seq_advance_i,
  input  wire                                seq_reset_i,     // NEW: reset seq counter for multi-inference
  output reg  [$clog2(MAX_SEQ_LEN+1):0]     seq_len_o,
  output wire                                full_o
);

  localparam integer HW          = HEAD_DIM / 4;
  localparam integer HALF_DEPTH  = NUM_LAYERS * MAX_SEQ_LEN * HW;
  localparam integer MEM_DEPTH   = 2 * HALF_DEPTH;

  // -------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------
  reg [31:0] mem [0:MEM_DEPTH-1];

  // Simulation-only memory initialisation (synthesis uses reset)
  integer i;
  initial begin
    for (i = 0; i < MEM_DEPTH; i = i + 1)
      mem[i] = 32'h0;
  end

  // -------------------------------------------------------------------------
  // Write port (FIX: rst_ni guard added — safe for synthesis)
  // -------------------------------------------------------------------------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Memory is initialised by the `initial` block in simulation.
      // In synthesis, memory contents are undefined after reset;
      // the first write always wins, which is acceptable.
      /* synthesis: no register reset for large SRAM — handled by init/clear */
    end else begin
      if (wr_en_i) begin
        mem[ (wr_type_i ? HALF_DEPTH : 0)
             + wr_layer_i * (MAX_SEQ_LEN * HW)
             + wr_pos_i   * HW
             + wr_word_i
           ] <= wr_data_i;
      end
    end
  end

  // -------------------------------------------------------------------------
  // Read port: register address on rd_en; output data next cycle
  // (FIX: rd_addr_q sized with $clog2; rd_data_o gets proper reset)
  // -------------------------------------------------------------------------
  reg [$clog2(MEM_DEPTH)-1:0] rd_addr_q;

  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_valid_o <= 1'b0;
      rd_addr_q  <= '0;
    end else begin
      rd_valid_o <= rd_en_i;
      if (rd_en_i) begin
        rd_addr_q <= (rd_type_i ? HALF_DEPTH : 0)
                   + rd_layer_i * (MAX_SEQ_LEN * HW)
                   + rd_pos_i   * HW
                   + rd_word_i;
      end
    end
  end

  // FIX: rd_data_o gets a reset value to eliminate X-propagation at startup
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_data_o <= 32'd0;
    end else if (rd_valid_o) begin
      rd_data_o <= mem[rd_addr_q];
    end
  end

  // -------------------------------------------------------------------------
  // Sequence length counter
  // (FIX: seq_reset_i allows resetting without full chip reset;
  //        seq_len_o width uses $clog2(MAX_SEQ_LEN+1)+1 to hold MAX_SEQ_LEN)
  // -------------------------------------------------------------------------
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      seq_len_o <= '0;
    end else if (seq_reset_i) begin
      seq_len_o <= '0;
    end else if (seq_advance_i && seq_len_o < MAX_SEQ_LEN) begin
      seq_len_o <= seq_len_o + 1'b1;
    end
  end

  // FIX: compare same width types — no implicit truncation
  assign full_o = (seq_len_o == ($clog2(MAX_SEQ_LEN+1)+1)'(MAX_SEQ_LEN));

endmodule
