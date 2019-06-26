`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module output_interconnect (
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0] bank_indexes,
        input   sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0] input_data,
        output  sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0] output_data
    );

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < `SM_PROCESSING_ELEMENTS; lane_idx++) begin
            assign output_data[lane_idx] = input_data[bank_indexes[lane_idx]];
        end
    endgenerate

endmodule
