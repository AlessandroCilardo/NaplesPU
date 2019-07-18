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
