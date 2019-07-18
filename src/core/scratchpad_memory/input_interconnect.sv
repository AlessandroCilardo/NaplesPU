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

module input_interconnect (
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_bank_indexes,
        input   sm_entry_address_t  [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_bank_offsets,
        input   sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_data,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0] satisfied_mask,
        input   sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0] input_byte_mask,
        output  sm_entry_address_t  [`SM_MEMORY_BANKS           - 1 : 0] output_bank_offsets,
        output  sm_data_t           [`SM_MEMORY_BANKS           - 1 : 0] output_data,
        output  logic               [`SM_MEMORY_BANKS           - 1 : 0] output_mask,
        output  sm_byte_mask_t      [`SM_MEMORY_BANKS           - 1 : 0] output_byte_mask
    );

    genvar i;
    generate
        for (i = 0; i < `SM_MEMORY_BANKS; i++)
            bank_steering_unit #(
                .BANK_ADDRESS(i)
            ) bank_steering_unit (
                .input_bank_indexes(input_bank_indexes),
                .input_bank_offsets(input_bank_offsets),
                .input_data(input_data),
                .input_mask(satisfied_mask),
                .input_byte_mask(input_byte_mask),
                .output_bank_offset(output_bank_offsets[i]),
                .output_data(output_data[i]),
                .output_enable(output_mask[i]),
                .output_byte_mask(output_byte_mask[i])
            );
    endgenerate

endmodule
