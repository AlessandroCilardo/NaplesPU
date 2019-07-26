/* $Id: crc.c,v 1.2 2005/04/04 11:34:58 csg Exp $ */

/*************************************************************************/
/*                                                                       */
/*   SNU-RT Benchmark Suite for Worst Case Timing Analysis               */
/*   =====================================================               */
/*                              Collected and Modified by S.-S. Lim      */
/*                                           sslim@archi.snu.ac.kr       */
/*                                         Real-Time Research Group      */
/*                                        Seoul National University      */
/*                                                                       */
/*                                                                       */
/*        < Features > - restrictions for our experimental environment   */
/*                                                                       */
/*          1. Completely structured.                                    */
/*               - There are no unconditional jumps.                     */
/*               - There are no exit from loop bodies.                   */
/*                 (There are no 'break' or 'return' in loop bodies)     */
/*          2. No 'switch' statements.                                   */
/*          3. No 'do..while' statements.                                */
/*          4. Expressions are restricted.                               */
/*               - There are no multiple expressions joined by 'or',     */
/*                'and' operations.                                      */
/*          5. No library calls.                                         */
/*               - All the functions needed are implemented in the       */
/*                 source file.                                          */
/*                                                                       */
/*                                                                       */
/*************************************************************************/
/*                                                                       */
/*  FILE: crc.c                                                          */
/*  SOURCE : Numerical Recipes in C - The Second Edition                 */
/*                                                                       */
/*  DESCRIPTION :                                                        */
/*                                                                       */
/*     A demonstration for CRC (Cyclic Redundancy Check) operation.      */
/*     The CRC is manipulated as two functions, icrc1 and icrc.          */
/*     icrc1 is for one character and icrc uses icrc1 for a string.      */
/*     The input string is stored in array lin[].                        */
/*     icrc is called two times, one for X-Modem string CRC and the      */
/*     other for X-Modem packet CRC.                                     */
/*                                                                       */
/*  REMARK :                                                             */
/*                                                                       */
/*  EXECUTION TIME :                                                     */
/*                                                                       */
/*                                                                       */
/*************************************************************************/

#ifndef NPU_ACCELERATOR
    #include <strings.h>
    #include <stdio.h>
#else
    #define CORE_ID    __builtin_npu_read_control_reg(0)
    #define THREAD_ID  __builtin_npu_read_control_reg(2)
#endif

typedef unsigned char uchar;
#define LOBYTE(x) ((uchar)((x) & 0xFF))
#define HIBYTE(x) ((uchar)((x) >> 8))

unsigned char lin[256] = "asdffeagewaHAFEFaeDsFEawFdsFaefaeerdjgp";
int result[16] __attribute__((aligned(64))) = {0};

unsigned short icrc1(unsigned short crc, unsigned char onech)
{
	int i;
	unsigned short ans=(crc^onech << 8);

	for (i=0;i<8;i++) {
		if (ans & 0x8000)
			ans = (ans <<= 1) ^ 4129;
		else
			ans <<= 1;
	}
	return ans;
}

unsigned short icrc(unsigned short crc, unsigned long len,
		    short jinit, int jrev)
{
  unsigned short icrc1(unsigned short crc, unsigned char onech);
  static unsigned short icrctb[256],init=0;
  static uchar rchr[256];
  unsigned short tmp1, tmp2, j,cword=crc;
  static uchar it[16]={0,8,4,12,2,10,6,14,1,9,5,13,3,11,7,15};

  if (!init) {
#ifdef NPU_ACCELERATOR
    // Only Thread 0 of Core 0 initializes data
    if (CORE_ID == 0 && THREAD_ID == 0) {
#endif
    init=1;
    for (j=0;j<=255;j++) {
      icrctb[j]=icrc1(j << 8,(uchar)0);
      rchr[j]=(uchar)(it[j & 0xF] << 4 | it[j >> 4]);
    }
#ifdef NPU_ACCELERATOR
  }
#endif
  }
#ifdef NPU_ACCELERATOR
  // Initialization synchronization barrier
  __builtin_npu_barrier(42, CORE_NUMB - 1);
#endif
  if (jinit >= 0) cword=((uchar) jinit) | (((uchar) jinit) << 8);
  else if (jrev < 0)
    cword=rchr[HIBYTE(cword)] | rchr[LOBYTE(cword)] << 8;
  for (j=1;j<=len;j++) {
    if (jrev < 0) {
      tmp1 = rchr[lin[j]]^ HIBYTE(cword);
    }
    else {
      tmp1 = lin[j]^ HIBYTE(cword);
    }
    cword = icrctb[tmp1] ^ LOBYTE(cword) << 8;
  }
  if (jrev >= 0) {
    tmp2 = cword;
  }
  else {
    tmp2 = rchr[HIBYTE(cword)] | rchr[LOBYTE(cword)] << 8;
  }
  return (tmp2 );
}


int main(void)
{

    unsigned long n;
    unsigned short i1,i2;

#ifdef NPU_ACCELERATOR
    // Each core runs the same code and stores the results in the result vector
    if (THREAD_ID == 0) {
        n=40;
        lin[n+1]=0;
        i1=icrc(0,n,(short)0,1);
        lin[n+1]=HIBYTE(i1);
        lin[n+2]=LOBYTE(i1);
        i2=icrc(i1,n+2,(short)0,1);
        result[CORE_ID * 2] = i2;
        result[CORE_ID * 2 + 1] = i1;
    }
    __builtin_npu_barrier(43, CORE_NUMB * THREAD_NUMB - 1);
#else
    n=40;
    lin[n+1]=0;
    i1=icrc(0,n,(short)0,1);
    lin[n+1]=HIBYTE(i1);
    lin[n+2]=LOBYTE(i1);
    i2=icrc(i1,n+2,(short)0,1);

    // Building expected results
    for (int i = 0; i < CORE_NUMB; i++){
        result[i * 2] = i2;
        result[i * 2 + 1] = i1;
    }
#endif

#ifdef NPU_ACCELERATOR

    if (CORE_ID == 0 && THREAD_ID == 0) {
      __builtin_npu_flush((int) &result[0]);
      __builtin_npu_write_control_reg(16, 12); // For cosimulation purpose
    }

    return (int)&result[0];

#else
    for (int i = 0; i < 16; i++){
        printf("%d ", result[i]);
    }
    printf("\n");

    return 0;

#endif
}

