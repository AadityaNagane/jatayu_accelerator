// KV Cache Buffer — Full UVM Verification Package (v2.0)
//
// FIX LOG v2.0:
//   CRITICAL - Scoreboard: push_read_expect() is now called from driver before
//              item_done() — all read checks were silently skipped in v1.0.
//   NEW — seq_reset operation type (KV_RESET) wired to seq_reset_i port.
//   NEW — Word-index coverpoint added to kv_cg coverage group.
//   NEW — full_o assertion coverpoint added.
//   NEW — kv_overwrite_seq: write same slot twice, read back latest value.
//   NEW — kv_overflow_seq: advance past MAX_SEQ_LEN, verify saturation.
//   NEW — kv_boundary_seq: read/write at position 0 and MAX_SEQ_LEN-1.
//   NEW — Corresponding test classes: kv_overwrite_test, kv_overflow_test,
//          kv_boundary_test.
//
// Tests provided:
//   kv_smoke_test    — deterministic: write 2 tokens, read back, check
//   kv_random_test   — 20 random write/read transactions, scoreboard checks all
//   kv_overwrite_test— write same slot twice, verify last write wins
//   kv_overflow_test — advance seq past maximum, verify saturation
//   kv_boundary_test — exercise position 0 and MAX_SEQ_LEN-1 boundaries

package kv_cache_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // -------------------------------------------------------------------------
  // Parameters  (match the DUT instantiation in the top-level)
  // -------------------------------------------------------------------------
  localparam int unsigned KV_LAYERS    = 4;
  localparam int unsigned KV_SEQ_LEN  = 8;
  localparam int unsigned KV_HEAD_DIM = 16;
  localparam int unsigned KV_WORDS    = KV_HEAD_DIM / 4;   // 4

  // -------------------------------------------------------------------------
  // Transaction types
  // -------------------------------------------------------------------------
  typedef enum int { KV_WRITE, KV_READ, KV_ADVANCE, KV_RESET } kv_op_e;

  // -------------------------------------------------------------------------
  // Sequence Item
  // -------------------------------------------------------------------------
  class kv_seq_item extends uvm_sequence_item;
    rand kv_op_e                                        op;
    rand bit                                            kv_type;  // 0=K, 1=V
    rand bit [$clog2(KV_LAYERS)-1:0]                   layer;
    rand bit [$clog2(KV_SEQ_LEN)-1:0]                  pos;
    rand bit [$clog2(KV_HEAD_DIM/4)-1:0]               word_idx;
    rand bit [31:0]                                     wr_data;

    // Observed read-back (set by driver)
    bit [31:0]                                          rd_data;
    bit                                                 rd_valid;

    `uvm_object_utils_begin(kv_seq_item)
      `uvm_field_enum(kv_op_e, op,        UVM_DEFAULT)
      `uvm_field_int (kv_type,            UVM_DEFAULT)
      `uvm_field_int (layer,              UVM_DEFAULT)
      `uvm_field_int (pos,                UVM_DEFAULT)
      `uvm_field_int (word_idx,           UVM_DEFAULT)
      `uvm_field_int (wr_data,            UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "kv_seq_item");
      super.new(name);
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Sequencer
  // -------------------------------------------------------------------------
  class kv_sequencer extends uvm_sequencer #(kv_seq_item);
    `uvm_component_utils(kv_sequencer)
    function new(string name = "kv_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Helper: build a deterministic 32-bit word from (type, layer, pos, word)
  // -------------------------------------------------------------------------
  function automatic logic [31:0] kv_make_word(
    input int t, l, p, w
  );
    automatic byte b0, b1, b2, b3;
    b0 = byte'((t * 64) + (l * 16) + (p * 2) + w + 1);
    b1 = byte'(b0 + 1);
    b2 = byte'(b0 + 2);
    b3 = byte'(b0 + 3);
    return {b3, b2, b1, b0};
  endfunction

  // -------------------------------------------------------------------------
  // Scoreboard forward declaration (needed by driver)
  // -------------------------------------------------------------------------
  // (full definition below)
  class kv_scoreboard;
  endclass

  // -------------------------------------------------------------------------
  // Base Sequence — write and read utility tasks
  // -------------------------------------------------------------------------
  class kv_base_seq extends uvm_sequence #(kv_seq_item);
    function new(string name = "kv_base_seq");
      super.new(name);
    endfunction

    // Write all HEAD_WORDS for one K or V vector
    protected task write_vector(input int t, l, p);
      kv_seq_item tr;
      for (int w = 0; w < KV_WORDS; w++) begin
        tr = kv_seq_item::type_id::create("wr_tr");
        start_item(tr);
        tr.op       = KV_WRITE;
        tr.kv_type  = t[0];
        tr.layer    = l[$clog2(KV_LAYERS)-1:0];
        tr.pos      = p[$clog2(KV_SEQ_LEN)-1:0];
        tr.word_idx = w[$clog2(KV_HEAD_DIM/4)-1:0];
        tr.wr_data  = kv_make_word(t, l, p, w);
        finish_item(tr);
      end
    endtask

    // Write a specific single word with a given raw data value
    protected task write_word_raw(input int t, l, p, w, input logic [31:0] data);
      kv_seq_item tr;
      tr = kv_seq_item::type_id::create("wr_raw_tr");
      start_item(tr);
      tr.op       = KV_WRITE;
      tr.kv_type  = t[0];
      tr.layer    = l[$clog2(KV_LAYERS)-1:0];
      tr.pos      = p[$clog2(KV_SEQ_LEN)-1:0];
      tr.word_idx = w[$clog2(KV_HEAD_DIM/4)-1:0];
      tr.wr_data  = data;
      finish_item(tr);
    endtask

    // Read one word (expected value is kv_make_word)
    protected task read_word(input int t, l, p, w, output kv_seq_item rtr);
      rtr = kv_seq_item::type_id::create("rd_tr");
      start_item(rtr);
      rtr.op       = KV_READ;
      rtr.kv_type  = t[0];
      rtr.layer    = l[$clog2(KV_LAYERS)-1:0];
      rtr.pos      = p[$clog2(KV_SEQ_LEN)-1:0];
      rtr.word_idx = w[$clog2(KV_HEAD_DIM/4)-1:0];
      rtr.wr_data  = kv_make_word(t, l, p, w);  // expected
      finish_item(rtr);
    endtask

    // Read one word, expecting a specific raw data value
    protected task read_word_expect(input int t, l, p, w,
                                    input logic [31:0] expected,
                                    output kv_seq_item rtr);
      rtr = kv_seq_item::type_id::create("rd_raw_tr");
      start_item(rtr);
      rtr.op       = KV_READ;
      rtr.kv_type  = t[0];
      rtr.layer    = l[$clog2(KV_LAYERS)-1:0];
      rtr.pos      = p[$clog2(KV_SEQ_LEN)-1:0];
      rtr.word_idx = w[$clog2(KV_HEAD_DIM/4)-1:0];
      rtr.wr_data  = expected;  // expected value carried in wr_data field
      finish_item(rtr);
    endtask

    // Advance sequence counter
    protected task advance_seq();
      kv_seq_item tr;
      tr = kv_seq_item::type_id::create("adv_tr");
      start_item(tr);
      tr.op = KV_ADVANCE;
      finish_item(tr);
    endtask

    // Reset sequence counter via seq_reset_i
    protected task reset_seq();
      kv_seq_item tr;
      tr = kv_seq_item::type_id::create("rst_tr");
      start_item(tr);
      tr.op = KV_RESET;
      finish_item(tr);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Smoke Sequence — 2 tokens, 2 layers, K and V
  // -------------------------------------------------------------------------
  class kv_smoke_seq extends kv_base_seq;
    `uvm_object_utils(kv_smoke_seq)
    function new(string name = "kv_smoke_seq");
      super.new(name);
    endfunction

    virtual task body();
      kv_seq_item rtr;
      // Token 0: write K and V for layers 0 and 1
      for (int l = 0; l < 2; l++) begin
        write_vector(0, l, 0);   // K[layer l][pos 0]
        write_vector(1, l, 0);   // V[layer l][pos 0]
      end
      advance_seq();

      // Token 1: write K and V for layers 0 and 1
      for (int l = 0; l < 2; l++) begin
        write_vector(0, l, 1);
        write_vector(1, l, 1);
      end
      advance_seq();

      // Read back everything and verify
      for (int l = 0; l < 2; l++) begin
        for (int p = 0; p < 2; p++) begin
          for (int w = 0; w < KV_WORDS; w++) begin
            read_word(0, l, p, w, rtr);  // K
            read_word(1, l, p, w, rtr);  // V
          end
        end
      end
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Random Sequence — randomised writes across all layers/positions
  // -------------------------------------------------------------------------
  class kv_random_seq extends kv_base_seq;
    `uvm_object_utils(kv_random_seq)

    int unsigned num_tokens = 4;

    function new(string name = "kv_random_seq");
      super.new(name);
    endfunction

    virtual task body();
      kv_seq_item rtr;
      int t, l, p, w;
      for (int tok = 0; tok < num_tokens; tok++) begin
        // For each token write K and V for all layers
        for (l = 0; l < KV_LAYERS; l++) begin
          write_vector(0, l, tok);
          write_vector(1, l, tok);
        end
        advance_seq();
      end
      // Read back spot-checks on random addresses
      repeat(20) begin
        t = $urandom_range(0, 1);
        l = $urandom_range(0, KV_LAYERS-1);
        p = $urandom_range(0, num_tokens-1);
        w = $urandom_range(0, KV_WORDS-1);
        read_word(t, l, p, w, rtr);
      end
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Overwrite Sequence — write same slot twice, verify latest value wins (NEW)
  // -------------------------------------------------------------------------
  class kv_overwrite_seq extends kv_base_seq;
    `uvm_object_utils(kv_overwrite_seq)
    function new(string name = "kv_overwrite_seq");
      super.new(name);
    endfunction

    virtual task body();
      kv_seq_item rtr;
      // First write to K[0][0] word 0
      write_word_raw(0, 0, 0, 0, 32'hDEADBEEF);
      // Overwrite with new value
      write_word_raw(0, 0, 0, 0, 32'hCAFEBABE);
      // Read back — must see CAFEBABE
      read_word_expect(0, 0, 0, 0, 32'hCAFEBABE, rtr);

      // Also verify V slot at same address is independent
      write_word_raw(1, 0, 0, 0, 32'h12345678);
      read_word_expect(1, 0, 0, 0, 32'h12345678, rtr);
      // K slot must still be CAFEBABE
      read_word_expect(0, 0, 0, 0, 32'hCAFEBABE, rtr);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Overflow Sequence — advance seq past MAX_SEQ_LEN, verify saturation (NEW)
  // -------------------------------------------------------------------------
  class kv_overflow_seq extends kv_base_seq;
    `uvm_object_utils(kv_overflow_seq)
    function new(string name = "kv_overflow_seq");
      super.new(name);
    endfunction

    virtual task body();
      // Reset counter first (in case prior test left it non-zero)
      reset_seq();
      // Advance exactly MAX_SEQ_LEN times
      for (int i = 0; i < KV_SEQ_LEN; i++)
        advance_seq();
      // Two more — should saturate
      advance_seq();
      advance_seq();
      // Verification is done by the test class checking full_o via monitor
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Boundary Sequence — corner positions: 0 and MAX_SEQ_LEN-1 (NEW)
  // -------------------------------------------------------------------------
  class kv_boundary_seq extends kv_base_seq;
    `uvm_object_utils(kv_boundary_seq)
    function new(string name = "kv_boundary_seq");
      super.new(name);
    endfunction

    virtual task body();
      kv_seq_item rtr;
      // Write and read position 0 for all layer/type combos
      for (int l = 0; l < KV_LAYERS; l++) begin
        write_vector(0, l, 0);
        write_vector(1, l, 0);
      end
      for (int l = 0; l < KV_LAYERS; l++) begin
        for (int w = 0; w < KV_WORDS; w++) begin
          read_word(0, l, 0, w, rtr);
          read_word(1, l, 0, w, rtr);
        end
      end

      // Write and read position MAX_SEQ_LEN-1 for all layers
      for (int l = 0; l < KV_LAYERS; l++) begin
        write_vector(0, l, KV_SEQ_LEN-1);
        write_vector(1, l, KV_SEQ_LEN-1);
      end
      for (int l = 0; l < KV_LAYERS; l++) begin
        for (int w = 0; w < KV_WORDS; w++) begin
          read_word(0, l, KV_SEQ_LEN-1, w, rtr);
          read_word(1, l, KV_SEQ_LEN-1, w, rtr);
        end
      end
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Driver (v2.0 — CRITICAL FIX: push_read_expect called before item_done)
  // -------------------------------------------------------------------------
  // Forward-declare scoreboard so driver can reference it
  // Driver gets handle set by env via config_db
  class kv_scoreboard;  // placeholder for type resolution
  endclass

  class kv_driver extends uvm_driver #(kv_seq_item);
    `uvm_component_utils(kv_driver)

    virtual kv_cache_if #(KV_LAYERS, KV_SEQ_LEN, KV_HEAD_DIM).drv_mp vif;

    // Handle to scoreboard — set by environment after build (for read expects)
    // Using config_db to decouple driver from scoreboard directly
    uvm_analysis_port #(kv_seq_item) rd_expect_ap;  // NEW: publish expected reads

    function new(string name = "kv_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(
            virtual kv_cache_if #(KV_LAYERS, KV_SEQ_LEN, KV_HEAD_DIM).drv_mp
          )::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "kv_driver: virtual interface not found")
      end
      rd_expect_ap = new("rd_expect_ap", this);
    endfunction

    task drive_idle();
      vif.drv_cb.wr_en       <= 0;
      vif.drv_cb.rd_en       <= 0;
      vif.drv_cb.seq_advance <= 0;
      vif.drv_cb.seq_reset   <= 0;
    endtask

    virtual task run_phase(uvm_phase phase);
      kv_seq_item tr;
      drive_idle();
      wait (vif.rst_ni === 1'b1);
      @(vif.drv_cb);

      forever begin
        seq_item_port.get_next_item(tr);

        case (tr.op)
          KV_WRITE: begin
            vif.drv_cb.wr_en    <= 1'b1;
            vif.drv_cb.wr_type  <= tr.kv_type;
            vif.drv_cb.wr_layer <= tr.layer;
            vif.drv_cb.wr_pos   <= tr.pos;
            vif.drv_cb.wr_word  <= tr.word_idx;
            vif.drv_cb.wr_data  <= tr.wr_data;
            @(vif.drv_cb);
            vif.drv_cb.wr_en <= 1'b0;
          end

          KV_READ: begin
            // CRITICAL FIX v2.0: publish expected value to scoreboard
            // BEFORE issuing the read, so the expectation is in the queue
            // before the monitor sees the rd_valid response.
            rd_expect_ap.write(tr);   // ← THIS WAS MISSING IN v1.0

            vif.drv_cb.rd_en    <= 1'b1;
            vif.drv_cb.rd_type  <= tr.kv_type;
            vif.drv_cb.rd_layer <= tr.layer;
            vif.drv_cb.rd_pos   <= tr.pos;
            vif.drv_cb.rd_word  <= tr.word_idx;
            @(vif.drv_cb);
            vif.drv_cb.rd_en <= 1'b0;
            @(vif.drv_cb);   // 1-cycle SRAM latency: data arrives
            tr.rd_data  = vif.drv_cb.rd_data;
            tr.rd_valid = vif.drv_cb.rd_valid;
          end

          KV_ADVANCE: begin
            vif.drv_cb.seq_advance <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.seq_advance <= 1'b0;
          end

          KV_RESET: begin            // NEW
            vif.drv_cb.seq_reset <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.seq_reset <= 1'b0;
          end
        endcase

        seq_item_port.item_done(tr);
      end
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Monitor (v2.0 — added word_idx and full_o coverpoints)
  // -------------------------------------------------------------------------
  class kv_monitor extends uvm_component;
    `uvm_component_utils(kv_monitor)

    virtual kv_cache_if #(KV_LAYERS, KV_SEQ_LEN, KV_HEAD_DIM).mon_mp vif;
    uvm_analysis_port #(kv_seq_item) wr_ap;   // write transactions
    uvm_analysis_port #(kv_seq_item) rd_ap;   // completed read transactions

    int wr_count, rd_count, adv_count, rst_count;

    // Enhanced covergroup: added word_idx and full_o coverpoints
    covergroup kv_cg with function sample(bit t, int l, int p, int w, bit fl);
      cp_type:  coverpoint t;
      cp_layer: coverpoint l { bins l[] = {[0:KV_LAYERS-1]}; }
      cp_pos:   coverpoint p { bins p[] = {[0:KV_SEQ_LEN-1]}; }
      cp_word:  coverpoint w { bins w[] = {[0:KV_WORDS-1]}; }   // NEW
      cp_full:  coverpoint fl;                                    // NEW
      cx:       cross cp_type, cp_layer, cp_pos;
    endgroup

    function new(string name = "kv_monitor", uvm_component parent = null);
      super.new(name, parent);
      wr_ap  = new("wr_ap",  this);
      rd_ap  = new("rd_ap",  this);
      kv_cg  = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(
            virtual kv_cache_if #(KV_LAYERS, KV_SEQ_LEN, KV_HEAD_DIM).mon_mp
          )::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "kv_monitor: virtual interface not found")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      kv_seq_item tr;
      wait (vif.rst_ni === 1'b1);
      forever begin
        @(vif.mon_cb);

        // Observe write
        if (vif.mon_cb.wr_en) begin
          tr = kv_seq_item::type_id::create("mon_wr");
          tr.op       = KV_WRITE;
          tr.kv_type  = vif.mon_cb.wr_type;
          tr.layer    = vif.mon_cb.wr_layer;
          tr.pos      = vif.mon_cb.wr_pos;
          tr.word_idx = vif.mon_cb.wr_word;
          tr.wr_data  = vif.mon_cb.wr_data;
          wr_ap.write(tr);
          kv_cg.sample(vif.mon_cb.wr_type,
                       int'(vif.mon_cb.wr_layer),
                       int'(vif.mon_cb.wr_pos),
                       int'(vif.mon_cb.wr_word),   // NEW
                       vif.mon_cb.full);            // NEW
          wr_count++;
        end

        // Observe read result (rd_valid pulses one cycle after rd_en)
        if (vif.mon_cb.rd_valid) begin
          tr = kv_seq_item::type_id::create("mon_rd");
          tr.op      = KV_READ;
          tr.rd_data  = vif.mon_cb.rd_data;
          tr.rd_valid = 1'b1;
          rd_ap.write(tr);
          rd_count++;
        end

        if (vif.mon_cb.seq_advance) adv_count++;
        if (vif.mon_cb.seq_reset)   rst_count++;
      end
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("KV_MON",
        $sformatf("Transactions: writes=%0d reads=%0d advances=%0d resets=%0d",
                  wr_count, rd_count, adv_count, rst_count), UVM_LOW)
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Scoreboard (v2.0 — rd_expect_q now reliably populated via driver analysis port)
  // -------------------------------------------------------------------------
  `uvm_analysis_imp_decl(_wr)
  `uvm_analysis_imp_decl(_rd)
  `uvm_analysis_imp_decl(_expect)  // NEW: separate import for expected reads

  class kv_scoreboard extends uvm_component;
    `uvm_component_utils(kv_scoreboard)

    uvm_analysis_imp_wr     #(kv_seq_item, kv_scoreboard) wr_imp;
    uvm_analysis_imp_rd     #(kv_seq_item, kv_scoreboard) rd_imp;
    uvm_analysis_imp_expect #(kv_seq_item, kv_scoreboard) expect_imp;  // NEW

    // Shadow memory: [type][layer][pos][word]
    logic [31:0] shadow [0:1][0:KV_LAYERS-1][0:KV_SEQ_LEN-1][0:KV_WORDS-1];
    bit          shadow_valid [0:1][0:KV_LAYERS-1][0:KV_SEQ_LEN-1][0:KV_WORDS-1];

    // Read FIFO — driver publishes expected data via rd_expect_ap
    // (FIX v2.0: this queue is now actually populated by the driver)
    kv_seq_item rd_expect_q[$];
    int checks_passed, checks_failed;

    function new(string name = "kv_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      wr_imp     = new("wr_imp",     this);
      rd_imp     = new("rd_imp",     this);
      expect_imp = new("expect_imp", this);  // NEW
      foreach (shadow[t, l, p, w]) shadow_valid[t][l][p][w] = 0;
    endfunction

    // Write side: update shadow memory
    function void write_wr(kv_seq_item t);
      if (t.op != KV_WRITE) return;
      shadow[t.kv_type][t.layer][t.pos][t.word_idx] = t.wr_data;
      shadow_valid[t.kv_type][t.layer][t.pos][t.word_idx] = 1;
    endfunction

    // NEW (v2.0 FIX): Receive expected reads from driver analysis port
    // This replaces the broken push_read_expect() function approach.
    function void write_expect(kv_seq_item t);
      rd_expect_q.push_back(t);
    endfunction

    // Read side: compare DUT output against expected from driver expectation queue
    function void write_rd(kv_seq_item t);
      kv_seq_item exp;
      if (rd_expect_q.size() == 0) begin
        `uvm_error("KV_SCB", "Received rd_valid but expectation queue is empty!")
        return;
      end
      exp = rd_expect_q.pop_front();
      if (t.rd_data === exp.wr_data) begin
        checks_passed++;
        `uvm_info("KV_SCB",
          $sformatf("PASS rd type=%0d layer=%0d pos=%0d word=%0d data=0x%08h",
                    exp.kv_type, exp.layer, exp.pos, exp.word_idx, t.rd_data), UVM_MEDIUM)
      end else begin
        checks_failed++;
        `uvm_error("KV_SCB",
          $sformatf("FAIL rd type=%0d layer=%0d pos=%0d word=%0d got=0x%08h exp=0x%08h",
                    exp.kv_type, exp.layer, exp.pos, exp.word_idx, t.rd_data, exp.wr_data))
      end
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (checks_passed + checks_failed == 0) begin
        `uvm_warning("KV_SCB", "No read checks performed!")
      end else if (checks_failed == 0) begin
        `uvm_info("KV_SCB",
          $sformatf("Scoreboard PASS: %0d checks, 0 failures", checks_passed), UVM_LOW)
      end else begin
        `uvm_error("KV_SCB",
          $sformatf("Scoreboard FAIL: %0d passed, %0d FAILED",
                    checks_passed, checks_failed))
      end
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Agent
  // -------------------------------------------------------------------------
  class kv_agent extends uvm_agent;
    `uvm_component_utils(kv_agent)

    kv_sequencer seqr;
    kv_driver    drv;
    kv_monitor   mon;

    function new(string name = "kv_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr = kv_sequencer::type_id::create("seqr", this);
      drv  = kv_driver::type_id::create("drv",  this);
      mon  = kv_monitor::type_id::create("mon",  this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Environment (v2.0 — wire driver's rd_expect_ap → scoreboard expect_imp)
  // -------------------------------------------------------------------------
  class kv_env extends uvm_env;
    `uvm_component_utils(kv_env)

    kv_agent      agent;
    kv_scoreboard scb;

    function new(string name = "kv_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = kv_agent::type_id::create("agent", this);
      scb   = kv_scoreboard::type_id::create("scb",   this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.mon.wr_ap.connect(scb.wr_imp);
      agent.mon.rd_ap.connect(scb.rd_imp);
      // FIX v2.0: connect driver's expected-read port to scoreboard
      agent.drv.rd_expect_ap.connect(scb.expect_imp);  // ← KEY FIX
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Base Test
  // -------------------------------------------------------------------------
  class kv_base_test extends uvm_test;
    `uvm_component_utils(kv_base_test)

    kv_env env;

    function new(string name = "kv_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = kv_env::type_id::create("env", this);
    endfunction
  endclass

  // -------------------------------------------------------------------------
  // Smoke Test — 2 tokens, deterministic vectors
  // -------------------------------------------------------------------------
  class kv_smoke_test extends kv_base_test;
    `uvm_component_utils(kv_smoke_test)

    function new(string name = "kv_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      kv_smoke_seq seq;
      phase.raise_objection(this);
      seq = kv_smoke_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
      repeat(50) @(posedge env.agent.drv.vif.clk_i);
      phase.drop_objection(this);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Random Test — 4 tokens across all layers, 20 random spot-check reads
  // -------------------------------------------------------------------------
  class kv_random_test extends kv_base_test;
    `uvm_component_utils(kv_random_test)

    function new(string name = "kv_random_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      kv_random_seq seq;
      phase.raise_objection(this);
      seq = kv_random_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
      repeat(100) @(posedge env.agent.drv.vif.clk_i);
      phase.drop_objection(this);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Overwrite Test — verify last write wins (NEW)
  // -------------------------------------------------------------------------
  class kv_overwrite_test extends kv_base_test;
    `uvm_component_utils(kv_overwrite_test)

    function new(string name = "kv_overwrite_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      kv_overwrite_seq seq;
      phase.raise_objection(this);
      seq = kv_overwrite_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
      repeat(30) @(posedge env.agent.drv.vif.clk_i);
      phase.drop_objection(this);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Overflow Test — seq_len saturates at MAX_SEQ_LEN (NEW)
  // -------------------------------------------------------------------------
  class kv_overflow_test extends kv_base_test;
    `uvm_component_utils(kv_overflow_test)

    function new(string name = "kv_overflow_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      kv_overflow_seq seq;
      phase.raise_objection(this);
      seq = kv_overflow_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
      // Allow settling time, then check full_o via monitor
      repeat(20) @(posedge env.agent.drv.vif.clk_i);
      if (!env.agent.drv.vif.drv_cb.full) begin
        `uvm_error("KV_OVF", "full_o not asserted after MAX_SEQ_LEN advances!")
      end else begin
        `uvm_info("KV_OVF", "PASS: full_o asserted correctly after saturation", UVM_LOW)
      end
      phase.drop_objection(this);
    endtask
  endclass

  // -------------------------------------------------------------------------
  // Boundary Test — position 0 and MAX_SEQ_LEN-1 corners (NEW)
  // -------------------------------------------------------------------------
  class kv_boundary_test extends kv_base_test;
    `uvm_component_utils(kv_boundary_test)

    function new(string name = "kv_boundary_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      kv_boundary_seq seq;
      phase.raise_objection(this);
      seq = kv_boundary_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
      repeat(80) @(posedge env.agent.drv.vif.clk_i);
      phase.drop_objection(this);
    endtask
  endclass

endpackage
