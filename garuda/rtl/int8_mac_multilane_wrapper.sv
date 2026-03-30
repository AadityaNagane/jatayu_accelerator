// Multi-Lane MAC Unit Wrapper for CVXIF Integration
// Handles the interface between CVXIF (32-bit registers) and multi-lane unit (wide buses)
// Implements register accumulation to build wide operands from multiple instructions

module int8_mac_multilane_wrapper
  import int8_mac_instr_pkg::*;
#(
    parameter int unsigned XLEN        = 32,
    parameter int unsigned NUM_LANES   = 16,  // Number of parallel MAC lanes
    parameter int unsigned LANE_WIDTH  = 32,  // Width per lane
    parameter type         opcode_t    = logic [3:0],
    parameter type         hartid_t    = logic [31:0],
    parameter type         id_t        = logic [31:0]
) (
    input  logic                         clk_i,
    input  logic                         rst_ni,
    
    // CVXIF-style interface (standard 32-bit operands)
    // For multi-lane operations, multiple register loads accumulate into wide buses
    input  logic [XLEN-1:0]              rs1_i,  // 32-bit register value
    input  logic [XLEN-1:0]              rs2_i,  // 32-bit register value
    input  logic [XLEN-1:0]              rd_i,   // 32-bit accumulator
    input  opcode_t                      opcode_i,
    input  hartid_t                      hartid_i,
    input  id_t                          id_i,
    input  logic [4:0]                   rd_addr_i,
    input  logic                         valid_i,  // New instruction valid
    
    // Multi-lane accumulator control
    input  logic [3:0]                   lane_idx_i,  // Which lane (0 to NUM_LANES-1) this instruction fills
    input  logic                         lane_load_i,  // Load new data into accumulator
    input  logic                         lane_exec_i,  // Execute multi-lane operation
    
    output logic [XLEN-1:0]              result_o,
    output logic                         valid_o,
    output logic                         we_o,
    output logic [4:0]                   rd_addr_o,
    output hartid_t                      hartid_o,
    output id_t                          id_o,
    output logic                         overflow_o
);

  // Internal accumulators for wide operands
  logic [NUM_LANES*LANE_WIDTH-1:0] rs1_acc, rs2_acc;
  logic [NUM_LANES-1:0]            lane_valid;  // Which lanes have valid data
  
  // Control signals
  logic                             exec_request;
  logic                             exec_pending;
  logic                             exec_uses_lanes;
  logic                             exec_done;
  logic                             use_accumulated_simd;
  logic [NUM_LANES*LANE_WIDTH-1:0] rs1_wide, rs2_wide;
  
  // Multi-lane unit interface
  logic [XLEN-1:0]                  ml_result;
  logic                             ml_valid;
  logic                             ml_we;
  logic [4:0]                       ml_rd_addr;
  hartid_t                          ml_hartid;
  id_t                              ml_id;
  logic                             ml_overflow;

  // Accumulate register inputs into wide buses
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rs1_acc <= '0;
      rs2_acc <= '0;
      lane_valid <= '0;
    end else begin
      if (exec_done && exec_uses_lanes) begin
        lane_valid <= '0;  // Clear after a completed multi-lane SIMD execution.
      end

      if (valid_i && lane_load_i) begin
        // Load data into specified lane
        if (lane_idx_i < NUM_LANES) begin
          rs1_acc[lane_idx_i*LANE_WIDTH +: LANE_WIDTH] <= rs1_i;
          rs2_acc[lane_idx_i*LANE_WIDTH +: LANE_WIDTH] <= rs2_i;
          lane_valid[lane_idx_i] <= 1'b1;
        end
      end
    end
  end

  assign use_accumulated_simd = (opcode_i == SIMD_DOT) && (lane_valid != '0);
  assign exec_request = valid_i && lane_exec_i;
  assign exec_done = exec_pending && ml_valid && ml_we;

  // Track outstanding execute request until the core produces a valid response.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      exec_pending <= 1'b0;
      exec_uses_lanes <= 1'b0;
    end else begin
      if (exec_done) begin
        exec_pending <= 1'b0;
      end

      if (exec_request) begin
        exec_pending <= 1'b1;
        exec_uses_lanes <= use_accumulated_simd;
      end
    end
  end
  
  // For non-SIMD_DOT operations, use standard 32-bit path
  // For SIMD_DOT, use accumulated lanes when available, otherwise fall back to lane0 direct input.
  assign rs1_wide = use_accumulated_simd ? rs1_acc : {{(NUM_LANES-1)*LANE_WIDTH{1'b0}}, rs1_i};
  assign rs2_wide = use_accumulated_simd ? rs2_acc : {{(NUM_LANES-1)*LANE_WIDTH{1'b0}}, rs2_i};
  
  // Instantiate multi-lane unit
  int8_mac_multilane_unit #(
      .XLEN(XLEN),
      .NUM_LANES(NUM_LANES),
      .LANE_WIDTH(LANE_WIDTH),
      .opcode_t(opcode_t),
      .hartid_t(hartid_t),
      .id_t(id_t)
  ) i_multilane_unit (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .rs1_i(rs1_wide),
      .rs2_i(rs2_wide),
      .rd_i(rd_i),
      .opcode_i(opcode_i),
      .hartid_i(hartid_i),
      .id_i(id_i),
      .rd_addr_i(rd_addr_i),
      .result_o(ml_result),
      .valid_o(ml_valid),
      .we_o(ml_we),
      .rd_addr_o(ml_rd_addr),
      .hartid_o(ml_hartid),
      .id_o(ml_id),
      .overflow_o(ml_overflow)
  );
  
  assign result_o   = exec_done ? ml_result : '0;
  assign valid_o    = exec_done;
  assign we_o       = exec_done;
  assign rd_addr_o  = ml_rd_addr;
  assign hartid_o   = ml_hartid;
  assign id_o       = ml_id;
  assign overflow_o = ml_overflow;

endmodule
