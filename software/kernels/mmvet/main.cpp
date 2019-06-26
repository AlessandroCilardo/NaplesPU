#include <stdint.h>
#include "data.h"

vec16i32 C[N];

extern void kernel_function(vec16i32 *A_VET, vec16i32 *B_VET, vec16i32 *C_VET, int n) ;

int main(){
  vec16i32* A_VET = reinterpret_cast<vec16i32*>(&A); 
	vec16i32* B_VET = reinterpret_cast<vec16i32*>(&B); 
	kernel_function(A_VET, B_VET, C, N);

  return (int)&C;
}


