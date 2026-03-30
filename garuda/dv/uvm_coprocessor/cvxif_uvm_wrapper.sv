// UVM Coprocessor testbench - proper include order for Verilator
`include "uvm_macros.svh"

import uvm_pkg::*;

`include "garuda/dv/uvm_coprocessor/cvxif_if.sv"
`include "garuda/dv/uvm_coprocessor/cvxif_uvm_pkg.sv"
`include "garuda/dv/uvm_coprocessor/tb_cvxif_uvm_top.sv"
