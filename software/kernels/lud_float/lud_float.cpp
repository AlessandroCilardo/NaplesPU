#include <stdint.h>
#include <math.h>

#define SIZE       16

#ifdef NPU_ACCELERATOR
    #define CORE_ID    __builtin_npu_read_control_reg(0)
    #define THREAD_ID  __builtin_npu_read_control_reg(2)
#else
#include <stdio.h>
    #define CORE_ID    0
    #define THREAD_ID  0
#endif

static float matrixA [SIZE][SIZE] __attribute__((aligned(64))) = {
    {72,    13,    75,    42,    16,    13,    86,    62,    62,    49,    14,    39,    17,    35,    29,    33},
    {52,    69,    24,    88,    86,    67,    61,    66,     3,    53,    16,    13,    66,     5,    13,    29},
    {99,     9,    44,    39,    98,    49,    98,    72,    61,    44,    62,     3,    33,    52,    21,     6},
    {21,    52,    68,    76,    51,    18,    52,    89,    36,    12,    57,    93,    89,    33,    89,    29},
    {10,    53,    35,    39,    88,    49,    47,    98,     4,    49,     5,    30,    11,    17,     7,     4},
    {10,    86,    73,    80,    58,    14,    80,    76,    48,    85,    93,    29,    98,    20,    24,    50},
    { 6,    48,    39,    75,    15,     5,    22,    58,    19,    87,    72,    33,    53,    90,     5,    76},
    {40,    39,    68,    37,    19,    85,    49,    92,    12,    27,    73,    46,    70,    67,    44,    63},
    {44,    67,    70,    21,    40,    56,    90,    58,    20,    20,     6,    64,    99,    46,     1,     8},
    {36,    74,    44,    79,    74,    92,    57,     1,    14,    56,    86,     2,    28,    91,    89,     8},
    {76,    52,     1,    94,    82,    69,    84,    12,    18,    64,    93,    84,    41,    10,    19,    77},
    {62,    34,    33,    32,    78,    58,    73,    86,     4,    41,    98,    55,    46,    74,     9,    90},
    {77,    14,    42,    67,    31,    81,    58,    48,    63,    20,    85,    85,    76,    73,    30,    53},
    {93,    58,    27,    43,    53,    87,    24,    84,    28,    94,    78,    34,    81,    56,    45,    10},
    {97,    26,    19,    83,     8,    98,    66,    20,    53,     8,    51,    44,    10,    18,    10,    82},
    {19,     4,    82,    76,    11,     0,     8,    55,    69,    10,    17,     5,    17,    59,    99,    33},
};

static float matrixU [SIZE][SIZE] __attribute__((aligned(64))) = {
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1}
};

static float matrixL [SIZE][SIZE] __attribute__((aligned(64))) = {
    {1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1}
};

void LUdecomposition() {
   int i = 0, j = 0, k = 0;
   for (i = 0; i < SIZE; i++) {
      for (j = 0; j < SIZE; j++) {
         if (j < i)
         matrixL[j][i] = 0;
         else {
            matrixL[j][i] = matrixA[j][i];
            for (k = 0; k < i; k++) {
               matrixL[j][i] = matrixL[j][i] - matrixL[j][k] * matrixU[k][i];
            }
         }
      }
      for (j = 0; j < SIZE; j++) {
         if (j < i)
            matrixU[i][j] = 0;
         else if (j == i)
            matrixU[i][j] = 1;
         else {
            matrixU[i][j] = matrixA[i][j] / matrixL[i][i];
            for (k = 0; k < i; k++) {
               matrixU[i][j] = matrixU[i][j] - ((matrixL[i][k] * matrixU[k][j]) / matrixL[i][i]);
            }
         }
      }
   }
}

int main () {
    //int mmap = (2 << 11) | (0x3FF << 1) | 1;
    //__builtin_npu_write_control_reg(mmap | (THREAD_ID << 21), 19);
#ifdef NPU_ACCELERATOR
	if(THREAD_ID == 0 && CORE_ID == 0)
    	LUdecomposition();
    __builtin_npu_barrier(42, CORE_NUMB * THREAD_NUMB - 1);
	if(THREAD_ID == 0 && CORE_ID == 0) {
		for (int i = 0; i < SIZE; i++) {
			__builtin_npu_flush((int)&matrixU[i][0]);
			__builtin_npu_flush((int)&matrixL[i][0]);
		}
        __builtin_npu_write_control_reg(SIZE * SIZE * 2, 12); // For cosimulation purpose
    }  
    __builtin_npu_barrier(43, CORE_NUMB * THREAD_NUMB - 1);

    return (int)&matrixL[0][0];
#else
   LUdecomposition();
   int pcount = 0;
   for(int i = 0; i < SIZE; i++){
     for( int j = 0; j < SIZE; j++){
       if (pcount % 16 == 0) 
           printf("\n");
        printf("%8.4f ", matrixL[i][j]);
        pcount++;
      }
    }

    pcount = 0;
    for(int i = 0; i < SIZE; i++){
      for( int j = 0; j < SIZE; j++){
        if (pcount % 16 == 0) 
          printf("\n");
        printf("%8.4f ", matrixU[i][j]);
        pcount++;
      }
    }

   return 0;
#endif
}
