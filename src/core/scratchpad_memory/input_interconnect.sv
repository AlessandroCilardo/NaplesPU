`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module input_interconnect (
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_bank_indexes,
        input   sm_entry_address_t  [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_bank_offsets,
        input   sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_data,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0] satisfied_mask,
        input   sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_byte_mask,
        output  sm_entry_address_t  [`SM_MEMORY_BANKS           - 1 : 0] output_bank_offsets,
        output  sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0] output_data,
        output  logic               [`SM_MEMORY_BANKS           - 1 : 0] output_mask,
        output  sm_byte_mask_t      [`SM_MEMORY_BANKS           - 1 : 0] output_byte_mask
    );

    genvar i;
    generate
        for (i = 0; i < `SM_MEMORY_BANKS; i++)
            bank_steering_unit #(
                .BANK_ADDRESS(i)
            ) bank_steering_unit (
                .input_bank_indexes(input_bank_indexes),
                .input_bank_offsets(input_bank_offsets),
                .input_data(input_data),
                .input_mask(satisfied_mask),
                .input_byte_mask(input_byte_mask),
                .output_bank_offset(output_bank_offsets[i]),
                .output_data(output_data[i]),
                .output_enable(output_mask[i]),
                .output_byte_mask(output_byte_mask[i])
            );
    endgenerate

endmodule
