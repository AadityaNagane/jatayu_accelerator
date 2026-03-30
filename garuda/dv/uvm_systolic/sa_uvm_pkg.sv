package sa_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam int SA_ROWS = 8;
  localparam int SA_COLS = 8;
  localparam int SA_DW   = 8;
  localparam int SA_AW   = 32;
  localparam int SA_READY_TIMEOUT = 500;

  typedef enum int {SA_OP_CLEAR, SA_OP_WEIGHT, SA_OP_ACT, SA_OP_RESULT} sa_op_e;

  class sa_seq_item extends uvm_sequence_item;
    rand sa_op_e op;
    rand bit start_load_weights;
    rand bit start_execute;
    rand bit signed [SA_DW-1:0] row_data[SA_COLS];
    rand bit signed [SA_DW-1:0] col_data[SA_COLS];
    bit signed [SA_AW-1:0] result_data[SA_ROWS];

    `uvm_object_utils_begin(sa_seq_item)
      `uvm_field_enum(sa_op_e, op, UVM_DEFAULT)
      `uvm_field_int(start_load_weights, UVM_DEFAULT)
      `uvm_field_int(start_execute, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "sa_seq_item");
      super.new(name);
    endfunction
  endclass

  class sa_sequencer extends uvm_sequencer #(sa_seq_item);
    `uvm_component_utils(sa_sequencer)

    function new(string name = "sa_sequencer", uvm_component parent = null);
      super.new(name, parent);
    endfunction
  endclass

  class sa_base_seq extends uvm_sequence #(sa_seq_item);
    bit signed [SA_DW-1:0] matrix_a[SA_ROWS][SA_COLS];
    bit signed [SA_DW-1:0] matrix_b[SA_COLS][SA_ROWS];

    function new(string name = "sa_base_seq");
      super.new(name);
    endfunction

    virtual function void build_matrices();
      foreach (matrix_a[r, c]) matrix_a[r][c] = '0;
      foreach (matrix_b[r, c]) matrix_b[r][c] = '0;
    endfunction

    protected task send_clear();
      sa_seq_item tr;
      tr = sa_seq_item::type_id::create("clr_tr");
      start_item(tr);
      tr.op = SA_OP_CLEAR;
      tr.start_load_weights = 0;
      tr.start_execute = 0;
      finish_item(tr);
    endtask

    protected task send_weights();
      sa_seq_item tr;
      for (int r = 0; r < SA_ROWS; r++) begin
        tr = sa_seq_item::type_id::create($sformatf("w_tr_%0d", r));
        start_item(tr);
        tr.op = SA_OP_WEIGHT;
        tr.start_load_weights = (r == 0);
        tr.start_execute = 0;
        for (int c = 0; c < SA_COLS; c++) tr.row_data[c] = matrix_a[r][c];
        finish_item(tr);
      end
    endtask

    protected task send_activations();
      sa_seq_item tr;
      for (int c = 0; c < SA_COLS; c++) begin
        tr = sa_seq_item::type_id::create($sformatf("a_tr_%0d", c));
        start_item(tr);
        tr.op = SA_OP_ACT;
        tr.start_load_weights = 0;
        tr.start_execute = (c == 0);
        for (int r = 0; r < SA_COLS; r++) tr.col_data[r] = matrix_b[r][c];
        finish_item(tr);
      end
    endtask

    virtual task body();
      build_matrices();
      send_clear();
      send_weights();
      send_activations();
    endtask
  endclass

  class sa_smoke_seq extends sa_base_seq;
    `uvm_object_utils(sa_smoke_seq)

    function new(string name = "sa_smoke_seq");
      super.new(name);
    endfunction

    virtual function void build_matrices();
      foreach (matrix_a[r, c]) matrix_a[r][c] = r + c;
      foreach (matrix_b[r, c]) matrix_b[r][c] = (r == c) ? 8'sd1 : 8'sd0;
    endfunction
  endclass

  class sa_random_seq extends sa_base_seq;
    `uvm_object_utils(sa_random_seq)

    function new(string name = "sa_random_seq");
      super.new(name);
    endfunction

    virtual function void build_matrices();
      foreach (matrix_a[r, c]) begin
        matrix_a[r][c] = $urandom_range(7, 0) - $urandom_range(7, 0);
      end
      foreach (matrix_b[r, c]) begin
        matrix_b[r][c] = $urandom_range(7, 0) - $urandom_range(7, 0);
      end
    endfunction
  endclass

  class sa_driver extends uvm_driver #(sa_seq_item);
    `uvm_component_utils(sa_driver)

    virtual sa_if #(SA_ROWS, SA_COLS, SA_DW, SA_AW).drv_mp vif;

    function new(string name = "sa_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual sa_if #(SA_ROWS, SA_COLS, SA_DW, SA_AW).drv_mp)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for sa_driver")
      end
    endfunction

    task drive_idle();
      vif.drv_cb.weight_valid_i <= 0;
      vif.drv_cb.activation_valid_i <= 0;
      vif.drv_cb.load_weights_i <= 0;
      vif.drv_cb.execute_i <= 0;
      vif.drv_cb.clear_accumulators_i <= 0;
      vif.drv_cb.result_ready_i <= 1;
      vif.drv_cb.weight_row_i <= '0;
      vif.drv_cb.activation_col_i <= '0;
    endtask

    task automatic wait_ready(input bit is_weight_path);
      int cycles;
      cycles = 0;
      while (((is_weight_path) ? vif.drv_cb.weight_ready_o : vif.drv_cb.activation_ready_o) !== 1'b1) begin
        @(vif.drv_cb);
        cycles++;
        if (cycles > SA_READY_TIMEOUT) begin
          `uvm_fatal("SA_DRV_TIMEOUT",
                     $sformatf("Timeout waiting for %s_ready_o after %0d cycles",
                               (is_weight_path ? "weight" : "activation"), SA_READY_TIMEOUT))
        end
      end
    endtask

    virtual task run_phase(uvm_phase phase);
      sa_seq_item tr;

      drive_idle();
      wait (vif.rst_ni === 1'b1);
      @(vif.drv_cb);

      forever begin
        seq_item_port.get_next_item(tr);
        case (tr.op)
          SA_OP_CLEAR: begin
            vif.drv_cb.clear_accumulators_i <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.clear_accumulators_i <= 1'b0;
          end

          SA_OP_WEIGHT: begin
            if (tr.start_load_weights) begin
              vif.drv_cb.load_weights_i <= 1'b1;
              @(vif.drv_cb);
              vif.drv_cb.load_weights_i <= 1'b0;
            end

            wait_ready(1'b1);
            for (int c = 0; c < SA_COLS; c++) begin
              vif.drv_cb.weight_row_i[c*SA_DW +: SA_DW] <= tr.row_data[c];
            end
            vif.drv_cb.weight_valid_i <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.weight_valid_i <= 1'b0;
          end

          SA_OP_ACT: begin
            if (tr.start_execute) begin
              vif.drv_cb.execute_i <= 1'b1;
              @(vif.drv_cb);
              vif.drv_cb.execute_i <= 1'b0;
            end

            wait_ready(1'b0);
            for (int r = 0; r < SA_COLS; r++) begin
              vif.drv_cb.activation_col_i[r*SA_DW +: SA_DW] <= tr.col_data[r];
            end
            vif.drv_cb.activation_valid_i <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.activation_valid_i <= 1'b0;
          end

          default: begin
          end
        endcase

        seq_item_port.item_done();
      end
    endtask
  endclass

  class sa_monitor extends uvm_component;
    `uvm_component_utils(sa_monitor)

    virtual sa_if #(SA_ROWS, SA_COLS, SA_DW, SA_AW).mon_mp vif;
    uvm_analysis_port #(sa_seq_item) req_ap;
    uvm_analysis_port #(sa_seq_item) rsp_ap;

    int weight_hs_count;
    int activation_hs_count;
    int result_hs_count;

    covergroup sa_hs_cg with function sample(bit w_hs, bit a_hs, bit r_hs, bit done_pulse);
      cp_w_hs: coverpoint w_hs;
      cp_a_hs: coverpoint a_hs;
      cp_r_hs: coverpoint r_hs;
      cp_done: coverpoint done_pulse;
      cross_hs: cross cp_w_hs, cp_a_hs, cp_r_hs;
    endgroup

    function new(string name = "sa_monitor", uvm_component parent = null);
      super.new(name, parent);
      req_ap = new("req_ap", this);
      rsp_ap = new("rsp_ap", this);
      sa_hs_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual sa_if #(SA_ROWS, SA_COLS, SA_DW, SA_AW).mon_mp)::get(this, "", "vif", vif)) begin
        `uvm_fatal("NOVIF", "virtual interface not set for sa_monitor")
      end
    endfunction

    virtual task run_phase(uvm_phase phase);
      sa_seq_item tr;
      bit w_hs, a_hs, r_hs;
      wait (vif.rst_ni === 1'b1);

      forever begin
        @(vif.mon_cb);

        w_hs = vif.mon_cb.weight_valid_i && vif.mon_cb.weight_ready_o;
        a_hs = vif.mon_cb.activation_valid_i && vif.mon_cb.activation_ready_o;
        r_hs = vif.mon_cb.result_valid_o && vif.mon_cb.result_ready_i;

        if (w_hs) begin
          weight_hs_count++;
          tr = sa_seq_item::type_id::create("mon_weight_tr");
          tr.op = SA_OP_WEIGHT;
          for (int c = 0; c < SA_COLS; c++) begin
            tr.row_data[c] = $signed(vif.mon_cb.weight_row_i[c*SA_DW +: SA_DW]);
          end
          req_ap.write(tr);
        end

        if (a_hs) begin
          activation_hs_count++;
          tr = sa_seq_item::type_id::create("mon_act_tr");
          tr.op = SA_OP_ACT;
          for (int r = 0; r < SA_COLS; r++) begin
            tr.col_data[r] = $signed(vif.mon_cb.activation_col_i[r*SA_DW +: SA_DW]);
          end
          req_ap.write(tr);
        end

        if (r_hs) begin
          result_hs_count++;
          tr = sa_seq_item::type_id::create("mon_result_tr");
          tr.op = SA_OP_RESULT;
          for (int r = 0; r < SA_ROWS; r++) begin
            tr.result_data[r] = $signed(vif.mon_cb.result_row_o[r*SA_AW +: SA_AW]);
          end
          rsp_ap.write(tr);
        end

        sa_hs_cg.sample(w_hs, a_hs, r_hs, vif.mon_cb.done_o);
      end
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("SA_MON", $sformatf("Handshakes weight=%0d activation=%0d result=%0d",
                                     weight_hs_count, activation_hs_count, result_hs_count), UVM_LOW)
    endfunction
  endclass

  class sa_agent extends uvm_agent;
    `uvm_component_utils(sa_agent)

    sa_sequencer seqr;
    sa_driver    drv;
    sa_monitor   mon;

    function new(string name = "sa_agent", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr = sa_sequencer::type_id::create("seqr", this);
      drv  = sa_driver::type_id::create("drv", this);
      mon  = sa_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  `uvm_analysis_imp_decl(_req)
  `uvm_analysis_imp_decl(_rsp)

  class sa_scoreboard extends uvm_component;
    `uvm_component_utils(sa_scoreboard)

    uvm_analysis_imp_req #(sa_seq_item, sa_scoreboard) req_imp;
    uvm_analysis_imp_rsp #(sa_seq_item, sa_scoreboard) rsp_imp;

    bit signed [SA_DW-1:0] matrix_a[SA_ROWS][SA_COLS];
    bit signed [SA_DW-1:0] matrix_b[SA_COLS][SA_ROWS];
    int w_rows_seen;
    int a_cols_seen;
    int checks_done;
    int mismatch_count;

    function new(string name = "sa_scoreboard", uvm_component parent = null);
      super.new(name, parent);
      req_imp = new("req_imp", this);
      rsp_imp = new("rsp_imp", this);
    endfunction

    function void write_req(sa_seq_item t);
      if (t.op == SA_OP_WEIGHT) begin
        if (w_rows_seen < SA_ROWS) begin
          for (int c = 0; c < SA_COLS; c++) matrix_a[w_rows_seen][c] = t.row_data[c];
          w_rows_seen++;
        end
      end

      if (t.op == SA_OP_ACT) begin
        if (a_cols_seen < SA_COLS) begin
          for (int r = 0; r < SA_COLS; r++) matrix_b[r][a_cols_seen] = t.col_data[r];
          a_cols_seen++;
        end
      end
    endfunction

    function void write_rsp(sa_seq_item t);
      int signed expected;
      int signed actual;

      if (w_rows_seen < SA_ROWS || a_cols_seen < SA_COLS) begin
        mismatch_count++;
        `uvm_error("SA_SCB", $sformatf("Result arrived too early rows=%0d cols=%0d", w_rows_seen, a_cols_seen))
        return;
      end

      for (int r = 0; r < SA_ROWS; r++) begin
        expected = 0;
        for (int k = 0; k < SA_COLS; k++) expected += matrix_a[r][k] * matrix_b[k][0];
        actual = t.result_data[r];

        if (actual !== expected) begin
          mismatch_count++;
          `uvm_error("SA_SCB", $sformatf("Mismatch row=%0d actual=%0d expected=%0d", r, actual, expected))
        end
      end

      checks_done++;
      `uvm_info("SA_SCB", "Checked first output column successfully", UVM_LOW)
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (checks_done == 0) begin
        `uvm_error("SA_SCB", "No result packet checked")
      end
      if (mismatch_count == 0) begin
        `uvm_info("SA_SCB", $sformatf("Scoreboard PASS, checks_done=%0d", checks_done), UVM_LOW)
      end
    endfunction
  endclass

  class sa_env extends uvm_env;
    `uvm_component_utils(sa_env)

    sa_agent      agent;
    sa_scoreboard scb;

    function new(string name = "sa_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = sa_agent::type_id::create("agent", this);
      scb   = sa_scoreboard::type_id::create("scb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      agent.mon.req_ap.connect(scb.req_imp);
      agent.mon.rsp_ap.connect(scb.rsp_imp);
    endfunction
  endclass

  class sa_base_test extends uvm_test;
    `uvm_component_utils(sa_base_test)

    sa_env env;

    function new(string name = "sa_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = sa_env::type_id::create("env", this);
    endfunction
  endclass

  class sa_smoke_test extends sa_base_test;
    `uvm_component_utils(sa_smoke_test)

    function new(string name = "sa_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      sa_smoke_seq seq;
      phase.raise_objection(this);

      seq = sa_smoke_seq::type_id::create("seq");
      seq.start(env.agent.seqr);

      repeat (100) @(posedge env.agent.drv.vif.clk_i);

      phase.drop_objection(this);
    endtask
  endclass

  class sa_random_test extends sa_base_test;
    `uvm_component_utils(sa_random_test)

    function new(string name = "sa_random_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      sa_random_seq seq;
      phase.raise_objection(this);

      seq = sa_random_seq::type_id::create("seq");
      seq.start(env.agent.seqr);

      repeat (120) @(posedge env.agent.drv.vif.clk_i);

      phase.drop_objection(this);
    endtask
  endclass

endpackage
