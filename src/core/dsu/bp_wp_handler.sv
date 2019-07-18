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

`include "npu_defines.sv"

module bp_wp_handler (

		input    address_t             [7 : 0]                  dsu_breakpoint,
		input    logic                 [7 : 0]					dsu_breakpoint_enable,
		input    logic											dsu_single_step,

		//From Instruction Scheduler
		input    logic                                           is_instruction_valid,
		input    instruction_decoded_t 						     is_instruction,
		
		output   logic                 [`THREAD_NUMB - 1 : 0]   dsu_breakpoint_detected
	) ;


	assign dsu_breakpoint_detected = ((
							 (dsu_breakpoint[7]==is_instruction.pc && dsu_breakpoint_enable[7])
                          || (dsu_breakpoint[6]==is_instruction.pc && dsu_breakpoint_enable[6])
                          || (dsu_breakpoint[5]==is_instruction.pc && dsu_breakpoint_enable[5])
                          || (dsu_breakpoint[4]==is_instruction.pc && dsu_breakpoint_enable[4])
                          || (dsu_breakpoint[3]==is_instruction.pc && dsu_breakpoint_enable[3])
                          || (dsu_breakpoint[2]==is_instruction.pc && dsu_breakpoint_enable[2])
                          || (dsu_breakpoint[1]==is_instruction.pc && dsu_breakpoint_enable[1])
                          || (dsu_breakpoint[0]==is_instruction.pc && dsu_breakpoint_enable[0])) 
						  || dsu_single_step) && is_instruction_valid;

//	assign dsu_breakpoint_detected = (((
//							 (dsu_breakpoint[7]==is_instruction.pc)
//                          || (dsu_breakpoint[6]==is_instruction.pc)
//                          || (dsu_breakpoint[5]==is_instruction.pc)
//                          || (dsu_breakpoint[4]==is_instruction.pc)
//                          || (dsu_breakpoint[3]==is_instruction.pc)
//                          || (dsu_breakpoint[2]==is_instruction.pc)
//                          || (dsu_breakpoint[1]==is_instruction.pc)
//                          || (dsu_breakpoint[0]==is_instruction.pc) )
//                      && dsu_breakpoint_enable) || dsu_single_step) && is_instruction_valid;
endmodule
