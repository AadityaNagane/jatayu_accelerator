`timescale 1ns / 1ps

module tb_norm_act_ctrl;
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
  reg [1023:0] dumpfile_path;

  int test_count, pass_count, fail_count;
  logic [7:0] gelu_lut [0:255];

  function automatic logic [31:0] mk_norm_act_instr(input logic [2:0] funct3, input logic [4:0] rd);
    mk_norm_act_instr = {7'b0001100, 5'd0, 5'd0, funct3, rd, 7'b1111011};
  endfunction

  // Optional waveform dumping: run with +dumpfile=<path>.vcd
  initial begin
    if ($value$plusargs("dumpfile=%s", dumpfile_path)) begin
      $display("[WAVE] Dumping VCD to %0s", dumpfile_path);
      $dumpfile(dumpfile_path);
      $dumpvars(0, tb_norm_act_ctrl);
    end
  end

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

  task automatic wait_result_count_busy(output cvxif_result_t r, output int busy_cycles);
    int timeout_cycles;
    busy_cycles = 0;
    timeout_cycles = 0;

    while (!cvxif_resp.result_valid && timeout_cycles < 200) begin
      @(posedge clk);
      timeout_cycles++;
      if (!cvxif_resp.issue_ready) busy_cycles++;
    end

    if (!cvxif_resp.result_valid) begin
      $fatal(1, "Timed out waiting for cvxif result");
    end

    r = cvxif_resp.result;
    @(posedge clk);
  endtask

  function automatic logic signed [7:0] clip_int8(input logic signed [31:0] v);
    if (v > 127) begin
      clip_int8 = 8'sd127;
    end else if (v < -128) begin
      clip_int8 = -8'sd128;
    end else begin
      clip_int8 = v[7:0];
    end
  endfunction

  function automatic logic [15:0] approx_inv_std_q8(input logic [31:0] var_eps);
    if (var_eps <= 1) begin
      approx_inv_std_q8 = 16'd256;
    end else if (var_eps <= 4) begin
      approx_inv_std_q8 = 16'd181;
    end else if (var_eps <= 9) begin
      approx_inv_std_q8 = 16'd128;
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

  function automatic logic [31:0] lnorm8_4lane_expected(
    input logic [31:0] x_word,
    input logic [31:0] param_word
  );
    logic signed [7:0] x0, x1, x2, x3;
    logic signed [7:0] gamma_q7, beta_i8;
    logic signed [31:0] sum, mean;
    logic signed [31:0] d0, d1, d2, d3;
    logic [31:0] var_acc, var_val;
    logic [15:0] inv_std_q8;
    logic signed [31:0] y0, y1, y2, y3;
    logic signed [31:0] t0, t1, t2, t3;

    x0 = x_word[7:0];
    x1 = x_word[15:8];
    x2 = x_word[23:16];
    x3 = x_word[31:24];

    gamma_q7 = param_word[7:0];
    beta_i8 = param_word[15:8];
    if (gamma_q7 == 8'sd0) gamma_q7 = 8'sd127;

    sum = x0 + x1 + x2 + x3;
    mean = sum >>> 2;

    d0 = x0 - mean;
    d1 = x1 - mean;
    d2 = x2 - mean;
    d3 = x3 - mean;

    var_acc = (d0 * d0) + (d1 * d1) + (d2 * d2) + (d3 * d3);
    var_val = var_acc >> 2;
    inv_std_q8 = approx_inv_std_q8(var_val + 1);

    t0 = (d0 * $signed({1'b0, inv_std_q8}) * gamma_q7);
    t1 = (d1 * $signed({1'b0, inv_std_q8}) * gamma_q7);
    t2 = (d2 * $signed({1'b0, inv_std_q8}) * gamma_q7);
    t3 = (d3 * $signed({1'b0, inv_std_q8}) * gamma_q7);

    y0 = (t0 >>> 15) + beta_i8;
    y1 = (t1 >>> 15) + beta_i8;
    y2 = (t2 >>> 15) + beta_i8;
    y3 = (t3 >>> 15) + beta_i8;

    lnorm8_4lane_expected = {
      clip_int8(y3),
      clip_int8(y2),
      clip_int8(y1),
      clip_int8(y0)
    };
  endfunction

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    #50;
    rst_n = 1'b1;
  end

  int compute_cycles;
  cvxif_result_t r;
  logic [31:0] lnorm_expected;

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
    $readmemh("data/gelu8_lut.hex", gelu_lut);

    test_count = 0;
    pass_count = 0;
    fail_count = 0;
    cvxif_req = '0;

    @(posedge rst_n);
    @(posedge clk);

    $display("========================================");
    $display("NORM_ACT (GELU8 / LayerNorm8) TB");
    $display("========================================");

    // Test NA_GELU8: feed some input, expect result with writeback
    issue_one(mk_norm_act_instr(3'b000, 5'd15), 32'h0000_0010, 32'h0, 2'd1, 5'd20);
    
    wait_result_count_busy(r, compute_cycles);
    check("issue_ready drops while GELU compute active", compute_cycles > 0);
    check("GELU result ID latched", r.id == 5'd20);
    check("GELU result RD latched", r.rd == 5'd15);
    check("GELU writeback asserted", r.we == 1'b1);
    check("GELU output matches LUT", r.data[7:0] == gelu_lut[8'h10]);

    // Test NA_LNORM8: feed some input, expect result with writeback
    lnorm_expected = lnorm8_4lane_expected(32'h100c0804, 32'h0000_007f);
    issue_one(mk_norm_act_instr(3'b001, 5'd16), 32'h100c0804, 32'h0000_007f, 2'd1, 5'd21);

    wait_result_count_busy(r, compute_cycles);
    check("issue_ready drops while LayerNorm compute active", compute_cycles > 0);
    check("LayerNorm result ID latched", r.id == 5'd21);
    check("LayerNorm result RD latched", r.rd == 5'd16);
    check("LayerNorm writeback asserted", r.we == 1'b1);
    check("LayerNorm output matches model", r.data == lnorm_expected);

    $display("========================================");
    $display("Summary: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");

    #50;
    if (fail_count != 0) $fatal(1, "NORM_ACT TB failed");
    $finish;
  end

endmodule
