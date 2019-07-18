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
 * Thread Controller handles eligible threads pool. This module blocks threads that cannot
 * proceed due cache misses or scoreboarding. Dually, Thread Controller handles threads
 * wake-up when the blocking conditions are no more trues.
 *
 * Furthermore, the Thread Controller interfaces core instruction cache and the higher level
 * in the memory hierarchy. Instruction miss requests are directly forwarded to the memory
 * controller through the network on chip (or the bus in the single core version).
 *
 * The third task performed is to accept the jobs from host interface and redirect them to the thread controller.
 *
 * Note:  a load/store miss blocks the corresponding thread until data is
 * gather from main memory throughput the ib_fifo_full signal.
 *
 */

module thread_controller (
		input                clk,
		input                reset,
		input                enable,

		// Host Interface
		input  logic         hi_job_valid,
		input  address_t     hi_job_pc,
		input  thread_id_t   hi_job_thread_id,

		// Instruction fetch stage
		input                if_cache_miss,
		input  thread_mask_t if_thread_miss,
		input  address_t     if_address_miss,

		output icache_lane_t tc_if_data_out,
		output address_t     tc_if_addr_update_cache,
		output logic         tc_if_valid_update_cache,
		output thread_mask_t tc_if_thread_en,

		output address_t     tc_job_pc,
		output thread_id_t   tc_job_thread_id,
		output logic         tc_job_valid,

		input  thread_mask_t thread_en,                  // external signal from user
		input  thread_mask_t ib_fifo_full,               // from instruction buffer
		input  thread_mask_t dsu_stop_issue,             // from dsu
		// Memory interface
		input                mem_instr_request_available,
		input  icache_lane_t mem_instr_request_data_in,
		input                mem_instr_request_valid,

		output logic         tc_instr_request_valid,
		output address_t     tc_instr_request_address
	);

	// Booting from Host Interface, directly connected to the Instruction Fetch stage
	assign tc_job_valid          = hi_job_valid;
	assign tc_job_pc             = hi_job_pc;
	assign tc_job_thread_id      = hi_job_thread_id;

//  -----------------------------------------------------------------------
//  -- Thread Controller - Instruction Request Queues
//  -----------------------------------------------------------------------

	logic         pending_out_icache;
	thread_mask_t thread_oh_out_icache, thread_oh_pending;
	address_t     address_out_icache, address_pending;

	// This module queues instruction cache load misses. It also merges requests
	// to the same instruction address from different threads, it tracks with a
	// bitmap each thread blocked on a memory request.
	load_miss_queue istruction_load_miss_queue (
		.clk        ( clk                     ),
		.reset      ( reset                   ),
		.enable     ( enable                  ),
		//Instruction Cache Interface
		.request    ( if_cache_miss           ),
		.address    ( if_address_miss         ),
		.threadOh   ( if_thread_miss          ),
		.dequeue    ( mem_instr_request_valid ),
		.pendingOut ( pending_out_icache      ),
		.addressOut ( address_out_icache      ),
		.threadOhOut( thread_oh_out_icache    )
	);

//  -----------------------------------------------------------------------
//  -- Thread Controller - Thread handler
//  -----------------------------------------------------------------------

	thread_mask_t thread_mem_wakeup, thread_miss_sleep;
	thread_mask_t wait_thread_mask, wait_thread_mask_next;

	// It's asserted a bit only if a non-waiting (active) thread is enabled from the user
	assign tc_if_thread_en       = ~wait_thread_mask & thread_en & ~ib_fifo_full & ~dsu_stop_issue;

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			wait_thread_mask <= {`THREAD_NUMB{1'b0}};
		end else begin
			wait_thread_mask <= wait_thread_mask_next;
		end
	end

	// The waiting thread signal is a registered signal and the output is feedback
	// and mixed with the asleep and activated current threads
	assign wait_thread_mask_next = ( wait_thread_mask | thread_miss_sleep ) & ~thread_mem_wakeup;

	// 1: thread[i] activated, 0: thread[i] state unmodified (only referred to the current threads)
	assign thread_mem_wakeup     = ( mem_instr_request_valid ) ?
		( if_cache_miss & if_address_miss[31:`ICACHE_OFFSET_LENGTH] == address_pending[31:`ICACHE_OFFSET_LENGTH] ) ? ( thread_oh_out_icache | thread_oh_pending | if_thread_miss )
		: thread_oh_out_icache
		: {`THREAD_NUMB{1'b0}};

	// 1: thread[i] asleep, 0: thread[i] state unmodified (only referred to the current threads)
	assign thread_miss_sleep     = ( if_cache_miss ) ?
		( mem_instr_request_valid & if_address_miss == address_pending ) ? {`THREAD_NUMB{1'b0}}
		: if_thread_miss
		: {`THREAD_NUMB{1'b0}};

//  -----------------------------------------------------------------------
//  -- Thread Controller - Instruction Memory Interface FSM
//  -----------------------------------------------------------------------

	typedef enum logic [1 : 0] {IDLE, FETCH, WAITING_MEM} state_t;
	state_t       state;

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			state                    <= IDLE;
			tc_instr_request_valid   <= 0;
			tc_if_valid_update_cache <= 0;
			address_pending          <= 0;
			thread_oh_pending        <= thread_mask_t'(0);
			tc_instr_request_address <= address_t'(0);
		end else begin
			tc_instr_request_valid   <= 1'b0;
			tc_if_valid_update_cache <= 0;

			case( state )
				IDLE        : begin
					if ( pending_out_icache ) begin
						// saving the pending address e register
						thread_oh_pending        <= thread_oh_out_icache;
						address_pending          <= address_out_icache;
						tc_instr_request_address <= address_out_icache;
						state                    <= FETCH;
					end else
						state                    <= IDLE;
				end

				FETCH       : begin
					if ( !mem_instr_request_available )
						state                    <= FETCH;
					else begin
						tc_instr_request_valid   <= 1'b1;
						state                    <= WAITING_MEM;
					end
				end

				WAITING_MEM : begin
					if ( !mem_instr_request_valid )
						state                    <= WAITING_MEM;
					else begin
						tc_if_valid_update_cache <= 1'b1;
						state                    <= IDLE;
					end
				end

			endcase
		end
	end

	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			tc_if_data_out          <= 0;
			tc_if_addr_update_cache <= 0;
		end else begin
			tc_if_data_out          <= mem_instr_request_data_in;
			tc_if_addr_update_cache <= address_pending;
		end


endmodule
