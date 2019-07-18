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

`include "npu_defines.sv"
`include "npu_user_defines.sv"
`include "npu_coherence_defines.sv"

/*
 * This module receives from the LDST unit requests for the main memory:
 *  - miss: L1 cache has no match for the current request
 *  - evict: a cache line has to be deleted in favor of another fresh cache line
 *  - flush: the user wants to forward the cache line to the memory (the line is NOT invalidated)
 *  - dinv: the user wants to invalidate the given memory line
 *
 * This module manages five queues (load, store, evict, flush, dinv) that store incoming requests from the LDST unit.
 * The cache controller sets the proper signal to dequeue the requests when it is ready to manage it.
 * Each request is a triple: {valid, threadID, address} (the flush event does not require a valid threadID)
 */

module core_interface (
		input                        clk,
		input                        reset,

		// Load Store Unit
		input  instruction_decoded_t ldst_instruction,
		input  dcache_address_t      ldst_address,
		input  logic                 ldst_miss,
		input  logic                 ldst_evict,
		input  dcache_line_t         ldst_cache_line,
		input  logic                 ldst_flush,
		input  logic                 ldst_dinv,
		input  dcache_store_mask_t   ldst_dirty_mask,

		// Cache Controller
		input  logic                 cc_dequeue_store_request,
		input  logic                 cc_dequeue_load_request,
		input  logic                 cc_dequeue_replacement_request,
		input  logic                 cc_dequeue_flush_request,
		input  logic                 cc_dequeue_dinv_request,
		output logic                 ci_store_request_valid,
		output thread_id_t           ci_store_request_thread_id,
		output dcache_address_t      ci_store_request_address,
		output logic                 ci_store_request_coherent,
		output logic                 ci_load_request_valid,
		output thread_id_t           ci_load_request_thread_id,
		output dcache_address_t      ci_load_request_address,
		output logic                 ci_load_request_coherent,
		output logic                 ci_replacement_request_valid,
		output thread_id_t           ci_replacement_request_thread_id,
		output dcache_address_t      ci_replacement_request_address,
		output dcache_line_t         ci_replacement_request_cache_line,
		output dcache_store_mask_t   ci_replacement_request_dirty_mask,
		output logic                 ci_flush_request_valid,
		output dcache_address_t      ci_flush_request_address,
		output dcache_line_t         ci_flush_request_cache_line,
		output dcache_store_mask_t   ci_flush_request_dirty_mask,
		output logic                 ci_flush_request_coherent,
		output logic                 ci_flush_fifo_available,
		output logic                 ci_dinv_request_valid,
		output dcache_address_t      ci_dinv_request_address,
		output thread_id_t           ci_dinv_request_thread_id,
		output dcache_line_t         ci_dinv_request_cache_line,
		output dcache_store_mask_t   ci_dinv_request_dirty_mask,
		output logic                 ci_dinv_request_coherent
	);

	typedef struct packed {
		thread_id_t      thread_id;
		dcache_address_t address;
		logic            is_coherent;
	} request_to_core;

	typedef struct packed {
		thread_id_t         thread_id;
		dcache_address_t    address;
		dcache_line_t       cache_line;
		dcache_store_mask_t dirty_mask;
		logic               is_coherent;
	} request_to_mem;

	localparam SIZE = `THREAD_NUMB;

	logic      flush_fifo_almost_full;
	assign     ci_flush_fifo_available = ~flush_fifo_almost_full;

	logic      rplcq_empty, lmq_empty, smq_empty, flush_empty, dinv_empty;

	assign ci_load_request_valid         = !lmq_empty,
			ci_store_request_valid       = !smq_empty,
			ci_replacement_request_valid = !rplcq_empty,
			ci_flush_request_valid       = !flush_empty,
			ci_dinv_request_valid        = !dinv_empty;

	request_to_core store_in, store_out;
	request_to_core load_in, load_out;

	request_to_mem  replacement_in, replacement_out;
	request_to_mem  flush_in, flush_out;
	request_to_mem  dinv_in, dinv_out;

	assign store_in.thread_id   = ldst_instruction.thread_id,
	       store_in.address     = ldst_address,
	       store_in.is_coherent = ldst_instruction.is_memory_access_coherent;
	
	assign ci_store_request_thread_id = store_out.thread_id,
	       ci_store_request_address   = store_out.address,
	       ci_store_request_coherent  = store_out.is_coherent;

	sync_fifo #(
		.WIDTH ( $bits(request_to_core) ),
		.SIZE  ( SIZE                   )
	)
	store_miss_queue
	(
		.almost_empty(                                        ),
		.almost_full (                                        ),
		.clk         ( clk                                    ),
		.dequeue_en  ( cc_dequeue_store_request               ),
		.empty       ( smq_empty                              ),
		.enqueue_en  ( ldst_miss && !ldst_instruction.is_load ),
		.flush_en    ( 1'b0                                   ),
		.full        (                                        ),
		.reset       ( reset                                  ),
		.value_i     ( store_in                               ),
		.value_o     ( store_out                              )
	);

	assign load_in.thread_id   = ldst_instruction.thread_id,
	       load_in.address     = ldst_address,
	       load_in.is_coherent = ldst_instruction.is_memory_access_coherent;
	
	assign ci_load_request_thread_id = load_out.thread_id,
	       ci_load_request_address   = load_out.address,
	       ci_load_request_coherent  = load_out.is_coherent;

	sync_fifo #(
		.WIDTH ( $bits(request_to_core) ),
		.SIZE  ( SIZE                   )
	)
	load_miss_queue
	(
		.almost_empty(                                       ),
		.almost_full (                                       ),
		.clk         ( clk                                   ),
		.dequeue_en  ( cc_dequeue_load_request               ),
		.empty       ( lmq_empty                             ),
		.enqueue_en  ( ldst_miss && ldst_instruction.is_load ),
		.flush_en    ( 1'b0                                  ),
		.full        (                                       ),
		.reset       ( reset                                 ),
		.value_i     ( load_in                               ),
		.value_o     ( load_out                              )
	);

	assign replacement_in.thread_id   = ldst_instruction.thread_id,
	       replacement_in.address     = ldst_address,
	       replacement_in.cache_line  = ldst_cache_line,
	       replacement_in.dirty_mask  = ldst_dirty_mask,
	       replacement_in.is_coherent = 1'b0; // is_coherent checked inside the cache controller
	
	assign ci_replacement_request_thread_id  = replacement_out.thread_id,
	       ci_replacement_request_address    = replacement_out.address,
	       ci_replacement_request_cache_line = replacement_out.cache_line,
	       ci_replacement_request_dirty_mask = replacement_out.dirty_mask;

	sync_fifo #(
		.WIDTH ( $bits(request_to_mem) ),
		.SIZE  ( SIZE                  )
	)
	replacement_queue
	(
		.almost_empty(                                ),
		.almost_full (                                ),
		.clk         ( clk                            ),
		.dequeue_en  ( cc_dequeue_replacement_request ),
		.empty       ( rplcq_empty                    ),
		.enqueue_en  ( ldst_evict                     ),
		.flush_en    ( 1'b0                           ),
		.full        (                                ),
		.reset       ( reset                          ),
		.value_i     ( replacement_in                 ),
		.value_o     ( replacement_out                )
	);

	assign flush_in.thread_id   = 0, // threads don't block on flush
	       flush_in.address     = ldst_address,
	       flush_in.cache_line  = ldst_cache_line,
	       flush_in.dirty_mask  = ldst_dirty_mask,
	       flush_in.is_coherent = ldst_instruction.is_memory_access_coherent;
	
	assign ci_flush_request_address    = flush_out.address,
	       ci_flush_request_cache_line = flush_out.cache_line,
	       ci_flush_request_dirty_mask = flush_out.dirty_mask,
	       ci_flush_request_coherent   = flush_out.is_coherent;

	sync_fifo #(
		.WIDTH                 ( $bits(request_to_mem) ),
		.SIZE                  ( SIZE                  ),
		.ALMOST_FULL_THRESHOLD ( SIZE - 3              )
	)
	flush_queue
	(
		.almost_empty(                          ),
		.almost_full ( flush_fifo_almost_full   ),
		.clk         ( clk                      ),
		.dequeue_en  ( cc_dequeue_flush_request ),
		.empty       ( flush_empty              ),
		.enqueue_en  ( ldst_flush               ),
		.flush_en    ( 1'b0                     ),
		.full        (                          ),
		.reset       ( reset                    ),
		.value_i     ( flush_in                 ),
		.value_o     ( flush_out                )
	);

	assign dinv_in.thread_id   = ldst_instruction.thread_id,
	       dinv_in.address     = ldst_address,
	       dinv_in.cache_line  = ldst_cache_line,
	       dinv_in.dirty_mask  = ldst_dirty_mask,
	       dinv_in.is_coherent = ldst_instruction.is_memory_access_coherent;
	
	assign ci_dinv_request_thread_id  = dinv_out.thread_id,
	       ci_dinv_request_address    = dinv_out.address,
	       ci_dinv_request_cache_line = dinv_out.cache_line,
	       ci_dinv_request_dirty_mask = dinv_out.dirty_mask,
	       ci_dinv_request_coherent   = dinv_out.is_coherent;

	sync_fifo #(
		.WIDTH ( $bits(request_to_mem) ),
		.SIZE  ( SIZE                  )
	)
	dinv_queue
	(
		.almost_empty(                         ),
		.almost_full (                         ),
		.clk         ( clk                     ),
		.dequeue_en  ( cc_dequeue_dinv_request ),
		.empty       ( dinv_empty              ),
		.enqueue_en  ( ldst_dinv               ),
		.flush_en    ( 1'b0                    ),
		.full        (                         ),
		.reset       ( reset                   ),
		.value_i     ( dinv_in                 ),
		.value_o     ( dinv_out                )
	);

endmodule
