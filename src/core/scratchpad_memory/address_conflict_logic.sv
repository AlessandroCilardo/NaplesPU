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
