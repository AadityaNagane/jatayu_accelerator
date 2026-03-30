#include "garuda_rtl_backend.h"

#include <array>
#include <cstdint>
#include <cstring>

#include "verilated.h"
#include "Vsystolic_array.h"

static vluint64_t g_main_time = 0;
static Vsystolic_array *g_top = nullptr;

double sc_time_stamp() {
  return static_cast<double>(g_main_time);
}

static inline void tick_once() {
  g_top->clk_i = 0;
  g_top->eval();
  g_main_time++;

  g_top->clk_i = 1;
  g_top->eval();
  g_main_time++;
}

static inline uint64_t pack_row8(const int8_t *vals) {
  uint64_t packed = 0;
  for (int i = 0; i < 8; i++) {
    packed |= (static_cast<uint64_t>(static_cast<uint8_t>(vals[i])) << (8 * i));
  }
  return packed;
}

int garuda_rtl_backend_init(void) {
  if (g_top != nullptr) {
    return 0;
  }

  Verilated::traceEverOn(false);
  g_top = new Vsystolic_array();

  g_top->rst_ni = 0;
  g_top->weight_valid_i = 0;
  g_top->weight_row_i = 0;
  g_top->activation_valid_i = 0;
  g_top->activation_col_i = 0;
  g_top->result_ready_i = 1;
  g_top->load_weights_i = 0;
  g_top->execute_i = 0;
  g_top->clear_accumulators_i = 0;

  for (int i = 0; i < 6; i++) tick_once();
  g_top->rst_ni = 1;
  tick_once();
  return 0;
}

void garuda_rtl_backend_shutdown(void) {
  if (g_top) {
    delete g_top;
    g_top = nullptr;
  }
}

int garuda_rtl_backend_is_ready(void) {
  return (g_top != nullptr) ? 1 : 0;
}

uint64_t garuda_rtl_backend_matmul8_col0(const int8_t *a_8x8,
                                         const int8_t *b_8x8,
                                         int32_t *out_col0_8) {
  if (!g_top) {
    return 0;
  }

  g_top->clear_accumulators_i = 1;
  tick_once();
  g_top->clear_accumulators_i = 0;

  g_top->load_weights_i = 1;
  tick_once();
  g_top->load_weights_i = 0;

  for (int r = 0; r < 8; r++) {
    int guard = 0;
    while (!g_top->weight_ready_o && guard < 512) {
      tick_once();
      guard++;
    }

    g_top->weight_row_i = pack_row8(&a_8x8[r * 8]);
    g_top->weight_valid_i = 1;
    tick_once();
    g_top->weight_valid_i = 0;
    tick_once();
  }

  g_top->execute_i = 1;
  tick_once();
  g_top->execute_i = 0;

  uint64_t start_cycle = g_main_time / 2;

  for (int c = 0; c < 8; c++) {
    int8_t col_vals[8];
    for (int r = 0; r < 8; r++) {
      col_vals[r] = b_8x8[r * 8 + c];
    }

    int guard = 0;
    while (!g_top->activation_ready_o && guard < 512) {
      tick_once();
      guard++;
    }

    g_top->activation_col_i = pack_row8(col_vals);
    g_top->activation_valid_i = 1;
    tick_once();
    g_top->activation_valid_i = 0;
    tick_once();
  }

  int guard = 0;
  while (!g_top->result_valid_o && guard < 1024) {
    tick_once();
    guard++;
  }

  uint64_t end_cycle = g_main_time / 2;

  if (!g_top->result_valid_o) {
    std::memset(out_col0_8, 0, 8 * sizeof(int32_t));
    return 0;
  }

  for (int r = 0; r < 8; r++) {
    out_col0_8[r] = static_cast<int32_t>(g_top->result_row_o[r]);
  }

  return (end_cycle > start_cycle) ? (end_cycle - start_cycle) : 0;
}
