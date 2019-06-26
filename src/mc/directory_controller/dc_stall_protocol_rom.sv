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

