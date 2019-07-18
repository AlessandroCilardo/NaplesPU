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
