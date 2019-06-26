#include "data.h"

#ifndef NPU_ACCELERATOR
    #include <strings.h>
    #include <stdio.h>
#else
	#define CORE_ID    __builtin_npu_read_control_reg(0)
	#define THREAD_ID  __builtin_npu_read_control_reg(2)
#endif

static volatile int B[M][N] __attribute__((aligned(64)))  = {{0}};

void matrix_transpose(const int in[N][M], volatile int out[M][N], int core_id, int thread_id);

int main()
{
#ifdef NPU_ACCELERATOR
  // start addr = 0x800000, end_addr = 0xFFFFFFFF, valid = 1
  //int mmap = (2 << 11) | (0x3FF << 1) | 1;
  //__builtin_npu_write_control_reg(mmap | (THREAD_ID << 21), 19);

  matrix_transpose(A, B, CORE_ID, THREAD_ID);

  __builtin_npu_barrier(42, CORE_NUMB * THREAD_NUMB - 1);

  if (THREAD_ID == 0 && CORE_ID == 0) {
    for (int i = 0; i < N*M; i += 64 / sizeof(int)) {
      __builtin_npu_flush((int) &B[i / N][i % N]);
    }
    __builtin_npu_write_control_reg(N*M, 12); // For consimulation purpose
  }
  __builtin_npu_barrier(43, CORE_NUMB * THREAD_NUMB - 1);

  return (int)&B[0][0];
#else
  bzero((void *) &B[0][0], N*M*sizeof(int));

  for (int i = 0; i < CORE_NUMB; i++) {
    for (int j = 0; j < THREAD_NUMB; j++) {
      matrix_transpose(A, B, i, j);
    }
  }
  
  int pcount = 0;
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) {
      if ((pcount % 16) == 0)
        printf("\n");
      printf("%d\t", B[i][j]);
      pcount++;
    }
  }

  return 0;
#endif
}

void matrix_transpose(const int in[N][M], volatile int out[M][N], int core_id, int thread_id)
{
  const int rows_per_core = N / CORE_NUMB;
  int row_start = core_id * rows_per_core;
  int row_end   = core_id < (CORE_NUMB - 1) ? (core_id + 1) * rows_per_core : N;

  for (int i = row_start + thread_id; i < row_end; i += THREAD_NUMB) {
    for (int j = 0; j < M; j++) {
      out[j][i] = in[i][j];
    }
  }
}
