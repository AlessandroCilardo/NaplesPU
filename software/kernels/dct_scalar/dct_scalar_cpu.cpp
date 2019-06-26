/*Expected output: 
2854 -6 3 407 2 -411 -8 5 
1632 7 -2 411 -410 -408 414 -407 
-2848 -812 -400 -405 -3 402 -4 -11 
-1640 -407 1 -406 814 411 -399 407 
-822 403 4 2 -2 7 -408 -1 
-402 -6 -401 4 -411 -7 413 -3 
1 4 4 -4 8 3 4 3 
-3 3 11 1 0 -6 9 -1 
*/

#include <stdint.h>
#include <stdio.h>
#include "dct_scalar.h"

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
	for (int i = 0; i < N; i++){
		for (int j = 0; j < N; j++){
			for (int k = 0; k < N; k++){
				*(C + (i * N) + j) += *(A + (i * N) + k) * (*(B + (k * N) + j));
			}
		}
	}
}

void multiply(int* A, int16_t* B, int N, int* C){
	for (int i = 0; i < N; i++){
		for (int j = 0; j < N; j++){
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

	for (int i = 0; i < N; i++){
		for (int j = 0; j < N; j++){
			*(Z + i * N + j) = clip3(coeffMin, coeffMax, (*(D + i * N + j) + (1 << (bdShift - 1))) >> bdShift);
		}
	}
	
	multiply(Z, D8T, N, C);
	bdShift = M + 6;
	for (int i = 0; i < N; i++){
		for (int j = 0; j < N; j++){
			*(C + i * N + j) = clip3(coeffMin, coeffMax, (*(C + i * N + j) + (1 << (bdShift - 1))) >> bdShift);
		}
	}
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
	
	printf("Output: \n");
	for(int i = 0; i < 64; i++){
		printf("%d\t", output[i]);
		if(((i+1) % 8) == 0) 
			printf("\n");
	}
	
	return 0;
}
