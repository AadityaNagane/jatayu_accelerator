// UVM DMA testbench - proper include order for Verilator
`include "uvm_macros.svh"

import uvm_pkg::*;

`include "garuda/dv/uvm_dma/dma_if.sv"
`include "garuda/dv/uvm_dma/dma_uvm_pkg.sv"
`include "garuda/dv/uvm_dma/tb_dma_uvm_top.sv"
