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
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"

// This module allocates the Cache Controller and the Core Interface associated.

module l1d_cache #(
		parameter TILE_ID = 0,
		parameter CORE_ID = 0 )
	(

		input                                                       clk,
		input                                                       reset,

		// Core
		input  instruction_decoded_t                                ldst_instruction,
		input  dcache_address_t                                     ldst_address,
		input  logic                                                ldst_miss,
		input  logic                                                ldst_evict,
		input  dcache_line_t                                        ldst_cache_line,
		input  logic                                                ldst_flush,
		input  logic                                                ldst_dinv,
		input  dcache_store_mask_t                                  ldst_dirty_mask,

		output logic                                                cc_update_ldst_valid,
		output dcache_way_idx_t                                     cc_update_ldst_way,
		output dcache_address_t                                     cc_update_ldst_address,
		output dcache_privileges_t                                  cc_update_ldst_privileges,
		output dcache_line_t                                        cc_update_ldst_store_value,
		output cc_command_t                                         cc_update_ldst_command,
		output logic                                                ci_flush_fifo_available,

		output logic                                                cc_snoop_data_valid,
		output dcache_set_t                                         cc_snoop_data_set,
		output dcache_way_idx_t                                     cc_snoop_data_way,
		input  dcache_line_t                                        ldst_snoop_data,

		input  dcache_set_t                                         ldst_lru_update_set,
		input  logic                                                ldst_lru_update_en,
		input  dcache_way_idx_t                                     ldst_lru_update_way,

		output logic                                                cc_wakeup,
		output thread_id_t                                          cc_wakeup_thread_id,

		output logic                                                cc_snoop_tag_valid,
		output dcache_set_t                                         cc_snoop_tag_set,

		input  dcache_privileges_t   [`DCACHE_WAY - 1 : 0]          ldst_snoop_privileges,
		input  dcache_tag_t          [`DCACHE_WAY - 1 : 0]          ldst_snoop_tag,

		// From Network Interface
		input  logic                                                ni_request_network_available,
		input  logic                                                ni_forward_network_available,
		input  logic                                                ni_response_network_available,
		input  coherence_forwarded_message_t                        ni_forwarded_request,
		input  logic                                                ni_forwarded_request_valid,
		input  coherence_response_message_t                         ni_response,
		input  logic                                                ni_response_valid,

		// To Network Interface
		output logic                                                l1d_forwarded_request_consumed,
		output logic                                                l1d_response_consumed,
		output logic                                                l1d_request_valid,
		output coherence_request_message_t                          l1d_request,
		output logic                                                l1d_request_has_data,
		output tile_address_t                [1 : 0]                l1d_request_destinations,
		output logic                         [1 : 0]                l1d_request_destinations_valid,

		output logic                                                l1d_response_valid,
		output coherence_response_message_t                         l1d_response,
		output logic                                                l1d_response_has_data,
		output tile_address_t                [1 : 0]                l1d_response_destinations,
		output logic                         [1 : 0]                l1d_response_destinations_valid,

		output logic                                                l1d_forwarded_request_valid,
		output coherence_forwarded_message_t                        l1d_forwarded_request,
		output tile_address_t                                       l1d_forwarded_request_destination,

		// To Thread Controller
		output icache_lane_t                                        mem_instr_request_data_in,
		output logic                                                mem_instr_request_valid
	);

	logic                                     ci_store_request_valid;
	thread_id_t                               ci_store_request_thread_id;
	dcache_address_t                          ci_store_request_address;
	logic                                     ci_store_request_coherent;
	logic                                     ci_load_request_valid;
	thread_id_t                               ci_load_request_thread_id;
	dcache_address_t                          ci_load_request_address;
	logic                                     ci_load_request_coherent;
	logic                                     ci_replacement_request_valid;
	thread_id_t                               ci_replacement_request_thread_id;
	dcache_address_t                          ci_replacement_request_address;
	dcache_line_t                             ci_replacement_request_cache_line;
	dcache_store_mask_t                       ci_replacement_request_dirty_mask;
	logic                                     ci_flush_request_valid;
	dcache_address_t                          ci_flush_request_address;
	logic                                     ci_flush_request_coherent;
	dcache_store_mask_t                       ci_flush_request_dirty_mask;
	logic                                     ci_dinv_request_valid;
	dcache_address_t                          ci_dinv_request_address;
	thread_id_t                               ci_dinv_request_thread_id;
	dcache_line_t                             ci_dinv_request_cache_line;
	logic                                     ci_dinv_request_coherent;
	dcache_store_mask_t                       ci_dinv_request_dirty_mask;

	logic                                     cc_dequeue_store_request;
	logic                                     cc_dequeue_load_request;
	logic                                     cc_dequeue_replacement_request;
	logic                                     cc_dequeue_flush_request;
	logic                                     cc_dequeue_dinv_request;

	core_interface u_core_interface (
		.clk                              ( clk                               ),
		.reset                            ( reset                             ),
		//Load Store Unit
		.ldst_instruction                 ( ldst_instruction                  ),
		.ldst_address                     ( ldst_address                      ),
		.ldst_miss                        ( ldst_miss                         ),
		.ldst_evict                       ( ldst_evict                        ),
		.ldst_flush                       ( ldst_flush                        ),
		.ldst_dinv                        ( ldst_dinv                         ),
		.ldst_dirty_mask                  ( ldst_dirty_mask                   ),
		.ldst_cache_line                  ( ldst_cache_line                   ),
		//Cache Controller
		.cc_dequeue_store_request         ( cc_dequeue_store_request          ),
		.cc_dequeue_load_request          ( cc_dequeue_load_request           ),
		.cc_dequeue_replacement_request   ( cc_dequeue_replacement_request    ),
		.cc_dequeue_flush_request         ( cc_dequeue_flush_request          ),
		.cc_dequeue_dinv_request          ( cc_dequeue_dinv_request           ),
		.ci_store_request_valid           ( ci_store_request_valid            ),
		.ci_store_request_thread_id       ( ci_store_request_thread_id        ),
		.ci_store_request_address         ( ci_store_request_address          ),
		.ci_store_request_coherent        ( ci_store_request_coherent         ),
		.ci_load_request_valid            ( ci_load_request_valid             ),
		.ci_load_request_thread_id        ( ci_load_request_thread_id         ),
		.ci_load_request_address          ( ci_load_request_address           ),
		.ci_load_request_coherent         ( ci_load_request_coherent          ),
		.ci_replacement_request_valid     ( ci_replacement_request_valid      ),
		.ci_replacement_request_thread_id ( ci_replacement_request_thread_id  ),
		.ci_replacement_request_address   ( ci_replacement_request_address    ),
		.ci_replacement_request_cache_line( ci_replacement_request_cache_line ),
		.ci_replacement_request_dirty_mask( ci_replacement_request_dirty_mask ),
		.ci_flush_request_valid           ( ci_flush_request_valid            ),
		.ci_flush_request_address         ( ci_flush_request_address          ),
		.ci_flush_request_cache_line      (                                   ),
		.ci_flush_request_coherent        ( ci_flush_request_coherent         ),
		.ci_flush_request_dirty_mask      ( ci_flush_request_dirty_mask       ),
		.ci_flush_fifo_available          ( ci_flush_fifo_available           ),
		.ci_dinv_request_valid            ( ci_dinv_request_valid             ),
		.ci_dinv_request_address          ( ci_dinv_request_address           ),
		.ci_dinv_request_thread_id        ( ci_dinv_request_thread_id         ),
		.ci_dinv_request_cache_line       ( ci_dinv_request_cache_line        ),
		.ci_dinv_request_coherent         ( ci_dinv_request_coherent          ),
		.ci_dinv_request_dirty_mask       ( ci_dinv_request_dirty_mask        )
	);

	cache_controller #(
		.TILE_ID( TILE_ID ),
		.CORE_ID( CORE_ID )
	) u_cache_controller (
		.clk                                  ( clk                               ),
		.reset                                ( reset                             ),
		//From Core Interface
		.ci_store_request_valid               ( ci_store_request_valid            ),
		.ci_store_request_thread_id           ( ci_store_request_thread_id        ),
		.ci_store_request_address             ( ci_store_request_address          ),
		.ci_store_request_coherent            ( ci_store_request_coherent         ),
		.ci_load_request_valid                ( ci_load_request_valid             ),
		.ci_load_request_thread_id            ( ci_load_request_thread_id         ),
		.ci_load_request_address              ( ci_load_request_address           ),
		.ci_load_request_coherent             ( ci_load_request_coherent          ),
		.ci_replacement_request_valid         ( ci_replacement_request_valid      ),
		.ci_replacement_request_thread_id     ( ci_replacement_request_thread_id  ),
		.ci_replacement_request_address       ( ci_replacement_request_address    ),
		.ci_replacement_request_cache_line    ( ci_replacement_request_cache_line ),
		.ci_replacement_request_dirty_mask    ( ci_replacement_request_dirty_mask ),
		.ci_flush_request_valid               ( ci_flush_request_valid            ),
		.ci_flush_request_address             ( ci_flush_request_address          ),
		.ci_flush_request_coherent            ( ci_flush_request_coherent         ),
		.ci_flush_request_dirty_mask          ( ci_flush_request_dirty_mask       ),
		.ci_dinv_request_valid                ( ci_dinv_request_valid             ),
		.ci_dinv_request_address              ( ci_dinv_request_address           ),
		.ci_dinv_request_cache_line           ( ci_dinv_request_cache_line        ),
		.ci_dinv_request_thread_id            ( ci_dinv_request_thread_id         ),
		.ci_dinv_request_coherent             ( ci_dinv_request_coherent          ),
		.ci_dinv_request_dirty_mask           ( ci_dinv_request_dirty_mask        ),
		//From Network Interface
		.ni_request_network_available         ( ni_request_network_available      ),
		.ni_forward_network_available         ( ni_forward_network_available      ),
		.ni_response_network_available        ( ni_response_network_available     ),
		.ni_forwarded_request                 ( ni_forwarded_request              ),
		.ni_forwarded_request_valid           ( ni_forwarded_request_valid        ),
		.ni_response_eject                    ( ni_response                       ),
		.ni_response_eject_valid              ( ni_response_valid                 ),
		//From Load Store Unit
		.ldst_snoop_tag                       ( ldst_snoop_tag                    ),
		.ldst_snoop_privileges                ( ldst_snoop_privileges             ),
		.ldst_lru_update_set                  ( ldst_lru_update_set               ),
		.ldst_lru_update_en                   ( ldst_lru_update_en                ),
		.ldst_lru_update_way                  ( ldst_lru_update_way               ),
		.ldst_snoop_data                      ( ldst_snoop_data                   ),
		//To Core Interface
		.cc_dequeue_store_request             ( cc_dequeue_store_request          ),
		.cc_dequeue_load_request              ( cc_dequeue_load_request           ),
		.cc_dequeue_replacement_request       ( cc_dequeue_replacement_request    ),
		.cc_dequeue_flush_request             ( cc_dequeue_flush_request          ),
		.cc_dequeue_dinv_request              ( cc_dequeue_dinv_request           ),
		//To Network Interface
		.cc_forwarded_request_consumed        ( l1d_forwarded_request_consumed    ),
		.cc_response_eject_consumed           ( l1d_response_consumed             ),
		.cc_request_valid                     ( l1d_request_valid                 ),
		.cc_request                           ( l1d_request                       ),
		.cc_request_has_data                  ( l1d_request_has_data              ),
		.cc_request_destinations              ( l1d_request_destinations          ),
		.cc_request_destinations_valid        ( l1d_request_destinations_valid    ),
		.cc_response_inject_valid             ( l1d_response_valid                ),
		.cc_response_inject                   ( l1d_response                      ),
		.cc_response_inject_has_data          ( l1d_response_has_data             ),
		.cc_response_inject_destinations      ( l1d_response_destinations         ),
		.cc_response_inject_destinations_valid( l1d_response_destinations_valid   ),
		.cc_forwarded_request_valid           ( l1d_forwarded_request_valid       ),
		.cc_forwarded_request                 ( l1d_forwarded_request             ),
		.cc_forwarded_request_destination     ( l1d_forwarded_request_destination ),
		//To Load Store Unit
		.cc_snoop_tag_valid                   ( cc_snoop_tag_valid                ),
		.cc_snoop_tag_set                     ( cc_snoop_tag_set                  ),
		.cc_update_ldst_valid                 ( cc_update_ldst_valid              ),
		.cc_update_ldst_command               ( cc_update_ldst_command            ),
		.cc_update_ldst_way                   ( cc_update_ldst_way                ),
		.cc_update_ldst_address               ( cc_update_ldst_address            ),
		.cc_update_ldst_privileges            ( cc_update_ldst_privileges         ),
		.cc_update_ldst_store_value           ( cc_update_ldst_store_value        ),
		.cc_snoop_data_valid                  ( cc_snoop_data_valid               ),
		.cc_snoop_data_set                    ( cc_snoop_data_set                 ),
		.cc_snoop_data_way                    ( cc_snoop_data_way                 ),
		.cc_wakeup                            ( cc_wakeup                         ),
		.cc_wakeup_thread_id                  ( cc_wakeup_thread_id               ),
		.mem_instr_request_data_in            ( mem_instr_request_data_in         ),
		.mem_instr_request_valid              ( mem_instr_request_valid           )
	);

endmodule
