`timescale 1ns / 1ps
`include "npu_defines.sv"
`include "npu_debug_log.sv"

/*
 * Int Pipe is the main execution module. It executes: jumps, arithmetic and logic operations, control register accesses, and moves.
 * Vectorial operations are executed in parallel spreading them among all the hardware lanes, where each lane performs a scalar
 * operation. The final vectorial result is composed chaining all the scalar intermediate results from the lanes.
 * If an operation is scalar, only the first lane is valid.
 *
 */

module int_pipe #(
		parameter TILE_ID = 0)
	(
		input                        clk,
		input                        reset,
		input                        enable,

		// From Operand Fetch
		input                        opf_valid,
		input  instruction_decoded_t opf_inst_scheduled,
		input  hw_lane_t             opf_fetched_op0,
		input  hw_lane_t             opf_fetched_op1,
		input  hw_lane_mask_t        opf_hw_lane_mask,

		// From Control Register
		input  register_t            cr_result,
		
		// To Writeback
		output logic                 int_valid,
		output instruction_decoded_t int_inst_scheduled,
		output hw_lane_t             int_result,
		output hw_lane_mask_t        int_hw_lane_mask
	);

	logic                         is_cr_access;
	logic                         is_int_instr;
	logic                         is_jmpsr;
	logic                         is_getlane;
	logic                         is_shuffle;
	register_t                    getlane_result;

	logic                         is_create_mask;
	logic      [`HW_LANE - 1 : 0] create_mask_result;

	logic                         is_compare;
	logic                         is_move_imm;
	register_t                    lane_cmp_result;
	register_t                    cmp_result;
	hw_lane_t                     vec_result;
	hw_lane_t                     movei_result;
	hw_lane_t                     shuffle_result;

	// Checks operation type
	assign is_jmpsr       = opf_inst_scheduled.pipe_sel == PIPE_BRANCH & opf_inst_scheduled.is_int & opf_inst_scheduled.is_branch;
	assign is_int_instr   = opf_inst_scheduled.pipe_sel == PIPE_INT;
	assign is_cr_access   = opf_inst_scheduled.pipe_sel == PIPE_CR & opf_inst_scheduled.op_code.contr_opcode == READ_CR;
	assign is_getlane     = opf_inst_scheduled.op_code.alu_opcode == GETLANE;
	assign is_shuffle     = opf_inst_scheduled.op_code.alu_opcode == SHUFFLE;
	assign is_create_mask = opf_inst_scheduled.op_code.alu_opcode == CRT_MASK;
	assign is_move_imm    = opf_inst_scheduled.is_movei;
	assign is_compare     = opf_inst_scheduled.op_code >= CMPEQ && opf_inst_scheduled.op_code <= CMPLE_U ;
	assign cmp_result     = ( opf_inst_scheduled.is_source0_vectorial || opf_inst_scheduled.is_source1_vectorial ) ?
		lane_cmp_result : register_t'( lane_cmp_result[0] );

	genvar                        i;
	generate
		for ( i = 0; i < `HW_LANE; i ++ ) begin : INT_HWLANE_GEN
			int_single_lane int_single_lane (
				.op0    ( opf_fetched_op0[i]         ),
				.op1    ( opf_fetched_op1[i]         ),
				.op_code( opf_inst_scheduled.op_code ),
				.result ( vec_result[i]              )
			);
		end

		for ( i = 0; i < `HW_LANE; i++ ) begin
			assign lane_cmp_result[i] = vec_result[i][0];

			//Move Immediate result composer
			always_comb begin : RESULT_COMPOSER_MOVE
				case ( opf_inst_scheduled.op_code )

					MOVEI,
					MOVEI_L : begin
						movei_result[i][`REGISTER_SIZE - 1 : `REGISTER_SIZE/2] = 0;
						movei_result[i][( `REGISTER_SIZE/2 ) - 1 : 0 ]         = (`REGISTER_SIZE/2)'(opf_fetched_op1[i]);
					end

					MOVEI_H : begin
						movei_result[i][`REGISTER_SIZE - 1 : `REGISTER_SIZE/2] = (`REGISTER_SIZE/2)'(opf_fetched_op1[i]);
						movei_result[i][( `REGISTER_SIZE/2 ) - 1 : 0 ]         = 0;
					end

					default : movei_result[i] = 0;

				endcase
			end

		end
	endgenerate

	always_comb
		for ( int i = 0; i < `HW_LANE; i ++ ) begin : SHUFFLE_CRTMASK_HWLANE_GEN
			shuffle_result[i]     = opf_fetched_op0[opf_fetched_op1[i]];
			create_mask_result[i] = opf_fetched_op0[i][0];
		end

	assign getlane_result = vec_result[opf_fetched_op1[0]];

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset )
			int_valid <= 1'b0;
		else if ( enable )
			int_valid <= opf_valid & ( is_int_instr | is_cr_access | is_jmpsr );
	end

	always_ff @ ( posedge clk ) begin
		if ( enable ) begin
			int_inst_scheduled <= opf_inst_scheduled;
			int_hw_lane_mask   <= opf_hw_lane_mask;

			if ( is_jmpsr )
				int_result[0] <= opf_fetched_op0[0] + 4; // PC + 4
			else if ( is_cr_access )
				int_result[0] <= cr_result;
			else if ( is_compare )
				int_result[0] <= cmp_result;
			else if ( is_getlane )
				int_result[0] <= getlane_result;
			else if ( is_shuffle )
				int_result    <= shuffle_result;
			else if ( is_create_mask )
				int_result[0] <= {{`HW_LANE{1'b0}}, create_mask_result};
			else if ( is_move_imm )
				int_result    <= movei_result;
			else
				int_result    <= vec_result;
		end
	end

`ifdef SIMULATION
	always_ff @ ( posedge clk )
		if ( int_valid ) begin
			assert( int_inst_scheduled.op_code.alu_opcode <= MOVE || ( int_inst_scheduled.op_code.alu_opcode >= SEXT8 & int_inst_scheduled.op_code.alu_opcode <= SEXT32 )
					|| int_inst_scheduled.op_code.alu_opcode == CRT_MASK )
			else $error( "[Time %t] [Int Pipe]: Opcode error! \tPC: %h \tTHREAD: %h", $time( ), int_inst_scheduled.pc, int_inst_scheduled.thread_id );

			assert ( !( int_result === {( `REGISTER_SIZE * `HW_LANE ){1'bX}} ) )
			else $error( "[Time %t] [Int Pipe]: Result error! \t PC: %h \tTHREAD: %h", $time( ), int_inst_scheduled.pc, int_inst_scheduled.thread_id );
		end

`ifdef DISPLAY_INT
	always_ff @ ( posedge clk )
		if ( int_valid )
			print_int_result( TILE_ID, int_inst_scheduled, int_result );
`endif

`endif

endmodule
