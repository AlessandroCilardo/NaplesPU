`timescale 1ns / 1ps
`include "npu_spm_defines.sv"

module scratchpad_memory_stage1 (
		input  logic                                                clock,
		input  logic                                                resetn,

		input  logic                                                is_store,
		input  sm_address_t       [`SM_PROCESSING_ELEMENTS - 1 : 0] addresses,
		input  sm_data_t          [`SM_PROCESSING_ELEMENTS - 1 : 0] write_data,
		input  sm_byte_mask_t     [`SM_PROCESSING_ELEMENTS - 1 : 0] byte_mask,
		input  logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] pending_mask,
		input  logic              [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  piggyback_data,

		output logic                                                sm1_is_store,
		output sm_bank_address_t  [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_bank_indexes,
		output sm_entry_address_t [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_bank_offsets,
		output logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_satisfied_mask,
		output sm_data_t          [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_write_data,
		output sm_byte_mask_t     [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_byte_mask,
		output logic                                                sm1_is_last_request,
		output logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_mask,
		output logic                                                sm1_ready,
		output logic              [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  sm1_piggyback_data
	);

	//From address_remapping_unit
	sm_bank_address_t  [`SM_PROCESSING_ELEMENTS - 1 : 0] aru_bank_indexes;
	sm_entry_address_t [`SM_PROCESSING_ELEMENTS - 1 : 0] aru_bank_offsets;


	//From address_conflict_logic
	/* verilator lint_off UNOPTFLAT */
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] acl_still_pending_mask;
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] acl_satisfied_mask;

	//From requests_issue_unit
	logic                                                riu_is_store;
	sm_bank_address_t  [`SM_PROCESSING_ELEMENTS - 1 : 0] riu_bank_indexes;
	sm_entry_address_t [`SM_PROCESSING_ELEMENTS - 1 : 0] riu_bank_offsets;
	sm_data_t          [`SM_PROCESSING_ELEMENTS - 1 : 0] riu_write_data;
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] riu_pending_mask;
	logic                                                riu_is_last_request;
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] riu_mask;
	sm_byte_mask_t     [`SM_PROCESSING_ELEMENTS - 1 : 0] riu_byte_mask;
	logic              [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  riu_piggyback_data;

	address_remapping_unit #(
		.NUM_ADDRESSES( `SM_PROCESSING_ELEMENTS )
	)
	address_remapping_unit (
		.addresses    ( addresses        ),
		.bank_indexes ( aru_bank_indexes ),
		.bank_offsets ( aru_bank_offsets )
	);

	requests_issue_unit requests_issue_unit (
		.clock                   ( clock                  ),
		.resetn                  ( resetn                 ),
		.input_is_store          ( is_store               ),
		.input_bank_indexes      ( aru_bank_indexes       ),
		.input_bank_offsets      ( aru_bank_offsets       ),
		.input_write_data        ( write_data             ),
		.input_byte_mask         ( byte_mask              ),
		.input_pending_mask      ( pending_mask           ),
		.input_still_pending_mask( acl_still_pending_mask ),
		.input_piggyback_data    ( piggyback_data         ),
		.output_is_store         ( riu_is_store           ),
		.output_bank_indexes     ( riu_bank_indexes       ),
		.output_bank_offsets     ( riu_bank_offsets       ),
		.output_write_data       ( riu_write_data         ),
		.output_byte_mask        ( riu_byte_mask          ),
		.output_pending_mask     ( riu_pending_mask       ),
		.output_is_last_request  ( riu_is_last_request    ),
		.mask                    ( riu_mask               ),
		.ready                   ( sm1_ready              ),
		.output_piggyback_data   ( riu_piggyback_data     )
	);

	address_conflict_logic address_conflict_logic (
		.is_store          ( riu_is_store           ),
		.bank_indexes      ( riu_bank_indexes       ),
		.bank_offsets      ( riu_bank_offsets       ),
		.pending_mask      ( riu_pending_mask       ),
		.still_pending_mask( acl_still_pending_mask ),
		.satisfied_mask    ( acl_satisfied_mask     )
	);

	always_ff @( posedge clock, negedge resetn ) begin
		if ( !resetn ) begin
			sm1_is_store        <= 0;
			sm1_satisfied_mask  <= 0;
			sm1_write_data      <= 0;
			sm1_is_last_request <= 0;
			sm1_piggyback_data  <= 0;
		end else begin
			sm1_is_store        <= riu_is_store;
			sm1_bank_indexes    <= riu_bank_indexes;
			sm1_bank_offsets    <= riu_bank_offsets;
			sm1_satisfied_mask  <= acl_satisfied_mask;
			sm1_write_data      <= riu_write_data;
			sm1_is_last_request <= riu_is_last_request;
			sm1_byte_mask       <= riu_byte_mask;
			sm1_mask            <= riu_mask;
			sm1_piggyback_data  <= riu_piggyback_data;
		end
	end

endmodule
