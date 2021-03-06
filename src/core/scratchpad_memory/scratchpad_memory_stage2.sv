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

module scratchpad_memory_stage2 (
        input   logic                                                       clock,
        input   logic                                                       resetn,

        input   logic                                                       sm1_is_store,
        input   logic                                                       sm1_is_last_request,
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm1_bank_indexes,
        input   sm_entry_address_t  [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm1_bank_offsets,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm1_satisfied_mask,
        input   sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm1_write_data,
        input   sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm1_byte_mask,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm1_mask,
        input   logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    sm1_piggyback_data,

        output  logic                                                       sm2_is_last_request,
        output  sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_bank_indexes,
        output  sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0]    sm2_read_data,
        output  logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_satisfied_mask,
        output  sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_byte_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_mask,
        output  logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    sm2_piggyback_data
    );

    //From input_interconnect
    sm_entry_address_t  [`SM_MEMORY_BANKS           - 1 : 0] ii_bank_offsets;
    sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0] ii_data;
    logic               [`SM_MEMORY_BANKS           - 1 : 0] ii_mask;
    sm_byte_mask_t      [`SM_MEMORY_BANKS           - 1 : 0] ii_byte_mask;

    input_interconnect input_interconnect (
        .input_bank_indexes(sm1_bank_indexes),
        .input_bank_offsets(sm1_bank_offsets),
        .input_data(sm1_write_data),
        .input_byte_mask(sm1_byte_mask),
        .satisfied_mask(sm1_satisfied_mask),
        .output_bank_offsets(ii_bank_offsets),
        .output_data(ii_data),
        .output_mask(ii_mask),
        .output_byte_mask(ii_byte_mask)
    );


    banked_memory banked_memory (
        .clock(clock),
        .enables(ii_mask),
        .is_store(sm1_is_store),
        .bank_offsets(ii_bank_offsets),
        .byte_mask(ii_byte_mask),
        .write_data(ii_data),
        .read_data(sm2_read_data)
    );

    always_ff @(posedge clock, negedge resetn) begin
        if (!resetn) begin
            sm2_bank_indexes    <= 0;
            sm2_satisfied_mask  <= 0;
            sm2_is_last_request <= 0;
            sm2_byte_mask       <= 0;
            sm2_piggyback_data  <= 0;
        end else begin
            sm2_bank_indexes    <= sm1_bank_indexes;
            sm2_satisfied_mask  <= sm1_satisfied_mask;
            sm2_is_last_request <= sm1_is_last_request;
            sm2_mask            <= sm1_mask;
            sm2_byte_mask       <= sm1_byte_mask;
            sm2_piggyback_data  <= sm1_piggyback_data;
        end
    end

endmodule
