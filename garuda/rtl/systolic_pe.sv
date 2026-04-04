// Systolic Processing Element (PE) - Basic building block for systolic array
// Phase 4.1 Enhancement: 2D Systolic Array (FIXED v2.1)
// Single PE with pipelined MAC operation and data flow
//
// ARCHITECTURE:
// - Weight is stored in weight_reg (loaded via weight_load_i)
// - Activation and partial-sum flow through (pass-through to neighbors)
// - Single MAC per clock cycle (multiply stored weight × current activation + partial sum)
// - Registered accumulator output (proper pipelining)

module systolic_pe #(
    parameter int unsigned DATA_WIDTH = 8,    // INT8 data width
    parameter int unsigned ACC_WIDTH  = 32,   // Accumulator width
    parameter int unsigned PE_ID      = 0     // PE identifier (for debugging)
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    // Data flow: systolic inputs/outputs
    input  logic [DATA_WIDTH-1:0]       weight_i,        // Weight from north (row)
    input  logic [DATA_WIDTH-1:0]       activation_i,    // Activation from west (column)
    input  logic [ACC_WIDTH-1:0]        partial_sum_i,   // Partial sum from west
    output logic [DATA_WIDTH-1:0]       weight_o,        // Pass weight to south
    output logic [DATA_WIDTH-1:0]       activation_o,    // Pass activation to east
    output logic [ACC_WIDTH-1:0]        partial_sum_o,   // Pass partial sum to east
    
    // Control
    input  logic                        weight_load_i,   // Load weight into PE
    input  logic                        accumulate_en_i, // Enable accumulation
    input  logic                        clear_acc_i      // Clear accumulator
);

  // =========================================================================
  // Internal State
  // =========================================================================
  logic [DATA_WIDTH-1:0] weight_reg_q, weight_reg_d;
  logic [ACC_WIDTH-1:0]  accumulator_q, accumulator_d;
  
  // =========================================================================
  // Multiply-AccumulateOperation (Combinational)
  // =========================================================================
  // Compute product of stored weight × current activation
  logic [2*DATA_WIDTH-1:0] product;
  assign product = $signed(weight_reg_q) * $signed(activation_i);
  
  // Combinational accumulator update logic
  always_comb begin
    accumulator_d = accumulator_q;
    
    if (accumulate_en_i) begin
      // MAC: new_accumulator = old_accumulator + (weight × activation) + partial_sum
      accumulator_d = accumulator_q + $signed(product) + $signed(partial_sum_i);
    end
  end
  
  // Weight register update logic
  always_comb begin
    weight_reg_d = weight_reg_q;
    
    if (weight_load_i) begin
      weight_reg_d = weight_i;  // Load new weight
    end
  end
  
  // =========================================================================
  // Data Pass-Through (Systolic Flow)
  // =========================================================================
  // Pass data to neighboring PEs (combinational, no delay)
 assign weight_o = weight_i;            // Pass weight to south
  assign activation_o = activation_i;    // Pass activation to east
  assign partial_sum_o = accumulator_q;  // Output accumulated partial sum to east
  
  // =========================================================================
  // Sequential Logic: Update Registers on Clock
  // =========================================================================
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      weight_reg_q <= '0;
      accumulator_q <= '0;
    end else begin
      weight_reg_q <= weight_reg_d;
      
      if (clear_acc_i) begin
        accumulator_q <= '0;
      end else begin
        accumulator_q <= accumulator_d;
      end
    end
  end

endmodule
