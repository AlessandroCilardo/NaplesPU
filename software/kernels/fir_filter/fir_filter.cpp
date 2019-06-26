/* MDH WCET BENCHMARK SUITE. */

/* 2012/09/28, Jan Gustafsson <jan.gustafsson@mdh.se>
 * Changes:
 *  - Adam Betts wrote: I'm currently looking at the fir benchmark and noticed something
 * peculiar. The "in_data" array has 701 elements (effectively 700 as the
 * last elements acts as a sentinel value) and "fir_filter_int" requires
 * the length of the input/output arrays (passed in the " in_len"
 * argument). So I was expecting 700 to be passed as this parameter. Indeed it was,
 * but it has since been changed. The code now contains the following 2
 * lines:
 *
 * //Â Â fir_filter_int(in_data,output,700,fir_int,35,285); Changed JG/Ebbe
 * fir_filter_int(in_data,output,10,fir_int,35,285);
 *
 * Can you explain why the change?
 *
 ***
 *
 * Jan G wrote: Since neither Ebbe nor I can explain the change, I propose to change it back.
 * =>
 * Action: Fixed.
 */


/* Execute the integer fir filter from "C Algorithms for DSP".
 *
 * Adapted for WCET benchmarking by IJAE May 2000.
 *
 * Features: nested variable-length loops.
 *           if-statement with branches taken a known number of times
 *
 * Added explicit sizes of the arrays to work-around a bug in the
 * NIC-compiler. Christer Sandberg
 */
/* #define LOOPS 720 */
#include <stdint.h>
#include "data.h"

#ifndef NUPLUS_ACCELERATOR
#include <stdio.h>
#endif

#define LOOPS 1

// To match size of input
#define OUTSIZE 32//760

static int output[OUTSIZE] __attribute__((aligned(64)));

/*--------------------------------------------------
 *--- Prototypes
 *--------------------------------------------------*/

void fir_filter_int(int* in,int* out,int in_len,
                    int* coef,int coef_len,
                    int scale);


/*--------------------------------------------------
 *--- Main Function
 *--------------------------------------------------*/
int main() {

  fir_filter_int(in_data,output,32,fir_int,35,285); 
  
#ifdef NUPLUS_ACCELERATOR
  for (int i = 0; i < OUTSIZE; i = i + 16)
    __builtin_nuplus_flush((int)(&output[i])); 
  __builtin_nuplus_write_control_reg(OUTSIZE, 12); // For cosimulation purpose
  return (int)(&output[0]);
#else
  for (int i = 0; i < OUTSIZE; i++) {
    printf("%d\t", output[i]);
    if ( ((i + 1) % 16) == 0)
      printf("\n");
  } 
  return 0;
#endif
}

/**************************************************************************
fir_filter_int - Filters int data array based on passed int coefficients.

The length of the input and output arrays are equal
and are allocated by the calller.
The length of the coefficient array is passed.
An integer scale factor (passed) is used to divide the accumulation result.

void fir_filter_int(int *in,int *out,int in_len,
                                  int *coef,int coef_len,int scale)

    in          integer pointer to input array
    out         integer pointer to output array
    in_len      length of input and output arrays
    coef        integer pointer to coefficient array
    coef_len    length of coeffient array
    scale       scale factor to divide after accumulation

No return value.

*************************************************************************/

void fir_filter_int(int* in,int* out,int in_len,
                    int* coef,int coef_len,
                    int scale)
{
  int i,j,coef_len2,acc_length;
  int acc;
  int *in_ptr,*data_ptr,*coef_start,*coef_ptr,*in_end;

  /* set up for coefficients */
  coef_start = coef;
  coef_len2 = (coef_len + 1) >> 1;

  /* set up input data pointers */
  in_end = in + in_len - 1;
  in_ptr = in + coef_len2 - 1;

  /* initial value of accumulation length for startup */
  acc_length = coef_len2;

  for(i = 0 ; i < in_len ; i++) {

    /* set up pointer for accumulation */
    data_ptr = in_ptr;
    coef_ptr = coef_start;

    /* do accumulation and write result with scale factor */

    acc = (*coef_ptr++) * (*data_ptr--);
    for(j = 1 ; j < acc_length ; j++)
      acc += (*coef_ptr++) * (*data_ptr--);
    *out++ = (acc/scale);

    /* check for end case */

    if(in_ptr == in_end) {
      acc_length--;       /* one shorter each time */
      coef_start++;       /* next coefficient each time */
    }

    /* if not at end, then check for startup, add to input pointer */

    else {
      if(acc_length < coef_len) acc_length++;
      in_ptr++;
    }
  }
}
