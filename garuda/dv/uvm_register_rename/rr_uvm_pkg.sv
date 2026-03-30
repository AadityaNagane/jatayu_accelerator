// UVM package for register rename table verification

package rr_uvm_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  parameter int unsigned ARCH_REGS = 32;
  parameter int unsigned PHYS_REGS = 64;
  parameter int unsigned ISSUE_WIDTH = 4;
  
  localparam int unsigned PHYS_IDX_W = $clog2(PHYS_REGS);
  localparam int unsigned ARCH_IDX_W = 5;

  // =========== Transaction ===========
  class rr_seq_item extends uvm_sequence_item;
    `uvm_object_utils(rr_seq_item)

    rand logic [ISSUE_WIDTH-1:0] valid;
    rand logic [ISSUE_WIDTH*ARCH_IDX_W-1:0] arch_rs1;
    rand logic [ISSUE_WIDTH*ARCH_IDX_W-1:0] arch_rs2;
    rand logic [ISSUE_WIDTH*ARCH_IDX_W-1:0] arch_rd;
    
    logic [ISSUE_WIDTH-1:0] ready;
    logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] phys_rs1;
    logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] phys_rs2;
    logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] phys_rd;
    logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] old_phys_rd;

    function new(string name = "rr_seq_item");
      super.new(name);
    endfunction

    function string convert2string();
      string s = "";
      int unsigned rs1, rs2, rd;
      for (int i = 0; i < ISSUE_WIDTH; i++) begin
        if (valid[i]) begin
          rs1 = arch_rs1[i*ARCH_IDX_W +: ARCH_IDX_W];
          rs2 = arch_rs2[i*ARCH_IDX_W +: ARCH_IDX_W];
          rd = arch_rd[i*ARCH_IDX_W +: ARCH_IDX_W];
          s = {s, $sformatf("lane%0d(x%0d->x%0d,rs1=x%0d,rs2=x%0d) ", i, rd, phys_rd[i*PHYS_IDX_W +: PHYS_IDX_W], rs1, rs2)};
        end
      end
      return s;
    endfunction
  endclass : rr_seq_item

  // =========== Driver ===========
  class rr_driver extends uvm_driver #(rr_seq_item);
    `uvm_component_utils(rr_driver)

    virtual rr_if vif;
    int cycle_count = 0;

    function new(string name = "rr_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual rr_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      rr_seq_item req;
      @(posedge vif.clk);  // Skip reset
      @(posedge vif.clk);

      forever begin
        seq_item_port.get_next_item(req);
        vif.cb.rename_valid <= req.valid;
        vif.cb.arch_rs1 <= req.arch_rs1;
        vif.cb.arch_rs2 <= req.arch_rs2;
        vif.cb.arch_rd <= req.arch_rd;
        vif.cb.commit_valid <= '0;
        @(vif.cb);
        req.ready = vif.cb.rename_ready;
        req.phys_rs1 = vif.cb.phys_rs1;
        req.phys_rs2 = vif.cb.phys_rs2;
        req.phys_rd = vif.cb.phys_rd;
        req.old_phys_rd = vif.cb.old_phys_rd;
        seq_item_port.item_done(req);
        cycle_count++;
      end
    endtask
  endclass : rr_driver

  // =========== Monitor ===========
  class rr_monitor extends uvm_monitor;
    `uvm_component_utils(rr_monitor)

    virtual rr_if vif;
    uvm_analysis_port #(rr_seq_item) ap;

    function new(string name = "rr_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual rr_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      rr_seq_item item;
      @(posedge vif.clk);
      @(posedge vif.clk);

      forever begin
        @(posedge vif.clk);
        if (vif.rename_valid != 0) begin
          item = rr_seq_item::type_id::create("item", this);
          item.valid = vif.rename_valid;
          item.arch_rs1 = vif.arch_rs1;
          item.arch_rs2 = vif.arch_rs2;
          item.arch_rd = vif.arch_rd;
          item.ready = vif.rename_ready;
          item.phys_rs1 = vif.phys_rs1;
          item.phys_rs2 = vif.phys_rs2;
          item.phys_rd = vif.phys_rd;
          item.old_phys_rd = vif.old_phys_rd;
          ap.write(item);
        end
      end
    endtask
  endclass : rr_monitor

  // =========== Scoreboard ===========
  class rr_scoreboard extends uvm_subscriber #(rr_seq_item);
    `uvm_component_utils(rr_scoreboard)

    rr_seq_item items[$];
    logic [PHYS_IDX_W-1:0] rename_map [ARCH_REGS];
    logic [PHYS_IDX_W-1:0] free_list [$];
    int error_count = 0;
    int check_count = 0;

    function new(string name = "rr_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      // Initialize: all physical regs free
      for (int i = 0; i < PHYS_REGS; i++)
        free_list.push_back(i);
    endfunction

    function void write(rr_seq_item t);
      logic [PHYS_IDX_W-1:0] exp_phys;
      int unsigned arch, exp_old;
      check_count++;

      for (int i = 0; i < ISSUE_WIDTH; i++) begin
        if (t.valid[i]) begin
          arch = t.arch_rd[i*ARCH_IDX_W +: ARCH_IDX_W];
          
          // Check: phys_rd should come from free list
          if (free_list.size() > 0) begin
            exp_phys = free_list[0];
            if (t.phys_rd[i*PHYS_IDX_W +: PHYS_IDX_W] != exp_phys) begin
              `uvm_error("RENAME", $sformatf("Lane %0d: Got phys_rd=%0d, expected %0d", i, 
                t.phys_rd[i*PHYS_IDX_W +: PHYS_IDX_W], exp_phys))
              error_count++;
            end
          end
          
          // Update map
          rename_map[arch] = t.phys_rd[i*PHYS_IDX_W +: PHYS_IDX_W];
        end
      end
    endfunction

    function void report_phase(uvm_report_phase phase);
      super.report_phase(phase);
      `uvm_info("SCOREBOARD", $sformatf("Checks: %0d, Errors: %0d", check_count, error_count), UVM_LOW)
    endfunction
  endclass : rr_scoreboard

  // =========== Environment ===========
  class rr_env extends uvm_env;
    `uvm_component_utils(rr_env)

    rr_driver driver;
    rr_monitor monitor;
    rr_scoreboard scoreboard;
    uvm_sequencer #(rr_seq_item) sequencer;

    function new(string name = "rr_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      driver = rr_driver::type_id::create("driver", this);
      monitor = rr_monitor::type_id::create("monitor", this);
      scoreboard = rr_scoreboard::type_id::create("scoreboard", this);
      sequencer = uvm_sequencer #(rr_seq_item)::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_connect_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass : rr_env

  // =========== Base Test ===========
  class rr_base_test extends uvm_test;
    `uvm_component_utils(rr_base_test)

    rr_env env;

    function new(string name = "rr_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      env = rr_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_end_of_elaboration_phase phase);
      super.end_of_elaboration_phase(phase);
      uvm_root::get().print_topology();
    endfunction
  endclass : rr_base_test

  // =========== Smoke Test ===========
  class rr_smoke_sequence extends uvm_sequence #(rr_seq_item);
    `uvm_object_utils(rr_smoke_sequence)

    function new(string name = "rr_smoke_sequence");
      super.new(name);
    endfunction

    task body();
      rr_seq_item item;
      for (int i = 0; i < 20; i++) begin
        `uvm_create(item)
        item.valid = 4'b0001 << (i % 4);
        item.arch_rd = 5 + (i % 20);
        `uvm_send(item)
      end
    endtask
  endclass : rr_smoke_sequence

  class rr_smoke_test extends rr_base_test;
    `uvm_component_utils(rr_smoke_test)

    function new(string name = "rr_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_run_phase phase);
      rr_smoke_sequence seq;
      phase.raise_objection(this);
      seq = rr_smoke_sequence::type_id::create("seq", this);
      seq.start(env.sequencer);
      #1000;
      phase.drop_objection(this);
    endtask
  endclass : rr_smoke_test

  // =========== Random Test ===========
  class rr_random_sequence extends uvm_sequence #(rr_seq_item);
    `uvm_object_utils(rr_random_sequence)

    function new(string name = "rr_random_sequence");
      super.new(name);
    endfunction

    task body();
      rr_seq_item item;
      for (int i = 0; i < 100; i++) begin
        `uvm_create_on(item, sequencer)
        if (!item.randomize())
          `uvm_fatal("RAND", "Randomization failed")
        `uvm_send(item)
      end
    endtask
  endclass : rr_random_sequence

  class rr_random_test extends rr_base_test;
    `uvm_component_utils(rr_random_test)

    function new(string name = "rr_random_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_run_phase phase);
      rr_random_sequence seq;
      phase.raise_objection(this);
      seq = rr_random_sequence::type_id::create("seq", this);
      seq.start(env.sequencer);
      #2000;
      phase.drop_objection(this);
    endtask
  endclass : rr_random_test

endpackage : rr_uvm_pkg
