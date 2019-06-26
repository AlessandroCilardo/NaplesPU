`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module address_conflict_logic (
        input   logic                                                   is_store,
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS - 1 : 0]   bank_indexes,
        input   sm_entry_address_t  [`SM_PROCESSING_ELEMENTS - 1 : 0]   bank_offsets,
        input   logic               [`SM_PROCESSING_ELEMENTS - 1 : 0]   pending_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS - 1 : 0]   still_pending_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS - 1 : 0]   satisfied_mask
    );

    logic               [`SM_PROCESSING_ELEMENTS - 1 : 0]   conflicts_mask;
    logic               [`SM_PROCESSING_ELEMENTS - 1 : 0]   broadcast_mask;


    conflict_detection conflict_detection (
        .bank_offsets(bank_indexes),
        .pending_mask(pending_mask),
        .conflicts_mask(conflicts_mask)
    );

    broadcast_selection broadcast_selection (
        .is_store(is_store),
        .bank_indexes(bank_indexes),
        .bank_offsets(bank_offsets),
        .pending_mask(pending_mask),
        .broadcast_mask(broadcast_mask)
    );

    decision_logic decision_logic (
        .pending_mask(pending_mask),
        .conflicts_mask(conflicts_mask),
        .broadcast_mask(broadcast_mask),
        .satisfied_mask(satisfied_mask)
    );

    assign still_pending_mask           = ~satisfied_mask & pending_mask;

endmodule
