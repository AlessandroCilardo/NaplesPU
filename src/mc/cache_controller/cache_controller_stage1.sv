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
`include "npu_coherence_defines.sv"

`ifdef DISPLAY_COHERENCE
`include "npu_debug_log.sv"
`endif

/*
 * Stage 1 is responsible for the scheduling of requests into the controller. 
 * A request could be a load miss, store miss, flush and replacement request 
 * from the local core or a coherence forwarded request or response from the 
 * network interface.
 */ 

module cache_controller_stage1 #(
		parameter TILE_ID = 0,
		parameter CORE_ID = 0 )
	(

		input                                                             clk,
		input                                                             reset,

		// From Core Interface
		input  logic                                                      ci_store_request_valid,
		input  thread_id_t                                                ci_store_request_thread_id,
		input  dcache_address_t                                           ci_store_request_address,
		input  logic                                                      ci_store_request_coherent,
		input  logic                                                      ci_load_request_valid,
		input  thread_id_t                                                ci_load_request_thread_id,
		input  dcache_address_t                                           ci_load_request_address,
		input  logic                                                      ci_load_request_coherent,
		input  logic                                                      ci_replacement_request_valid,
		input  thread_id_t                                                ci_replacement_request_thread_id,
		input  dcache_address_t                                           ci_replacement_request_address,
		input  dcache_line_t                                              ci_replacement_request_cache_line,
		input  dcache_store_mask_t                                        ci_replacement_request_dirty_mask,
		input  logic                                                      ci_flush_request_valid,
		input  dcache_address_t                                           ci_flush_request_address,
		input  dcache_store_mask_t                                        ci_flush_request_dirty_mask,
		input  logic                                                      ci_flush_request_coherent,
		input  logic                                                      ci_dinv_request_valid,
		input  dcache_address_t                                           ci_dinv_request_address,
		input  thread_id_t                                                ci_dinv_request_thread_id,
		input  dcache_line_t                                              ci_dinv_request_cache_line,
		input  dcache_store_mask_t                                        ci_dinv_request_dirty_mask,
		input  logic                                                      ci_dinv_request_coherent,

		// From Response Recycled Buffer
		input  logic                                                      rrb_response_valid,
		input  coherence_response_message_t                               rrb_response,

		// From Network Interface
		input  coherence_forwarded_message_t                              ni_forwarded_request,
		input                                                             ni_forwarded_request_valid,
		input  coherence_response_message_t                               ni_response,
		input                                                             ni_response_valid,
		input  logic                                                      ni_request_network_available,
		input  logic                                                      ni_forward_network_available,
		input  logic                                                      ni_response_network_available,

		// From Cache Controller Stage 2
		input  logic                                                      cc2_pending_valid,
		input  dcache_address_t                                           cc2_pending_address,
		input  logic                         [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_hit,
		input  logic                         [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_hit_set,
		input  mshr_idx_t                    [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_index,
		input  mshr_entry_t                  [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_entry_info,
        input  logic 		                                              cc2_request_mshr_full,


		// From Cache Controller Stage 3
		input  logic                                                      cc3_pending_valid,
		input  dcache_address_t                                           cc3_pending_address,

		// To Core Interface
		output logic                                                      cc1_dequeue_store_request,
		output logic                                                      cc1_dequeue_load_request,
		output logic                                                      cc1_dequeue_replacement_request,
		output logic                                                      cc1_dequeue_flush_request,
		output logic                                                      cc1_dequeue_dinv_request,

		// To Network Interface
		output logic                                                      cc1_forwarded_request_consumed,
		output logic                                                      cc1_response_eject_consumed,

		// To Response Recycled Buffer
		output logic                                                      cc1_response_recycled_consumed,

		// To Cache Controller Stage 2
		output logic                                                      cc1_request_valid,
		output coherence_request_t                                        cc1_request,
		output logic                                                      cc1_request_mshr_hit,
		output mshr_idx_t                                                 cc1_request_mshr_index,
		output mshr_entry_t                                               cc1_request_mshr_entry_info,
		output thread_id_t                                                cc1_request_thread_id,
		output dcache_address_t                                           cc1_request_address,
		output dcache_line_t                                              cc1_request_data,
		output dcache_store_mask_t                                        cc1_request_dirty_mask,
		output tile_address_t                                             cc1_request_source,
		output sharer_count_t                                             cc1_request_sharers_count,
		output message_response_t                                         cc1_request_packet_type,
		output logic                                                      cc1_request_from_dir,   
		output dcache_tag_t                  [`MSHR_LOOKUP_PORTS - 2 : 0] cc1_mshr_lookup_tag,
		output dcache_set_t                  [`MSHR_LOOKUP_PORTS - 2 : 0] cc1_mshr_lookup_set,

		// To Load Store Unit
		output logic                                                      cc1_snoop_tag_valid,
		output dcache_set_t                                               cc1_snoop_tag_set,

		// To Thread Controller
		output icache_lane_t                                              mem_instr_request_data_in,
		output logic                                                      mem_instr_request_valid

	);

	localparam MSHR_LOOKUP_PORT_REPLACEMENT       = `MSHR_LOOKUP_PORT_REPLACEMENT;
	localparam MSHR_LOOKUP_PORT_STORE             = `MSHR_LOOKUP_PORT_STORE;
	localparam MSHR_LOOKUP_PORT_LOAD              = `MSHR_LOOKUP_PORT_LOAD;
	localparam MSHR_LOOKUP_PORT_FORWARDED_REQUEST = `MSHR_LOOKUP_PORT_FORWARDED_REQUEST;
	localparam MSHR_LOOKUP_PORT_RESPONSE          = `MSHR_LOOKUP_PORT_RESPONSE;
	localparam MSHR_LOOKUP_PORT_FLUSH             = `MSHR_LOOKUP_PORT_FLUSH;
	localparam MSHR_LOOKUP_PORT_RECYCLED          = `MSHR_LOOKUP_PORT_RECYCLED;
	localparam MSHR_LOOKUP_PORT_DINV              = `MSHR_LOOKUP_PORT_DINV;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 1 - Signals declaration
//  -----------------------------------------------------------------------

	logic                    output_request_valid;
	logic                    output_instr_request_valid;
	coherence_request_t      output_request;
	logic                    output_mshr_hit;
	mshr_idx_t               output_mshr_index;
	mshr_entry_t             output_mshr_entry;
	thread_id_t              output_request_thread_id;
	dcache_address_t         output_request_address;
	dcache_line_t            output_request_data;
	dcache_store_mask_t      output_request_dirty_mask;
	tile_address_t           output_request_source;
	sharer_count_t           output_request_sharers_count;
	message_responses_enum_t output_request_packet_type;
	logic                    output_request_from_dir;

	mshr_entry_t    recycled_response_mshr;
	mshr_entry_t    replacement_mshr;
	mshr_entry_t    store_mshr;
	mshr_entry_t    load_mshr;
	mshr_entry_t    flush_mshr;
	mshr_entry_t    dinv_mshr;
	mshr_entry_t    forwarded_request_mshr;
	mshr_entry_t    response_mshr;

	mshr_idx_t      recycled_response_mshr_index;
	mshr_idx_t      replacement_mshr_index;
	mshr_idx_t      store_mshr_index;
	mshr_idx_t      load_mshr_index;
	mshr_idx_t      flush_mshr_index;
	mshr_idx_t      dinv_mshr_index;
	mshr_idx_t      forwarded_request_mshr_index;
	mshr_idx_t      response_mshr_index;

	logic           recycled_response_mshr_hit;
	logic           replacement_mshr_hit_set;
	logic           store_mshr_hit;
	logic           load_mshr_hit;
	logic           flush_mshr_hit;
	logic           dinv_mshr_hit;
	logic           forwarded_request_mshr_hit;
	logic           response_mshr_hit;

	logic           stall_replacement;
	logic           stall_store;
	logic           stall_load;
	logic           stall_forwarded_request;
	logic           stall_flush;
	logic           stall_dinv;

	logic           can_issue_replacement;
	logic           can_issue_flush;
	logic           can_issue_dinv;
	logic           can_issue_store;
	logic           can_issue_load;
	logic           can_issue_forwarded_request;
	logic           can_issue_response;
	logic 		can_issue_recycled_response;

	logic           load_is_coherent;
	logic           store_is_coherent;
	logic           replacement_is_coherent;
	logic           flush_is_coherent;
	logic           dinv_is_coherent;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 1 - Request & MSHR info retrieving
//  -----------------------------------------------------------------------

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_RECYCLED ]         = rrb_response.memory_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_RECYCLED ]         = rrb_response.memory_address.index;
	assign recycled_response_mshr                                  = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_RECYCLED];
	assign recycled_response_mshr_hit                              = cc2_mshr_lookup_hit[MSHR_LOOKUP_PORT_RECYCLED];
	assign recycled_response_mshr_index                            = cc2_mshr_lookup_index [MSHR_LOOKUP_PORT_RECYCLED];

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_REPLACEMENT ]      = ci_replacement_request_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_REPLACEMENT ]      = ci_replacement_request_address.index;
	assign replacement_mshr                                        = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_REPLACEMENT ];
	assign replacement_mshr_hit_set                                = cc2_mshr_lookup_hit_set[MSHR_LOOKUP_PORT_REPLACEMENT ];
	assign replacement_mshr_index                                  = cc2_mshr_lookup_index [MSHR_LOOKUP_PORT_REPLACEMENT ];

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_STORE ]            = ci_store_request_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_STORE ]            = ci_store_request_address.index;
	assign store_mshr                                              = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_STORE ];
	assign store_mshr_hit                                          = cc2_mshr_lookup_hit [MSHR_LOOKUP_PORT_STORE ];
	assign store_mshr_index                                        = cc2_mshr_lookup_index [MSHR_LOOKUP_PORT_STORE ];

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_FLUSH ]            = ci_flush_request_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_FLUSH ]            = ci_flush_request_address.index;
	assign flush_mshr                                              = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_FLUSH ];
	assign flush_mshr_hit                                          = cc2_mshr_lookup_hit [MSHR_LOOKUP_PORT_FLUSH ];
	assign flush_mshr_index                                        = cc2_mshr_lookup_index [MSHR_LOOKUP_PORT_FLUSH ];

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_DINV ]             = ci_dinv_request_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_DINV ]             = ci_dinv_request_address.index;
	assign dinv_mshr                                               = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_DINV ];
	assign dinv_mshr_hit                                           = cc2_mshr_lookup_hit [MSHR_LOOKUP_PORT_DINV ];
	assign dinv_mshr_index                                         = cc2_mshr_lookup_index [MSHR_LOOKUP_PORT_DINV ];

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_LOAD ]             = ci_load_request_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_LOAD ]             = ci_load_request_address.index;
	assign load_mshr                                               = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_LOAD ];
	assign load_mshr_hit                                           = cc2_mshr_lookup_hit[MSHR_LOOKUP_PORT_LOAD ];
	assign load_mshr_index                                         = cc2_mshr_lookup_index[MSHR_LOOKUP_PORT_LOAD ];

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_FORWARDED_REQUEST] = ni_forwarded_request.memory_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_FORWARDED_REQUEST] = ni_forwarded_request.memory_address.index;
	assign forwarded_request_mshr                                  = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_FORWARDED_REQUEST];
	assign forwarded_request_mshr_hit                              = cc2_mshr_lookup_hit [MSHR_LOOKUP_PORT_FORWARDED_REQUEST];
	assign forwarded_request_mshr_index                            = cc2_mshr_lookup_index [MSHR_LOOKUP_PORT_FORWARDED_REQUEST];

	assign cc1_mshr_lookup_tag[MSHR_LOOKUP_PORT_RESPONSE ]         = ni_response.memory_address.tag;
	assign cc1_mshr_lookup_set[MSHR_LOOKUP_PORT_RESPONSE ]         = ni_response.memory_address.index;
	assign response_mshr                                           = cc2_mshr_lookup_entry_info[MSHR_LOOKUP_PORT_RESPONSE ];
	assign response_mshr_hit                                       = cc2_mshr_lookup_hit [MSHR_LOOKUP_PORT_RESPONSE ];
	assign response_mshr_index                                     = cc2_mshr_lookup_index [MSHR_LOOKUP_PORT_RESPONSE ];

	assign load_is_coherent                                        = ci_load_request_coherent;
	assign store_is_coherent                                       = ci_store_request_coherent;
	assign replacement_is_coherent                                 = ~state_is_uncoherent(replacement_mshr.state);
	assign flush_is_coherent                                       = ci_flush_request_coherent;
	assign dinv_is_coherent                                        = ci_dinv_request_coherent;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 1 - Protocol stall calculation
//  -----------------------------------------------------------------------

	stall_protocol_rom replacement_stall_protocol_rom (
		.current_request ( replacement_is_coherent ? replacement : replacement_uncoherent ),
		.current_state   ( replacement_mshr.state                                         ),
		.pr_output_stall ( stall_replacement                                              )
	);

	stall_protocol_rom store_stall_protocol_rom (
		.current_request ( store_is_coherent ? store : store_uncoherent ),
		.current_state   ( store_mshr.state                             ),
		.pr_output_stall ( stall_store                                  )
	);

	stall_protocol_rom flush_stall_protocol_rom (
		.current_request ( flush_is_coherent ? flush : flush_uncoherent ),
		.current_state   ( flush_mshr.state                             ),
		.pr_output_stall ( stall_flush                                  )
	);

	stall_protocol_rom load_stall_protocol_rom (
		.current_request ( load_is_coherent ? load : load_uncoherent ),
		.current_state   ( load_mshr.state                           ),
		.pr_output_stall ( stall_load                                )
	);

	stall_protocol_rom forwarded_stall_protocol_rom (
		.current_request ( fwd_2_creq( ni_forwarded_request.packet_type ) ),
		.current_state   ( forwarded_request_mshr.state                   ),
		.pr_output_stall ( stall_forwarded_request                        )
	);

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 1 - Request issue calculation
//  -----------------------------------------------------------------------
	// A core or a forwarded request can be issued if:
	//      a - It is pending
	//      b - It is not in MSHR, or if the request has an entry the protocol does not stall it
	//      c - The same request is not in the pipeline, in other words it is not in Cache Controller
	//          Stage 2 or Cache Controller Stage 3

	assign can_issue_replacement                                   = ci_replacement_request_valid && 
		( !replacement_mshr_hit_set || ( replacement_mshr_hit_set && ( !stall_replacement || replacement_mshr.waiting_for_eviction ) ) ) &&
		!(
			( cc2_pending_valid && ( ci_replacement_request_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( ci_replacement_request_address.index == cc3_pending_address.index ) )
		) & ((replacement_is_coherent && ni_request_network_available) || (~replacement_is_coherent && ni_response_network_available));

	assign can_issue_store                                         = ~cc2_request_mshr_full && ci_store_request_valid && 
		( !store_mshr_hit || ( store_mshr_hit && !store_mshr.waiting_for_eviction && !stall_store && (store_mshr_index != ci_store_request_address.index) ) ) &&
		!(
			( cc2_pending_valid && ( ci_store_request_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( ci_store_request_address.index == cc3_pending_address.index ) )
		) & ((store_is_coherent && ni_request_network_available) || (~store_is_coherent && ni_response_network_available));

	assign can_issue_load                                          = ~cc2_request_mshr_full && ci_load_request_valid && 
		( !load_mshr_hit || ( load_mshr_hit && !load_mshr.waiting_for_eviction && !stall_load && (load_mshr_index != ci_load_request_address.index)) ) &&
		!(
			( cc2_pending_valid && ( ci_load_request_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( ci_load_request_address.index == cc3_pending_address.index ) )
		) & ((load_is_coherent && ni_request_network_available) || (~load_is_coherent && ni_forward_network_available));

	// Flushes can either generate a response message (WB, in case of hit) or a request to the Directory (DIR_FLUSH, in case of miss).
	// For those reason, a flush request is dispatched if both response and request networks are available.
	assign can_issue_flush                                         = ci_flush_request_valid & 
		( !flush_mshr_hit || (flush_mshr_hit && !flush_mshr.waiting_for_eviction && !stall_flush) ) &&
		!(
			( cc2_pending_valid && ( ci_flush_request_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( ci_flush_request_address.index == cc3_pending_address.index ) )
		) & (ni_response_network_available & ni_request_network_available);

	assign can_issue_dinv                                          = ci_dinv_request_valid & 
		//( !dinv_mshr_hit || (dinv_mshr_hit && !dinv_mshr.waiting_for_eviction && !stall_dinv) ) &&
		!dinv_mshr_hit &&
		!(
			( cc2_pending_valid && ( ci_dinv_request_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( ci_dinv_request_address.index == cc3_pending_address.index ) )
		) & ni_response_network_available;

	assign can_issue_forwarded_request                             = ni_forwarded_request_valid &&
		( !forwarded_request_mshr_hit || ( forwarded_request_mshr_hit && !forwarded_request_mshr.waiting_for_eviction && !stall_forwarded_request )
				) &&
		!(
			( cc2_pending_valid && ( ni_forwarded_request.memory_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( ni_forwarded_request.memory_address.index == cc3_pending_address.index ) )
		) & ni_response_network_available;

	assign can_issue_response                                      = ni_response_valid &
		!(
			( cc2_pending_valid && ( ni_response.memory_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( ni_response.memory_address.index == cc3_pending_address.index ) )
		);

	assign can_issue_recycled_response                             = rrb_response_valid &
		!(
			( cc2_pending_valid && ( rrb_response.memory_address.index == cc2_pending_address.index ) ) ||
			( cc3_pending_valid && ( rrb_response.memory_address.index == cc3_pending_address.index ) )
		);

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 1 - Fixed priority scheduling
//  -----------------------------------------------------------------------

	always @(*) begin : arbiter

		output_request_valid            = 1'b0;
		output_mshr_hit                 = 1'b0;
		cc1_dequeue_replacement_request = 1'b0;
		cc1_dequeue_flush_request       = 1'b0;
		cc1_dequeue_dinv_request        = 1'b0;
		cc1_dequeue_store_request       = 1'b0;
		cc1_response_recycled_consumed  = 1'b0;
		cc1_response_eject_consumed     = 1'b0;
		cc1_forwarded_request_consumed  = 1'b0;
		cc1_dequeue_load_request        = 1'b0;
		cc1_snoop_tag_valid             = 1'b0;
		output_instr_request_valid      = 1'b0;
		output_request                  = 0;
		output_mshr_index               = 0;
		output_mshr_entry               = 0;
		output_request_thread_id        = 0;
		output_request_address          = 0;
		output_request_data             = 0;
		output_request_dirty_mask       = dcache_store_mask_t'(0);
		output_request_source           = 0;
		output_request_sharers_count    = 0;
		output_request_packet_type      = message_responses_enum_t'(0);
		output_request_from_dir			= 1'b0;

		if ( can_issue_flush ) begin

			output_request_valid            = 1'b1;
			output_request                  = flush_is_coherent ? flush : flush_uncoherent;
			output_mshr_hit                 = flush_mshr_hit;
			output_mshr_index               = flush_mshr_index;
			output_mshr_entry               = flush_mshr;
			output_request_address          = ci_flush_request_address;
			output_request_dirty_mask       = ci_flush_request_dirty_mask;
			cc1_dequeue_flush_request       = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;

		end else if ( can_issue_dinv ) begin

			output_request_valid            = 1'b1;
			output_request                  = dinv_is_coherent ? dinv : dinv_uncoherent;
			output_mshr_hit                 = dinv_mshr_hit;
			output_mshr_index               = dinv_mshr_index;
			output_mshr_entry               = dinv_mshr;
			output_request_thread_id        = ci_dinv_request_thread_id;
			output_request_address          = ci_dinv_request_address;
			output_request_data             = ci_dinv_request_cache_line;
			output_request_dirty_mask       = ci_dinv_request_dirty_mask;
			cc1_dequeue_dinv_request        = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;

		end else if ( can_issue_replacement ) begin

			output_request_valid            = 1'b1;
			output_request                  = replacement_is_coherent ? replacement : replacement_uncoherent;
			output_mshr_hit                 = replacement_mshr_hit_set;
			output_mshr_index               = replacement_mshr_index;
			output_mshr_entry               = replacement_mshr;
			output_request_thread_id        = ci_replacement_request_thread_id;
			output_request_address          = ci_replacement_request_address;
			output_request_data             = ci_replacement_request_cache_line;
			output_request_dirty_mask       = ci_replacement_request_dirty_mask;
			cc1_dequeue_replacement_request = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;

		end else if ( can_issue_store ) begin

			output_request_valid            = 1'b1;
			output_request                  = store_is_coherent ? store : store_uncoherent;
			output_mshr_hit                 = store_mshr_hit;
			output_mshr_index               = store_mshr_index;
			output_mshr_entry               = store_mshr;
			output_request_thread_id        = ci_store_request_thread_id;
			output_request_address          = ci_store_request_address;
			cc1_dequeue_store_request       = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;

		end else if ( can_issue_response ) begin

			if ( ni_response.requestor == ICACHE ) begin
				output_request_valid       = 1'b0;
				output_instr_request_valid = 1'b1;
			end else begin
				output_request_valid       = 1'b1;
				output_instr_request_valid = 1'b0;
			end

			output_request                  = res_2_creq( ni_response, response_mshr );
			output_mshr_hit                 = response_mshr_hit;
			output_mshr_index               = response_mshr_index;
			output_mshr_entry               = response_mshr;
			output_request_address          = ni_response.memory_address;
			output_request_data             = ni_response.data;
			output_request_source           = ni_response.source;
			output_request_sharers_count    = ni_response.sharers_count;
			output_request_packet_type      = ni_response.packet_type;
			output_request_from_dir			= ni_response.from_directory;
			cc1_response_eject_consumed     = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;
		
		end else if ( can_issue_forwarded_request ) begin

			output_request_valid            = 1'b1;
			output_request                  = fwd_2_creq( ni_forwarded_request.packet_type );
			output_mshr_hit                 = forwarded_request_mshr_hit;
			output_mshr_index               = forwarded_request_mshr_index;
			output_mshr_entry               = forwarded_request_mshr;
			output_request_address          = ni_forwarded_request.memory_address;
			output_request_source           = ni_forwarded_request.source;
			cc1_forwarded_request_consumed  = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;

		end else if ( can_issue_load ) begin

			output_request_valid            = 1'b1;
			output_request                  = load_is_coherent ? load : load_uncoherent;
			output_mshr_hit                 = load_mshr_hit;
			output_mshr_index               = load_mshr_index;
			output_mshr_entry               = load_mshr;
			output_request_thread_id        = ci_load_request_thread_id;
			output_request_address          = ci_load_request_address;
			cc1_dequeue_load_request        = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;

		end else if ( can_issue_recycled_response ) begin

			if ( rrb_response.requestor == ICACHE ) begin
				output_request_valid       = 1'b0;
				output_instr_request_valid = 1'b1;
			end else begin
				output_request_valid       = 1'b1;
				output_instr_request_valid = 1'b0;
			end

			output_request                  = res_2_creq( rrb_response, recycled_response_mshr );
			output_mshr_hit                 = recycled_response_mshr_hit;
			output_mshr_index               = recycled_response_mshr_index;
			output_mshr_entry               = recycled_response_mshr;
			output_request_address          = rrb_response.memory_address;
			output_request_data             = rrb_response.data;
			output_request_source           = rrb_response.source;
			output_request_sharers_count    = rrb_response.sharers_count;
			output_request_packet_type      = rrb_response.packet_type;
			output_request_from_dir			= rrb_response.from_directory;
			cc1_response_recycled_consumed  = 1'b1;
			cc1_snoop_tag_valid             = 1'b1;

		end
	end

	assign cc1_snoop_tag_set                                       = output_request_address.index;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 1 - Output registers
//  -----------------------------------------------------------------------
	always_ff @( posedge clk ) begin
		cc1_request                 <= output_request;
		cc1_request_mshr_hit        <= output_mshr_hit;
		cc1_request_mshr_index      <= output_mshr_index;
		cc1_request_mshr_entry_info <= output_mshr_entry;
		cc1_request_thread_id       <= output_request_thread_id;
		cc1_request_address         <= output_request_address;
		cc1_request_data            <= output_request_data;
		cc1_request_dirty_mask      <= output_request_dirty_mask;
		cc1_request_source          <= output_request_source;
		cc1_request_sharers_count   <= output_request_sharers_count;
		cc1_request_packet_type     <= output_request_packet_type;
		cc1_request_from_dir        <= output_request_from_dir;	
		mem_instr_request_data_in   <= output_request_data;
	end

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			cc1_request_valid       <= 1'b0;
			mem_instr_request_valid <= 1'b0;
		end else begin
			cc1_request_valid       <= output_request_valid;
			mem_instr_request_valid <= output_instr_request_valid;
		end
	end


`ifdef DISPLAY_COHERENCE

	always_ff @( posedge clk ) begin
		if ( output_request_valid & ~reset ) begin
			$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
			$fdisplay( `DISPLAY_COHERENCE_VAR, "Cache Controller - [Time %.16d] [TILE %.2h] [Core %.2h]", $time( ), TILE_ID, CORE_ID );

			if ( can_issue_flush ) begin
				print_flush( ci_flush_request_address );
			end else if ( can_issue_dinv ) begin
				print_dinv ( ci_dinv_request_address, ci_dinv_request_thread_id );
			end else if ( can_issue_replacement ) begin
				print_replacement( ci_replacement_request_address, ci_replacement_request_thread_id );
			end else if ( can_issue_store ) begin
				print_store( ci_store_request_address, ci_store_request_thread_id );
			end else if ( can_issue_response ) begin
				print_resp( ni_response );
			end else if ( can_issue_forwarded_request ) begin
				print_fwd_req( ni_forwarded_request );
			end else if ( can_issue_load ) begin
				print_load( ci_load_request_address, ci_load_request_thread_id );
			end

			$fflush( `DISPLAY_COHERENCE_VAR );
		end
	end

`endif

endmodule
