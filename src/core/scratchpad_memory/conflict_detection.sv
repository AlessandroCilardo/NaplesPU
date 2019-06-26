`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module conflict_detection (
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS - 1 : 0] bank_offsets,
        input   logic               [`SM_PROCESSING_ELEMENTS - 1 : 0] pending_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS - 1 : 0] conflicts_mask
    );

    logic [`SM_PROCESSING_ELEMENTS - 1 : 0]  conflict_matrix [`SM_PROCESSING_ELEMENTS - 1 : 0];

    genvar i, j;
    generate

        for (i = 0; i < `SM_PROCESSING_ELEMENTS; i++) begin
            for (j = i + 1; j < `SM_PROCESSING_ELEMENTS; j++)
                assign conflict_matrix[j][i] = ((bank_offsets[i] == bank_offsets[j]) && pending_mask[i]);
        end

        for (i = 0; i < `SM_PROCESSING_ELEMENTS; i++) begin
            for (j = 0; j < i + 1; j++) begin
                assign conflict_matrix[j][i] = 1'b0;
            end
        end

        for (j = 0; j < `SM_PROCESSING_ELEMENTS; j++) begin
            assign conflicts_mask[j] = |(conflict_matrix[j]);
        end


    endgenerate


endmodule
