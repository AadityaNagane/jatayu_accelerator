// UVM package for INT8 MAC coprocessor
// NOTE: uvm_pkg is imported and macros included by wrapper

package cvxif_uvm_pkg;
  // Imports and macros provided by wrapper file

  class cvxif_seq_item extends uvm_sequence_item;
    `uvm_object_utils(cvxif_seq_item)

    rand logic [31:0] instr;
    rand logic [4:0] rd;
    
    logic result_valid;
    logic [31:0] result;

    function new(string name = "cvxif_seq_item");
      super.new(name);
    endfunction
  endclass

  class cvxif_driver extends uvm_driver #(cvxif_seq_item);
    `uvm_component_utils(cvxif_driver)
    virtual cvxif_if vif;
    int cycle_count = 0;

    function new(string name = "cvxif_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual cvxif_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      cvxif_seq_item req;
      @(posedge vif.clk);
      @(posedge vif.clk);

      forever begin
        seq_item_port.get_next_item(req);
        vif.issue_valid <= 1;
        vif.issue_instr <= req.instr;
        vif.issue_rd <= req.rd;
        @(posedge vif.clk);
        while (!vif.issue_ready) @(posedge vif.clk);
        vif.issue_valid <= 0;
        @(posedge vif.clk);
        while (!vif.result_valid) @(posedge vif.clk);
        req.result = vif.result;
        seq_item_port.item_done(req);
      end
    endtask
  endclass

  class cvxif_monitor extends uvm_monitor;
    `uvm_component_utils(cvxif_monitor)
    virtual cvxif_if vif;
    uvm_analysis_port #(cvxif_seq_item) ap;

    function new(string name = "cvxif_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual cvxif_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      cvxif_seq_item item;
      @(posedge vif.clk);
      @(posedge vif.clk);

      forever begin
        @(posedge vif.clk);
        if (vif.issue_valid)  begin
          item = cvxif_seq_item::type_id::create("item", this);
          item.instr = vif.issue_instr;
          item.rd = vif.issue_rd;
          ap.write(item);
        end
      end
    endtask
  endclass

  class cvxif_scoreboard extends uvm_subscriber #(cvxif_seq_item);
    `uvm_component_utils(cvxif_scoreboard)
    int instr_count = 0;

    function new(string name = "cvxif_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void write(cvxif_seq_item t);
      instr_count++;
    endfunction

    function void report_phase(uvm_report_phase phase);
      super.report_phase(phase);
      `uvm_info("CVXIF_SB", $sformatf("Instructions: %0d", instr_count), UVM_LOW)
    endfunction
  endclass

  class cvxif_env extends uvm_env;
    `uvm_component_utils(cvxif_env)
    cvxif_driver driver;
    cvxif_monitor monitor;
    cvxif_scoreboard scoreboard;
    uvm_sequencer #(cvxif_seq_item) sequencer;

    function new(string name = "cvxif_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      driver = cvxif_driver::type_id::create("driver", this);
      monitor = cvxif_monitor::type_id::create("monitor", this);
      scoreboard = cvxif_scoreboard::type_id::create("scoreboard", this);
      sequencer = uvm_sequencer #(cvxif_seq_item)::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_connect_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass

  class cvxif_base_test extends uvm_test;
    `uvm_component_utils(cvxif_base_test)
    cvxif_env env;

    function new(string name = "cvxif_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      env = cvxif_env::type_id::create("env", this);
    endfunction
  endclass

  class cvxif_smoke_sequence extends uvm_sequence #(cvxif_seq_item);
    `uvm_object_utils(cvxif_smoke_sequence)

    function new(string name = "cvxif_smoke_sequence");
      super.new(name);
    endfunction

    task body();
      cvxif_seq_item item;
      for (int i = 0; i < 10; i++) begin
        `uvm_create(item)
        item.instr = 32'h00000000 + (i << 8);
        item.rd = i % 8;
        `uvm_send(item)
      end
    endtask
  endclass

  class cvxif_smoke_test extends cvxif_base_test;
    `uvm_component_utils(cvxif_smoke_test)

    function new(string name = "cvxif_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_run_phase phase);
      cvxif_smoke_sequence seq;
      phase.raise_objection(this);
      seq = cvxif_smoke_sequence::type_id::create("seq", this);
      seq.start(env.sequencer);
      #5000;
      phase.drop_objection(this);
    endtask
  endclass

endpackage : cvxif_uvm_pkg
