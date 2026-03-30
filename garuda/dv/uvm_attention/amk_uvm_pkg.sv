package amk_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int AMK_XLEN = 32;
  localparam int AMK_MAX_K = 256;
  localparam int AMK_WORD_ELEMS = 4;
  localparam int AMK_MAX_WORDS = (AMK_MAX_K + AMK_WORD_ELEMS - 1) / AMK_WORD_ELEMS;
  localparam int AMK_WORD_W = $clog2(AMK_MAX_WORDS);
  localparam int AMK_DONE_TIMEOUT = 2000;

  class amk_seq_item extends uvm_sequence_item;
    rand int unsigned active_words;
    rand logic [31:0] q_words[AMK_MAX_WORDS];
    rand logic [31:0] k_words[AMK_MAX_WORDS];

    rand bit en_scale;
    rand bit en_clip;
    rand logic signed [15:0] scale;
    rand logic [3:0] shift;
    rand logic signed [31:0] clip_min;
    rand logic signed [31:0] clip_max;

    logic signed [31:0] result;

    constraint c_words { active_words inside {[1:AMK_MAX_WORDS]}; }
    constraint c_clip { clip_min <= clip_max; }

    `uvm_object_utils_begin(amk_seq_item)
      `uvm_field_int(active_words, UVM_DEFAULT)
      `uvm_field_int(en_scale, UVM_DEFAULT)
      `uvm_field_int(en_clip, UVM_DEFAULT)
      `uvm_field_int(scale, UVM_DEFAULT)
      `uvm_field_int(shift, UVM_DEFAULT)
      `uvm_field_int(clip_min, UVM_DEFAULT)
      `uvm_field_int(clip_max, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "amk_seq_item");
      super.new(name);
    endfunction
  endclass

  class amk_result_item extends uvm_sequence_item;
    logic signed [31:0] result;

    `uvm_object_utils_begin(amk_result_item)
      `uvm_field_int(result, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "amk_result_item");
      super.new(name);
    endfunction
  endclass

  class amk_sequencer extends uvm_sequencer #(amk_seq_item);
    `uvm_component_utils(amk_sequencer)

    function new(string name = "amk_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class amk_smoke_seq extends uvm_sequence #(amk_seq_item);
    `uvm_object_utils(amk_smoke_seq)

    function new(string name = "amk_smoke_seq");
      super.new(name);
    endfunction

    task body();
      amk_seq_item tr;

      tr = amk_seq_item::type_id::create("smoke_tr");
      start_item(tr);
      tr.active_words = 32; // 128 int8 elems
      tr.en_scale = 0;
      tr.en_clip = 0;
      tr.scale = 16'sd256;
      tr.shift = 0;
      tr.clip_min = -32'sd32768;
      tr.clip_max = 32'sd32767;
      for (int w = 0; w < AMK_MAX_WORDS; w++) begin
        tr.q_words[w] = 32'h0;
        tr.k_words[w] = 32'h0;
      end
      for (int w = 0; w < tr.active_words; w++) begin
        tr.q_words[w][7:0]   = (w + 1);
        tr.q_words[w][15:8]  = (w + 2);
        tr.q_words[w][23:16] = (w + 3);
        tr.q_words[w][31:24] = (w + 4);

        tr.k_words[w][7:0]   = 8'sd1;
        tr.k_words[w][15:8]  = 8'sd1;
        tr.k_words[w][23:16] = 8'sd1;
        tr.k_words[w][31:24] = 8'sd1;
      end
      finish_item(tr);
    endtask
  endclass

  class amk_random_seq extends uvm_sequence #(amk_seq_item);
    `uvm_object_utils(amk_random_seq)

    rand int unsigned num_transactions;
    constraint c_num_transactions { num_transactions inside {[5:20]}; }

    function new(string name = "amk_random_seq");
      super.new(name);
      num_transactions = 10;
    endfunction

    task body();
      amk_seq_item tr;

      for (int t = 0; t < num_transactions; t++) begin
        tr = amk_seq_item::type_id::create($sformatf("rand_tr_%0d", t));
        start_item(tr);
        if (!tr.randomize() with {
          active_words inside {[1:32]};
          en_scale == 0;
          en_clip == 0;
          scale == 16'sd256;
          shift == 0;
          clip_min == -32'sd32768;
          clip_max == 32'sd32767;
        }) begin
          `uvm_fatal("AMK_SEQ", "Randomization failed")
        end
        finish_item(tr);
      end
    endtask
  endclass

  class amk_driver extends uvm_driver #(amk_seq_item);
    `uvm_component_utils(amk_driver)

    virtual amk_if #(AMK_XLEN, AMK_MAX_K, AMK_WORD_ELEMS).drv_mp vif;
    uvm_analysis_port #(amk_seq_item) req_ap;

    function new(string name = "amk_driver", uvm_component parent = null);
      super.new(name, parent);
      req_ap = new("req_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual amk_if #(AMK_XLEN, AMK_MAX_K, AMK_WORD_ELEMS).drv_mp)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for amk_driver")
      end
    endfunction

    task drive_idle();
      vif.drv_cb.cfg_valid_i <= 0;
      vif.drv_cb.cfg_k_i <= '0;
      vif.drv_cb.cfg_scale_i <= '0;
      vif.drv_cb.cfg_shift_i <= '0;
      vif.drv_cb.cfg_clip_min_i <= '0;
      vif.drv_cb.cfg_clip_max_i <= '0;
      vif.drv_cb.cfg_enable_scale_i <= 0;
      vif.drv_cb.cfg_enable_clip_i <= 0;

      vif.drv_cb.load_q_valid_i <= 0;
      vif.drv_cb.load_q_idx_i <= '0;
      vif.drv_cb.load_q_word_i <= '0;
      vif.drv_cb.load_k_valid_i <= 0;
      vif.drv_cb.load_k_idx_i <= '0;
      vif.drv_cb.load_k_word_i <= '0;

      vif.drv_cb.start_i <= 0;
    endtask

    task automatic wait_done();
      int cycles;
      cycles = 0;
      while (vif.drv_cb.done_o !== 1'b1) begin
        @(vif.drv_cb);
        cycles++;
        if (cycles > AMK_DONE_TIMEOUT) begin
          `uvm_fatal("AMK_DRV_TIMEOUT", $sformatf("Timeout waiting done_o after %0d cycles", AMK_DONE_TIMEOUT))
        end
      end
    endtask

    virtual task run_phase(uvm_phase phase);
      amk_seq_item tr;
      amk_seq_item tr_clone;

      drive_idle();
      wait (vif.rst_ni === 1'b1);
      @(vif.drv_cb);

      forever begin
        seq_item_port.get_next_item(tr);

        // Configure
        vif.drv_cb.cfg_valid_i <= 1'b1;
        vif.drv_cb.cfg_k_i <= tr.active_words * AMK_WORD_ELEMS;
        vif.drv_cb.cfg_scale_i <= tr.scale;
        vif.drv_cb.cfg_shift_i <= tr.shift;
        vif.drv_cb.cfg_clip_min_i <= tr.clip_min;
        vif.drv_cb.cfg_clip_max_i <= tr.clip_max;
        vif.drv_cb.cfg_enable_scale_i <= tr.en_scale;
        vif.drv_cb.cfg_enable_clip_i <= tr.en_clip;
        @(vif.drv_cb);
        vif.drv_cb.cfg_valid_i <= 1'b0;

        // Stage operands
        for (int w = 0; w < tr.active_words; w++) begin
          vif.drv_cb.load_q_valid_i <= 1'b1;
          vif.drv_cb.load_q_idx_i <= w[AMK_WORD_W-1:0];
          vif.drv_cb.load_q_word_i <= tr.q_words[w];

          vif.drv_cb.load_k_valid_i <= 1'b1;
          vif.drv_cb.load_k_idx_i <= w[AMK_WORD_W-1:0];
          vif.drv_cb.load_k_word_i <= tr.k_words[w];
          @(vif.drv_cb);
        end
        vif.drv_cb.load_q_valid_i <= 1'b0;
        vif.drv_cb.load_k_valid_i <= 1'b0;

        // Kick execution
        vif.drv_cb.start_i <= 1'b1;
        @(vif.drv_cb);
        vif.drv_cb.start_i <= 1'b0;

        // Publish request for scoreboard expected-modeling
        $cast(tr_clone, tr.clone());
        req_ap.write(tr_clone);

        wait_done();

        seq_item_port.item_done();
      end
    endtask
  endclass

  class amk_monitor extends uvm_component;
    `uvm_component_utils(amk_monitor)

    virtual amk_if #(AMK_XLEN, AMK_MAX_K, AMK_WORD_ELEMS).mon_mp vif;
    uvm_analysis_port #(amk_result_item) rsp_ap;

    function new(string name = "amk_monitor", uvm_component parent = null);
      super.new(name, parent);
      rsp_ap = new("rsp_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual amk_if #(AMK_XLEN, AMK_MAX_K, AMK_WORD_ELEMS).mon_mp)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for amk_monitor")
      end
    endfunction

    task run_phase(uvm_phase phase);
      amk_result_item r;
      wait (vif.rst_ni === 1'b1);

      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.result_valid_o) begin
          r = amk_result_item::type_id::create("rsp");
          r.result = vif.mon_cb.result_o;
          rsp_ap.write(r);
        end
      end
    endtask
  endclass

  class amk_agent extends uvm_agent;
    `uvm_component_utils(amk_agent)

    amk_sequencer seqr;
    amk_driver drv;
    amk_monitor mon;

    function new(string name = "amk_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr = amk_sequencer::type_id::create("seqr", this);
      drv  = amk_driver::type_id::create("drv", this);
      mon  = amk_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  `uvm_analysis_imp_decl(_req)
  `uvm_analysis_imp_decl(_rsp)

  class amk_scoreboard extends uvm_component;
    `uvm_component_utils(amk_scoreboard)

    uvm_analysis_imp_req #(amk_seq_item, amk_scoreboard) req_imp;
    uvm_analysis_imp_rsp #(amk_result_item, amk_scoreboard) rsp_imp;

    int signed expected_q[$];
    int checks_done;
    int mismatch_count;

    function new(string name = "amk_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      req_imp = new("req_imp", this);
      rsp_imp = new("rsp_imp", this);
    endfunction

    function automatic int signed s8(input logic [7:0] b);
      return $signed(b);
    endfunction

    function automatic int signed model_expected(amk_seq_item t);
      longint signed acc;
      longint signed tmp;
      acc = 0;

      for (int w = 0; w < t.active_words; w++) begin
        acc += s8(t.q_words[w][7:0])   * s8(t.k_words[w][7:0]);
        acc += s8(t.q_words[w][15:8])  * s8(t.k_words[w][15:8]);
        acc += s8(t.q_words[w][23:16]) * s8(t.k_words[w][23:16]);
        acc += s8(t.q_words[w][31:24]) * s8(t.k_words[w][31:24]);
      end

      tmp = acc;
      if (t.en_scale) begin
        tmp = (tmp * t.scale) >>> (8 + t.shift);
      end
      if (t.en_clip) begin
        if (tmp > t.clip_max) tmp = t.clip_max;
        else if (tmp < t.clip_min) tmp = t.clip_min;
      end

      return int'(tmp);
    endfunction

    function void write_req(amk_seq_item t);
      expected_q.push_back(model_expected(t));
    endfunction

    function void write_rsp(amk_result_item r);
      int signed exp;
      exp = 0;

      if (expected_q.size() == 0) begin
        mismatch_count++;
        `uvm_error("AMK_SCB", "Received result with empty expected queue")
        return;
      end

      exp = expected_q.pop_front();
      if (r.result !== exp) begin
        mismatch_count++;
        `uvm_error("AMK_SCB", $sformatf("Mismatch: actual=%0d expected=%0d", r.result, exp))
      end else begin
        `uvm_info("AMK_SCB", $sformatf("Match: %0d", r.result), UVM_LOW)
      end
      checks_done++;
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (checks_done == 0) begin
        `uvm_error("AMK_SCB", "No checks were performed")
      end
      if (mismatch_count == 0) begin
        `uvm_info("AMK_SCB", $sformatf("Scoreboard PASS checks=%0d", checks_done), UVM_LOW)
      end
    endfunction
  endclass

  class amk_env extends uvm_env;
    `uvm_component_utils(amk_env)

    amk_agent agent;
    amk_scoreboard scb;

    function new(string name = "amk_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = amk_agent::type_id::create("agent", this);
      scb = amk_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.drv.req_ap.connect(scb.req_imp);
      agent.mon.rsp_ap.connect(scb.rsp_imp);
    endfunction
  endclass

  class amk_base_test extends uvm_test;
    `uvm_component_utils(amk_base_test)

    amk_env env;

    function new(string name = "amk_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = amk_env::type_id::create("env", this);
    endfunction
  endclass

  class amk_smoke_test extends amk_base_test;
    `uvm_component_utils(amk_smoke_test)

    function new(string name = "amk_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      amk_smoke_seq seq;
      phase.raise_objection(this);
      seq = amk_smoke_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
      repeat (50) @(posedge env.agent.drv.vif.clk_i);
      phase.drop_objection(this);
    endtask
  endclass

  class amk_random_test extends amk_base_test;
    `uvm_component_utils(amk_random_test)

    function new(string name = "amk_random_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      amk_random_seq seq;
      phase.raise_objection(this);
      seq = amk_random_seq::type_id::create("seq");
      seq.start(env.agent.seqr);
      repeat (120) @(posedge env.agent.drv.vif.clk_i);
      phase.drop_objection(this);
    endtask
  endclass

endpackage
