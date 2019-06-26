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
			//{SMad, recall},
			{SMad, Fwd_Flush},
			{SMad, Fwd_GetS},
			{SMad, Fwd_GetM}              : begin
				pr_output_stall                  = 1'b1;
			end
			
			{SMa, flush},
			{SMa, store},
			{SMa, replacement},
			//{SMa, recall},
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

