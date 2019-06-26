#include <stdint.h>
#include "dct_scalar.h"

#ifndef NUPLUS_ACCELERATOR
 #include <strings.h>
 #include <stdio.h>
 #define THREAD_ID    0
 #define CORE_ID      0
 #define THREAD_NUMB  1
 #define CORE_NUMB    1
#else
 #define THREAD_ID  __builtin_nuplus_read_control_reg(2)
 #define CORE_ID    __builtin_nuplus_read_control_reg(0)
#endif

#define bitNumber 8
#define blockSize 8

int clip3(const int a, const int b, int x){
	if (x < a)
		return a;
	else if (x > b)
		return b;
	else
		return x;
}

void multiply(int* A, int* B, int N, int* C){
	for (int i = CORE_ID; i < N; i += CORE_NUMB){
		for (int j = THREAD_ID; j < N; j += THREAD_NUMB){
			for (int k = 0; k < N; k++){
				*(C + (i * N) + j) += *(A + (i * N) + k) * (*(B + (k * N) + j));
			}
		}
	}
}

void multiply(int* A, int16_t* B, int N, int* C){
	for (int i = CORE_ID; i < N; i += CORE_NUMB){
		for (int j = THREAD_ID; j < N; j += THREAD_NUMB){
			for (int k = 0; k < N; k++){
				*(C + (i * N) + j) += *(A + (i * N) + k) * (*(B + (k * N) + j));
			}
		}
	}
}

void forward2DTransform(int* A, int NB, int N, int* C){
	int log2TransformRange = 15;
	int bitDepth = 8;
	int coeffMin = -32768;
	int coeffMax = 32767;
	int M = 3; //log2(N)

	int bdShift = (NB + M - 9);

	static int D[blockSize * blockSize]  __attribute__((aligned(64))) = { 
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		};
	
	static int Z[blockSize * blockSize]  __attribute__((aligned(64))) = { 
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		};
	
	multiply(D8, A, N, D);
#ifdef NUPLUS_ACCELERATOR	
	__builtin_nuplus_barrier(CORE_ID*CORE_NUMB + 10, THREAD_NUMB - 1);
#endif

	for (int i = CORE_ID; i < N; i += CORE_NUMB){
		for (int j = THREAD_ID; j < N; j += THREAD_NUMB){
			*(Z + i * N + j) = clip3(coeffMin, coeffMax, (*(D + i * N + j) + (1 << (bdShift - 1))) >> bdShift);
		}
	}
#ifdef NUPLUS_ACCELERATOR
	__builtin_nuplus_barrier(CORE_ID*CORE_NUMB + 11, THREAD_NUMB - 1);
#endif

	multiply(Z, D8T, N, C);

#ifdef NUPLUS_ACCELERATOR
	__builtin_nuplus_barrier(CORE_ID*CORE_NUMB + 12, THREAD_NUMB - 1);
#endif

	bdShift = M + 6;
	for (int i = CORE_ID; i < N; i += CORE_NUMB){
		for (int j = THREAD_ID; j < N; j += THREAD_NUMB){
			*(C + i * N + j) = clip3(coeffMin, coeffMax, (*(C + i * N + j) + (1 << (bdShift - 1))) >> bdShift);
		}
	}

#ifdef NUPLUS_ACCELERATOR	
	__builtin_nuplus_barrier(CORE_ID*CORE_NUMB + 13, THREAD_NUMB - 1);
#endif
}

int main(){
	static int input[64]  __attribute__((aligned(64))) = {
		-33,-27,-17,-5,-3,-2,-7,-8,
		36,41,23,26,40,63,34,50,
		73,91,70,36,61,118,42,54,
		70,90,58,30,55,80,29,25,
		64,55,12,30,50,3,31,34,
		23,-3,3,19,33,-14,22,32,
		-23,-31,4,-2,3,-5,1,-1,
		-22,-9,-18,-6,-10,-23,-1,-17
		};
		
	static int output[64]  __attribute__((aligned(64))) = { 
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		0, 0, 0, 0, 0, 0, 0, 0,
		};
	
	forward2DTransform(input, bitNumber, blockSize, output);

#ifdef NUPLUS_ACCELERATOR		
	if (THREAD_ID == 0 && CORE_ID == 0) {
		for (int mout_rows = 0; mout_rows < 4; mout_rows++)
      		__builtin_nuplus_flush((int)(&output[mout_rows*16]));
    	__builtin_nuplus_write_control_reg(64, 12); // For cosimulation purpose
	}

	return (int)&output;
#else

	for (int i = 0; i < 8; i++)
  	{
    	for (int j = 0; j < 8; j++)
    	{
      		printf(" %7d", output[i*8+j]);
    	
    	if ((i*8+j+1)%16 == 0) 
			printf("\n");
		}
  	}

  return 0;
#endif
}
