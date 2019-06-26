`timescale 1ns / 1ps
`include "npu_defines.sv"

/*
 * Branch Control, this module handles conditional and unconditional jumps and restores
 * scoreboards if the jump is taken.
 *
 * NPU supports two jump instruction formats:
 *      - JRA: Jump Relative Address is an unconditional jump instruction, it takes an immediate
 *             and the core will always jump to PC + immediate location.
 *             E.g. jmp -12   ->  BC will jump to PC-12 (3 instruction back) memory location.
 *
 *      - JBA: Jump Base Address can be a conditional or unconditional jump, it takes a register
 *             and an immediate as input. In case of conditional jump, the input register holds the
 *             jump condition, if the condition is satisfied BC will jump to PC + immediate location.
 *             E.g. branch_eqz s4, -12   -> BC will jump if register s4 is equal zero to PC-12 location.
 *             In case of unconditional jump, the input register is the effective address where to jump.
 *             E.g. jmp s4   -> BC will jump to memory location stored in s4.
 *
 * Base address or condition are stored in opf_fetched_op0[0], immediate is stored in opf_fetched_op1[0].
 */

module branch_control (
		// From Operand Fetch
		input                        opf_valid,
		input  instruction_decoded_t opf_inst_scheduled,
		input  hw_lane_t             opf_fetched_op0,
		input  hw_lane_t             opf_fetched_op1,
		input  scoreboard_t          opf_destination_bitmap,

		//To Rollback Handler
		output logic                 bc_rollback_enable,
		output logic                 bc_rollback_valid,
		output address_t             bc_rollback_pc,
		output thread_id_t           bc_rollback_thread_id,
		output scoreboard_t          bc_scoreboard
	);

	logic src_is_eqz;
	logic jump;
	logic is_conditional_branch;

	assign bc_rollback_enable    = jump & opf_inst_scheduled.is_branch & opf_valid;
	assign bc_rollback_valid     = opf_valid && opf_inst_scheduled.pipe_sel == PIPE_BRANCH && ~bc_rollback_enable;
	assign bc_rollback_thread_id = opf_inst_scheduled.thread_id;
	assign bc_scoreboard         = opf_destination_bitmap;

	assign src_is_eqz            = opf_fetched_op0[0] == 0;
	assign is_conditional_branch = opf_inst_scheduled.op_code == BRANCH_EQZ ||
		opf_inst_scheduled.op_code == BRANCH_NEZ;

	always_comb
		if( opf_inst_scheduled.is_branch )
			case( opf_inst_scheduled.branch_type )
				JBA : begin
					if( is_conditional_branch )
						bc_rollback_pc = opf_inst_scheduled.pc + opf_fetched_op1[0];
					else
						bc_rollback_pc = opf_fetched_op0[0];
				end
				JRA : bc_rollback_pc = opf_inst_scheduled.pc + opf_fetched_op1[0];
				default :
					`ifdef SIMULATION
					bc_rollback_pc = {`ADDRESS_SIZE{1'bX}};
					`else
				bc_rollback_pc     = {`ADDRESS_SIZE{1'b0}};
					`endif
			endcase
		else
			bc_rollback_pc = {`ADDRESS_SIZE{1'b0}};

	always_comb begin
		jump = 1'b0;

		if( opf_inst_scheduled.is_branch )
			case ( opf_inst_scheduled.op_code )
				JMP,
				JMPSR,
				JERET,
				JRET       : jump = 1'b1;
				BRANCH_EQZ : jump = src_is_eqz;
				BRANCH_NEZ : jump = ~src_is_eqz;
				default : jump    = 1'b0;
			endcase
	end

endmodule
