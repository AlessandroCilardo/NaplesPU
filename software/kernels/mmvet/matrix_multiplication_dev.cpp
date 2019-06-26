/* 
 *
 * Test application. This application will
 * launch a kernel in nu+. The kernel will just
 * compute a square matrix multiplication.
 * The size of the matrix and the matrices pointers  
 * will be passed as parameters. The size of the  
 * matrix must be multiple of 16. The multiplication
 * will be computed in a SIMD multithreading fashion.
 *
 * After executing the kernel, the application shows
 * the resulting output matrix
 *
*/
#include <stdint.h>

#define CORE_NUMB 8

void kernel_function(vec16i32 *A, vec16i32 *B, vec16i32 *C, int N) {
	
	uint32_t coreId =  __builtin_nuplus_read_control_reg(0);
	uint32_t threadId = __builtin_nuplus_read_control_reg(2);
	static uint32_t nT = 2; // number of threads
	static uint32_t nL = 16; // number of lanes
	uint32_t nC = N/nL; 
  	uint32_t ndivnT = N/nT;
  	uint32_t tIdndivnT = threadId*ndivnT;
  	uint32_t tIdndivnTnC = tIdndivnT*nC;
	
	//if(coreId == 0){
		for (uint32_t i = coreId; i < ndivnT*nC; i+=CORE_NUMB){
			uint32_t col = (tIdndivnT+i)%nC;
			C[tIdndivnTnC+i] = 0;
			for (uint32_t j = 0; j < nC; j++){
				for (uint32_t k = 0; k < nL; k++){
					C[tIdndivnTnC+i] += A[tIdndivnTnC+i-col+j][k] * B[(nC*k)+(j*N)+col]; 
				}
			}
			__builtin_nuplus_flush((int)&C[tIdndivnTnC+i]);
		}
		__builtin_nuplus_barrier(coreId + 1, nT - 1);
	//}
}
