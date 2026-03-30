// UVM package for DMA engine verification
// NOTE: uvm_pkg is imported and macros included by wrapper

package dma_uvm_pkg;
  // Imports and macros provided by wrapper file
  
  parameter int unsigned DATA_WIDTH = 32;
  parameter int unsigned ADDR_WIDTH = 32;
  parameter int unsigned NUM_LANES = 16;
  parameter int unsigned LANE_WIDTH = 32;

  class dma_seq_item extends uvm_sequence_item;
    `uvm_object_utils(dma_seq_item)

    rand logic [ADDR_WIDTH-1:0] src_addr;
    rand logic [ADDR_WIDTH-1:0] dst_addr;
    rand logic [ADDR_WIDTH-1:0] size;
    
    logic cfg_done;
    logic cfg_error;
    logic [NUM_LANES*LANE_WIDTH-1:0] data_transferred;

    constraint addr_align { src_addr[4:0] == 5'h0; dst_addr[4:0] == 5'h0; }
    constraint size_range { size > 0 && size <= 1024; }

    function new(string name = "dma_seq_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("src=0x%h dst=0x%h size=%0d", src_addr, dst_addr, size);
    endfunction
  endclass

  class dma_driver extends uvm_driver #(dma_seq_item);
    `uvm_component_utils(dma_driver)

    virtual dma_if vif;
    int cycle_count = 0;

    function new(string name = "dma_driver", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual dma_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      dma_seq_item req;
      @(posedge vif.clk);
      @(posedge vif.clk);

      forever begin
        seq_item_port.get_next_item(req);
        
        // Issue DMA command
        vif.cfg_valid <= 1;
        vif.cfg_src_addr <= req.src_addr;
        vif.cfg_dst_addr <= req.dst_addr;
        vif.cfg_size <= req.size;
        @(posedge vif.clk);
        
        // Wait for ready
        while (!vif.cfg_ready) @(posedge vif.clk);
        vif.cfg_start <= 1;
        @(posedge vif.clk);
        vif.cfg_start <= 0;
        vif.cfg_valid <= 0;
        @(posedge vif.clk);
        
        // Wait for done or error
        while (!vif.cfg_done && !vif.cfg_error) @(posedge vif.clk);
        req.cfg_done = vif.cfg_done;
        req.cfg_error = vif.cfg_error;
        
        seq_item_port.item_done(req);
        cycle_count++;
      end
    endtask
  endclass

  class dma_monitor extends uvm_monitor;
    `uvm_component_utils(dma_monitor)

    virtual dma_if vif;
    uvm_analysis_port #(dma_seq_item) ap;

    function new(string name = "dma_monitor", uvm_component parent = null);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(virtual dma_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "Virtual interface not found")
    endfunction

    task run_phase(uvm_run_phase phase);
      dma_seq_item item;
      @(posedge vif.clk);
      @(posedge vif.clk);

      forever begin
        @(posedge vif.clk);
        if (vif.cfg_valid) begin
          item = dma_seq_item::type_id::create("item", this);
          item.src_addr = vif.cfg_src_addr;
          item.dst_addr = vif.cfg_dst_addr;
          item.size = vif.cfg_size;
          ap.write(item);
        end
      end
    endtask
  endclass

  class dma_scoreboard extends uvm_subscriber #(dma_seq_item);
    `uvm_component_utils(dma_scoreboard)

    int transfer_count = 0;
    int error_count = 0;

    function new(string name = "dma_scoreboard", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void write(dma_seq_item t);
      transfer_count++;
      // Basic check: size must be aligned
      if (t.size[4:0] != 0) begin
        `uvm_error("DMA_ALIGN", $sformatf("Size not aligned: %0d", t.size))
        error_count++;
      end
    endfunction

    function void report_phase(uvm_report_phase phase);
      super.report_phase(phase);
      `uvm_info("DMA_SB", $sformatf("Transfers: %0d, Errors: %0d", transfer_count, error_count), UVM_LOW)
    endfunction
  endclass

  class dma_env extends uvm_env;
    `uvm_component_utils(dma_env)

    dma_driver driver;
    dma_monitor monitor;
    dma_scoreboard scoreboard;
    uvm_sequencer #(dma_seq_item) sequencer;

    function new(string name = "dma_env", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      driver = dma_driver::type_id::create("driver", this);
      monitor = dma_monitor::type_id::create("monitor", this);
      scoreboard = dma_scoreboard::type_id::create("scoreboard", this);
      sequencer = uvm_sequencer #(dma_seq_item)::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_connect_phase phase);
      super.connect_phase(phase);
      driver.seq_item_port.connect(sequencer.seq_item_export);
      monitor.ap.connect(scoreboard.analysis_export);
    endfunction
  endclass

  class dma_base_test extends uvm_test;
    `uvm_component_utils(dma_base_test)
    dma_env env;

    function new(string name = "dma_base_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_build_phase phase);
      super.build_phase(phase);
      env = dma_env::type_id::create("env", this);
    endfunction
  endclass

  class dma_smoke_sequence extends uvm_sequence #(dma_seq_item);
    `uvm_object_utils(dma_smoke_sequence)

    function new(string name = "dma_smoke_sequence");
      super.new(name);
    endfunction

    task body();
      dma_seq_item item;
      for (int i = 0; i < 10; i++) begin
        `uvm_create(item)
        item.src_addr = i * 256;
        item.dst_addr = 4096 + i * 256;
        item.size = 256;
        `uvm_send(item)
      end
    endtask
  endclass

  class dma_smoke_test extends dma_base_test;
    `uvm_component_utils(dma_smoke_test)

    function new(string name = "dma_smoke_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_run_phase phase);
      dma_smoke_sequence seq;
      phase.raise_objection(this);
      seq = dma_smoke_sequence::type_id::create("seq", this);
      seq.start(env.sequencer);
      #5000;
      phase.drop_objection(this);
    endtask
  endclass

endpackage : dma_uvm_pkg
