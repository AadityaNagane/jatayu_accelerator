#!/usr/bin/env python3
"""
Generate INT8 GELU lookup table for Garuda accelerator.
 
GELU(x) ≈ 0.5 * x * (1 + tanh(sqrt(2/π) * (x + 0.044715 * x³)))

INT8 domain: -128 to 127
Output scaling: configurable (default S=0.125 = 1/8 for some headroom)

Usage:
    python3 generate_gelu_lut.py > gelu_lut.hex
"""

import math
import sys

def gelu_approx(x):
    """Approximation of GELU function using tanh."""
    cdf = 0.5 * (1.0 + math.tanh(math.sqrt(2.0 / math.pi) * (x + 0.044715 * x**3)))
    return x * cdf

def generate_gelu_lut(scale_factor=0.125, int8_bits=True):
    """
    Generate GELU LUT for INT8 input.
    
    Args:
        scale_factor: Output scale (default 0.125 = 1/8). Lower = more headroom.
        int8_bits: If True, treat inputs as signed INT8 (-128..127).
    
    Returns:
        List of 256 int8 values (or 256 int16 if wider output needed).
    """
    lut = []
    
    for idx in range(256):
        # Map index to input range
        if int8_bits:
            # Signed INT8: idx 0..127 -> x -128..0, idx 128..255 ->  x 0..127
            if idx < 128:
                x = idx - 128
            else:
                x = idx - 128
            # Actually simpler: just treat idx as signed int8
            x = int8_to_signed(idx)
        else:
            x = idx - 128
        
        # Compute GELU (float)
        y_float = gelu_approx(float(x))
        
        # Scale and quantize
        y_scaled = y_float * scale_factor
        y_int = int(round(y_scaled))
        
        # Clamp to INT8 or INT16 range
        y_int = max(-128, min(127, y_int))
        
        lut.append(y_int & 0xFF)  # Mask to 8-bit width for hex output
    
    return lut

def int8_to_signed(val):
    """Convert index/byte to signed int8."""
    if val > 127:
        return val - 256
    return val

def generate_hex_file(lut, entries_per_line=16):
    """Generate hex format suitable for $readmemh."""
    lines = []
    for i in range(0, len(lut), entries_per_line):
        hex_vals = ' '.join(f'{(val & 0xFF):02x}' for val in lut[i:i+entries_per_line])
        lines.append(hex_vals)
    return '\n'.join(lines)

if __name__ == '__main__':
    # Generate LUT with scaling factor S = 0.125 (1/8)
    # This leaves ample headroom: GELU max ≈ 1 * 0.841 ≈ 0.84, scaled by 0.125 = 0.105
    lut = generate_gelu_lut(scale_factor=0.125)
    
    # Print header comment
    print(f"@ Generated GELU8 LUT for Garuda")
    print(f"@ Input: signed INT8 (-128..127)")
    print(f"@ Output: scaled by 0.125 (1/8), quantized to INT8")
    print(f"@ Total entries: 256")
    print()
    
    # Print hex data
    hex_output = generate_hex_file(lut, entries_per_line=16)
    print(hex_output)
    
    # Also print stats to stderr for reference
    print(f"\n\nStats:\n", file=sys.stderr)
    print(f"Min output: {min(lut):3d} (0x{min(lut) & 0xFF:02x})", file=sys.stderr)
    print(f"Max output: {max(lut):3d} (0x{max(lut) & 0xFF:02x})", file=sys.stderr)
    print(f"Example: GELU(0) ≈ {lut[128]:3d}", file=sys.stderr)
    print(f"Example: GELU(64) ≈ {lut[128+64]:3d}", file=sys.stderr)
    print(f"Example: GELU(-64) ≈ {lut[128-64]:3d}", file=sys.stderr)
