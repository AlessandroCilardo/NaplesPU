`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module decision_logic (
        input   logic [`SM_PROCESSING_ELEMENTS - 1 : 0] pending_mask,
        input   logic [`SM_PROCESSING_ELEMENTS - 1 : 0] conflicts_mask,
        input   logic [`SM_PROCESSING_ELEMENTS - 1 : 0] broadcast_mask,
        output  logic [`SM_PROCESSING_ELEMENTS - 1 : 0] satisfied_mask
    );

    genvar i;
    generate
        for (i = 0; i < `SM_PROCESSING_ELEMENTS; i++)
            assign satisfied_mask[i] = pending_mask[i] && (broadcast_mask[i] || !conflicts_mask[i]);
    endgenerate

endmodule
