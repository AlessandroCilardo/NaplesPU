#include <math.h>
#include <stdint.h>
#include "data.h"

#ifndef NPU_ACCELERATOR
    #include <strings.h>
    #include <stdio.h>
#else
    #define CORE_ID __builtin_npu_read_control_reg(0)
    #define THREAD_ID __builtin_npu_read_control_reg(2)
#endif

#ifdef NPU_ACCELERATOR
static vec16i32 matrix_output[IN_MATR_DIM * ROW_LENGTH] = {{0}};
void conv_layer(vec16i32 *matrix_input, int kernel_input[KERNEL_DIM][KERNEL_DIM], vec16i32 *matrix_output, int core_id, int thread_id);
void vect_rows_shift(vec16i32 *matrix_output);
#else
static int matrix_output[IN_MATR_DIM][IN_MATR_DIM] __attribute__((aligned(64))) = {{0}};
void conv_layer(int matrix_in[IN_MATR_DIM][IN_MATR_DIM], int kernel[KERNEL_DIM][KERNEL_DIM], int matrix_out[IN_MATR_DIM][IN_MATR_DIM], int core_id, int thread_id);
#endif

int main()
{

#ifdef NPU_ACCELERATOR

#ifdef SCRATCHPAD
  __builtin_npu_barrier(1, THREAD_NUMB - 1);
#endif

  conv_layer(matrix_input, kernel_input, matrix_output, CORE_ID, THREAD_ID);
  __builtin_npu_barrier(42, CORE_NUMB * THREAD_NUMB - 1);

  vec16i32 shift_coeff_out = {15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};

  if (THREAD_ID == 0 && CORE_ID == 0)
  {
    for (int mout_cols = 0; mout_cols < IN_MATR_DIM; mout_cols++)
    {
      for (int mout_rows = 0; mout_rows < IN_MATR_DIM; mout_rows++)
      {
        if (mout_cols > OUT_MATR_DIM)
          matrix_output[mout_rows][mout_cols] = 0;
      }
    }

    for (int mout_cols = 0; mout_cols < IN_MATR_DIM; mout_cols++)
      matrix_output[mout_cols] = __builtin_npu_shufflei32(matrix_output[mout_cols], shift_coeff_out);

    vect_rows_shift(matrix_output);

    for (int mout_rows = 0; mout_rows < IN_MATR_DIM; mout_rows++)
      __builtin_npu_flush((int)(&matrix_output[mout_rows]));
    __builtin_npu_write_control_reg(IN_MATR_DIM * IN_MATR_DIM, 12); // For cosimulation purpose
  }
  __builtin_npu_barrier(43, CORE_NUMB * THREAD_NUMB - 1);

  return (int)&matrix_output;
#else
  bzero((void *)&matrix_output[0][0], OUT_MATR_DIM * OUT_MATR_DIM * sizeof(int));

  for (int i = 0; i < CORE_NUMB; i++)
  {
    for (int j = 0; j < THREAD_NUMB; j++)
    {
      conv_layer(matrix_input, kernel_input, matrix_output, i, j);
    }
  }

  int pcout = 0;

  for (int i = 0; i < IN_MATR_DIM; i++)
  {
    for (int j = 0; j < IN_MATR_DIM; j++)
    {
      printf(" %7d", matrix_output[i][j]);
      pcout++;
    }
    if ((pcout % 16) == 0) 
        printf("\n");
  }

  return 0;
#endif
}

#ifdef NPU_ACCELERATOR
void conv_layer(vec16i32 *matrix_input, int kernel_input[KERNEL_DIM][KERNEL_DIM], vec16i32 *matrix_output, int core_id, int thread_id)
{
  volatile uint32_t i = 15;
  volatile vec16i32 shifted_row = 0;
  vec16i32 shift_coeff = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0};

  for (int mout_rows =  (thread_id + core_id * THREAD_NUMB) * ROW_LENGTH; mout_rows <= OUT_MATR_DIM * ROW_LENGTH; mout_rows += (ROW_LENGTH * THREAD_NUMB * CORE_NUMB))
  {
    for (int hrow = 0; hrow < ROW_LENGTH; hrow++)
      for (int krows = 0; krows < KERNEL_DIM; krows++)
      {
        shifted_row = matrix_input[mout_rows + krows * ROW_LENGTH + hrow];
        for (int kcols = 0; kcols < KERNEL_DIM; kcols++)
        {
          matrix_output[mout_rows + hrow] += shifted_row * kernel_input[krows][kcols];
          shifted_row = __builtin_npu_shufflei32(shifted_row, shift_coeff);
          shifted_row[i] = matrix_input[mout_rows + krows * ROW_LENGTH + hrow + 1][kcols];
        }
      }
  }
}

void vect_rows_shift(vec16i32 *matrix_output)
{
  vec16i32 tmp = matrix_output[0], tmp1 = matrix_output[IN_MATR_DIM-1];

  matrix_output[0] = tmp1;

  for (int mout_rows = 0; mout_rows <= IN_MATR_DIM; mout_rows++)
  {
    tmp1 = matrix_output[mout_rows+1];
    matrix_output[mout_rows+1] = tmp;
    tmp = tmp1;
  }
}

#else
void conv_layer(int matrix_in[IN_MATR_DIM][IN_MATR_DIM], int kernel[KERNEL_DIM][KERNEL_DIM], int matrix_out[IN_MATR_DIM][IN_MATR_DIM], int core_id, int thread_id)
{
  const int rows_per_core = IN_MATR_DIM / CORE_NUMB;
  int row_start = core_id != 0 ? core_id * rows_per_core : HALF_KERNEL_DIM;
  int row_end = core_id < (CORE_NUMB - 1) ? (core_id + 1) * rows_per_core : IN_MATR_DIM - HALF_KERNEL_DIM;

  for (int mout_rows = row_start + thread_id; mout_rows < row_end; mout_rows += THREAD_NUMB)
  {
    for (int mout_cols = HALF_KERNEL_DIM; mout_cols < IN_MATR_DIM - HALF_KERNEL_DIM; mout_cols++)
    {
      for (int krows = 0; krows < KERNEL_DIM; krows++)
      {
        for (int kcols = 0; kcols < KERNEL_DIM; kcols++)
        {
          if (krows == 0 && kcols == 0)
          {
            matrix_out[mout_rows][mout_cols] = matrix_in[mout_rows + krows - HALF_KERNEL_DIM][mout_cols + kcols - HALF_KERNEL_DIM] * kernel[krows][kcols];
          }
          else
          {
            matrix_out[mout_rows][mout_cols] += matrix_in[mout_rows + krows - HALF_KERNEL_DIM][mout_cols + kcols - HALF_KERNEL_DIM] * kernel[krows][kcols];
          }
        }
      }
    }
  }
}
#endif
