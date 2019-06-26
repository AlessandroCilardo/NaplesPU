#include <stdint.h>
#include <math.h>
#include "data.h"

#ifndef NPU_ACCELERATOR
     #include <strings.h>
     #include <stdio.h>
#else 
     #define CORE_ID    __builtin_npu_read_control_reg(0)
     #define THREAD_ID  __builtin_npu_read_control_reg(2)
#endif

static int matrix_output[IN_MATR_DIM][IN_MATR_DIM] __attribute__((aligned(64))) = {{0}};

void conv_layer(int matrix_res[IN_MATR_DIM][IN_MATR_DIM], int core_id, int thread_id);

int main () {
#ifdef NPU_ACCELERATOR
#ifdef SCRATCHPAD
    __builtin_npu_barrier(13, THREAD_NUMB - 1);
#endif

    conv_layer(matrix_output, CORE_ID, THREAD_ID);
	__builtin_npu_barrier(42, CORE_NUMB * THREAD_NUMB - 1);
  
    if (THREAD_ID == 0 && CORE_ID == 0)
    {
      for (int i = 0; i <= IN_MATR_DIM; i++)
      { 
        __builtin_npu_flush((int) &matrix_output[i][0]);
      }
      __builtin_npu_write_control_reg(IN_MATR_DIM * IN_MATR_DIM, 12); // For cosimulation purpose
    }
    __builtin_npu_barrier(43, CORE_NUMB * THREAD_NUMB - 1);

    return (int)&matrix_output;
#else
	bzero((void *) &matrix_output[0][0], IN_MATR_DIM*IN_MATR_DIM*sizeof(int));
  
    for (int i = 0; i < CORE_NUMB; i++) {
      for (int j = 0; j < THREAD_NUMB; j++) {
        conv_layer(matrix_output, i, j);
      }
    }
  
    for (int i = 0; i < IN_MATR_DIM; i++) {
      for (int j = 0; j < IN_MATR_DIM; j++) {
        printf(" %7d", matrix_output[i][j]);
        if ((j+1) % 16 == 0)
          printf("\n");
      }
    }
  
    return 0;
#endif
}

void conv_layer(int matrix_res[IN_MATR_DIM][IN_MATR_DIM], int core_id, int thread_id) {
    int row_start = thread_id + core_id * THREAD_NUMB;

    for (int mout_rows = row_start; mout_rows <= OUT_MATR_DIM; mout_rows += (THREAD_NUMB * CORE_NUMB))
        for (int mout_cols = 0; mout_cols <= OUT_MATR_DIM; mout_cols++)
            for (int krows = 0; krows < KERNEL_DIM; krows++)
                for (int kcols = 0; kcols < KERNEL_DIM; kcols++)
                    if (kcols == 0 && krows == 0)
						matrix_res[mout_rows+1][mout_cols+1] = matrix_input[mout_rows + krows][mout_cols + kcols] * kernel_input[krows][kcols];
					else
						matrix_res[mout_rows+1][mout_cols+1] += matrix_input[mout_rows + krows][mout_cols + kcols] * kernel_input[krows][kcols];
}
