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
 * This module manages instruction load requests. It implements a simplification of a circular queue, based on the fact that:
 *      1 - there will not be a number of request major than the number of the queue length;
 *      2 - it is not possible that a request will come when the queue is full (max one request per thread);
 *      3 - a dequeue signal will come only after a request.
 * It has a grouping mechanism: if a request occurs when another request is pending on the same address, it will not create
 * another element in the buffer, but it merges the two requests.
 *
 */

module load_miss_queue(
		input                   clk,
		input                   reset,
		input                   enable,

		/* From Instruction Cache Interface */
		input                   request,
		input  icache_address_t address,
		input  thread_mask_t    threadOh,

		/* From Memory Interface */
		input                   dequeue,

		/* To Instruction Cache Interface */
		output logic            pendingOut,
		output address_t        addressOut,
		output thread_mask_t    threadOhOut
	);

	thread_mask_t    queue_valid;
	icache_address_t queue_address [`THREAD_NUMB];
	thread_mask_t    queue_thread_mask [`THREAD_NUMB];

	thread_id_t      queue_head;
	thread_id_t      queue_tail;

	thread_mask_t    grouping_mask;
	thread_id_t      group_id;
	//logic       is_gropued;

	always_comb begin
		pendingOut  = queue_valid[queue_head];
		addressOut  = queue_address[queue_head];
		threadOhOut = queue_thread_mask[queue_head];
	end

	genvar           thread_id;
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id ++ ) begin
			assign grouping_mask[thread_id]        = ( queue_address[thread_id].index == address.index ) && ( queue_address[thread_id].tag == address.tag );
		end
	endgenerate

	// assign is_gropued = |(queue_valid & grouping_mask);

	oh_to_idx #(
		.NUM_SIGNALS( `THREAD_NUMB           ),
		.DIRECTION  ( "LSB0"                 ),
		.INDEX_WIDTH( $clog2( `THREAD_NUMB ) )
	)
	u_oh_to_idx (
		.one_hot( grouping_mask ),
		.index  ( group_id      )
	);

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			queue_valid <= 0;
			queue_head  <= 0;
			queue_tail  <= 0;
		end else if( enable ) begin
			if ( request & dequeue ) begin
				queue_valid[queue_head] <= 1'b0;
				queue_head              <= queue_head + 1;
				if( |( queue_valid & grouping_mask ) )
					queue_thread_mask[group_id]     <= queue_thread_mask[group_id] | threadOh;
				else begin
					queue_thread_mask[queue_tail]   <= threadOh;
					queue_address[queue_tail].tag   <= address.tag;
					queue_address[queue_tail].index <= address.index;
					queue_address[queue_tail].offset<= 0;
					queue_valid[queue_tail]         <= 1'b1;
					queue_tail                      <= queue_tail + 1;
				end
			end else if ( request ) begin
				if( |( queue_valid & grouping_mask ) )
					queue_thread_mask[group_id]     <= queue_thread_mask[group_id] | threadOh;
				else begin
					queue_thread_mask[queue_tail]   <= threadOh;
					queue_address[queue_tail].tag   <= address.tag;
					queue_address[queue_tail].index <= address.index;
					queue_address[queue_tail].offset<= 0;
					queue_valid[queue_tail]         <= 1'b1;
					queue_tail                      <= queue_tail + 1;
				end
			end else if ( dequeue ) begin
				queue_valid[queue_head] <= 1'b0;
				queue_head              <= queue_head + 1;
			end

		end
	end

endmodule
