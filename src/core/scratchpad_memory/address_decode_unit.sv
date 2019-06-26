`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module address_decode_unit (
        input   sm_address_t            address,
        output  sm_bank_address_t       bank_index,
        output  sm_entry_address_t      bank_offset
    );

    //XXX: Dummy address remapping logic
    assign bank_offset    = address[`SM_ADDRESS_LEN - 1   -:  `SM_ENTRY_ADDRESS_LEN        ];
    assign bank_index     = address[`SM_BYTE_ADDRESS_LEN  +:  `SM_MEMORY_BANK_ADDRESS_LEN  ];

endmodule
