#include <stdint.h>
#include "data.h"

vec16f32 C[N];

extern void kernel_function(vec16f32 *A_VET, vec16f32 *B_VET, vec16f32 *C_VET, int n) ;

int main(){
  vec16f32* A_VET = reinterpret_cast<vec16f32*>(&A); 
	vec16f32* B_VET = reinterpret_cast<vec16f32*>(&B); 
	kernel_function(A_VET, B_VET, C, N);

  return (int)&C;
}


