#include "data.h"

#ifndef NPU_ACCELERATOR
    #include <strings.h>
    #include <stdio.h>
#else
    #define CORE_ID    __builtin_npu_read_control_reg(0)
    #define THREAD_ID  __builtin_npu_read_control_reg(2)
#endif

//#define LOOP 1

static int C[N][N] __attribute__((aligned(64)))  = {{0}}; // destination matrix

void init_matrix(int a[N][N]);
void matrix_mult (int mult[N][N], const int a[N][N], const int b[N][N], int core_id, int thread_id);

int main(){
    init_matrix(A);
    init_matrix(B);
#ifdef NPU_ACCELERATOR
    
    // The NxN matrix multiplication (C = A*B) is spread into N/TILE_DIM sub-operations. Each thread computes
    // TILE_DIM elements of the output matrix C in each iteration (N elements totally). Moreover, in each iteration, 
    // every core loads NxTILE_DIM elements of B matrix, and the requested rows of A matrix into the local SPM. 
    // The partitioning is based on both the running thread and core IDs. 
    // E.g. thread 0 in the core 0 fetches row 0 of matrix A, while thread 1 fetches row 1 and so on. 
    // TILE_DIM have to be equal to N / CORE_NUMB. The total number of executing cores and threads have to be equal
    // to the following formula: CORE_NUMB * THREAD_NUMB = N.
   
  for (unsigned turn = 0; turn < N / TILE_DIM; turn++) {
    unsigned int col0 = turn * TILE_DIM;
    unsigned int tid = THREAD_ID;
    unsigned int row = CORE_ID * TILE_DIM + tid;

    if (THREAD_ID == 0)
      for (unsigned int i = 0; i < N; i++)
        for (unsigned int j = 0; j < TILE_DIM; j++)
          Bs[i][j] = B[i][col0 + j];
 
    __builtin_npu_barrier(CORE_ID + 1, THREAD_NUMB - 1);
    
    for (unsigned int i = 0; i < N; i++)
      As[tid][i] = A[row][i];
   
    int sum = 0;
    for (unsigned int col = 0; col < TILE_DIM; col++) {
      sum = 0; 
      for (unsigned int i = 0; i < N; i++)
        sum += As[tid][i] * Bs[i][col];

      C[row][col + col0] = sum;
    }
  }

  __builtin_npu_barrier(100, CORE_NUMB * THREAD_NUMB - 1); 
  
  if (THREAD_ID == 0 && CORE_ID == 0) {
    for (int i = 0; i < N*N; i += 64 / sizeof(int)) {
      __builtin_npu_flush((int) &C[i / N][i % N]);
    }
    __builtin_npu_write_control_reg(N*N, 12); // For cosimulation purpose
  }

  __builtin_npu_barrier(88, CORE_NUMB * THREAD_NUMB - 1); 

  return (int)&C;
#else
  //CPU part
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

// Matrix multiplication executed by CPU
void matrix_mult(int mult[N][N], const int a[N][N], const int b[N][N], int core_id, int thread_id) {
  int start_loop = (core_id * N / CORE_NUMB) + thread_id;
  int end_loop = N / CORE_NUMB * (core_id + 1);
  
  for (int i = start_loop; i < end_loop; i += THREAD_NUMB)
    for (int j = 0; j < N; j++)
      for (int k = 0; k < N; k++)
        mult[i][j] += a[i][k] * b[k][j];
}

void init_matrix(int a[N][N]){
    for (int i = 0; i < N; i++){
        for (int j = 0; j < N; j++){
            a[i][j] = (i*N + j) % N;
        }
    }
}
