// Testbench for kv_cache_buffer (v2.0)
// Updated for new port widths ($clog2-based) and new seq_reset_i port.
// Added:
//   TEST 9  — reset mid-sequence (verifies seq_reset_i)
//   TEST 10 — back-to-back reads (rd_en held high)
//   TEST 11 — overwrite same slot and verify new value wins
`timescale 1ns / 1ps

module tb_kv_cache_buffer;

  localparam integer NUM_LAYERS  = 4;
  localparam integer MAX_SEQ_LEN = 8;
  localparam integer HEAD_DIM    = 16;
  localparam integer HEAD_WORDS  = HEAD_DIM / 4;  // 4

  // Derived widths to match DUT after $clog2 port fix
  localparam integer LW = $clog2(NUM_LAYERS);    // 2
  localparam integer PW = $clog2(MAX_SEQ_LEN);   // 3
  localparam integer WW = $clog2(HEAD_DIM/4);    // 2
  localparam integer SW = $clog2(MAX_SEQ_LEN+1)+1; // seq_len width

  logic clk, rst_n;
  logic        wr_en, wr_type;
  logic [LW-1:0]  wr_layer;
  logic [PW-1:0]  wr_pos;
  logic [WW-1:0]  wr_word;
  logic [31:0] wr_data;
  logic        rd_en, rd_type;
  logic [LW-1:0]  rd_layer;
  logic [PW-1:0]  rd_pos;
  logic [WW-1:0]  rd_word;
  logic [31:0] rd_data;
  logic        rd_valid;
  logic        seq_advance;
  logic        seq_reset;    // NEW
  logic [SW-1:0] seq_len;
  logic        full;

  kv_cache_buffer #(
    .NUM_LAYERS (NUM_LAYERS),
    .MAX_SEQ_LEN(MAX_SEQ_LEN),
    .HEAD_DIM   (HEAD_DIM)
  ) dut (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .wr_en_i       (wr_en),
    .wr_type_i     (wr_type),
    .wr_layer_i    (wr_layer),
    .wr_pos_i      (wr_pos),
    .wr_word_i     (wr_word),
    .wr_data_i     (wr_data),
    .rd_en_i       (rd_en),
    .rd_type_i     (rd_type),
    .rd_layer_i    (rd_layer),
    .rd_pos_i      (rd_pos),
    .rd_word_i     (rd_word),
    .rd_data_o     (rd_data),
    .rd_valid_o    (rd_valid),
    .seq_advance_i (seq_advance),
    .seq_reset_i   (seq_reset),
    .seq_len_o     (seq_len),
    .full_o        (full)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  int test_count, pass_count, fail_count;

  task automatic check(input string name, input bit cond);
    test_count++;
    if (cond) begin pass_count++; $display("[PASS] %s", name); end
    else       begin fail_count++; $display("[FAIL] %s", name); end
  endtask

  // Deterministic data: encode (type, layer, pos, word) into 32 bits
  function automatic logic [31:0] make_word(input int t, l, p, w);
    logic [7:0] b0, b1, b2, b3;
    int base_val;
    base_val = t*64 + l*16 + p*4 + w + 1;
    b0 = base_val[7:0];
    b1 = (base_val + 1) & 8'hFF;
    b2 = (base_val + 2) & 8'hFF;
    b3 = (base_val + 3) & 8'hFF;
    return {b3, b2, b1, b0};
  endfunction

  // Write all HEAD_WORDS words of one K or V vector
  task automatic write_vector(input int t, l, p);
    for (int w = 0; w < HEAD_WORDS; w++) begin
      @(negedge clk);
      wr_en    = 1'b1;
      wr_type  = t[0];
      wr_layer = l[LW-1:0];
      wr_pos   = p[PW-1:0];
      wr_word  = w[WW-1:0];
      wr_data  = make_word(t, l, p, w);
      @(posedge clk);
    end
    @(negedge clk);
    wr_en = 1'b0;
  endtask

  // Read all HEAD_WORDS words and check each against expected
  // DUT latency: addr registered on posedge(rd_en=1), data output posedge after
  task automatic read_vector_and_check(input int t, l, p);
    for (int w = 0; w < HEAD_WORDS; w++) begin
      @(negedge clk);
      rd_en    = 1'b1;
      rd_type  = t[0];
      rd_layer = l[LW-1:0];
      rd_pos   = p[PW-1:0];
      rd_word  = w[WW-1:0];
      @(posedge clk);     // cycle 1: rd_addr registered, rd_valid goes 1
      @(posedge clk);     // cycle 2: rd_data latched from mem
      #1;
      check(
        $sformatf("rd t=%0d l=%0d p=%0d w=%0d", t, l, p, w),
        rd_valid && (rd_data == make_word(t, l, p, w))
      );
      @(negedge clk);
      rd_en = 1'b0;
    end
  endtask

  // Single-word read (for overwrite and back-to-back tests)
  task automatic read_word_check(input int t, l, p, w, input logic [31:0] expected);
    @(negedge clk);
    rd_en    = 1'b1;
    rd_type  = t[0];
    rd_layer = l[LW-1:0];
    rd_pos   = p[PW-1:0];
    rd_word  = w[WW-1:0];
    @(posedge clk);
    @(posedge clk);
    #1;
    check(
      $sformatf("rd_word t=%0d l=%0d p=%0d w=%0d exp=0x%08h", t, l, p, w, expected),
      rd_valid && (rd_data == expected)
    );
    @(negedge clk);
    rd_en = 1'b0;
  endtask

  initial begin
    test_count = 0; pass_count = 0; fail_count = 0;
    wr_en = 0; rd_en = 0; seq_advance = 0; seq_reset = 0;
    wr_type = 0; wr_layer = 0; wr_pos = 0; wr_word = 0; wr_data = 0;
    rd_type = 0; rd_layer = 0; rd_pos = 0; rd_word = 0;

    rst_n = 0;
    repeat(4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    $display("========================================");
    $display("KV Cache Buffer Testbench v2.0");
    $display("Layers=%0d SeqLen=%0d HeadDim=%0d Words=%0d",
             NUM_LAYERS, MAX_SEQ_LEN, HEAD_DIM, HEAD_WORDS);
    $display("========================================");

    // ------------------------------------------------------------------
    // TEST 1: Initial state after reset
    // ------------------------------------------------------------------
    $display("\n[TEST 1] Initial state");
    check("seq_len==0 after reset", seq_len == 0);
    check("full==0 after reset",    full    == 0);
    check("rd_valid==0 after reset", rd_valid == 0);
    check("rd_data==0 after reset",  rd_data  == 32'd0);

    // ------------------------------------------------------------------
    // TEST 2: K write/read
    // ------------------------------------------------------------------
    $display("\n[TEST 2] Write K[0][0] then read back");
    write_vector(0, 0, 0);
    read_vector_and_check(0, 0, 0);

    // ------------------------------------------------------------------
    // TEST 3: V write/read
    // ------------------------------------------------------------------
    $display("\n[TEST 3] Write V[0][0] then read back");
    write_vector(1, 0, 0);
    read_vector_and_check(1, 0, 0);

    // ------------------------------------------------------------------
    // TEST 4: K and V don't alias
    // ------------------------------------------------------------------
    $display("\n[TEST 4] K[0][0] unchanged after V write");
    read_vector_and_check(0, 0, 0);

    // ------------------------------------------------------------------
    // TEST 5: Multi-layer / multi-position
    // ------------------------------------------------------------------
    $display("\n[TEST 5] Multi-layer/position write then read");
    for (int l = 0; l < NUM_LAYERS; l++)
      for (int p = 0; p < 3; p++) begin
        write_vector(0, l, p);
        write_vector(1, l, p);
      end
    for (int l = 0; l < NUM_LAYERS; l++)
      for (int p = 0; p < 3; p++) begin
        read_vector_and_check(0, l, p);
        read_vector_and_check(1, l, p);
      end

    // ------------------------------------------------------------------
    // TEST 6: seq_len tracking
    // ------------------------------------------------------------------
    $display("\n[TEST 6] Sequence length tracking");
    check("seq_len still 0", seq_len == 0);
    repeat(3) begin
      @(negedge clk); seq_advance = 1; @(posedge clk);
      @(negedge clk); seq_advance = 0; @(posedge clk);
    end
    check("seq_len==3",   seq_len == 3);
    check("full==0 at 3", full    == 0);

    // ------------------------------------------------------------------
    // TEST 7: Fill to max
    // ------------------------------------------------------------------
    $display("\n[TEST 7] Fill to MAX_SEQ_LEN");
    repeat(MAX_SEQ_LEN - 3) begin
      @(negedge clk); seq_advance = 1; @(posedge clk);
      @(negedge clk); seq_advance = 0; @(posedge clk);
    end
    check($sformatf("seq_len==%0d", MAX_SEQ_LEN), seq_len == MAX_SEQ_LEN);
    check("full==1",                              full    == 1);

    // ------------------------------------------------------------------
    // TEST 8: No overflow past MAX_SEQ_LEN
    // ------------------------------------------------------------------
    $display("\n[TEST 8] No overflow past MAX_SEQ_LEN");
    @(negedge clk); seq_advance = 1; @(posedge clk);
    @(negedge clk); seq_advance = 0; @(posedge clk);
    check("seq_len still MAX", seq_len == MAX_SEQ_LEN);
    check("full still 1",      full    == 1);

    // ------------------------------------------------------------------
    // TEST 9: seq_reset_i — reset mid-sequence (NEW)
    // ------------------------------------------------------------------
    $display("\n[TEST 9] seq_reset_i resets counter without full chip reset");
    // Currently at MAX; assert seq_reset for one cycle
    @(negedge clk); seq_reset = 1; @(posedge clk);
    @(negedge clk); seq_reset = 0; @(posedge clk);
    check("seq_len==0 after seq_reset", seq_len == 0);
    check("full==0 after seq_reset",    full    == 0);
    // Verify counter can advance again after reset
    @(negedge clk); seq_advance = 1; @(posedge clk);
    @(negedge clk); seq_advance = 0; @(posedge clk);
    check("seq_len==1 after reset+advance", seq_len == 1);

    // ------------------------------------------------------------------
    // TEST 10: Back-to-back reads with rd_en held high (NEW)
    // ------------------------------------------------------------------
    $display("\n[TEST 10] Back-to-back reads (rd_en held high)");
    // Write K[1][2] words 0 and 1 first
    write_vector(0, 1, 2);
    // Now keep rd_en high for 3 consecutive cycles on different words
    @(negedge clk);
    rd_en = 1'b1;
    rd_type  = 1'b0; rd_layer = 2'b01; rd_pos = 3'd2; rd_word = 2'd0;
    
    @(posedge clk); // cycle A (posedge): addr_word0 registered
    @(negedge clk); // cycle A (negedge): change word to avoid race condition
    rd_word = 2'd1;
    
    @(posedge clk); // cycle B (posedge): word0 data arrives, addr_word1 registered
    #1;
    check("bb_read word0 valid", rd_valid == 1'b1);
    
    if (rd_data != make_word(0, 1, 2, 0)) begin
      $display("bb_read word0 data FAIL: got %08x, exp %08x", rd_data, make_word(0, 1, 2, 0));
    end
    check("bb_read word0 data",  rd_data  == make_word(0, 1, 2, 0));
    
    @(posedge clk); // cycle C: word1 data arrives
    #1;
    check("bb_read word1 valid", rd_valid == 1'b1);
    if (rd_data != make_word(0, 1, 2, 1)) begin
      $display("bb_read word1 data FAIL: got %08x, exp %08x", rd_data, make_word(0, 1, 2, 1));
    end
    check("bb_read word1 data",  rd_data  == make_word(0, 1, 2, 1));
    @(negedge clk);
    rd_en = 1'b0;

    // ------------------------------------------------------------------
    // TEST 11: Overwrite same slot — new value must win (NEW)
    // ------------------------------------------------------------------
    $display("\n[TEST 11] Overwrite same slot, verify new value wins");
    // Write a known value to K[0][0] word 0
    @(negedge clk);
    wr_en = 1'b1; wr_type = 1'b0; wr_layer = '0; wr_pos = '0; wr_word = '0;
    wr_data = 32'hDEADBEEF;
    @(posedge clk);
    @(negedge clk); wr_en = 1'b0;
    // Overwrite with a different value
    @(negedge clk);
    wr_en = 1'b1; wr_data = 32'hCAFEBABE;
    @(posedge clk);
    @(negedge clk); wr_en = 1'b0;
    // Read back — must see CAFEBABE
    read_word_check(0, 0, 0, 0, 32'hCAFEBABE);

    // ------------------------------------------------------------------
    // TEST 12: rst_ni mid-simulation (NEW)
    // ------------------------------------------------------------------
    $display("\n[TEST 12] rst_ni mid-simulation clears state");
    // Advance seq to 3
    seq_reset = 1; @(negedge clk); @(posedge clk);
    seq_reset = 0;
    repeat(3) begin
      @(negedge clk); seq_advance = 1; @(posedge clk);
      @(negedge clk); seq_advance = 0; @(posedge clk);
    end
    check("seq_len==3 before rst", seq_len == 3);
    // Assert rst_ni
    rst_n = 0; repeat(2) @(posedge clk);
    rst_n = 1; @(posedge clk);
    #1;
    check("seq_len==0 after rst_ni", seq_len == 0);
    check("full==0 after rst_ni",    full    == 0);
    check("rd_valid==0 after rst_ni", rd_valid == 0);
    check("rd_data==0 after rst_ni",  rd_data  == 32'd0);

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    $display("\n========================================");
    $display("Summary: %0d passed, %0d failed / %0d total",
             pass_count, fail_count, test_count);
    $display("========================================");

    repeat(4) @(posedge clk);
    if (fail_count != 0) $fatal(1, "KV Cache TB FAILED");
    $finish;
  end

endmodule
