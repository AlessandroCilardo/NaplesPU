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

module stall_protocol_rom (

		input  coherence_state_t    current_state,
		input  coherence_request_t  current_request,

		output logic pr_output_stall

	);

	always_comb begin

		pr_output_stall                  = 1'b0;

		unique case ( {current_state, current_request} )

			{ISd, load},
			{ISd, store},
			{ISd, replacement},
			{ISd, recall},
			{ISd, Fwd_Flush},
			{ISd, Inv}                    : begin
				pr_output_stall                  = 1'b1;
			end

			{IMad, flush},
			{IMad, load},
			{IMad, store},
			{IMad, replacement},
			{IMad, recall},
			{IMad, Fwd_Flush},
			{IMad, Fwd_GetS},
			{IMad, Fwd_GetM}              : begin
				pr_output_stall                  = 1'b1;
			end
			
			{IUd, load_uncoherent},
			{IUd, store_uncoherent},
			{IUd, replacement_uncoherent},
			{IUd, flush_uncoherent}       : begin
				pr_output_stall                  = 1'b1;
			end

			{IMd, Fwd_Flush},
			{IMd, flush},
			{IMd, load},
			{IMd, store},
			{IMd, replacement},
			{IMd, recall},
			{IMd, Fwd_GetS},
			{IMd, Fwd_GetM}              : begin
				pr_output_stall                  = 1'b1;
			end

			{IMa, flush},
			{IMa, load},
			{IMa, store},
			{IMa, replacement},
			{IMa, recall},
			{IMa, Fwd_Flush},
			{IMa, Fwd_GetS},
			{IMa, Fwd_GetM}               : begin
				pr_output_stall                  = 1'b1;
			end
			
			{SMad, flush},
			{SMad, store},
			{SMad, replacement},
			{SMad, Fwd_Flush},
			{SMad, Fwd_GetS},
			{SMad, Fwd_GetM}              : begin
				pr_output_stall                  = 1'b1;
			end
			
			{SMa, flush},
			{SMa, store},
			{SMa, replacement},
			{SMa, Fwd_Flush},
			{SMa, Fwd_GetS},
			{SMa, Fwd_GetM}               : begin
				pr_output_stall                  = 1'b1;
			end

			{MIa, load},
			{MIa, store},
			{MIa, replacement}            : begin
				pr_output_stall                  = 1'b1;
			end

			{SIa, load},
			{SIa, store},
			{SIa, replacement}            : begin
				pr_output_stall                  = 1'b1;
			end

			{IIa, load},
			{IIa, store},
			{IIa, recall},
			{IIa, replacement}            : begin
				pr_output_stall                  = 1'b1;
			end

			default : begin
				pr_output_stall                  = 0;
			end

		endcase
	end

endmodule

