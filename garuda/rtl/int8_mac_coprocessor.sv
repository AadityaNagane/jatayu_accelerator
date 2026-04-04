// INT8 MAC coprocessor top-level module
// Connects to CVA6 via CVXIF interface

module int8_mac_coprocessor
  import int8_mac_instr_pkg::*;
#(
    parameter  int unsigned NrRgprPorts         = 2,
    parameter  int unsigned XLEN                = 32,
    parameter  type         readregflags_t      = logic,
    parameter  type         writeregflags_t     = logic,
    parameter  type         id_t                = logic,
    parameter  type         hartid_t            = logic,
    parameter  type         x_compressed_req_t  = logic,
    parameter  type         x_compressed_resp_t = logic,
    parameter  type         x_issue_req_t       = logic,
    parameter  type         x_issue_resp_t      = logic,
    parameter  type         x_register_t        = logic,
    parameter  type         x_commit_t          = logic,
    parameter  type         x_result_t          = logic,
    parameter  type         cvxif_req_t         = logic,
    parameter  type         cvxif_resp_t        = logic,
    localparam type         registers_t         = logic [NrRgprPorts-1:0][XLEN-1:0]
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  cvxif_req_t  cvxif_req_i,
    output cvxif_resp_t cvxif_resp_o
);

  x_compressed_req_t  compressed_req;
  x_compressed_resp_t compressed_resp;
  logic               compressed_valid, compressed_ready;
  
  x_issue_req_t       issue_req;
  x_issue_resp_t      issue_resp;
  x_issue_resp_t      issue_resp_dec;
  logic               issue_valid, issue_ready, issue_ready_dec;
  
  x_register_t        register;
  logic               register_valid;
  
  registers_t         registers;
  opcode_t            opcode;
  hartid_t            issue_hartid, hartid;
  id_t                issue_id, id;
  logic [4:0]         issue_rd, rd;
  
  logic [XLEN-1:0]    result;
  logic               result_valid;
  logic               we;
  logic               overflow;  // Overflow/saturation flag

  // Attention microkernel engine signals
  localparam int unsigned MAX_K = 256;
  localparam int unsigned WORD_ELEMS = 4;
  
  logic                    mk_cfg_valid;
  logic [$clog2(MAX_K+1)-1:0] mk_cfg_k;
  logic signed [15:0]         mk_cfg_scale;
  logic [3:0]                mk_cfg_shift;
  logic signed [31:0]        mk_cfg_clip_min, mk_cfg_clip_max;
  logic                      mk_cfg_en_scale, mk_cfg_en_clip;
  
  logic                      mk_load_q_valid;
  logic [$clog2((MAX_K+WORD_ELEMS-1)/WORD_ELEMS)-1:0] mk_load_q_idx;
  logic [31:0]               mk_load_q_word;
  
  logic                      mk_load_k_valid;
  logic [$clog2((MAX_K+WORD_ELEMS-1)/WORD_ELEMS)-1:0] mk_load_k_idx;
  logic [31:0]               mk_load_k_word;
  
  logic                      mk_start;
  logic                      mk_busy;
  logic                      mk_done;
  logic                      mk_result_valid;
  logic signed [31:0]        mk_result;
  
  // Microkernel state machine for operand staging
  localparam int unsigned MAX_WORDS = (MAX_K + WORD_ELEMS - 1) / WORD_ELEMS;
  logic [$clog2(MAX_WORDS)-1:0] mk_k_words_q, mk_k_words_d;
  logic [$clog2(MAX_WORDS)-1:0] mk_current_word_idx_q, mk_current_word_idx_d;
  
  // Latched configuration values (persist across instructions)
  logic [$clog2(MAX_K+1)-1:0] mk_latched_k_q, mk_latched_k_d;
  logic signed [31:0] mk_latched_clip_min_q, mk_latched_clip_min_d;
  logic signed [31:0] mk_latched_clip_max_q, mk_latched_clip_max_d;
  
  // Selection between regular MAC unit and microkernel engine
  logic use_microkernel;
  logic use_matmul_ctrl;
  logic use_norm_act;
  logic microkernel_busy;
  logic matmul_busy;
  logic na_busy;
  logic accel_busy;
  logic issue_accept;
  logic [2:0] issue_funct3;
  matmul_subop_t matmul_subop;

  // Systolic array (MATMUL_CTRL) signals
  localparam int unsigned SA_ROW_SIZE = 8;
  localparam int unsigned SA_COL_SIZE = 8;
  localparam int unsigned SA_DW = 8;
  localparam int unsigned SA_AW = 32;

  logic sa_weight_valid;
  logic [SA_ROW_SIZE*SA_DW-1:0] sa_weight_row;
  logic sa_weight_ready;
  logic sa_activation_valid;
  logic [SA_COL_SIZE*SA_DW-1:0] sa_activation_col;
  logic sa_activation_ready;
  logic sa_result_valid;
  logic [SA_ROW_SIZE*SA_AW-1:0] sa_result_row;
  logic sa_result_ready;
  logic sa_load_weights;
  logic sa_execute;
  logic sa_clear_accumulators;
  logic sa_done;

  // MATMUL control FSM and latched metadata/response
  typedef enum logic [2:0] {
    MM_IDLE,
    MM_LOAD_W_STREAM,
    MM_LOAD_A_STREAM,
    MM_WAIT_DONE,
    MM_RESP
  } mm_state_t;

  mm_state_t mm_state_q, mm_state_d;
  logic [2:0] mm_stream_idx_q, mm_stream_idx_d;
  logic [SA_ROW_SIZE*SA_DW-1:0] mm_stream_payload_q, mm_stream_payload_d;
  logic [31:0] mm_result_data_q, mm_result_data_d;
  logic mm_result_we_q, mm_result_we_d;
  logic [SA_ROW_SIZE*SA_AW-1:0] sa_result_row_q, sa_result_row_d;
  logic [SA_COL_SIZE*SA_DW-1:0] mm_activation_col;
  logic [4:0] mm_resp_rd_q, mm_resp_rd_d;
  hartid_t mm_resp_hartid_q, mm_resp_hartid_d;
  id_t     mm_resp_id_q, mm_resp_id_d;

  // Latched metadata for attention microkernel multi-cycle response
  logic mk_resp_pending_q, mk_resp_pending_d;
  logic [4:0] mk_resp_rd_q, mk_resp_rd_d;
  hartid_t mk_resp_hartid_q, mk_resp_hartid_d;
  id_t     mk_resp_id_q, mk_resp_id_d;

  // NORM_ACT (GELU8/LayerNorm8) control FSM and metadata
  typedef enum logic [1:0] {
    NA_IDLE,
    NA_COMPUTE,
    NA_RESP
  } na_state_t;

  na_state_t na_state_q, na_state_d;
  logic [7:0] na_compute_cycles_q, na_compute_cycles_d;
  logic [31:0] na_input_data_q, na_input_data_d;
  logic [31:0] na_param_data_q, na_param_data_d;
  logic [31:0] na_result_data_q, na_result_data_d;
  logic na_result_we_q, na_result_we_d;
  logic na_result_valid_q, na_result_valid_d;  // Persistent result valid flag
  norm_subop_t na_subop_q, na_subop_d;
  logic [4:0] na_resp_rd_q, na_resp_rd_d;
  hartid_t na_resp_hartid_q, na_resp_hartid_d;
  id_t     na_resp_id_q, na_resp_id_d;

  // GELU8 ROM
  logic [7:0] gelu_addr;
  logic [7:0] gelu_result;
  assign gelu_addr = na_input_data_q[7:0];  // Two's complement index maps directly to 0..255

  function automatic logic signed [7:0] clip_int8(input logic signed [31:0] v);
    if (v > 127) begin
      clip_int8 = 8'sd127;
    end else if (v < -128) begin
      clip_int8 = -8'sd128;
    end else begin
      clip_int8 = v[7:0];
    end
  endfunction

  // Q8 approximation of inverse sqrt for hackathon-friendly LNORM8 datapath.
  function automatic logic [15:0] approx_inv_std_q8(input logic [31:0] var_eps);
    if (var_eps <= 1) begin
      approx_inv_std_q8 = 16'd256;  // 1.0
    end else if (var_eps <= 4) begin
      approx_inv_std_q8 = 16'd181;  // ~0.707
    end else if (var_eps <= 9) begin
      approx_inv_std_q8 = 16'd128;  // 0.5
    end else if (var_eps <= 16) begin
      approx_inv_std_q8 = 16'd96;
    end else if (var_eps <= 36) begin
      approx_inv_std_q8 = 16'd64;
    end else if (var_eps <= 64) begin
      approx_inv_std_q8 = 16'd45;
    end else if (var_eps <= 100) begin
      approx_inv_std_q8 = 16'd32;
    end else begin
      approx_inv_std_q8 = 16'd16;
    end
  endfunction

  // LNORM over packed 4xINT8 lanes in a 32-bit word.
  // rs2 payload format: gamma in rs2[7:0] (Q1.7), beta in rs2[15:8] (INT8).
  function automatic logic [31:0] lnorm8_4lane(
    input logic [31:0] x_word,
    input logic [31:0] param_word
  );
    logic signed [7:0] x0, x1, x2, x3;
    logic signed [7:0] gamma_q7, beta_i8;
    logic signed [31:0] sum;
    logic signed [31:0] mean;
    logic signed [31:0] d0, d1, d2, d3;
    logic [31:0] var_acc;
    logic [31:0] var_val;
    logic [15:0] inv_std_q8;
    logic signed [31:0] y0, y1, y2, y3;
    logic signed [31:0] t0, t1, t2, t3;

    x0 = x_word[7:0];
    x1 = x_word[15:8];
    x2 = x_word[23:16];
    x3 = x_word[31:24];

    gamma_q7 = param_word[7:0];
    beta_i8 = param_word[15:8];

    // Default gamma=1.0 if caller passes 0 (keeps programming simple for bring-up).
    if (gamma_q7 == 8'sd0) begin
      gamma_q7 = 8'sd127;
    end

    sum = x0 + x1 + x2 + x3;
    mean = sum >>> 2;

    d0 = x0 - mean;
    d1 = x1 - mean;
    d2 = x2 - mean;
    d3 = x3 - mean;

    var_acc = (d0 * d0) + (d1 * d1) + (d2 * d2) + (d3 * d3);
    var_val = var_acc >> 2;
    inv_std_q8 = approx_inv_std_q8(var_val + 1);  // epsilon = 1

    // y = ((x-mean) * inv_std_q8 * gamma_q7) >> 15 + beta
    t0 = (d0 * $signed({1'b0, inv_std_q8}) * gamma_q7);
    t1 = (d1 * $signed({1'b0, inv_std_q8}) * gamma_q7);
    t2 = (d2 * $signed({1'b0, inv_std_q8}) * gamma_q7);
    t3 = (d3 * $signed({1'b0, inv_std_q8}) * gamma_q7);

    y0 = (t0 >>> 15) + beta_i8;
    y1 = (t1 >>> 15) + beta_i8;
    y2 = (t2 >>> 15) + beta_i8;
    y3 = (t3 >>> 15) + beta_i8;

    lnorm8_4lane = {
      clip_int8(y3),
      clip_int8(y2),
      clip_int8(y1),
      clip_int8(y0)
    };
  endfunction

  assign compressed_req    = cvxif_req_i.compressed_req;
  assign compressed_valid  = cvxif_req_i.compressed_valid;
  assign compressed_ready  = 1'b1;
  assign compressed_resp   = x_compressed_resp_t'(0);
  
  assign issue_req         = cvxif_req_i.issue_req;
  assign issue_valid       = cvxif_req_i.issue_valid;
  assign register          = cvxif_req_i.register;
  assign register_valid    = cvxif_req_i.register_valid;
  
  assign cvxif_resp_o.compressed_ready = compressed_ready;
  assign cvxif_resp_o.compressed_resp  = compressed_resp;
  assign cvxif_resp_o.issue_ready      = issue_ready;
  assign cvxif_resp_o.issue_resp       = issue_resp;
  assign cvxif_resp_o.register_ready   = cvxif_resp_o.issue_ready;
  assign issue_funct3 = issue_req.instr[14:12];
  assign matmul_subop = matmul_subop_t'(issue_funct3);

  int8_mac_decoder #(
      .copro_issue_resp_t(copro_issue_resp_t),
      .opcode_t          (opcode_t),
      .NbInstr           (NbInstr),
      .CoproInstr        (int8_mac_instr_pkg::CoproInstr),
      .NrRgprPorts       (NrRgprPorts),
      .hartid_t          (hartid_t),
      .id_t              (id_t),
      .x_issue_req_t     (x_issue_req_t),
      .x_issue_resp_t    (x_issue_resp_t),
      .x_register_t      (x_register_t),
      .registers_t       (registers_t)
  ) i_int8_mac_decoder (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .issue_valid_i    (issue_valid),
      .issue_req_i      (issue_req),
      .issue_ready_o    (issue_ready_dec),
      .issue_resp_o     (issue_resp_dec),
      .register_valid_i (register_valid),
      .register_i       (register),
      .registers_o      (registers),
      .opcode_o         (opcode),
      .hartid_o         (issue_hartid),
      .id_o             (issue_id),
      .rd_o             (issue_rd)
  );

  assign microkernel_busy = (mk_state_q == MK_EXECUTING) || mk_resp_pending_q;
  assign matmul_busy = (mm_state_q != MM_IDLE);
  assign na_busy = (na_state_q != NA_IDLE);
  assign accel_busy = microkernel_busy || matmul_busy || na_busy;
  assign issue_ready = issue_ready_dec && !accel_busy;

  always_comb begin
    issue_resp = issue_resp_dec;
    if (accel_busy) begin
      issue_resp.accept = 1'b0;
      issue_resp.writeback = 1'b0;
      issue_resp.register_read = '0;
    end
  end

  assign issue_accept = issue_valid && issue_ready && issue_resp.accept;

  // Determine if we should use microkernel engine
  assign use_microkernel = (opcode inside {ATT_DOT_SETUP, ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP});
  assign use_matmul_ctrl = (opcode == MATMUL_CTRL);
  assign use_norm_act = (opcode == NORM_ACT);
  assign sa_result_ready = 1'b1;

  // Decode NORM_ACT sub-opcode
  norm_subop_t norm_subop;
  assign norm_subop = norm_subop_t'(issue_funct3);

  int8_mac_unit #(
      .XLEN      (XLEN)
  ) i_int8_mac_unit (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .rs1_i      (registers[0]),
      .rs2_i      (registers[1]),
      .rd_i       (registers[0]),
      .opcode_i   (opcode),
      .hartid_i   (issue_hartid),
      .id_i       (issue_id),
      .rd_addr_i  (issue_rd),
      .result_o   (result),
      .valid_o    (result_valid),
      .we_o       (we),
      .overflow_o (overflow),
      .rd_addr_o  (rd),
      .hartid_o   (hartid),
      .id_o       (id)
  );

  // Attention microkernel engine
  attention_microkernel_engine #(
      .XLEN(XLEN),
      .MAX_K(MAX_K),
      .WORD_ELEMS(WORD_ELEMS)
  ) i_attention_microkernel_engine (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .cfg_valid_i(mk_cfg_valid),
      .cfg_k_i(mk_cfg_k),
      .cfg_scale_i(mk_cfg_scale),
      .cfg_shift_i(mk_cfg_shift),
      .cfg_clip_min_i(mk_cfg_clip_min),
      .cfg_clip_max_i(mk_cfg_clip_max),
      .cfg_enable_scale_i(mk_cfg_en_scale),
      .cfg_enable_clip_i(mk_cfg_en_clip),
      .load_q_valid_i(mk_load_q_valid),
      .load_q_idx_i(mk_load_q_idx),
      .load_q_word_i(mk_load_q_word),
      .load_k_valid_i(mk_load_k_valid),
      .load_k_idx_i(mk_load_k_idx),
      .load_k_word_i(mk_load_k_word),
      .start_i(mk_start),
      .busy_o(mk_busy),
      .done_o(mk_done),
      .result_valid_o(mk_result_valid),
      .result_o(mk_result)
  );

      // Systolic array backend for MATMUL_CTRL grouped opcode.
      systolic_array #(
        .ROW_SIZE(SA_ROW_SIZE),
        .COL_SIZE(SA_COL_SIZE),
        .DATA_WIDTH(SA_DW),
        .ACC_WIDTH(SA_AW)
      ) i_systolic_array (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .weight_valid_i(sa_weight_valid),
        .weight_row_i(sa_weight_row),
        .weight_ready_o(sa_weight_ready),
        .activation_valid_i(sa_activation_valid),
        .activation_col_i(sa_activation_col),
        .activation_ready_o(sa_activation_ready),
        .result_valid_o(sa_result_valid),
        .result_row_o(sa_result_row),
        .result_ready_i(sa_result_ready),
        .load_weights_i(sa_load_weights),
        .execute_i(sa_execute),
        .clear_accumulators_i(sa_clear_accumulators),
        .done_o(sa_done)
      );

  // GELU8 ROM for NORM_ACT (GELU activation)
  gelu8_rom #(
    .ADDR_WIDTH(8),
    .DATA_WIDTH(8),
    .INIT_FILE("data/gelu8_lut.hex")
  ) i_gelu8_rom (
    .clk_i(clk_i),
    .addr_i(gelu_addr),
    .data_o(gelu_result)
  );

  // Microkernel control logic - handles multi-cycle operand staging
  typedef enum logic [1:0] {
    MK_IDLE,
    MK_STAGING,
    MK_EXECUTING
  } mk_state_t;
  
  mk_state_t mk_state_q, mk_state_d;
  logic signed [15:0] mk_latched_scale_q, mk_latched_scale_d;
  logic [3:0] mk_latched_shift_q, mk_latched_shift_d;
  logic mk_latched_en_scale_q, mk_latched_en_scale_d;
  logic mk_latched_en_clip_q, mk_latched_en_clip_d;
  
  always_comb begin
    mk_state_d = mk_state_q;
    mk_k_words_d = mk_k_words_q;
    mk_current_word_idx_d = mk_current_word_idx_q;
    mk_latched_k_d = mk_latched_k_q;
    mk_latched_scale_d = mk_latched_scale_q;
    mk_latched_shift_d = mk_latched_shift_q;
    mk_latched_en_scale_d = mk_latched_en_scale_q;
    mk_latched_en_clip_d = mk_latched_en_clip_q;
    mk_latched_clip_min_d = mk_latched_clip_min_q;
    mk_latched_clip_max_d = mk_latched_clip_max_q;

    mk_cfg_valid = 1'b0;
    mk_load_q_valid = 1'b0;
    mk_load_k_valid = 1'b0;
    mk_start = 1'b0;
    
      // Default: use latched configuration settings
      mk_cfg_en_scale = mk_latched_en_scale_q;
      mk_cfg_en_clip = mk_latched_en_clip_q;
      mk_cfg_scale = mk_latched_scale_q;
      mk_cfg_shift = mk_latched_shift_q;
      mk_cfg_k = mk_latched_k_q;
      mk_cfg_clip_min = mk_latched_clip_min_q;
      mk_cfg_clip_max = mk_latched_clip_max_q;
    
    case (mk_state_q)
      MK_IDLE: begin
        // Handle ATT_DOT_SETUP: configure engine
        if (issue_accept && opcode == ATT_DOT_SETUP) begin
          mk_cfg_valid = 1'b1;
          mk_cfg_k = registers[0][$clog2(MAX_K+1)-1:0];  // K from rs1[7:0]
          mk_cfg_shift = registers[0][11:8];              // shift from rs1[11:8]
          mk_cfg_scale = registers[1][15:0];              // scale from rs2[15:0]
          mk_cfg_clip_min = mk_latched_clip_min_q;          // Use latched values (defaults)
          mk_cfg_clip_max = mk_latched_clip_max_q;
          mk_cfg_en_scale = 1'b0;  // Setup doesn't enable post-ops (will be updated before execution)
          mk_cfg_en_clip = 1'b0;

          mk_latched_k_d = registers[0][$clog2(MAX_K+1)-1:0];
          mk_latched_scale_d = registers[1][15:0];
          mk_latched_shift_d = registers[0][11:8];
          mk_k_words_d = ((registers[0][$clog2(MAX_K+1)-1:0] + (WORD_ELEMS-1)) / WORD_ELEMS);
          mk_latched_clip_min_d = -32'sd32768;
          mk_latched_clip_max_d = 32'sd32767;
          mk_current_word_idx_d = '0;
          mk_state_d = MK_IDLE;  // Stay in IDLE, ready for staging
        end
        
        // Handle ATT_DOT_RUN*: start staging operands
        if (issue_accept && opcode inside {ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP}) begin
          mk_latched_en_scale_d = (opcode == ATT_DOT_RUN_SCALE || opcode == ATT_DOT_RUN_CLIP);
          mk_latched_en_clip_d = (opcode == ATT_DOT_RUN_CLIP);
          mk_cfg_en_scale = (opcode == ATT_DOT_RUN_SCALE || opcode == ATT_DOT_RUN_CLIP);
          mk_cfg_en_clip = (opcode == ATT_DOT_RUN_CLIP);
          
          // Stage first word pair
          mk_load_q_valid = 1'b1;
          mk_load_q_idx = '0;
          mk_load_q_word = registers[0];  // Q_word from rs1
          
          mk_load_k_valid = 1'b1;
          mk_load_k_idx = '0;
          mk_load_k_word = registers[1];  // K_word from rs2
          
          // Update engine config with scale/clip settings before execution
          mk_cfg_valid = 1'b1;  // Re-assert config to update scale/clip enables
          
          if (mk_k_words_q == 1) begin
            // Single word, execute immediately
            mk_start = 1'b1;
            mk_state_d = MK_EXECUTING;
            mk_current_word_idx_d = '0;
          end else begin
            // Multiple words, enter staging state
            mk_state_d = MK_STAGING;
            mk_current_word_idx_d = 1;  // Next word index
          end
        end
      end
      
      MK_STAGING: begin
        // Continue staging operands (one word pair per instruction)
        if (issue_accept && opcode inside {ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP}) begin
          mk_latched_en_scale_d = (opcode == ATT_DOT_RUN_SCALE || opcode == ATT_DOT_RUN_CLIP);
          mk_latched_en_clip_d = (opcode == ATT_DOT_RUN_CLIP);
          mk_cfg_en_scale = (opcode == ATT_DOT_RUN_SCALE || opcode == ATT_DOT_RUN_CLIP);
          mk_cfg_en_clip = (opcode == ATT_DOT_RUN_CLIP);
          
          // Stage current word pair
          mk_load_q_valid = 1'b1;
          mk_load_q_idx = mk_current_word_idx_q;
          mk_load_q_word = registers[0];  // Q_word from rs1
          
          mk_load_k_valid = 1'b1;
          mk_load_k_idx = mk_current_word_idx_q;
          mk_load_k_word = registers[1];  // K_word from rs2
          
          if (mk_current_word_idx_q == (mk_k_words_q - 1)) begin
            // All words staged, update config and trigger execution
            mk_cfg_valid = 1'b1;  // Re-assert config to update scale/clip enables
            mk_start = 1'b1;
            mk_state_d = MK_EXECUTING;
            mk_current_word_idx_d = '0;
          end else begin
            // More words to stage, increment index
            mk_current_word_idx_d = mk_current_word_idx_q + 1'b1;
            mk_state_d = MK_STAGING;
          end
        end
      end
      
      MK_EXECUTING: begin
        // Wait for execution to complete
        mk_cfg_en_scale = mk_latched_en_scale_q;
        mk_cfg_en_clip = mk_latched_en_clip_q;
        
        if (mk_done && mk_result_valid) begin
          // Execution complete, return to IDLE
          mk_state_d = MK_IDLE;
          mk_current_word_idx_d = '0;
        end
      end
      
      default: begin
        mk_state_d = MK_IDLE;
      end
    endcase
  end
  
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mk_state_q <= MK_IDLE;
      mk_k_words_q <= '0;
      mk_current_word_idx_q <= '0;
      mk_latched_k_q <= '0;
      mk_latched_scale_q <= '0;
      mk_latched_shift_q <= '0;
      mk_latched_en_scale_q <= 1'b0;
      mk_latched_en_clip_q <= 1'b0;
      mk_latched_clip_min_q <= -32'sd32768;
      mk_latched_clip_max_q <= 32'sd32767;
      mk_resp_pending_q <= 1'b0;
      mk_resp_hartid_q <= '0;
      mk_resp_id_q <= '0;
      mk_resp_rd_q <= '0;
    end else begin
      mk_state_q <= mk_state_d;
      mk_k_words_q <= mk_k_words_d;
      mk_current_word_idx_q <= mk_current_word_idx_d;
      mk_latched_k_q <= mk_latched_k_d;
      mk_latched_scale_q <= mk_latched_scale_d;
      mk_latched_shift_q <= mk_latched_shift_d;
      mk_latched_en_scale_q <= mk_latched_en_scale_d;
      mk_latched_en_clip_q <= mk_latched_en_clip_d;
      mk_latched_clip_min_q <= mk_latched_clip_min_d;
      mk_latched_clip_max_q <= mk_latched_clip_max_d;
      mk_resp_pending_q <= mk_resp_pending_d;
      mk_resp_hartid_q <= mk_resp_hartid_d;
      mk_resp_id_q <= mk_resp_id_d;
      mk_resp_rd_q <= mk_resp_rd_d;
    end
  end

  always_comb begin
    mk_resp_pending_d = mk_resp_pending_q;
    mk_resp_hartid_d = mk_resp_hartid_q;
    mk_resp_id_d = mk_resp_id_q;
    mk_resp_rd_d = mk_resp_rd_q;

    // Latch response metadata when execution is kicked.
    if (issue_accept && opcode inside {ATT_DOT_RUN, ATT_DOT_RUN_SCALE, ATT_DOT_RUN_CLIP}) begin
      if ((mk_state_q == MK_IDLE && (mk_k_words_q == 1)) ||
          (mk_state_q == MK_STAGING && (mk_current_word_idx_q == (mk_k_words_q - 1)))) begin
        mk_resp_pending_d = 1'b1;
        mk_resp_hartid_d = issue_hartid;
        mk_resp_id_d = issue_id;
        mk_resp_rd_d = issue_rd;
      end
    end

    // Clear pending marker once result is produced.
    if (mk_result_valid) begin
      mk_resp_pending_d = 1'b0;
    end
  end

  // MATMUL control path (grouped opcode with funct3 sub-ops)
  always_comb begin
    for (int i = 0; i < SA_COL_SIZE; i++) begin
      // Systolic backend only accepts a new activation when input changes.
      // Add stream index to each lane so successive MM_RUN beats are consumed.
      mm_activation_col[i*SA_DW +: SA_DW] = mm_stream_payload_q[i*SA_DW +: SA_DW] + mm_stream_idx_q;
    end

    mm_state_d = mm_state_q;
    mm_stream_idx_d = mm_stream_idx_q;
    mm_stream_payload_d = mm_stream_payload_q;
    mm_result_data_d = mm_result_data_q;
    mm_result_we_d = mm_result_we_q;
    mm_resp_hartid_d = mm_resp_hartid_q;
    mm_resp_id_d = mm_resp_id_q;
    mm_resp_rd_d = mm_resp_rd_q;
    sa_result_row_d = sa_result_row_q;

    sa_weight_valid = 1'b0;
    sa_weight_row = '0;
    sa_activation_valid = 1'b0;
    sa_activation_col = '0;
    sa_load_weights = 1'b0;
    sa_execute = 1'b0;
    sa_clear_accumulators = 1'b0;

    // Keep latest systolic result row for MM_DRAIN reads.
    if (sa_result_valid) begin
      sa_result_row_d = sa_result_row;
    end

    case (mm_state_q)
      MM_IDLE: begin
        if (issue_accept && use_matmul_ctrl) begin
          mm_resp_hartid_d = issue_hartid;
          mm_resp_id_d = issue_id;
          mm_resp_rd_d = issue_rd;

          unique case (matmul_subop)
            MM_RESET: begin
              sa_clear_accumulators = 1'b1;
              mm_result_data_d = 32'h0000_0000;
              mm_result_we_d = 1'b0;
              mm_state_d = MM_RESP;
            end

            MM_LOAD_W: begin
              mm_stream_payload_d = {2{registers[0]}};
              mm_stream_idx_d = '0;
              mm_result_data_d = 32'h0000_0000;
              mm_result_we_d = 1'b0;
              mm_state_d = MM_LOAD_W_STREAM;
            end

            MM_LOAD_A: begin
              mm_stream_payload_d = {2{registers[0]}};
              mm_stream_idx_d = '0;
              mm_result_data_d = 32'h0000_0000;
              mm_result_we_d = 1'b0;
              mm_state_d = MM_RESP;
            end

            MM_RUN: begin
              // MM_RUN is the explicit compute trigger.
              mm_stream_payload_d = {2{registers[0]}};
              mm_stream_idx_d = '0;
              mm_result_data_d = 32'h0000_0000;
              mm_result_we_d = 1'b0;
              mm_state_d = MM_LOAD_A_STREAM;
            end

            MM_DRAIN: begin
              // Return the first element from packed result row as scalar status/output.
              mm_result_data_d = sa_result_row_q[31:0];
              mm_result_we_d = 1'b1;
              mm_state_d = MM_RESP;
            end

            default: begin
              mm_result_data_d = 32'h0000_0000;
              mm_result_we_d = 1'b0;
              mm_state_d = MM_RESP;
            end
          endcase
        end
      end

      MM_LOAD_W_STREAM: begin
        sa_load_weights = 1'b1;
        sa_weight_valid = 1'b1;
        sa_weight_row = mm_stream_payload_q;

        if (sa_weight_ready) begin
          if (mm_stream_idx_q == (SA_ROW_SIZE - 1)) begin
            mm_state_d = MM_RESP;
          end else begin
            mm_stream_idx_d = mm_stream_idx_q + 1'b1;
          end
        end
      end

      MM_LOAD_A_STREAM: begin
        sa_execute = 1'b1;
        sa_activation_valid = 1'b1;
        sa_activation_col = mm_activation_col;

        if (sa_activation_ready) begin
          if (mm_stream_idx_q == (SA_COL_SIZE - 1)) begin
            mm_state_d = MM_WAIT_DONE;
          end else begin
            mm_stream_idx_d = mm_stream_idx_q + 1'b1;
          end
        end
      end

      MM_WAIT_DONE: begin
        if (sa_done) begin
          mm_state_d = MM_RESP;
        end
      end

      MM_RESP: begin
        // One-cycle completion response.
        mm_state_d = MM_IDLE;
      end

      default: begin
        mm_state_d = MM_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mm_state_q <= MM_IDLE;
      mm_stream_idx_q <= '0;
      mm_stream_payload_q <= '0;
      mm_result_data_q <= '0;
      mm_result_we_q <= 1'b0;
      mm_resp_hartid_q <= '0;
      mm_resp_id_q <= '0;
      mm_resp_rd_q <= '0;
      sa_result_row_q <= '0;
    end else begin
      mm_state_q <= mm_state_d;
      mm_stream_idx_q <= mm_stream_idx_d;
      mm_stream_payload_q <= mm_stream_payload_d;
      mm_result_data_q <= mm_result_data_d;
      mm_result_we_q <= mm_result_we_d;
      mm_resp_hartid_q <= mm_resp_hartid_d;
      mm_resp_id_q <= mm_resp_id_d;
      mm_resp_rd_q <= mm_resp_rd_d;
      sa_result_row_q <= sa_result_row_d;
    end
  end

  // NORM_ACT control path (GELU8 / LayerNorm8)
  always_comb begin
    na_state_d = na_state_q;
    na_compute_cycles_d = na_compute_cycles_q;
    na_input_data_d = na_input_data_q;
    na_param_data_d = na_param_data_q;
    na_result_data_d = na_result_data_q;
    na_result_we_d = na_result_we_q;
    na_result_valid_d = 1'b0;  // Default: clear result_valid each cycle
    na_subop_d = na_subop_q;
    na_resp_hartid_d = na_resp_hartid_q;
    na_resp_id_d = na_resp_id_q;
    na_resp_rd_d = na_resp_rd_q;

    case (na_state_q)
      NA_IDLE: begin
        if (issue_accept && use_norm_act) begin
          na_resp_hartid_d = issue_hartid;
          na_resp_id_d = issue_id;
          na_resp_rd_d = issue_rd;
          na_input_data_d = registers[0];
          na_param_data_d = registers[1];
          na_subop_d = norm_subop;
          na_result_we_d = 1'b1;  // All NORM_ACT ops writeback

          // Fixed 5-cycle latency for both GELU8 and LayerNorm8
          na_compute_cycles_d = 4;  // 4 cycles of compute
          na_state_d = NA_COMPUTE;
        end
      end

      NA_COMPUTE: begin
        // Countdown compute cycles
        if (na_compute_cycles_q == 0) begin
          unique case (na_subop_q)
            NA_GELU8:  na_result_data_d = {24'h0, gelu_result};
            NA_LNORM8: na_result_data_d = lnorm8_4lane(na_input_data_q, na_param_data_q);
            default:   na_result_data_d = 32'h0;
          endcase
          na_state_d = NA_RESP;
          na_result_valid_d = 1'b1;  // Result ready in next cycle
        end else begin
          na_compute_cycles_d = na_compute_cycles_q - 1;
        end
      end

      NA_RESP: begin
        // Hold response for testbench to read, then return to idle
        na_result_valid_d = 1'b1;  // Keep result valid while in RESP state
        na_state_d = NA_IDLE;
      end

      default: begin
        na_state_d = NA_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      na_state_q <= NA_IDLE;
      na_compute_cycles_q <= '0;
      na_input_data_q <= '0;
      na_param_data_q <= '0;
      na_result_data_q <= '0;
      na_result_we_q <= 1'b0;
      na_result_valid_q <= 1'b0;
      na_subop_q <= NA_GELU8;
      na_resp_hartid_q <= '0;
      na_resp_id_q <= '0;
      na_resp_rd_q <= '0;
    end else begin
      na_state_q <= na_state_d;
      na_compute_cycles_q <= na_compute_cycles_d;
      na_input_data_q <= na_input_data_d;
      na_param_data_q <= na_param_data_d;
      na_result_data_q <= na_result_data_d;
      na_result_we_q <= na_result_we_d;
      na_result_valid_q <= na_result_valid_d;
      na_subop_q <= na_subop_d;
      na_resp_hartid_q <= na_resp_hartid_d;
      na_resp_id_q <= na_resp_id_d;
      na_resp_rd_q <= na_resp_rd_d;
    end
  end

  // Result mux: select between regular MAC unit and microkernel engine
  always_comb begin
    if (mm_state_q == MM_RESP) begin
      cvxif_resp_o.result_valid = 1'b1;
      cvxif_resp_o.result.hartid = mm_resp_hartid_q;
      cvxif_resp_o.result.id = mm_resp_id_q;
      cvxif_resp_o.result.data = mm_result_data_q;
      cvxif_resp_o.result.rd = mm_resp_rd_q;
      cvxif_resp_o.result.we = mm_result_we_q;
    end else if (na_result_valid_q) begin
      cvxif_resp_o.result_valid = 1'b1;
      cvxif_resp_o.result.hartid = na_resp_hartid_q;
      cvxif_resp_o.result.id = na_resp_id_q;
      cvxif_resp_o.result.data = na_result_data_q;
      cvxif_resp_o.result.rd = na_resp_rd_q;
      cvxif_resp_o.result.we = na_result_we_q;
    end else if (mk_result_valid) begin
      cvxif_resp_o.result_valid = mk_result_valid;
      cvxif_resp_o.result.hartid = mk_resp_hartid_q;
      cvxif_resp_o.result.id = mk_resp_id_q;
      cvxif_resp_o.result.data = mk_result;
      cvxif_resp_o.result.rd = mk_resp_rd_q;
      cvxif_resp_o.result.we = 1'b1;
    end else begin
      cvxif_resp_o.result_valid  = result_valid && !use_microkernel;
      cvxif_resp_o.result.hartid = hartid;
      cvxif_resp_o.result.id     = id;
      cvxif_resp_o.result.data   = result;
      cvxif_resp_o.result.rd     = rd;
      cvxif_resp_o.result.we     = we && !use_microkernel;
    end
    // Note: overflow flag not part of standard CVXIF result
    // Could be exposed via custom CSR or debug interface in future
  end
  
  // Assertions for top-level verification
  `ifndef SYNTHESIS
  // Check CVXIF protocol compliance
  property p_issue_accept_implies_ready;
    @(posedge clk_i) disable iff (!rst_ni)
    (issue_resp.accept |-> issue_ready);
  endproperty
  assert property (p_issue_accept_implies_ready) 
    else $error("Accepted instruction but not ready");
  
  // Coverage: Track overflow events for debug
  cover property (@(posedge clk_i) overflow);
  `endif

endmodule
