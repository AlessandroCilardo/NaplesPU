`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"

/*
 * This module receives a decoded instruction and stores it in a FIFO. Each thread has its private FIFO.
 * The enqueue is allowed only when the FIFO is not full, otherwise the Decode unit is notified and it will
 * stop the instruction decoding until the FIFO is full.
 * The output instruction is forwarded to the instruction scheduler (or Dynamic Scheduler), which controls
 * the dequeue signal for each FIFO. The Dynamic Scheduler dequeues the request when processes it.
 *
 * The main purpose of this module is to decouple the high speed of instruction decoding with the lower speed
 * of instruction issuing due to hazards and stalls in the datapath. The second goal is to flush the instruction
 * fetched when a rollback is performed, avoiding inaccurate handling of exceptional event that change the
 * normal flow of fetching.
 *
 */
module instruction_buffer #(
		parameter THREAD_FIFO_LENGTH = 8 )
	(
		input                                               clk,
		input                                               reset,
		input                                               enable,

		//From Decode
		input                                               dec_valid,
		input  instruction_decoded_t                        dec_instr,

		//From Dynamic Scheduler
		input  thread_mask_t                                is_thread_scheduled_mask,

		// From L1D
		input  thread_mask_t                                l1d_full,

		//From Rollback Handler
		input  thread_mask_t                                rb_valid,

		//To Instruction Fetch
		output thread_mask_t                                ib_fifo_full,

		//To Dynamic Scheduler
		output thread_mask_t                                ib_instructions_valid,
		output instruction_decoded_t [`THREAD_NUMB - 1 : 0] ib_instructions
	);

	genvar thread_id;
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin

			logic instruction_valid;
			logic fifo_empty;

			assign instruction_valid                = dec_valid && ( dec_instr.thread_id == thread_id_t'( thread_id ) ) && ( !rb_valid[thread_id] );

			sync_fifo #(
				.WIDTH                ( $bits( instruction_decoded_t ) ),
				.SIZE                 ( THREAD_FIFO_LENGTH             ),
				.ALMOST_FULL_THRESHOLD( THREAD_FIFO_LENGTH - 5         )
			) instruction_fifo (
				.clk          ( clk                                 ),
				.reset        ( reset                               ),
				.flush_en     ( rb_valid[thread_id]                 ),
				.full         (                                     ),
				.almost_full  ( ib_fifo_full[thread_id]             ),
				.enqueue_en   ( instruction_valid                   ),
				.value_i      ( dec_instr                           ),
				.empty        ( fifo_empty                          ),
				.almost_empty (                                     ),
				.dequeue_en   ( is_thread_scheduled_mask[thread_id] ),
				.value_o      ( ib_instructions[thread_id]          )
			);

			assign ib_instructions_valid[thread_id] = ~fifo_empty & ~( l1d_full[thread_id] & ib_instructions[thread_id].pipe_sel == PIPE_MEM ) & enable;

		end
	endgenerate

endmodule
