#include "data.h"

#ifndef NPU_ACCELERATOR
    #include <strings.h>
    #include <stdio.h>
#else
    #define CORE_ID    __builtin_npu_read_control_reg(0)
    #define THREAD_ID  __builtin_npu_read_control_reg(2)
#endif

#define LOOP 1

static int C[N][N] __attribute__((aligned(64)))  = {{0}};


void matrix_mult (int mult[N][N], const int a[N][N], const int b[N][N], int core_id, int thread_id);

int main(){

#ifdef NPU_ACCELERATOR
  // start addr = 0x800000, end_addr = 0xFFFFFFFF, valid = 1
  // int mmap = (2 << 11) | (0x3FF << 1) | 1;
  // __builtin_npu_write_control_reg(mmap | (THREAD_ID << 21), 19);
  
  __builtin_npu_barrier(13, CORE_NUMB * THREAD_NUMB - 1);

  for (int i = 0; i < LOOP; i++) {
    //copy matrix in SPM and evaluate results
    int start_loop = (CORE_ID * N / CORE_NUMB) + THREAD_ID;
    int end_loop = N / CORE_NUMB * (CORE_ID + 1);
  
    for (int i = start_loop; i < end_loop; i += THREAD_NUMB)
      for (int j = 0; j < N; j++) {
        As[i][j] = A[i][j];
        Bs[i][j] = B[i][j];
    }

    __builtin_npu_barrier(CORE_ID + 1, THREAD_NUMB - 1);
    
    for (int i = start_loop; i < end_loop; i += THREAD_NUMB)
      for (int j = 0; j < N; j++)
        for (int k = 0; k < N; k++)
          Cs[i][j] += As[i][k] * Bs[k][j];
 
    __builtin_npu_barrier(CORE_ID + 1, THREAD_NUMB - 1);
    
    for (int i = start_loop; i < end_loop; i += THREAD_NUMB)
      for (int j = 0; j < N; j++)
        C[i][j] = Cs[i][j];    
   
    //matrix_copy(Bs, B, CORE_ID, THREAD_ID);
    //matrix_mult_spm(CORE_ID, THREAD_ID);
  }

  __builtin_npu_barrier(100, CORE_NUMB * THREAD_NUMB - 1);

  if (THREAD_ID == 0 && CORE_ID == 0) {
    for (int i = 0; i < N*N; i += 64 / sizeof(int)) {
      __builtin_npu_flush((int) &C[i / N][i % N]);
    }
    __builtin_npu_write_control_reg(N*N, 12); // For cosimulation purpose
  }

  return (int)&C;
#else

  bzero((void *) &C[0][0], N*N*sizeof(int));

  for (int i = 0; i < CORE_NUMB; i++) {
    for (int j = 0; j < THREAD_NUMB; j++) {
      matrix_mult(C, A, B, i, j);
    }
  }
  int pcout = 0;
  for (int i = 0; i < N; i++) {
    for (int j = 0; j < N; j++) {
      printf(" %7d", C[i][j]);
      pcout++;
      if ((pcout) % 16 == 0)
        printf("\n");
    }
  }

  return 0;
#endif
}

/*
#ifdef NPU_ACCELERATOR
void matrix_copy(int a[N][N], const int b[N][N], int core_id, int thread_id) {
  int start_loop = (core_id * N / CORE_NUMB) + thread_id;
  int end_loop = N / CORE_NUMB * (core_id + 1);
  
  for (int i = start_loop; i < end_loop; i += THREAD_NUMB)
    for (int j = 0; j < N; j++)
      for (int k = 0; k < N; k++) {
        a[i][j] = b[i][k];
        //Bs[i][j] = b[i][k];
      }
};

void matrix_mult_spm(int core_id, int thread_id) {
  int start_loop = (core_id * N / CORE_NUMB) + thread_id;
  int end_loop = N / CORE_NUMB * (core_id + 1);
  
  for (int i = start_loop; i < end_loop; i += THREAD_NUMB)
    for (int j = 0; j < N; j++)
      for (int k = 0; k < N; k++)
        Cs[i][j] += As[i][k] * Bs[k][j];
};
#endif
*/

void matrix_mult(int mult[N][N], const int a[N][N], const int b[N][N], int core_id, int thread_id) {
  int start_loop = (core_id * N / CORE_NUMB) + thread_id;
  int end_loop = N / CORE_NUMB * (core_id + 1);
  
  for (int i = start_loop; i < end_loop; i += THREAD_NUMB)
    for (int j = 0; j < N; j++)
      for (int k = 0; k < N; k++)
        mult[i][j] += a[i][k] * b[k][j];
};
