`timescale 1ns / 1ps

module tb_matmul_gelu_sandwich;
  import int8_mac_instr_pkg::*;

  localparam int unsigned XLEN = 32;

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
  int unsigned cycle_ctr;

  int test_count, pass_count, fail_count;

  logic [7:0] gelu_lut [0:255];

  function automatic logic [31:0] mk_matmul_instr(input logic [2:0] funct3, input logic [4:0] rd);
    mk_matmul_instr = {7'b0001011, 5'd0, 5'd0, funct3, rd, 7'b1111011};
  endfunction

  function automatic logic [31:0] mk_norm_act_instr(input logic [2:0] funct3, input logic [4:0] rd);
    mk_norm_act_instr = {7'b0001100, 5'd0, 5'd0, funct3, rd, 7'b1111011};
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
    int timeout_cycles;
    timeout_cycles = 0;

    while (!cvxif_resp.result_valid && timeout_cycles < 500) begin
      @(posedge clk);
      timeout_cycles++;
    end

    if (!cvxif_resp.result_valid) begin
      $fatal(1, "Timed out waiting for cvxif result");
    end

    r = cvxif_resp.result;
    @(posedge clk);
  endtask

  task automatic issue_and_measure(
    input logic [31:0] instr,
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    input cvxif_hartid_t hartid,
    input cvxif_id_t id,
    output cvxif_result_t r,
    output int unsigned cycles,
    output int unsigned issue_wait_cycles,
    output int unsigned result_wait_cycles
  );
    int unsigned start_cycle;
    int unsigned issue_done_cycle;
    int unsigned result_cycle;
    int timeout_cycles;

    start_cycle = cycle_ctr;

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
    issue_done_cycle = cycle_ctr;

    @(posedge clk);
    cvxif_req.issue_valid    = 1'b0;
    cvxif_req.register_valid = 1'b0;

    timeout_cycles = 0;
    while (!cvxif_resp.result_valid && timeout_cycles < 500) begin
      @(posedge clk);
      timeout_cycles++;
    end

    if (!cvxif_resp.result_valid) begin
      $fatal(1, "Timed out waiting for cvxif result");
    end

    r = cvxif_resp.result;
    result_cycle = cycle_ctr;
    issue_wait_cycles = issue_done_cycle - start_cycle;
    result_wait_cycles = result_cycle - issue_done_cycle;
    cycles = result_cycle - start_cycle;
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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_ctr <= 0;
    end else begin
      cycle_ctr <= cycle_ctr + 1;
    end
  end

  cvxif_result_t r_mm, r_gelu;
  logic [7:0] expected_gelu;
  int unsigned lat_load_w;
  int unsigned lat_load_a;
  int unsigned lat_mm_run;
  int unsigned lat_mm_drain;
  int unsigned lat_gelu;
  int unsigned lat_issue_load_w;
  int unsigned lat_issue_load_a;
  int unsigned lat_issue_mm_run;
  int unsigned lat_issue_mm_drain;
  int unsigned lat_issue_gelu;
  int unsigned lat_result_load_w;
  int unsigned lat_result_load_a;
  int unsigned lat_result_mm_run;
  int unsigned lat_result_mm_drain;
  int unsigned lat_result_gelu;
  int unsigned lat_issue_total;
  int unsigned lat_result_total;
  int unsigned lat_matmul_total;
  int unsigned lat_pipeline_total;

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
    $display("MATMUL -> GELU Sandwich TB");
    $display("========================================");

    // Stage 1A: MATMUL weight load
    issue_and_measure(mk_matmul_instr(3'b001, 5'd7), 32'h0102_0304, 32'h0, 2'd1, 5'd30,
                      r_mm, lat_load_w, lat_issue_load_w, lat_result_load_w);
    check("LOAD_W completed", (r_mm.id == 5'd30) && (r_mm.rd == 5'd7) && (r_mm.we == 1'b0));
    check("LOAD_W latency captured", lat_load_w > 0);

    // Stage 1B: MATMUL activation stage
    issue_and_measure(mk_matmul_instr(3'b010, 5'd8), 32'h1111_2222, 32'h0, 2'd1, 5'd31,
                      r_mm, lat_load_a, lat_issue_load_a, lat_result_load_a);
    check("LOAD_A completed", (r_mm.id == 5'd31) && (r_mm.rd == 5'd8) && (r_mm.we == 1'b0));
    check("LOAD_A latency captured", lat_load_a > 0);

    // Stage 1C: MATMUL run
    issue_and_measure(mk_matmul_instr(3'b011, 5'd9), 32'h0000_0003, 32'h0000_0001, 2'd1, 5'd0,
                      r_mm, lat_mm_run, lat_issue_mm_run, lat_result_mm_run);
    check("MM_RUN completed", (r_mm.id == 5'd0) && (r_mm.rd == 5'd9) && (r_mm.we == 1'b0));
    check("MM_RUN latency captured", lat_mm_run > 0);

    // Stage 1D: MATMUL drain result Z
    issue_and_measure(mk_matmul_instr(3'b100, 5'd10), 32'h0, 32'h0, 2'd1, 5'd1,
                      r_mm, lat_mm_drain, lat_issue_mm_drain, lat_result_mm_drain);
    check("MM_DRAIN writeback", (r_mm.id == 5'd1) && (r_mm.rd == 5'd10) && (r_mm.we == 1'b1));
    check("MM_DRAIN latency captured", lat_mm_drain > 0);

    // Stage 2: GELU(Z)
    expected_gelu = gelu_lut[r_mm.data[7:0]];
    issue_and_measure(mk_norm_act_instr(3'b000, 5'd11), r_mm.data, 32'h0, 2'd1, 5'd2,
                      r_gelu, lat_gelu, lat_issue_gelu, lat_result_gelu);

    check("GELU tag ID", r_gelu.id == 5'd2);
    check("GELU tag RD", r_gelu.rd == 5'd11);
    check("GELU writeback", r_gelu.we == 1'b1);
    check("GELU output matches LUT", r_gelu.data[7:0] == expected_gelu);
    check("GELU latency captured", lat_gelu > 0);

    lat_matmul_total = lat_load_w + lat_load_a + lat_mm_run + lat_mm_drain;
    lat_pipeline_total = lat_matmul_total + lat_gelu;
    lat_issue_total = lat_issue_load_w + lat_issue_load_a + lat_issue_mm_run + lat_issue_mm_drain + lat_issue_gelu;
    lat_result_total = lat_result_load_w + lat_result_load_a + lat_result_mm_run + lat_result_mm_drain + lat_result_gelu;

    check("Latency split sums to pipeline total", (lat_issue_total + lat_result_total) == lat_pipeline_total);

    $display("========================================");
    $display("Latency Breakdown (cycles, total = issue_wait + post_issue_wait)");
    $display("  LOAD_W     : %0d = %0d + %0d", lat_load_w, lat_issue_load_w, lat_result_load_w);
    $display("  LOAD_A     : %0d = %0d + %0d", lat_load_a, lat_issue_load_a, lat_result_load_a);
    $display("  MM_RUN     : %0d = %0d + %0d", lat_mm_run, lat_issue_mm_run, lat_result_mm_run);
    $display("  MM_DRAIN   : %0d = %0d + %0d", lat_mm_drain, lat_issue_mm_drain, lat_result_mm_drain);
    $display("  GELU       : %0d = %0d + %0d", lat_gelu, lat_issue_gelu, lat_result_gelu);
    $display("----------------------------------------");
    $display("  Issue wait : %0d", lat_issue_total);
    $display("  Datapath   : %0d", lat_result_total);
    $display("  MATMUL sum : %0d", lat_matmul_total);
    $display("  Pipeline   : %0d", lat_pipeline_total);

    $display("========================================");
    $display("Summary: %0d passed, %0d failed", pass_count, fail_count);
    $display("========================================");

    #50;
    if (fail_count != 0) $fatal(1, "Sandwich TB failed");
    $finish;
  end

endmodule
