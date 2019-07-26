#include <stdint.h>

#ifndef NPU_ACCELERATOR
    #include <stdio.h>
    typedef int vector_t [16];
    typedef float fvector_t [16];
#else
    #define CORE_ID    __builtin_npu_read_control_reg(0)
    #define THREAD_ID  __builtin_npu_read_control_reg(2)
    typedef vec16i32 vector_t;
    typedef vec16f32 fvector_t;
#endif

#define LOOP      100
#define DEBUG_REG 8
#define VECDIM    16
#define OUTDIM    VECDIM * 6

static int Seed = 0;
static int result[OUTDIM] __attribute__((aligned(64))) = {0};

int RandomInteger(void);

int main(){
    vector_t shuffle_pos = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0};
    fvector_t fvet = {1.1, 2.2, 3.3, 4.4, 5.5, 6.6, 7.7, 8.8, 9.9, 10.1, 11.1, 12.2, 13.3, 14.4, 15.5, 16.6};
    vector_t vet1;
    vector_t vet2;
    volatile vector_t vet3 = {0};
    vector_t vet_cast = {0};
    int mask_gt = 0;
    int mask_ge = 0;
    int mask_lt = 0;
    int mask_le = 0;
    int mask_sgt = 0;
    int mask_sge = 0;
    int mask_slt = 0;
    int mask_sle = 0;
    int mask_eq = 0;
    int mask_ne = 0;
    int cntr_reg_value[8] = {0};
    int a = 11;

#ifdef NPU_ACCELERATOR

    if (CORE_ID == 0 && THREAD_ID == 0) {
#endif
    for (int i = 0; i < VECDIM; i++){
        vet1[i] = RandomInteger();
    }

#ifdef NPU_ACCELERATOR
    // Rearranging vet1 using shuffle builtin
    for(int j = 0; j < LOOP; j++)
        vet1 = __builtin_npu_shufflei32(vet1, shuffle_pos);

    // Creating a vector using variable a
    for(int j = 0; j < LOOP; j++)
        vet2 = __builtin_npu_makevectori32(a);

    // Testing compare builtins for vectors
    for(int j = 0; j < LOOP; j++){
        mask_gt = __builtin_npu_mask_cmpi32_ugt(vet2, shuffle_pos);
        mask_ge = __builtin_npu_mask_cmpi32_uge(vet2, shuffle_pos);
        mask_lt = __builtin_npu_mask_cmpi32_ult(vet2, shuffle_pos);
        mask_le = __builtin_npu_mask_cmpi32_ule(vet2, shuffle_pos);
        mask_sgt = __builtin_npu_mask_cmpi32_sgt(vet2, shuffle_pos);
        mask_sge = __builtin_npu_mask_cmpi32_sge(vet2, shuffle_pos);
        mask_slt = __builtin_npu_mask_cmpi32_slt(vet2, shuffle_pos);
        mask_sle = __builtin_npu_mask_cmpi32_sle(vet2, shuffle_pos);
        mask_eq = __builtin_npu_mask_cmpi32_eq(vet2, shuffle_pos);
        mask_ne = __builtin_npu_mask_cmpi32_ne(vet2, shuffle_pos);
    }

    // Writing Debug registers
    for (int i = 0; i < DEBUG_REG; i++){
        __builtin_npu_write_control_reg(i + 100, 20 + i);
        cntr_reg_value[i] = __builtin_npu_read_control_reg(20 + i);
    }

    // Masking vector operations
    __builtin_npu_write_mask_reg(0x00FF);
    vet3 = vet2;
    __builtin_npu_write_mask_reg(0xFF00);
    vet3 = 0xFF;
    __builtin_npu_write_mask_reg(0xFFFF);

    // Converting floating vector into integer vector
    vet_cast = __builtin_convertvector(fvet, vec16i32);

#else

    // Rearranging vet1 
    for(int j = 0; j < LOOP; j++)
        for (int i = 0; i < VECDIM-1; i++){
            int tmp = vet1[i];
            vet1[i] = vet1[i+1];
            vet1[i+1] = tmp;
        }

    // Creating a vector using variable a
    for (int i = 0; i < VECDIM; i++)
        vet2[i] = a;


    // Creating expected result for masked vector operations
    for (int i = 0; i < VECDIM/2; i++)
        vet3[i] = vet2[i];

    for (int i = VECDIM/2; i < VECDIM; i++)
        vet3[i] = 0xFF;
    
    // Creating expected results for vectorial compare operations
    for (int i = 0; i < VECDIM; i++){
        if ((uint32_t)vet2[i] > (uint32_t)shuffle_pos[i])
            mask_gt = mask_gt | (1u << i);

        if (vet2[i] > shuffle_pos[i])
            mask_sgt = mask_sgt | (1u << i);

        if ((uint32_t)vet2[i] >= (uint32_t)shuffle_pos[i])
            mask_ge = mask_ge | (1u << i);

        if (vet2[i] >= shuffle_pos[i])
            mask_sge = mask_sge | (1u << i);

        if ((uint32_t)vet2[i] < (uint32_t)shuffle_pos[i])
            mask_lt = mask_lt | (1u << i);

        if (vet2[i] < shuffle_pos[i])
            mask_slt = mask_slt | (1u << i);

        if ((uint32_t)vet2[i] <= (uint32_t)shuffle_pos[i])
            mask_le = mask_le | (1u << i);

        if (vet2[i] <= shuffle_pos[i])
            mask_sle = mask_sle | (1u << i);

        if (vet2[i] == shuffle_pos[i])
            mask_eq = mask_eq | (1u << i);

        if (vet2[i] != shuffle_pos[i])
            mask_ne = mask_ne | (1u << i);
    }

    // Creating expected result for control registers check
    for (int i = 0; i < DEBUG_REG; i++){
        cntr_reg_value[i] = i + 100;
    }

    // Converting floating vector into integer vector
    for (int i = 0; i < VECDIM; i++){
        vet_cast[i] = (uint32_t)fvet[i];
    }

#endif

    for(int i = 0; i < VECDIM; i++){
        result[i] = vet1[i];
        result[i+VECDIM] = vet2[i];
        result[i+VECDIM*2] = vet3[i];
    }
    result[VECDIM * 3] = mask_gt;
    result[VECDIM * 3 + 1] = mask_ge;
    result[VECDIM * 3 + 2] = mask_lt;
    result[VECDIM * 3 + 3] = mask_le;
    result[VECDIM * 3 + 4] = mask_sgt;
    result[VECDIM * 3 + 5] = mask_sge;
    result[VECDIM * 3 + 6] = mask_slt;
    result[VECDIM * 3 + 7] = mask_sle;
    result[VECDIM * 3 + 8] = mask_eq;
    result[VECDIM * 3 + 9] = mask_ne;

    for (int i = 0; i < DEBUG_REG; i++)
        result[VECDIM * 3 + 10 + i] = cntr_reg_value[i];

    for (int i = 0; i < VECDIM; i++) 
        result[VECDIM * 5 + i] = vet_cast[i];

#ifdef NPU_ACCELERATOR
    __builtin_npu_flush((int) &result[0]);
    __builtin_npu_flush((int) &result[16]);
    __builtin_npu_flush((int) &result[32]);
    __builtin_npu_flush((int) &result[48]);
    __builtin_npu_flush((int) &result[64]);
    __builtin_npu_flush((int) &result[80]);
    __builtin_npu_write_control_reg(OUTDIM, 12); // For cosimulation purpose
    }

    __builtin_npu_barrier(CORE_ID + 100, THREAD_NUMB - 1);

    return (int)&result[0];

#else
    for (int i = 0; i < OUTDIM; i++){
        printf("%5d ", result[i]);
        if (((i+1) % 16) == 0)
            printf("\n");
    }

    return 0;

#endif

}

// Generates random integers between 0 and 8095
int RandomInteger(void)
{
   Seed = ((Seed * 133) + 81) % 8095;
   return Seed;
}
