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

module scratchpad_memory_stage3 (
        input   logic                                                       clock,
        input   logic                                                       resetn,

        input   logic                                                       sm2_is_last_request,
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_bank_indexes,
        input   sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0]    sm2_read_data,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_satisfied_mask,
        input   sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_byte_mask,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm2_mask,
        input   logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    sm2_piggyback_data,

        output  logic                                                       sm3_is_last_request,
        output  sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm3_read_data,
        output  sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm3_byte_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    sm3_mask,
        output  logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    sm3_piggyback_data
    );

    //From output_interconnect
    sm_data_t       [`SM_PROCESSING_ELEMENTS    - 1 : 0]    ii_output_data;


    output_interconnect output_interconnect (
        .bank_indexes(sm2_bank_indexes),
        .input_data(sm2_read_data),
        .output_data(ii_output_data)
    );

    //Collector Unit
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < `SM_PROCESSING_ELEMENTS; lane_idx++) begin
            always_ff @(posedge clock, negedge resetn) begin
                if (!resetn) begin

                end else begin
                    if (sm2_satisfied_mask[lane_idx])
                        sm3_read_data[lane_idx] <= ii_output_data[lane_idx];
                end
            end
        end
    endgenerate

    always_ff @(posedge clock, negedge resetn)
        if (!resetn) begin
            sm3_is_last_request <= 0;
            sm3_mask            <= 0;
            sm3_byte_mask       <= 0;
            sm3_piggyback_data  <= 0;
        end else begin
            sm3_is_last_request <= sm2_is_last_request;
            sm3_mask            <= sm2_mask;
            sm3_byte_mask       <= sm2_byte_mask;
            sm3_piggyback_data  <= sm2_piggyback_data;
        end

endmodule
