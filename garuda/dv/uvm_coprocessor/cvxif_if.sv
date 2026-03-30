// UVM Interface for INT8 MAC coprocessor (simplified CVXIF)

interface cvxif_if (
  input logic clk,
  input logic rst_n
);

  // Simplified CVXIF interface
  logic issue_valid;
  logic issue_ready;
  logic [31:0] issue_instr;
  logic [4:0] issue_rd;
  
  logic result_valid;
  logic [31:0] result;
  
  logic busy;

endinterface : cvxif_if
