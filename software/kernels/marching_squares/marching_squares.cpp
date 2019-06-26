#include "data.h"

#ifndef NPU_ACCELERATOR
	#include <strings.h>
	#include <stdio.h>
#else
	#define CORE_ID    __builtin_npu_read_control_reg(0)
	#define THREAD_ID  __builtin_npu_read_control_reg(2)
#endif

static volatile int B[N][M] __attribute__((aligned(64)))  = {{0}};

void marching_squares(const int in[N][M], volatile int out[N][M], int core_id, int thread_id);

int main()
{
#ifdef NPU_ACCELERATOR
  // start addr = 0x800000, end_addr = 0xFFFFFFFF, valid = 1
  // int mmap = (2 << 11) | (0x3FF << 1) | 1;
  // __builtin_npu_write_control_reg(mmap | (THREAD_ID << 21), 19);

  marching_squares(A, B, CORE_ID, THREAD_ID);
  __builtin_npu_barrier(42, CORE_NUMB * THREAD_NUMB - 1);

  if (CORE_ID == 0 && THREAD_ID == 0) {
    for (int i = 0; i < N*M; i += 64 / sizeof(int)) {
      __builtin_npu_flush((int) &B[i / M][i % M]);
    }
    __builtin_npu_write_control_reg(N * M, 12); // For cosimulation purpose
  }
  __builtin_npu_barrier(43, CORE_NUMB * THREAD_NUMB - 1);

  return (int)&B[0][0];
#else
  bzero((void *) &B[0][0], N*M*sizeof(int));

  for (int i = 0; i < CORE_NUMB; i++) {
    for (int j = 0; j < THREAD_NUMB; j++) {
      marching_squares(A, B, i, j);
    }
  }
  
  int pcount = 0;
  for (int i = 0; i < N; i++) {
    for (int j = 0; j < M; j++) {
      if(pcount % 16 == 0)
        printf("\n");
      printf(" %d", B[i][j]);
      pcount++; 
    }
  }

  return 0;
#endif
}

void marching_squares(const int in[N][M], volatile int out[N][M], int core_id, int thread_id)
{
  const int rows_per_core = N / CORE_NUMB;
  int row_start = core_id * rows_per_core;
  int row_end   = core_id < (CORE_NUMB - 1) ? (core_id + 1) * rows_per_core : N;

  for (int i = row_start + thread_id; i < row_end; i += THREAD_NUMB) {
    for (int j = 0; j < M; j++) {
      int sum = 0;

      for (int n = -1; n < 2; n++) {
        for (int m = -1; m < 2; m++) {
          if (i + n > 0 && i + n < N && j + m > 0 && j + m < M) {
            sum += in[i+n][j+m];
          }
        }
      }

      out[i][j] = (sum != 9) && in[i][j];
    }
  }
}
