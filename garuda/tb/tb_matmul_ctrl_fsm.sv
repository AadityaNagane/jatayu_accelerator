`timescale 1ns / 1ps

module tb_matmul_ctrl_fsm;
  import int8_mac_instr_pkg::*;

  localparam int unsigned XLEN = 32;

  typedef logic [XLEN-1:0] cvxif_reg_t;
  typedef logic [4:0] cvxif_rd_t;
  typedef logic [1:0] cvxif_hartid_t;
  typedef logic [4:0] cvxif_id_t;

  typedef struct packed {
    logic [XLEN-1:0] instr;
    cvxif_hartid_t hartid;
    cvxif_id_t id;
  } cvxif_issue_req_t;

  typedef struct packed {
    logic accept;
    logic writeback;
    logic [2:0] register_read;
  } cvxif_issue_resp_t;

  typedef struct packed {
    logic [1:0] rs_valid;
    logic [1:0][XLEN-1:0] rs;
  } cvxif_register_t;

  typedef struct packed {
    cvxif_hartid_t hartid;
    cvxif_id_t id;
    logic [31:0] data;
    cvxif_rd_t rd;
    logic we;
  } cvxif_result_t;

  typedef struct packed {
    cvxif_issue_resp_t issue_resp;
    logic issue_ready;
    logic compressed_ready;
    logic [XLEN-1:0] compressed_resp;
    cvxif_result_t result;
    logic result_valid;
    logic register_ready;
  } cvxif_resp_t;

  typedef struct packed {
    cvxif_issue_req_t issue_req;
    logic issue_valid;
    cvxif_register_t register;
    logic register_valid;
    logic compressed_valid;
    logic [15:0] compressed_req;
  } cvxif_req_t;

  logic clk, rst_n;
  cvxif_req_t  cvxif_req;
  cvxif_resp_t cvxif_resp;

  int test_count, pass_count, fail_count;

  function automatic logic [31:0] mk_matmul_instr(input logic [2:0] funct3, input logic [4:0] rd);
    mk_matmul_instr = {7'b0001011, 5'd0, 5'd0, funct3, rd, 7'b1111011};
  endfunction

  task automatic check(input string name, input bit cond);
    test_count++;
    if (cond) begin
      pass_count++;
      $display("[PASS] %s", name);
    end else begin
      fail_count++;
      $display("[FAIL] %s", name);
    end
  endtask

  task automatic issue_one(
    input logic [31:0] instr,
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    input cvxif_hartid_t hartid,
    input cvxif_id_t id
  );
    cvxif_req.issue_req.instr  = instr;
    cvxif_req.issue_req.hartid = hartid;
    cvxif_req.issue_req.id     = id;
    cvxif_req.issue_valid      = 1'b1;
    cvxif_req.register_valid   = 1'b1;
    cvxif_req.register.rs_valid[0] = 1'b1;
    cvxif_req.register.rs_valid[1] = 1'b1;
    cvxif_req.register.rs[0] = rs1;
    cvxif_req.register.rs[1] = rs2;

    @(posedge clk);
    while (!cvxif_resp.issue_ready) @(posedge clk);

    @(posedge clk);
    cvxif_req.issue_valid    = 1'b0;
    cvxif_req.register_valid = 1'b0;
  endtask

  task automatic wait_result(output cvxif_result_t r);
    while (!cvxif_resp.result_valid) @(posedge clk);
    r = cvxif_resp.result;
    @(posedge clk);
  endtask

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    #50;
    rst_n = 1'b1;
  end

  int ready_low_cycles;
  cvxif_result_t r;

  int8_mac_coprocessor #(
    .NrRgprPorts(2),
    .XLEN(XLEN),
    .readregflags_t(logic),
    .writeregflags_t(logic),
    .id_t(cvxif_id_t),
    .hartid_t(cvxif_hartid_t),
    .x_compressed_req_t(logic [15:0]),
    .x_compressed_resp_t(logic [XLEN-1:0]),
    .x_issue_req_t(cvxif_issue_req_t),
    .x_issue_resp_t(cvxif_issue_resp_t),
    .x_register_t(cvxif_register_t),
    .x_commit_t(logic),
    .x_result_t(cvxif_result_t),
    .cvxif_req_t(cvxif_req_t),
    .cvxif_resp_t(cvxif_resp_t)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .cvxif_req_i(cvxif_req),
    .cvxif_resp_o(cvxif_resp)
  );

  initial begin
    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    cvxif_req = '0;

    @(posedge rst_n);
    @(posedge clk);

    $display("========================================");
    $display("MATMUL_CTRL FSM + Tagging TB");
    $display("========================================");

    // MM_LOAD_W should enter busy streaming path.
    issue_one(mk_matmul_instr(3'b001, 5'd7), 32'h0102_0304, 32'h0, 2'd1, 5'd9);

    ready_low_cycles = 0;
    repeat (6) begin
      @(posedge clk);
      if (!cvxif_resp.issue_ready) ready_low_cycles++;
    end
    check("issue_ready drops while MATMUL busy", ready_low_cycles > 0);

    wait_result(r);
    check("LOAD_W response ID latched", r.id == 5'd9);
    check("LOAD_W response RD latched", r.rd == 5'd7);
    check("LOAD_W no writeback", r.we == 1'b0);

    // MM_LOAD_A should be a quick staging ack (no long busy window).
    issue_one(mk_matmul_instr(3'b010, 5'd5), 32'h1111_2222, 32'h0, 2'd1, 5'd10);
    wait_result(r);
    check("LOAD_A response ID latched", r.id == 5'd10);
    check("LOAD_A response RD latched", r.rd == 5'd5);
    check("LOAD_A no writeback", r.we == 1'b0);

    // MM_RUN should now drive the long activation stream/compute path.
    issue_one(mk_matmul_instr(3'b011, 5'd6), 32'h0, 32'h1, 2'd1, 5'd11);
    ready_low_cycles = 0;
    repeat (6) begin
      @(posedge clk);
      if (!cvxif_resp.issue_ready) ready_low_cycles++;
    end
    check("issue_ready drops while MM_RUN busy", ready_low_cycles > 0);
    wait_result(r);
    check("RUN response ID latched", r.id == 5'd11);
    check("RUN response RD latched", r.rd == 5'd6);
    check("RUN no writeback", r.we == 1'b0);

    // MM_DRAIN should return writeback with matching tags.
    issue_one(mk_matmul_instr(3'b100, 5'd11), 32'h0, 32'h0, 2'd1, 5'd12);
    wait_result(r);
    check("DRAIN response ID latched", r.id == 5'd12);
    check("DRAIN response RD latched", r.rd == 5'd11);
    check("DRAIN writeback asserted", r.we == 1'b1);

    $display("========================================");
    $display("Summary: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");

    #50;
    if (fail_count != 0) $fatal(1, "MATMUL_CTRL TB failed");
    $finish;
  end

endmodule
