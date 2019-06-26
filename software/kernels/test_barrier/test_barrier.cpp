#ifndef NUPLUS_ACCELERATOR
#include <strings.h>
#include <stdio.h>

#else

#define CORE_ID    __builtin_nuplus_read_control_reg(0)
#define THREAD_ID  __builtin_nuplus_read_control_reg(2)

#endif

#define CORE_NUMB   1 
#define THREAD_NUMB 4

#define BARRIER_NUM CORE_NUMB * THREAD_NUMB * 4
#define STEP 4 // stimulate one out of STEP barries, each one STEP times

static int output[BARRIER_NUM] __attribute__((aligned(64))) = {0};

int main()
{
#ifdef NUPLUS_ACCELERATOR 
  for (int j = 0; j < STEP; j ++)
	  for (int i = 0; i < BARRIER_NUM; i++) {
	      __builtin_nuplus_barrier(i, CORE_NUMB * THREAD_NUMB - 1);

	      if(THREAD_ID == 0)
		output[i] += 1;
	  }

  if (THREAD_ID == 0){
      for (int i = 0; i < BARRIER_NUM; i += 16)
          __builtin_nuplus_flush((int)&output[i]);

      __builtin_nuplus_write_control_reg(BARRIER_NUM, 12); // For cosimulation purpose
  }

  return (int)&output;

#else
  for (int j = 0; j < STEP; j++)
	  for (int i = 0; i < BARRIER_NUM; i++)
	      output[i] += 1;
	  
  for (int i = 0; i < BARRIER_NUM; i++){
      printf("%7d", output[i]);
      if ((i+1) % 16 == 0)
        printf("\n");
  } 
  return 0;
#endif
}
