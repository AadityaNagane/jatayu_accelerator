#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>

#include "verilated.h"
#include "Vsystolic_array.h"

static vluint64_t main_time = 0;

double sc_time_stamp() {
  return static_cast<double>(main_time);
}

static inline void tick(Vsystolic_array &top) {
  top.clk_i = 0;
  top.eval();
  main_time++;

  top.clk_i = 1;
  top.eval();
  main_time++;
}

static inline uint64_t pack_vec8(const std::array<int8_t, 8> &v) {
  uint64_t packed = 0;
  for (int i = 0; i < 8; ++i) {
    packed |= (static_cast<uint64_t>(static_cast<uint8_t>(v[i])) << (i * 8));
  }
  return packed;
}

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  Verilated::traceEverOn(false);

  Vsystolic_array top;

  top.rst_ni = 0;
  top.weight_valid_i = 0;
  top.weight_row_i = 0;
  top.activation_valid_i = 0;
  top.activation_col_i = 0;
  top.result_ready_i = 1;
  top.load_weights_i = 0;
  top.execute_i = 0;
  top.clear_accumulators_i = 0;

  for (int i = 0; i < 6; ++i) {
    tick(top);
  }
  top.rst_ni = 1;
  tick(top);

  std::array<std::array<int8_t, 8>, 8> matrix_a{};
  std::array<std::array<int8_t, 8>, 8> matrix_b{};

  for (int r = 0; r < 8; ++r) {
    for (int c = 0; c < 8; ++c) {
      matrix_a[r][c] = static_cast<int8_t>(r + c);
      matrix_b[r][c] = static_cast<int8_t>((r == c) ? 1 : 0);
    }
  }

  top.clear_accumulators_i = 1;
  tick(top);
  top.clear_accumulators_i = 0;

  top.load_weights_i = 1;
  tick(top);
  top.load_weights_i = 0;

  for (int r = 0; r < 8; ++r) {
    int guard = 0;
    while (!top.weight_ready_o && guard < 200) {
      tick(top);
      guard++;
    }
    if (!top.weight_ready_o) {
      std::cerr << "ERROR: weight_ready_o timeout at row " << r << "\n";
      return 2;
    }

    std::array<int8_t, 8> row{};
    for (int c = 0; c < 8; ++c) {
      row[c] = matrix_a[r][c];
    }

    top.weight_row_i = pack_vec8(row);
    top.weight_valid_i = 1;
    tick(top);
    top.weight_valid_i = 0;
    tick(top);
  }

  top.execute_i = 1;
  tick(top);
  top.execute_i = 0;

  uint64_t compute_start = main_time;

  for (int c = 0; c < 8; ++c) {
    int guard = 0;
    while (!top.activation_ready_o && guard < 200) {
      tick(top);
      guard++;
    }
    if (!top.activation_ready_o) {
      std::cerr << "ERROR: activation_ready_o timeout at col " << c << "\n";
      return 3;
    }

    std::array<int8_t, 8> col{};
    for (int r = 0; r < 8; ++r) {
      col[r] = matrix_b[r][c];
    }

    top.activation_col_i = pack_vec8(col);
    top.activation_valid_i = 1;
    tick(top);
    top.activation_valid_i = 0;
    tick(top);
  }

  int wait_cycles = 0;
  while (!top.result_valid_o && wait_cycles < 400) {
    tick(top);
    wait_cycles++;
  }
  if (!top.result_valid_o) {
    std::cerr << "ERROR: result_valid_o timeout\n";
    return 4;
  }

  uint64_t compute_end = main_time;
  uint64_t measured_cycles = (compute_end - compute_start) / 2;

  bool pass = true;
  std::cout << "\n=== Systolic RTL Co-sim Results ===\n";
  for (int r = 0; r < 8; ++r) {
    int32_t expected = 0;
    for (int k = 0; k < 8; ++k) {
      expected += static_cast<int32_t>(matrix_a[r][k]) * static_cast<int32_t>(matrix_b[k][0]);
    }

    int32_t actual = static_cast<int32_t>(top.result_row_o[r]);
    std::cout << "row[" << r << "]: actual=" << actual << " expected=" << expected;
    if (actual == expected) {
      std::cout << "  PASS\n";
    } else {
      std::cout << "  FAIL\n";
      pass = false;
    }
  }

  std::cout << "Measured compute latency (execute->result_valid): " << measured_cycles << " cycles\n";

  if (!pass) {
    std::cerr << "\nCo-sim FAILED\n";
    return 1;
  }

  std::cout << "\nCo-sim PASSED\n";
  return 0;
}
