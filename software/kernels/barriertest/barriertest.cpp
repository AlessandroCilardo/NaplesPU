#ifndef NPU_ACCELERATOR
		#include <strings.h>
		#include <stdio.h>
#else
		#define CORE_ID    __builtin_npu_read_control_reg(0)
		#define THREAD_ID  __builtin_npu_read_control_reg(2)
#endif

#define BARRIER_NUM CORE_NUMB * THREAD_NUMB * 4
#define STEP 4 // stimulate one out of STEP barries, each one STEP times
#define OUTDIM 16 

static int output[OUTDIM] __attribute__((aligned(64))) = {0};

int main()
{
#ifdef NPU_ACCELERATOR 
  for (int j = 0; j < STEP; j ++)
      for (int i = 0; i < BARRIER_NUM; i++) {
          __builtin_npu_barrier(CORE_ID * 100 + i,  THREAD_NUMB - 1);
      }

  if (THREAD_ID == 0 && CORE_ID == 0)
    for(int i = 0; i < OUTDIM; i++)
        output[i] = i;
  
  if (THREAD_ID == 0 && CORE_ID == 0){
      __builtin_npu_flush((int)&output[0]);
      __builtin_npu_write_control_reg(OUTDIM, 12); // For cosimulation purpose
  }

  return (int)&output;

#else

  for(int i = 0; i < OUTDIM; i++)
    output[i] = i;
	  
  for (int i = 0; i < OUTDIM; i++){
      printf("%7d", output[i]);
      if ((i+1) % 16 == 0)
        printf("\n");
  } 
  return 0;
#endif
}
