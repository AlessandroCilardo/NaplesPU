//        Copyright 2019 NaplesPU
//   
//   	 
//   Redistribution and use in source and binary forms, with or without modification,
//   are permitted provided that the following conditions are met:
//   
//   1. Redistributions of source code must retain the above copyright notice,
//      this list of conditions and the following disclaimer.
//   
//   2. Redistributions in binary form must reproduce the above copyright notice,
//      this list of conditions and the following disclaimer in the documentation
//      and/or other materials provided with the distribution.
//   
//   3. Neither the name of the copyright holder nor the names of its contributors
//      may be used to endorse or promote products derived from this software
//      without specific prior written permission.
//   
//      
//   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//   IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//   INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//   BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
//   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//   OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
//   OF THE POSSIBILITY OF SUCH DAMAGE.

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
