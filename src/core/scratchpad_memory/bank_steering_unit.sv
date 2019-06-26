`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module bank_steering_unit #(
        parameter BANK_ADDRESS = 0
    )(
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_bank_indexes,
        input   sm_entry_address_t  [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_bank_offsets,
        input   sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_data,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_mask,
        input   sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_byte_mask,
        output  sm_entry_address_t                                          output_bank_offset,
        output  sm_data_t                                                   output_data,
        output  logic                                                       output_enable,
        output  sm_byte_mask_t                                              output_byte_mask
    );

    logic               [`SM_PROCESSING_ELEMENTS            - 1 : 0]    compare_mask;
    logic               [$clog2(`SM_PROCESSING_ELEMENTS)    - 1 : 0]    selected_address;
    logic                                                               priority_encoder_valid;


    genvar i;
    generate
        for (i = 0; i < `SM_PROCESSING_ELEMENTS; i++)
            assign compare_mask[i] = input_bank_indexes[i] == BANK_ADDRESS;
    endgenerate

    priority_encoder_npu #(
        .INPUT_WIDTH(`SM_PROCESSING_ELEMENTS),
        .MAX_PRIORITY("LSB")
    ) controller (
        .decode(input_mask & compare_mask),
        .encode(selected_address),
        .valid(priority_encoder_valid)
    );

    assign output_bank_offset  = input_bank_offsets[selected_address];
    assign output_data          = input_data[selected_address];
    assign output_enable        = input_mask[selected_address] & priority_encoder_valid;
    assign output_byte_mask     = input_byte_mask[selected_address];

endmodule
