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

`ifndef __NPU_SPM_DEFINES_SV
`define __NPU_SPM_DEFINES_SV

`include "npu_defines.sv"

 `define SM_PROCESSING_ELEMENTS      16		// Number of SIMD Lanes
 `define SM_ENTRIES                  1024	// Number of bank entries
 `define SM_MEMORY_BANKS             16		// Number of memory banks
 `define SM_BYTE_PER_ENTRY           4		// Number of byte per entry
 `define SM_PIGGYBACK_DATA_LEN       $bits(instruction_decoded_t)

`define SM_ENTRY_ADDRESS_LEN        $clog2(`SM_ENTRIES)
`define SM_MEMORY_BANK_ADDRESS_LEN  $clog2(`SM_MEMORY_BANKS)
`define SM_BYTE_ADDRESS_LEN         $clog2(`SM_BYTE_PER_ENTRY)
`define SM_ADDRESS_LEN              `SM_ENTRY_ADDRESS_LEN + `SM_MEMORY_BANK_ADDRESS_LEN + `SM_BYTE_ADDRESS_LEN

typedef logic   [`SM_BYTE_PER_ENTRY * 8         - 1 : 0] sm_data_t;
typedef logic   [`SM_ADDRESS_LEN                - 1 : 0] sm_address_t;          
typedef logic   [`SM_ENTRY_ADDRESS_LEN          - 1 : 0] sm_entry_address_t;    
typedef logic   [`SM_MEMORY_BANK_ADDRESS_LEN    - 1 : 0] sm_bank_address_t;     
typedef logic   [`SM_BYTE_ADDRESS_LEN           - 1 : 0] sm_byte_address_t;     
typedef logic   [`SM_BYTE_PER_ENTRY             - 1 : 0] sm_byte_mask_t;

`endif
