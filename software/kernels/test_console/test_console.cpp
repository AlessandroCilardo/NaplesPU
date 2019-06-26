#include <stdint.h>

#ifndef NUPLUS_ACCELERATOR
# include <strings.h>
# include <stdio.h>
#endif

#define CORE_NUMB   1
#define THREAD_NUMB 4

#ifdef NUPLUS_ACCELERATOR
# define CORE_ID    __builtin_nuplus_read_control_reg(0)
# define THREAD_ID  __builtin_nuplus_read_control_reg(2)
#endif

typedef struct {
  uint32_t data;
  uint32_t data_pending;
} __attribute__((packed)) console_mmap;

char out[255];

int main()
{
#ifdef NUPLUS_ACCELERATOR
  if (THREAD_ID != 0)
    return 0;

  volatile console_mmap *c0 = (console_mmap *) 0xFF000000;

  bool leave = false;
  char *ptr = &out[0];

  while (!leave) {
    while (c0->data_pending == 0);

    *ptr = (char) c0->data;
    c0->data = *ptr;

    leave = (*ptr) == 'Z';
    ptr++;
  }

  __builtin_nuplus_flush((int) &out[0]);
  __builtin_nuplus_write_control_reg(16, 12);

  return (int)&out[0];
#else
  // hardcoded result, assuming that the testbench sends "ABCDEFZ" on the console
  printf("1145258561   5916229         0         0         0         0         0         0         0         0         0         0         0         0         0         0\n");

  return 0;
#endif
}
