`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module banked_memory (
        input                                                               clock,
        input   logic               [`SM_MEMORY_BANKS           - 1 : 0]    enables,
        input   logic                                                       is_store,
        input   sm_entry_address_t  [`SM_MEMORY_BANKS           - 1 : 0]    bank_offsets,
        input   sm_byte_mask_t      [`SM_MEMORY_BANKS           - 1 : 0]    byte_mask,
        input   sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0]    write_data,
        output  sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0]    read_data
    );

    genvar bank;
    generate
        for (bank = 0; bank < `SM_MEMORY_BANKS; bank++)
            memory_bank # (
                .SIZE(`SM_ENTRIES),
                .ADDR_WIDTH(`SM_ENTRY_ADDRESS_LEN),
                .COL_WIDTH(8),
                .NB_COL(`SM_BYTE_PER_ENTRY)
            ) memory_bank (
                .clock(clock),
                .enable(enables[bank]),
                .address(bank_offsets[bank]),
                .write_enable(byte_mask[bank] & {`SM_BYTE_PER_ENTRY{is_store}}),
                .write_data(write_data[bank]),
                .read_data(read_data[bank])
            );
    endgenerate

endmodule
