`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_debug_log.sv"

/*
 * The Instruction Scheduler (often referred as Dynamic Scheduler) schedules in a Round Robin way active threads
 * checking data and structural hazards. A scoreboard for each thread is allocated in this module, whenever an
 * instruction is scheduled, the scoreboard keeps track of which register are busy setting a bit high in its structure.
 * In this way, if another instruction requires this very register, it raises a WAR or RAW hazard. Dually, when an
 * instruction reaches the Writeback module and writes the computed outcome on its destination register, the relative
 * bit is freed in the scoreboard, from this moment onward the register results free to use.
 *
 */

module instruction_scheduler #(
		parameter TILE_ID = 0 )
	(
		input                                               clk,
		input                                               reset,
		input                                               enable,
		// From Instruction Buffer
		input  thread_mask_t                                ib_instructions_valid,
		input  instruction_decoded_t [`THREAD_NUMB - 1 : 0] ib_instructions,

		// From Writeback
		input                                               wb_valid,
		input  thread_id_t                                  wb_thread_id,
		input  wb_result_t                                  wb_result,
		input  ex_pipe_mask_t                               wb_fifo_full,

		// From Rollback Handler
		input  thread_mask_t                                rb_valid,
		input  scoreboard_t          [`THREAD_NUMB - 1 : 0] rb_destination_mask,

		// From DSU
		input  logic                 [`THREAD_NUMB - 1 : 0] dsu_stop_issue,

		// From SPM
		input  logic                                        spm_can_issue,

		// To Operand fetch
		output logic                                        is_instruction_valid,
		output thread_id_t                                  is_thread_id,
		output instruction_decoded_t                        is_instruction,
		output scoreboard_t                                 is_destination_mask,

		output logic                 [`THREAD_NUMB - 1 : 0] scoreboard_empty,
		input  logic                 [`THREAD_NUMB - 1 : 0] bc_release_val,

		// To Instruction Buffer
		output thread_mask_t                                is_thread_scheduled_mask
	);

	logic         [`THREAD_NUMB - 1 : 0 ]   sync_detect, sync_detect_cmb;

	thread_mask_t                           can_issue;
	thread_id_t                             thread_scheduled_id;
	scoreboard_t  [`THREAD_NUMB - 1 : 0]    scoreboard_set_bitmap;

	// FP pending instruction tracker
	logic         [`FP_DIV_DP_LATENCY - 1 : 0] fp_pending_queue;
	logic         [`THREAD_NUMB - 1 : 0]    fp_add_issued, fp_mul_issued, fp_div_issued, fp_cmp_issued, fp_itof_issued, fp_ftoi_issued, fp_dp_add_issued, fp_dp_mul_issued, fp_dp_div_issued, fp_dp_cmp_issued, fp_dp_itof_issued, fp_dp_ftoi_issued;

	genvar                                  thread_id;
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin                                                          : SCOREBOARD_GEN_LOGIC

			scoreboard_t         scoreboard;
			scoreboard_t         scoreboard_next;
			scoreboard_t         scoreboard_clear_bitmap;

			scoreboard_t         source_mask_0;
			scoreboard_t         source_mask_1;
			scoreboard_t         destination_mask;
			scoreboard_t         release_mask;
			logic                issue_this_thread;
			logic                hazard_raw;
			logic                hazard_waw;
			logic        [2 : 0] synch_count;
			
			// FP structural hazard signals
			logic        can_issue_fp;
			logic        is_fp, fp_is_add, fp_is_sub, fp_is_mul, fp_is_div, fp_is_cmp, fp_is_itof, fp_is_ftoi,
						 is_dp, fp_dp_is_add, fp_dp_is_sub, fp_dp_is_mul, fp_dp_is_div, fp_dp_is_cmp, fp_dp_is_itof, fp_dp_is_ftoi;
			
			// SPM structural hazard signal
			logic                is_spm;
			logic                can_issue_spm;

			assign issue_this_thread                = is_thread_scheduled_mask[thread_id];

			always_comb begin
				source_mask_0                                                                                                   = scoreboard_t' ( 1'b0 );
				source_mask_1                                                                                                   = scoreboard_t' ( 1'b0 );
				destination_mask                                                                                                = scoreboard_t' ( 1'b0 );
				release_mask                                                                                                    = scoreboard_t' ( 1'b0 );

				// For each instruction from Instruction Buffer module, a source mask is created. The main purpose is to
				// check eventual data hazards. Each source mask has the same bit number of the scoreboard.
				if ( ib_instructions[thread_id].mask_enable ) begin
					source_mask_0 [reg_addr_t' ( `MASK_REG ) ] = 1'b1;
					source_mask_1 [reg_addr_t' ( `MASK_REG ) ] = 1'b1;
				end

				source_mask_0 [{ib_instructions[thread_id].is_source0_vectorial, ib_instructions[thread_id].source0 }]          = ib_instructions[thread_id].has_source0;
				source_mask_1 [{ib_instructions[thread_id].is_source1_vectorial, ib_instructions[thread_id].source1 }]          = ib_instructions[thread_id].has_source1;
				destination_mask[{ib_instructions[thread_id].is_destination_vectorial, ib_instructions[thread_id].destination}] = ib_instructions[thread_id].has_destination;
				release_mask [{~wb_result.wb_result_is_scalar, wb_result.wb_result_register }]                                  = wb_valid && ( wb_thread_id == thread_id_t' ( thread_id ) );
			end

			// When the AND between the source mask and the scoreboard is not a vector of 0, the current instruction requires
			// a busy register, and a RAW hazard arises. In the same way we check eventual WAW hazard.
			assign hazard_raw                       = |( ( source_mask_0 | source_mask_1 ) & scoreboard );
			assign hazard_waw                       = |( destination_mask & scoreboard );

			// If the instruction is valid, there are no data hazards, the Writeback fifo are not full, no rollback, and the instruction
			// does not raise a structural hazard in the FP pipeline, the thread can be issued.
			assign can_issue[thread_id]             = ib_instructions_valid[thread_id] && !( hazard_raw || hazard_waw ) && ( ~( |wb_fifo_full ) ) &&
				~rb_valid[thread_id] && can_issue_fp && can_issue_spm && bc_release_val[thread_id] && ~sync_detect[thread_id] && ~sync_detect_cmb[thread_id]
				&& ~dsu_stop_issue[thread_id];

			// Scoreboard update logic. When the thread is scheduled, the scoreboard_set_bitmap will update the scoreboard with the destination
			// register, it will set a bit in order to track the destination register used by the current operation. From this moment onward, this
			// register results busy and an instruction which wants to use it will raise a data hazard.
			// The scoreboard_clear_bitmap tracks all registers released by the Writeback stage. An operation in Writeback releases its destination
			// register
			assign scoreboard_set_bitmap[thread_id] = destination_mask & {`SCOREBOARD_LENGTH{issue_this_thread}};
			assign scoreboard_clear_bitmap          = release_mask | ( rb_destination_mask[thread_id] & {`SCOREBOARD_LENGTH{rb_valid[thread_id]}} ) ;
			//assign scoreboard_next                  = ( scoreboard | scoreboard_set_bitmap[thread_id] ) & ( ~scoreboard_clear_bitmap ) ;
			assign scoreboard_next                  = ( scoreboard & ~scoreboard_clear_bitmap ) | scoreboard_set_bitmap[thread_id] ;

			always_ff @ ( posedge clk, posedge reset ) begin
				if ( reset ) begin
					scoreboard <= scoreboard_t' ( 1'b0 );
				end else begin
					scoreboard <= scoreboard_next;
				end
			end

			assign scoreboard_empty[thread_id]      = |scoreboard;
			assign sync_detect[thread_id]           = synch_count != 0;
			assign sync_detect_cmb[thread_id]       = is_instruction.pipe_sel == PIPE_SYNC & is_instruction.thread_id == thread_id_t' ( thread_id ) & is_instruction_valid;

			always_ff @ ( posedge clk, posedge reset )
				if ( reset )
					synch_count <= 0;
				else
					if ( sync_detect_cmb[thread_id] )
						synch_count <= 3;
					else
						if ( synch_count != 0 )
							synch_count <= synch_count - 1;

			// FP structural hazard checking. The FP pipe has one output DEMUX to the Writeback unit. There is no conflict control
			// inside the FP module, two different operation can terminate at the same time and collide in the output propagation.
			// FP operation decoding.
			assign is_fp                            = ib_instructions[thread_id].is_fp;
			assign is_dp							= ib_instructions[thread_id].is_long;
			assign fp_is_add                        = is_fp & (~is_dp) & ib_instructions[thread_id].op_code.alu_opcode == ADD_FP;
			assign fp_is_sub                        = is_fp & (~is_dp) & ib_instructions[thread_id].op_code.alu_opcode == SUB_FP;
			assign fp_is_mul                        = is_fp & (~is_dp) & ib_instructions[thread_id].op_code.alu_opcode == MUL_FP;
			assign fp_is_div                        = is_fp & (~is_dp) & ib_instructions[thread_id].op_code.alu_opcode == DIV_FP;
			assign fp_is_itof                       = is_fp & (~is_dp) & ib_instructions[thread_id].op_code.alu_opcode == ITOF;
			assign fp_is_ftoi                       = is_fp & (~is_dp) & ib_instructions[thread_id].op_code.alu_opcode == FTOI;
			assign fp_is_cmp                        = is_fp & (~is_dp) & ( ib_instructions[thread_id].op_code.alu_opcode >= CMPEQ_FP
					& ib_instructions[thread_id].op_code.alu_opcode <= CMPLE_FP ) ;
			assign fp_dp_is_add                        = is_fp & is_dp & ib_instructions[thread_id].op_code.alu_opcode == ADD_FP;
			assign fp_dp_is_sub                        = is_fp & is_dp & ib_instructions[thread_id].op_code.alu_opcode == SUB_FP;
			assign fp_dp_is_mul                        = is_fp & is_dp & ib_instructions[thread_id].op_code.alu_opcode == MUL_FP;
			assign fp_dp_is_div                        = is_fp & is_dp & ib_instructions[thread_id].op_code.alu_opcode == DIV_FP;
			assign fp_dp_is_itof                       = is_fp & is_dp & ib_instructions[thread_id].op_code.alu_opcode == ITOF;
			assign fp_dp_is_ftoi                       = is_fp & is_dp & ib_instructions[thread_id].op_code.alu_opcode == FTOI;
			assign fp_dp_is_cmp                        = is_fp & is_dp & ( ib_instructions[thread_id].op_code.alu_opcode >= CMPEQ_FP
					& ib_instructions[thread_id].op_code.alu_opcode <= CMPLE_FP ) ;
			// FP checking for collisions. If the element is 1 the FP operation cannot be scheduled
			always_comb begin
				fp_add_issued[thread_id]  = 1'b0;
				fp_mul_issued[thread_id]  = 1'b0;
				fp_div_issued[thread_id]  = 1'b0;
				fp_cmp_issued[thread_id]  = 1'b0;
				fp_itof_issued[thread_id] = 1'b0;
				fp_ftoi_issued[thread_id] = 1'b0;
				fp_dp_add_issued[thread_id]  = 1'b0;
				fp_dp_mul_issued[thread_id]  = 1'b0;
				fp_dp_div_issued[thread_id]  = 1'b0;
				fp_dp_cmp_issued[thread_id]  = 1'b0;
				fp_dp_itof_issued[thread_id] = 1'b0;
				fp_dp_ftoi_issued[thread_id] = 1'b0;

				if ( fp_is_add | fp_is_sub ) begin
					fp_add_issued[thread_id]  = ~fp_pending_queue[`FP_ADD_LATENCY-1];
				end
				else if ( fp_is_mul ) begin
					fp_mul_issued[thread_id]  = ~fp_pending_queue[`FP_MULT_LATENCY-1];
				end
				else if ( fp_is_div ) begin
					fp_div_issued[thread_id]  = ~fp_pending_queue[16];
				end
				else if ( fp_is_cmp ) begin
					fp_cmp_issued[thread_id]  = ~fp_pending_queue[0];
				end
				else if ( fp_is_itof ) begin
					fp_itof_issued[thread_id] = ~fp_pending_queue[`FP_ITOF_LATENCY-1];
				end
				else if ( fp_is_ftoi ) begin
					fp_ftoi_issued[thread_id] = ~fp_pending_queue[`FP_FTOI_LATENCY-1];
				end
				else if ( fp_dp_is_add | fp_dp_is_sub ) begin
					fp_dp_add_issued[thread_id]  = ~fp_pending_queue[`FP_ADD_DP_LATENCY-1];
				end
				else if ( fp_dp_is_mul ) begin
					fp_dp_mul_issued[thread_id]  = ~fp_pending_queue[`FP_MULT_DP_LATENCY-1];
				end
				else if ( fp_dp_is_div ) begin
					fp_dp_div_issued[thread_id]  = ~fp_pending_queue[31];//can remove
				end
				else if ( fp_dp_is_cmp ) begin
					fp_dp_cmp_issued[thread_id]  = ~fp_pending_queue[0];
				end
				else if ( fp_dp_is_itof ) begin
					fp_dp_itof_issued[thread_id] = ~fp_pending_queue[7];
				end
				else if ( fp_dp_is_ftoi ) begin
					fp_dp_ftoi_issued[thread_id] = ~fp_pending_queue[4];
				end
			end

			// When a FP instruction is scheduled (is_fp high), this signal states whether the current instruction causes an
			// instruction hazard or not. When a scheduled FP instruction causes an hazard, this signal disable the thread
			// can issue.
			assign can_issue_fp                     = ( is_fp ) ? ( fp_add_issued[thread_id] | fp_mul_issued[thread_id] 
				| fp_div_issued[thread_id] | fp_cmp_issued[thread_id] | fp_itof_issued[thread_id] | fp_ftoi_issued[thread_id]|
				fp_dp_add_issued[thread_id] | fp_dp_mul_issued[thread_id] | fp_dp_div_issued[thread_id] | fp_dp_cmp_issued[thread_id] | 
				fp_dp_itof_issued[thread_id] | fp_dp_ftoi_issued[thread_id]) : 1'b1;

			// When a SPM memory instruction is scheduled (is_spm high), this signal states whether the current instruction can be
			// dispatched to the SPM or not. The input signal spm_can_issue states if the component is ready to receive a new
			// request.
			assign is_spm                           = ib_instructions[thread_id].pipe_sel == PIPE_SPM;
			assign can_issue_spm                    = ( is_spm ) ? spm_can_issue      : 1'b1;
		end
	endgenerate

	// The arbiter selects an eligible thread from the pool. A thread is eligible if its can_issue
	// bit is high. The arbiter evaluates every can_issue bit and in a Round Robin fashion selects
	// one thread from the eligible pool.
	rr_arbiter # (
		.NUM_REQUESTERS ( `THREAD_NUMB )
	)
	thread_arbiter (
		.clk        ( clk                      ),
		.reset      ( reset                    ),
		.request    ( can_issue                ),
		.update_lru ( |can_issue               ),
		.grant_oh   ( is_thread_scheduled_mask )
	);

	oh_to_idx # (
		.NUM_SIGNALS ( `THREAD_NUMB          ),
		.DIRECTION   ( "LSB0"                ),
		.INDEX_WIDTH ( $bits ( thread_id_t ) )
	)
	oh_to_idx (
		.one_hot ( is_thread_scheduled_mask ),
		.index   ( thread_scheduled_id      )
	);

	// FP pending shifting queue update. This queue keeps track of all FP operation already issued by all threads. When
	// the current thread is scheduled by the arbiter (thread_scheduled_id == thread_id) and it issues a floating point
	// instruction, the queue is updated according to the scheduled operation latency.
    always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			fp_pending_queue <= 0;
		else begin
			//fp_pending_queue <= {1'b0, fp_pending_queue[31 : 1]};
			if ( |can_issue ) begin
				if ( fp_add_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : `FP_ADD_LATENCY],1'b1, fp_pending_queue[`FP_ADD_LATENCY-2 : 1]};
				else if ( fp_mul_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : `FP_MULT_LATENCY],1'b1, fp_pending_queue[`FP_MULT_LATENCY-2 : 1]};
				else if ( fp_div_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : 17],1'b1, fp_pending_queue[15 : 1]};
				else if ( fp_itof_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : `FP_ITOF_LATENCY],1'b1, fp_pending_queue[`FP_ITOF_LATENCY-2 : 1]};
				else if ( fp_ftoi_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : `FP_FTOI_LATENCY],1'b1, fp_pending_queue[`FP_FTOI_LATENCY-2 : 1]};
				else if ( fp_dp_add_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : `FP_ADD_DP_LATENCY],1'b1, fp_pending_queue[`FP_ADD_DP_LATENCY-2 : 1]};
				else if ( fp_dp_mul_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : `FP_MULT_DP_LATENCY],1'b1, fp_pending_queue[`FP_MULT_DP_LATENCY-2 : 1]};
				else if ( fp_dp_div_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,1'b1, fp_pending_queue[30 : 1]};
				else if ( fp_dp_itof_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : 8],1'b1, fp_pending_queue[6 : 1]};
				else if ( fp_dp_ftoi_issued[thread_scheduled_id] )
					fp_pending_queue <= {1'b0,fp_pending_queue[31 : 5],1'b1, fp_pending_queue[3 : 1]};
				else
					fp_pending_queue <= {1'b0, fp_pending_queue[31 : 1]};	
			end else
				fp_pending_queue <= {1'b0, fp_pending_queue[31 : 1]};			
		end
		
	// If at least one thread is eligible (at least one can_issue bit is high), the output is valid
	// and the selected instruction is propagated to the Operand Fetch module.
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			is_instruction_valid <= 1'b0;
		else if ( enable ) begin
			is_instruction_valid <= ( |can_issue ) & ( ~rb_valid[thread_scheduled_id] ) ;
		end

	always_ff @ ( posedge clk ) begin
		if ( enable ) begin
			is_instruction      <= ib_instructions[thread_scheduled_id];
			is_thread_id        <= thread_scheduled_id;
			is_destination_mask <= scoreboard_set_bitmap[thread_scheduled_id];
		end
	end

`ifdef DISPLAY_ISSUE
	always_ff @ ( posedge clk ) begin
		if ( is_instruction_valid & ~reset )
			print_core_issue ( TILE_ID, is_instruction ) ;
	end
`endif

endmodule
