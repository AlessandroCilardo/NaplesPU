`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module address_remapping_unit # (
        parameter NUM_ADDRESSES = `SM_PROCESSING_ELEMENTS
    )
    (
        input   sm_address_t        [NUM_ADDRESSES - 1 : 0] addresses,
        output  sm_bank_address_t   [NUM_ADDRESSES - 1 : 0] bank_indexes,
        output  sm_entry_address_t  [NUM_ADDRESSES - 1 : 0] bank_offsets
    );

    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_ADDRESSES; lane_idx++)
            address_decode_unit address_decode_unit (
                .address(addresses[lane_idx]),
                .bank_offset(bank_offsets[lane_idx]),
                .bank_index(bank_indexes[lane_idx])
            );
    endgenerate

endmodule
