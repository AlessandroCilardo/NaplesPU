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
`include "npu_coherence_defines.sv"

module dc_stall_protocol_rom (

		input  logic [`DIRECTORY_STATE_WIDTH - 1 : 0]        input_state,
		input        [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] input_request,
		input  logic                                         input_is_from_owner,
		output logic                                         dpr_output_stall

	);

	always_comb begin

		dpr_output_stall = 1'b0;

		casex ( {input_state, input_request, input_is_from_owner } )

			{STATE_S_D, REPLACEMENT, 1'b?},
			{STATE_S_D, MESSAGE_GETS, 1'b?},
			{STATE_S_D, MESSAGE_GETM, 1'b?},
			{STATE_MN_A, REPLACEMENT, 1'b?},
			{STATE_MN_A, MESSAGE_GETS, 1'b?},
			{STATE_MN_A, MESSAGE_GETM, 1'b?},
			{STATE_SN_A, REPLACEMENT, 1'b?},
			{STATE_SN_A, MESSAGE_GETS, 1'b?},
			{STATE_SN_A, MESSAGE_GETM, 1'b?},
			{STATE_NS_D, REPLACEMENT, 1'b?},
			{STATE_NS_D, MESSAGE_GETS, 1'b?},
			{STATE_NS_D, MESSAGE_GETM, 1'b?}: begin

				dpr_output_stall = 1'b1;

			end

			//--------------------------------------------------------------------------------
			// -- Others
			//--------------------------------------------------------------------------------

			default : begin

				dpr_output_stall = 1'b0;

			end

		endcase

	end

endmodule

