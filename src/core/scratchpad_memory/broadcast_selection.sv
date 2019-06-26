`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module broadcast_selection (
        input   logic                                                   is_store,
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS - 1 : 0]   bank_indexes,
        input   sm_entry_address_t  [`SM_PROCESSING_ELEMENTS - 1 : 0]   bank_offsets,
        input   logic               [`SM_PROCESSING_ELEMENTS - 1 : 0]   pending_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS - 1 : 0]   broadcast_mask
    );

    sm_bank_address_t      broadcast_bank_index;
    sm_entry_address_t     broadcast_bank_offset;
    logic       [$clog2(`SM_PROCESSING_ELEMENTS) - 1 : 0]   broadcast_sel;



    assign broadcast_bank_index = bank_indexes[broadcast_sel];
    assign broadcast_bank_offset = bank_offsets[broadcast_sel];


    priority_encoder_npu #(
        .INPUT_WIDTH(`SM_PROCESSING_ELEMENTS),
        .MAX_PRIORITY("LSB")
    ) priority_encoder (
        .decode(pending_mask),
        .encode(broadcast_sel),
        .valid());


    genvar i;
    generate
        for (i = 0; i < `SM_PROCESSING_ELEMENTS; i++)
            assign broadcast_mask[i] = ((bank_indexes[i] == broadcast_bank_index) && (bank_offsets[i] == broadcast_bank_offset) && !is_store);
    endgenerate

endmodule
