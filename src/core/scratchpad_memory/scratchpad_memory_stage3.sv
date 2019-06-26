`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module scratchpad_memory_stage3 (
        input   logic                                                       clock,
        input   logic                                                       resetn,

        input   logic                                                       sm2_is_last_request,
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_bank_indexes,
        input   sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0]    sm2_read_data,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_satisfied_mask,
        input   sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_byte_mask,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_mask,
        input   logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    sm2_piggyback_data,

        output  logic                                                       sm3_is_last_request,
        output  sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm3_read_data,
        output  sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm3_byte_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm3_mask,
        output  logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    sm3_piggyback_data
    );

    //From output_interconnect
    sm_data_t       [`SM_PROCESSING_ELEMENTS    - 1 : 0]    ii_output_data;


    output_interconnect output_interconnect (
        .bank_indexes(sm2_bank_indexes),
        .input_data(sm2_read_data),
        .output_data(ii_output_data)
    );

    //Collector Unit
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < `SM_PROCESSING_ELEMENTS; lane_idx++) begin
            always_ff @(posedge clock, negedge resetn) begin
                if (!resetn) begin

                end else begin
                    if (sm2_satisfied_mask[lane_idx])
                        sm3_read_data[lane_idx] <= ii_output_data[lane_idx];
                end
            end
        end
    endgenerate

    always_ff @(posedge clock, negedge resetn)
        if (!resetn) begin
            sm3_is_last_request <= 0;
            sm3_mask            <= 0;
            sm3_byte_mask       <= 0;
            sm3_piggyback_data  <= 0;
        end else begin
            sm3_is_last_request <= sm2_is_last_request;
            sm3_mask            <= sm2_mask;
            sm3_byte_mask       <= sm2_byte_mask;
            sm3_piggyback_data  <= sm2_piggyback_data;
        end

endmodule
