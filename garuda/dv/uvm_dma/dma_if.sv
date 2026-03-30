// UVM Interface for DMA engine

interface dma_if #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned NUM_LANES = 16,
  parameter int unsigned LANE_WIDTH = 32
) (
  input logic clk,
  input logic rst_n
);

  localparam int unsigned CMD_TOTAL_WIDTH = ADDR_WIDTH * 2 + 32 + 1;

  // Config/Control
  logic cfg_valid;
  logic [ADDR_WIDTH-1:0] cfg_src_addr;
  logic [ADDR_WIDTH-1:0] cfg_dst_addr;
  logic [ADDR_WIDTH-1:0] cfg_size;
  logic cfg_start;
  logic cfg_ready;
  logic cfg_done;
  logic cfg_error;

  // AXI4 read
  logic axi_arvalid;
  logic axi_arready;
  logic [ADDR_WIDTH-1:0] axi_araddr;
  logic [7:0] axi_arlen;
  logic [2:0] axi_arsize;
  logic [1:0] axi_arburst;
  
  logic axi_rvalid;
  logic axi_rready;
  logic [DATA_WIDTH-1:0] axi_rdata;
  logic axi_rlast;

  // Data output
  logic data_valid;
  logic [NUM_LANES*LANE_WIDTH-1:0] data;
  logic data_ready;

  // Status
  logic busy;

endinterface : dma_if
