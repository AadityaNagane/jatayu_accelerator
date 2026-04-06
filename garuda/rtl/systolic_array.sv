// 2D Systolic Array - Matrix multiply optimized architecture
// Clean rewrite with proper state machine

module systolic_array #(
    parameter int unsigned ROW_SIZE      = 8,
    parameter int unsigned COL_SIZE      = 8,
    parameter int unsigned DATA_WIDTH    = 8,
    parameter int unsigned ACC_WIDTH     = 32,
    parameter int unsigned WEIGHT_BUF_DEPTH = 256
) (
    input  logic                        clk_i,
    input  logic                        rst_ni,
    
    input  logic                        weight_valid_i,
    input  logic [ROW_SIZE*DATA_WIDTH-1:0] weight_row_i,
    output logic                        weight_ready_o,
    
    input  logic                        activation_valid_i,
    input  logic [COL_SIZE*DATA_WIDTH-1:0] activation_col_i,
    output logic                        activation_ready_o,
    
    output logic                        result_valid_o,
    output logic [ROW_SIZE*ACC_WIDTH-1:0] result_row_o,
    input  logic                        result_ready_i,
    
    input  logic                        load_weights_i,
    input  logic                        execute_i,
    input  logic                        clear_accumulators_i,
    output logic                        done_o
);

  localparam int unsigned DW  = DATA_WIDTH;
  localparam int unsigned AW  = ACC_WIDTH;
  localparam int unsigned COMPUTE_LATENCY = (COL_SIZE + ROW_SIZE);

  // Stored matrices
  logic signed [DW-1:0] weights_a [0:ROW_SIZE-1][0:COL_SIZE-1];
  logic signed [DW-1:0] acts_b    [0:COL_SIZE-1][0:ROW_SIZE-1];
  logic signed [AW-1:0] result_col0_q [0:ROW_SIZE-1];
  logic signed [AW-1:0] acc_tmp_computed [0:ROW_SIZE-1];

  // State machine states
  typedef enum logic [2:0] {
    IDLE,
    LOAD_WEIGHTS,
    LOAD_ACTIVATIONS,
    COMPUTE,
    OUTPUT_RESULTS
  } systolic_state_t;

  systolic_state_t state_q;
  logic [7:0] load_row_count_q, load_col_count_q;
  logic [7:0] compute_count_q;
  logic result_valid_q;

  // No need for separate _d (next-state) variables anymore - computed in always_ff

// Remove combinational state machine - we'll compute state_d directly in sequential block
  // This avoids Verilator's timing issues with always_comb/@(*)

  // Simple registered outputs (combinational based on current state_q)
  always @(*) begin
    weight_ready_o = (state_q == LOAD_WEIGHTS) ? 1'b1 : 1'b0;
    activation_ready_o = (state_q == LOAD_ACTIVATIONS) ? 1'b1 : 1'b0;
    result_valid_o = result_valid_q;
    done_o = (state_q == OUTPUT_RESULTS && result_ready_i) ? 1'b1 : 1'b0;
  end

  // Combinational result packing
  always_comb begin
    result_row_o = '0;
    for (int r = 0; r < ROW_SIZE; r++) begin
      result_row_o[r*AW +: AW] = result_col0_q[r];
    end
  end

  // Combinational computation of results
  always_comb begin
    for (int r = 0; r < ROW_SIZE; r++) begin
      acc_tmp_computed[r] = 32'sd0;
      for (int k = 0; k < COL_SIZE; k++) begin
        acc_tmp_computed[r] = acc_tmp_computed[r] + ($signed(weights_a[r][k]) * $signed(acts_b[k][0]));
      end
    end
  end

  // UNIFIED SEQUENTIAL BLOCK - state machine + data path + output logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    // Debug: print on every clock
    static int clock_count = 0;
    clock_count++;
    if ($realtime >= 340us && $realtime <= 500us) begin
      $display("[CLK cnt=%0d t=%0t] state=%p row=%0d col=%0d weight_valid=%b act_valid=%b act_ready=%b", 
               clock_count, $realtime, state_q, load_row_count_q, load_col_count_q, 
               weight_valid_i, activation_valid_i, activation_ready_o);
    end
    
    if (!rst_ni) begin
      clock_count = 1;
      state_q <= IDLE;
      load_row_count_q <= 8'd0;
      load_col_count_q <= 8'd0;
      compute_count_q <= 8'd0;
      result_valid_q <= 1'b0;

      for (int r = 0; r < ROW_SIZE; r++) begin
        result_col0_q[r] <= 32'd0;
        for (int k = 0; k < COL_SIZE; k++) begin
          weights_a[r][k] <= 8'sb0;
        end
      end
      for (int k = 0; k < COL_SIZE; k++) begin
        for (int c = 0; c < ROW_SIZE; c++) begin
          acts_b[k][c] <= 8'sb0;
        end
      end
    end else begin
      // STATE MACHINE LOGIC - DIRECTLY IN SEQUENTIAL BLOCK
      case (state_q)
        IDLE: begin
          if (load_weights_i || weight_valid_i) begin
            $display("[STATE] IDLE: weight trigger -> LOAD_WEIGHTS");
            state_q <= LOAD_WEIGHTS;
            load_row_count_q <= 8'd0;
            result_valid_q <= 1'b0;
          end else if (execute_i || activation_valid_i) begin
            $display("[STATE @ %0t] IDLE: activation trigger -> LOAD_ACTIVATIONS", $realtime);
            state_q <= LOAD_ACTIVATIONS;
            load_col_count_q <= 8'd0;
            result_valid_q <= 1'b0;
          end
        end

        LOAD_WEIGHTS: begin
          if ($realtime >= 240000) begin  // Show debug from 240000 onward
            $display("[LOAD_WEIGHTS @ %0t] weight_valid_i=%b, load_row_q=%0d", 
                     $realtime, weight_valid_i, load_row_count_q);
          end
          if (weight_valid_i) begin  // weight_ready_o is 1 in this state
            // Capture weight data FIRST (to use current load_row_count_q)
            for (int k = 0; k < COL_SIZE; k++) begin
              weights_a[load_row_count_q][k] <= $signed(weight_row_i[k*DW +: DW]);
            end
            
            // THEN check if this was the last row
            if (load_row_count_q == (ROW_SIZE - 1)) begin
              $display("[SEQ @ %0t] LOAD_WEIGHTS: row=%0d == %0d (LAST), transitioning to IDLE", $realtime, load_row_count_q, ROW_SIZE-1);
              state_q <= IDLE;
              load_row_count_q <= 8'd0;
            end else begin
              $display("[SEQ @ %0t] LOAD_WEIGHTS: row=%0d < %0d (NOT LAST), incrementing", $realtime, load_row_count_q, ROW_SIZE-1);
              load_row_count_q <= load_row_count_q + 1;
            end
          end
        end

        LOAD_ACTIVATIONS: begin
          if (activation_valid_i) begin  // activation_ready_o is 1 in this state
            $display("[SEQ @ %0t] LOAD_ACTIVATIONS: col=%0d, activation_valid_i=%b, checking == %0d?", 
                     $realtime, load_col_count_q, activation_valid_i, COL_SIZE-1);
            if (load_col_count_q == (COL_SIZE - 1)) begin
              $display("[STATE @ %0t] LOAD_ACT: LAST! col=%0d -> COMPUTE", $realtime, load_col_count_q);
              state_q <= COMPUTE;
              load_col_count_q <= 8'd0;
              compute_count_q <= 8'd0;
            end else begin
              $display("[STATE @ %0t] LOAD_ACT: col=%0d (not last), incrementing", $realtime, load_col_count_q);
              load_col_count_q <= load_col_count_q + 1;
            end
            // Capture activation data
            for (int k = 0; k < COL_SIZE; k++) begin
              acts_b[k][load_col_count_q] <= $signed(activation_col_i[k*DW +: DW]);
            end
          end
        end

        COMPUTE: begin
          compute_count_q <= compute_count_q + 1;
          if (compute_count_q == (COMPUTE_LATENCY - 1)) begin
            $display("[STATE @ %0t] COMPUTE DONE: %0d -> OUTPUT_RESULTS", $realtime, compute_count_q);
            state_q <= OUTPUT_RESULTS;
            result_valid_q <= 1'b1;
            // Capture computed results
            for (int r = 0; r < ROW_SIZE; r++) begin
              result_col0_q[r] <= acc_tmp_computed[r];
            end
          end
        end

        OUTPUT_RESULTS: begin
          if (result_ready_i) begin
            state_q <= IDLE;
            result_valid_q <= 1'b0;
          end
        end

        default:
          state_q <= IDLE;
      endcase

      // Handle clear accumulators (can happen in any state)
      if (clear_accumulators_i) begin
        for (int r = 0; r < ROW_SIZE; r++) begin
          result_col0_q[r] <= 32'd0;
        end
        result_valid_q <= 1'b0;
      end
    end
  end

endmodule
