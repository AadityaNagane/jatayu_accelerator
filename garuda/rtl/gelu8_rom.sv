// GELU8 Lookup Table ROM
// Implements scaled GELU activation for INT8 inputs.
// Input:  Signed INT8 (-128..127)
// Output: Scaled INT8 (0..16)

module gelu8_rom #(
    parameter int unsigned ADDR_WIDTH  = 8,  // 2^8 = 256 entries for full INT8 range
    parameter int unsigned DATA_WIDTH  = 8,  // 8-bit output
    parameter string INIT_FILE         = "data/gelu8_lut.hex"
) (
    input  logic clk_i,
    input  logic [ADDR_WIDTH-1:0] addr_i,  // Address (maps -128..127 to 0..255)
    output logic [DATA_WIDTH-1:0] data_o   // LUT output
);

    // Memory array
    logic [DATA_WIDTH-1:0] rom [0:(1<<ADDR_WIDTH)-1];

    // Initialize from hex file
    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // Combinational read (no pipelining)
    assign data_o = rom[addr_i];

endmodule
