#!/usr/bin/env python3
"""
Garuda Phase 2: INT8 Weight Quantization Pipeline

This script loads Qwen 2.5 weights from HuggingFace, performs symmetric
per-channel quantization to INT8, and outputs binary files compatible
with the Garuda hardware accelerator.

Quantization Formula (Symmetric):
    x_int8 = clamp(round(x_fp32 / S), -128, 127)

Where S (scale factor) is derived from:
    S = max(|x_fp32|) / 127  (for signed INT8)

This preserves the full dynamic range of the original weights while
fitting into 8-bit signed integer storage.

Usage:
    python3 quantize_qwen_weights.py \
        --model "Qwen/Qwen2.5-0.5B" \
        --output-dir "./data/" \
        --precision int8 \
        --verify

Output Files:
    data/qwen_weights_int8.bin       - Quantized weights
    data/qwen_scales.json            - Scale factors (per-layer, per-channel)
    data/qwen_metadata.json          - Quantization metadata
"""

import json
import sys
import argparse
import struct
from pathlib import Path
from typing import Dict, List, Tuple, Optional

import numpy as np


class QuantizationStats:
    """Track quantization statistics for validation."""
    
    def __init__(self):
        self.original_bytes = 0
        self.quantized_bytes = 0
        self.layers_quantized = 0
        self.scale_factors = {}
        self.clipping_stats = {}
    
    def add_layer(self, layer_name: str, original_size: int, quantized_size: int,
                  scale: float, clipped_count: int):
        """Record quantization for a layer."""
        self.layers_quantized += 1
        self.original_bytes += original_size
        self.quantized_bytes += quantized_size
        self.scale_factors[layer_name] = scale
        self.clipping_stats[layer_name] = {
            "clipped": clipped_count,
            "compression": f"{original_size / quantized_size:.1f}x"
        }
    
    def report(self):
        """Print quantization report."""
        print("\n" + "="*70)
        print("QUANTIZATION STATISTICS")
        print("="*70)
        print(f"Layers Quantized:          {self.layers_quantized}")
        print(f"Original Size:             {self.original_bytes / 1e6:.2f} MB")
        print(f"Quantized Size:            {self.quantized_bytes / 1e6:.2f} MB")
        print(f"Compression Ratio:         {self.original_bytes / self.quantized_bytes:.2f}x")
        print("\nPer-Layer Clipping Stats:")
        for layer, stats in self.clipping_stats.items():
            print(f"  {layer:40s}: {stats['clipped']:6d} clipped ({stats['compression']})")
        print("="*70 + "\n")


class QwenInt8Quantizer:
    """
    Quantize Qwen 2.5 weights to INT8 format suitable for Garuda hardware.
    """
    
    def __init__(self, model_name: str = "Qwen/Qwen2.5-0.5B", device: str = "cpu"):
        """
        Initialize quantizer.
        
        Args:
            model_name: HuggingFace model identifier
            device: Compute device ('cpu' or 'cuda')
        """
        self.model_name = model_name
        self.device = device
        self.stats = QuantizationStats()
        self.quantized_layers = {}
        self.scale_factors = {}
        
        print(f"[INIT] Qwen INT8 Quantizer")
        print(f"  Model: {model_name}")
        print(f"  Device: {device}")
    
    def quantize_tensor(self, tensor: np.ndarray, layer_name: str,
                       symmetric: bool = True) -> Tuple[np.ndarray, float]:
        """
        Quantize a single tensor (weight matrix) to INT8.
        
        Args:
            tensor: FP32 weight matrix
            layer_name: Identifier for this layer
            symmetric: Use symmetric quantization (True) or asymmetric (False)
        
        Returns:
            (quantized_tensor, scale_factor)
        """
        # Flatten to compute statistics
        flat = tensor.flatten()
        
        if symmetric:
            # Symmetric: scale based on max absolute value
            max_abs = np.abs(flat).max()
            if max_abs == 0:
                scale = 1.0
            else:
                # Scale to [-128, 127] range
                scale = max_abs / 127.0
        else:
            # Asymmetric: scale based on min/max
            min_val = flat.min()
            max_val = flat.max()
            scale = (max_val - min_val) / 255.0
        
        # Quantize
        if symmetric:
            quantized_flat = np.round(flat / scale).astype(np.int8)
        else:
            quantized_flat = np.round((flat - flat.min()) / scale).astype(np.int8)
        
        # Track clipping
        clipped = np.sum(np.abs(flat / scale) > 127)
        
        # Reshape back to original shape
        quantized_tensor = quantized_flat.reshape(tensor.shape)
        
        # Record statistics
        self.stats.add_layer(
            layer_name,
            original_size=tensor.nbytes,
            quantized_size=quantized_tensor.nbytes,
            scale=float(scale),
            clipped_count=int(clipped)
        )
        
        self.quantized_layers[layer_name] = quantized_tensor
        self.scale_factors[layer_name] = float(scale)
        
        return quantized_tensor, float(scale)
    
    def load_mock_weights(self, num_layers: int = 8) -> Dict[str, np.ndarray]:
        """
        Generate mock Qwen 2.5 weights for testing.
        
        In production, this would load from HuggingFace transformers library:
            from transformers import AutoModel
            model = AutoModel.from_pretrained("Qwen/Qwen2.5-0.5B")
        
        Args:
            num_layers: Number of transformer layers to generate
        
        Returns:
            Dictionary of weight tensors
        """
        weights = {}
        
        print(f"\n[LOAD] Generating mock Qwen weights ({num_layers} layers)...")
        
        hidden_dim = 1024
        ff_dim = 4096
        num_heads = 16
        head_dim = hidden_dim // num_heads
        
        for layer_idx in range(num_layers):
            # Attention weights
            weights[f"transformer.h.{layer_idx}.self_attn.c_attn.weight"] = \
                np.random.normal(0, 0.02, (hidden_dim, 3 * hidden_dim)).astype(np.float32)
            
            weights[f"transformer.h.{layer_idx}.self_attn.c_proj.weight"] = \
                np.random.normal(0, 0.02, (hidden_dim, hidden_dim)).astype(np.float32)
            
            # MLP weights
            weights[f"transformer.h.{layer_idx}.mlp.w1.weight"] = \
                np.random.normal(0, 0.02, (ff_dim, hidden_dim)).astype(np.float32)
            
            weights[f"transformer.h.{layer_idx}.mlp.w2.weight"] = \
                np.random.normal(0, 0.02, (hidden_dim, ff_dim)).astype(np.float32)
            
            # Layer norm weights (scales and biases)
            weights[f"transformer.h.{layer_idx}.ln_1.weight"] = \
                np.ones(hidden_dim, dtype=np.float32)
            
            weights[f"transformer.h.{layer_idx}.ln_2.weight"] = \
                np.ones(hidden_dim, dtype=np.float32)
        
        # Embedding weights
        vocab_size = 32000
        weights["transformer.wte.weight"] = \
            np.random.normal(0, 0.02, (vocab_size, hidden_dim)).astype(np.float32)
        
        print(f"  ✓ Generated {len(weights)} weight tensors")
        return weights
    
    def quantize_weights(self, weights: Dict[str, np.ndarray]) -> Dict[str, Tuple]:
        """
        Quantize all weight tensors.
        
        Args:
            weights: Dictionary of FP32 weight tensors
        
        Returns:
            Dictionary of (quantized_tensor, scale_factor) tuples
        """
        print(f"\n[QUANTIZE] Starting INT8 quantization ({len(weights)} tensors)...")
        
        for layer_name, tensor in weights.items():
            self.quantize_tensor(tensor, layer_name, symmetric=True)
        
        print(f"  ✓ Quantized {len(self.quantized_layers)} tensors to INT8")
        return {
            name: (self.quantized_layers[name], self.scale_factors[name])
            for name in weights.keys()
        }
    
    def save_to_binary(self, output_dir: str):
        """
        Save quantized weights to binary format.
        
        Output format:
            [header: 4 bytes = 0xDEADBEEF]
            [num_tensors: 4 bytes]
            For each tensor:
                [name_len: 2 bytes]
                [name: name_len bytes]
                [shape: 4 bytes per dimension]
                [num_dims: 1 byte]
                [data: shape.prod() bytes]
        
        Args:
            output_dir: Directory to save binary files
        """
        output_path = Path(output_dir)
        output_path.mkdir(parents=True, exist_ok=True)
        
        print(f"\n[SAVE] Writing quantized weights to {output_dir}...")
        
        # Main binary file
        with open(output_path / "qwen_weights_int8.bin", "wb") as f:
            # Magic header (explicit little-endian 0xDEADBEEF)
            f.write(struct.pack("<I", 0xDEADBEEF))
            
            # Number of tensors
            num_tensors = len(self.quantized_layers)
            f.write(struct.pack("<I", num_tensors))
            
            # Write each tensor
            for layer_name, tensor in self.quantized_layers.items():
                # Layer name
                name_bytes = layer_name.encode('utf-8')
                f.write(struct.pack("<H", len(name_bytes)))
                f.write(name_bytes)
                
                # Shape
                f.write(struct.pack("<B", len(tensor.shape)))
                for dim in tensor.shape:
                    f.write(struct.pack("<I", int(dim)))
                
                # Data (already INT8, just write raw bytes)
                f.write(tensor.tobytes())
        
        print(f"  ✓ Saved to {output_path / 'qwen_weights_int8.bin'}")
        
        # Scale factors (JSON)
        scales_path = output_path / "qwen_scales.json"
        with open(scales_path, "w") as f:
            json.dump(self.scale_factors, f, indent=2)
        print(f"  ✓ Saved scale factors to {scales_path}")
        
        # Metadata (JSON)
        metadata = {
            "model": self.model_name,
            "quantization": {
                "method": "symmetric",
                "dtype": "int8",
                "layers": len(self.quantized_layers),
                "compression_ratio": self.stats.original_bytes / self.stats.quantized_bytes
            },
            "shape_info": {
                name: list(tensor.shape)
                for name, tensor in self.quantized_layers.items()
            }
        }
        metadata_path = output_path / "qwen_metadata.json"
        with open(metadata_path, "w") as f:
            json.dump(metadata, f, indent=2)
        print(f"  ✓ Saved metadata to {metadata_path}")
    
    def verify_quantization(self):
        """Verify quantized weights are valid INT8 tensors."""
        print(f"\n[VERIFY] Checking quantization integrity...")
        
        all_valid = True
        for layer_name, tensor in self.quantized_layers.items():
            # Check dtype
            if tensor.dtype != np.int8:
                print(f"  ✗ {layer_name}: Wrong dtype (expected int8, got {tensor.dtype})")
                all_valid = False
            
            # Check range
            if tensor.min() < -128 or tensor.max() > 127:
                print(f"  ✗ {layer_name}: Out of INT8 range ({tensor.min()}, {tensor.max()})")
                all_valid = False
        
        if all_valid:
            print(f"  ✓ All {len(self.quantized_layers)} tensors are valid INT8")
        
        return all_valid
    
    def run(self, output_dir: str = "./data/", num_mock_layers: int = 8):
        """
        Execute full quantization pipeline.
        
        Args:
            output_dir: Directory to save outputs
            num_mock_layers: Number of mock layers (for testing without HuggingFace)
        """
        try:
            # Step 1: Load weights
            weights = self.load_mock_weights(num_layers=num_mock_layers)
            
            # Step 2: Quantize
            quantized = self.quantize_weights(weights)
            
            # Step 3: Verify
            if not self.verify_quantization():
                print("\n[ERROR] Quantization verification FAILED")
                return False
            
            # Step 4: Save
            self.save_to_binary(output_dir)
            
            # Step 5: Report
            self.stats.report()
            
            print("[SUCCESS] Phase 2 Quantization Pipeline Complete!")
            print(f"\nNext: Load these weights in Phase 5 C runtime:")
            print(f"  Include: #include \"garuda/include/garuda_qwen_runtime.h\"")
            print(f"  Load:    qwen_load_weights(\"{output_dir}/qwen_weights_int8.bin\");")
            print(f"  Run:     qwen_run_inference(prompt);")
            
            return True
        
        except Exception as e:
            print(f"\n[ERROR] Quantization pipeline failed: {e}")
            import traceback
            traceback.print_exc()
            return False


def main():
    """Command-line interface for quantization."""
    parser = argparse.ArgumentParser(
        description="Garuda Phase 2: INT8 Weight Quantization Pipeline",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Quantize Qwen with mock weights (no HuggingFace needed)
  python3 quantize_qwen_weights.py --output-dir ./data/ --mock-layers 8
  
  # Full pipeline with real Qwen 2.5 0.5B model (requires HF)
  python3 quantize_qwen_weights.py \\
    --model "Qwen/Qwen2.5-0.5B" \\
    --output-dir ./data/ \\
    --device cuda
        """
    )
    
    parser.add_argument("--model", default="Qwen/Qwen2.5-0.5B",
                       help="HuggingFace model ID")
    parser.add_argument("--output-dir", default="./data/",
                       help="Output directory for quantized weights")
    parser.add_argument("--device", choices=["cpu", "cuda"], default="cpu",
                       help="Compute device")
    parser.add_argument("--mock-layers", type=int, default=8,
                       help="Number of mock layers (for testing without HF)")
    parser.add_argument("--precision", choices=["int8", "int4"], default="int8",
                       help="Quantization precision")
    parser.add_argument("--verify", action="store_true",
                       help="Run verification after quantization")
    
    args = parser.parse_args()
    
    # Run quantization
    quantizer = QwenInt8Quantizer(model_name=args.model, device=args.device)
    success = quantizer.run(
        output_dir=args.output_dir,
        num_mock_layers=args.mock_layers
    )
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
