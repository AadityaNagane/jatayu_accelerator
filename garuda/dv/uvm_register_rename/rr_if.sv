// UVM Interface for register rename table
interface rr_if #(
  parameter int unsigned ARCH_REGS = 32,
  parameter int unsigned PHYS_REGS = 64,
  parameter int unsigned ISSUE_WIDTH = 4
) (
  input logic clk,
  input logic rst_n
);

  localparam int unsigned PHYS_IDX_W = $clog2(PHYS_REGS);
  localparam int unsigned ARCH_IDX_W = 5;

  // Rename port (4 parallel requests)
  logic [ISSUE_WIDTH-1:0] rename_valid;
  logic [ISSUE_WIDTH*ARCH_IDX_W-1:0] arch_rs1;
  logic [ISSUE_WIDTH*ARCH_IDX_W-1:0] arch_rs2;
  logic [ISSUE_WIDTH*ARCH_IDX_W-1:0] arch_rd;
  logic [ISSUE_WIDTH-1:0] rename_ready;
  logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] phys_rs1;
  logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] phys_rs2;
  logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] phys_rd;
  logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] old_phys_rd;

  // Commit port (for free list management)
  logic [ISSUE_WIDTH-1:0] commit_valid;
  logic [ISSUE_WIDTH*PHYS_IDX_W-1:0] commit_phys_rd;
  logic commit_ready;

  // Status
  logic free_list_empty;
  logic [$clog2(PHYS_REGS):0] free_count;

  // Clocking block for TB
  clocking cb @(posedge clk);
    input clk, rst_n;
    output rename_valid, arch_rs1, arch_rs2, arch_rd;
    input rename_ready, phys_rs1, phys_rs2, phys_rd, old_phys_rd;
    output commit_valid, commit_phys_rd;
    input commit_ready, free_list_empty, free_count;
  endclocking

  // Modport for driver
  modport driver (
    clocking cb,
    input rename_ready, phys_rs1, phys_rs2, phys_rd, old_phys_rd,
    input commit_ready, free_list_empty, free_count
  );

  // Modport for monitor
  modport monitor (
    input rename_valid, arch_rs1, arch_rs2, arch_rd, rename_ready,
    input phys_rs1, phys_rs2, phys_rd, old_phys_rd,
    input commit_valid, commit_phys_rd, commit_ready,
    input free_list_empty, free_count,
    input clk, rst_n
  );

  // Modport for DUT
  modport dut (
    input rename_valid, arch_rs1, arch_rs2, arch_rd,
    output rename_ready, phys_rs1, phys_rs2, phys_rd, old_phys_rd,
    input commit_valid, commit_phys_rd,
    output commit_ready, free_list_empty, free_count
  );

endinterface : rr_if
