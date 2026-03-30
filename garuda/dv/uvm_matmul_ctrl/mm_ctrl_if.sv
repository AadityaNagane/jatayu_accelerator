// UVM Interface for matmul control (decoder/FSM)

interface mm_ctrl_if (
  input logic clk,
  input logic rst_n
);

  logic [31:0] instr;
  logic instr_valid;
  logic instr_ready;
  
  logic [7:0] m, n, k;
  logic [2:0] opcode;
  logic decode_valid;
  logic decode_error;

endinterface : mm_ctrl_if
