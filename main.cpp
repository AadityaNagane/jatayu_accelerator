#include "Vtb_systolic_array.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// Global variable for tracking sim time
vluint64_t main_time = 0;

double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // Create module
    Vtb_systolic_array* top = new Vtb_systolic_array;

    // Generate trace file if requested
    VerilatedVcdC* tfp = NULL;
    Verilated::traceEverOn(true);
    tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("trace.vcd");

    // Run simulation for specified number of cycles
    const int MAX_CYCLES = 10000000;  // 10 million cycles max
    while (!Verilated::gotFinish() && main_time < MAX_CYCLES * 10) {
        top->eval();
        if (tfp) tfp->dump(main_time);
        main_time += 10;  // 10 time units per clock cycle (5ns half period)
    }

    // Clean up
    if (tfp) {
        tfp->close();
        delete tfp;
    }
    delete top;
    exit(0);
}
