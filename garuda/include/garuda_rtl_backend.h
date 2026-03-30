#ifndef GARUDA_RTL_BACKEND_H
#define GARUDA_RTL_BACKEND_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int garuda_rtl_backend_init(void);
void garuda_rtl_backend_shutdown(void);
int garuda_rtl_backend_is_ready(void);

/*
 * Run one 8x8 matmul on RTL systolic array and return first output column.
 * Inputs are row-major signed INT8 matrices A and B, both 8x8.
 * out_col0_8 receives C[0..7][0]. Returns measured cycles for execute->result_valid.
 */
uint64_t garuda_rtl_backend_matmul8_col0(const int8_t *a_8x8,
                                         const int8_t *b_8x8,
                                         int32_t *out_col0_8);

#ifdef __cplusplus
}
#endif

#endif
