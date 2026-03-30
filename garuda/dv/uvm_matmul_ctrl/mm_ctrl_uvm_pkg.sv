// UVM package for matmul control
// NOTE: uvm_pkg is imported and macros included by wrapper

package mm_ctrl_uvm_pkg;
  // Imports and macros provided by wrapper file

  class mm_ctrl_seq_item extends uvm_sequence_item;
    `uvm_object_utils(mm_ctrl_seq_item)

    rand logic [31:0] instr;
    rand logic [7:0] m, n, k;
    
    logic decode_valid;
    logic decode_error;

    constraint instr_range { instr inside {[32'h00000000:32'h0000FFFF]}; }

    function new(string name = "mm_ctrl_seq_item");
      super.new(name);
    endfunction
  endclass

  class mm_ctrl_driver extends uvm_driver #(mm_ctrl_seq_item);
    `uvm_component_utils(mm_ctrl_driver)
    virtual mm_ctrl_if vif;

    function new(string name = "mm_ctrl_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual mm_ctrl_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      mm_ctrl_seq_item req;
      @(posedge vif.clk);
      @(posedge vif.clk);

      forever begin
        seq_item_port.get_next_item(req);
        vif.instr_valid <= 1;
        vif.instr <= req.instr;
        @(posedge vif.clk);
        while (!vif.instr_ready) @(posedge vif.clk);
        vif.instr_valid <= 0;
        @(posedge vif.clk);
        req.decode_valid = vif.decode_valid;
        req.decode_error = vif.decode_error;
        seq_item_port.item_done(req);
      end
    endtask
  endclass

  class mm_ctrl_monitor extends uvm_monitor;
    `uvm_component_utils(mm_ctrl_monitor)
    virtual mm_ctrl_if vif;
    uvm_analysis_port #(mm_ctrl_seq_item) ap;

    function new(string name = "mm_ctrl_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual mm_ctrl_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      mm_ctrl_seq_item item;
      @(posedge vif.clk);
      @(posedge vif.clk);

      forever begin
        @(posedge vif.clk);
        if (vif.instr_valid) begin
          item = mm_ctrl_seq_item::type_id::create("item", this);
          item.instr = vif.instr;
          ap.write(item);
        end
      end
    endtask
  endclass

  class mm_ctrl_scoreboard extends uvm_subscriber #(mm_ctrl_seq_item);
    `uvm_component_utils(mm_ctrl_scoreboard)
    int decode_count = 0;

    function new(string name = "mm_ctrl_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void write(mm_ctrl_seq_item t);
      decode_count++;
    endfunction

    function void report_phase(uvm_report_phase phase);
      super.report_phase(phase);
      `uvm_info("MM_CTRL_SB", $sformatf("Decodes: %0d", decode_count), UVM_LOW)
    endfunction
  endclass

  class mm_ctrl_env extends uvm_env;
    `uvm_component_utils(mm_ctrl_env)
    mm_ctrl_driver driver;
    mm_ctrl_monitor monitor;
    mm_ctrl_scoreboard scoreboard;
    uvm_sequencer #(mm_ctrl_seq_item) sequencer;

    function new(string name = "mm_ctrl_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      driver = mm_ctrl_driver::type_id::create("driver", this);
      monitor = mm_ctrl_monitor::type_id::create("monitor", this);
      scoreboard = mm_ctrl_scoreboard::type_id::create("scoreboard", this);
      sequencer = uvm_sequencer #(mm_ctrl_seq_item)::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_connect_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass

  class mm_ctrl_base_test extends uvm_test;
    `uvm_component_utils(mm_ctrl_base_test)
    mm_ctrl_env env;

    function new(string name = "mm_ctrl_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      env = mm_ctrl_env::type_id::create("env", this);
    endfunction
  endclass

  class mm_ctrl_smoke_sequence extends uvm_sequence #(mm_ctrl_seq_item);
    `uvm_object_utils(mm_ctrl_smoke_sequence)

    function new(string name = "mm_ctrl_smoke_sequence");
      super.new(name);
    endfunction

    task body();
      mm_ctrl_seq_item item;
      for (int i = 0; i < 10; i++) begin
        `uvm_create(item)
        item.instr = 32'h00000000 + i;
        `uvm_send(item)
      end
    endtask
  endclass

  class mm_ctrl_smoke_test extends mm_ctrl_base_test;
    `uvm_component_utils(mm_ctrl_smoke_test)

    function new(string name = "mm_ctrl_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_run_phase phase);
      mm_ctrl_smoke_sequence seq;
      phase.raise_objection(this);
      seq = mm_ctrl_smoke_sequence::type_id::create("seq", this);
      seq.start(env.sequencer);
      #2000;
      phase.drop_objection(this);
    endtask
  endclass

endpackage : mm_ctrl_uvm_pkg
