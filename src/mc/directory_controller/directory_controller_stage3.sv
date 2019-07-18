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
`include "npu_coherence_defines.sv"

`ifdef DISPLAY_COHERENCE
`include "npu_debug_log.sv"
`endif

/* Stage 3 is responsible for the actual execution of requests based on the protocol ROM. 
 * Once a request is processed, this module issues signals to the units in the above stages
 * in order to update information and data in caches properly. Every group of signals to a 
 * particular unit is managed by a subsystem, each one represented in the picture below.  
 * Each subsystem is simply a combinatorial logic that "converts" signals from protocol
 * ROM in proper commands to the relative unit. 
 */ 

module directory_controller_stage3 # (
		parameter TILE_ID        = 0,
		parameter TILE_MEMORY_ID = 0
	)(
		input                                                                        clk,
		input                                                                        reset,

		// From NI
		input  logic                                                                 ni_forwarded_request_network_available,
		// From Instruction Request Buffer
		input                                                                        instr_request_pending,
		input  address_t                                                             instr_request_address,

		// To Instruction Request Buffer
		output logic                                                                 dc3_instr_request_dequeue,

		// From Directory Controller Stage 2
		input  logic                                                                 dc2_message_valid,
		input  logic                         [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] dc2_message_type,
		input  l2_cache_address_t                                                    dc2_message_address,
		input  dcache_line_t                                                         dc2_message_data,
		input  tile_address_t                                                        dc2_message_source,

		input  logic                         [`DIRECTORY_STATE_WIDTH - 1 : 0]        dc2_replacement_state,
		input  logic                         [`TILE_COUNT - 1 : 0]                   dc2_replacement_sharers_list,
		input  tile_address_t                                                        dc2_replacement_owner,

		input  logic                                                                 dc2_message_tshr_hit,
		input  tshr_idx_t                                                            dc2_message_tshr_index,
		input  tshr_entry_t                                                          dc2_message_tshr_entry_info,

		input  logic                                                                 dc2_message_cache_hit,
		input  logic                                                                 dc2_message_cache_valid,
		input  logic                         [`DIRECTORY_STATE_WIDTH - 1 : 0]        dc2_message_cache_state,
		input  logic                         [`TILE_COUNT - 1 : 0]                   dc2_message_cache_sharers_list,
		input  tile_address_t                                                        dc2_message_cache_owner,
		input  l2_cache_tag_t                                                        dc2_message_cache_tag,
		input  dcache_line_t                                                         dc2_message_cache_data,
		input  l2_cache_way_idx_t                                                    dc2_message_cache_way,

		// From TSHR
		input  tshr_idx_t                                                            tshr_empty_index,

		// To Directory Controller Stage 1 and Directory Controller Stage 2
		output logic                                                                 dc3_pending,
		output l2_cache_address_t                                                    dc3_pending_address,

		output logic                                                                 dc3_update_cache_enable,
		output logic                                                                 dc3_update_cache_validity_bit,
		output l2_cache_set_t                                                        dc3_update_cache_set,
		output l2_cache_way_idx_t                                                    dc3_update_cache_way,
		output l2_cache_tag_t                                                        dc3_update_cache_tag,
		output logic                         [`DIRECTORY_STATE_WIDTH - 1 : 0]        dc3_update_cache_state,
		output logic                         [`TILE_COUNT - 1 : 0]                   dc3_update_cache_sharers_list,
		output tile_address_t                                                        dc3_update_cache_owner,
		output dcache_line_t                                                         dc3_update_cache_data,

		output logic                                                                 dc3_update_plru_en,
		output l2_cache_set_t                                                        dc3_update_plru_set,
		output l2_cache_way_idx_t                                                    dc3_update_plru_way,

		// To TSHR
		output logic                                                                 dc3_update_tshr_enable,
		output tshr_idx_t                                                            dc3_update_tshr_index,
		output tshr_entry_t                                                          dc3_update_tshr_entry_info,

		// To Sleep Queue
		output logic                                                                 dc3_replacement_enqueue,
		output replacement_request_t                                                 dc3_replacement_request,

		// To WB gen Queue
		output logic                                                                 dc3_wb_enable,
		output dcache_line_t                                                         dc3_wb_data,
		output address_t                                                             dc3_wb_addr, 

		// To Network Interface
		output coherence_forwarded_message_t                                         dc3_forwarded_request,
		output logic                                                                 dc3_forwarded_request_valid,
		output logic                         [`TILE_COUNT - 1 : 0]                   dc3_forwarded_request_destinations,

		output coherence_response_message_t                                          dc3_response,
		output logic                                                                 dc3_response_valid,
		output logic                                                                 dc3_response_has_data,
		output logic                         [`TILE_COUNT - 1 : 0]                   dc3_response_destinations
	);

	logic                                                                  do_replacement;
	logic                                                                  is_replacement;
	logic                                                                  update_cache;
	logic                                                                  deallocate_cache;
	logic                                                                  allocate_cache;

	logic                                                                  tshr_allocate;
	logic                                                                  tshr_deallocate;
	logic                                                                  tshr_update;

	l2_cache_address_t                                                     current_address;
	logic                          [`DIRECTORY_STATE_WIDTH - 1 : 0]        current_state;
	logic                          [`TILE_COUNT - 1 : 0]                   current_sharers_list;
	logic                          [$clog2( `TILE_COUNT ) - 1 : 0]         current_sharers_count;
	tile_address_t                                                         current_owner;

	logic                          [`DIRECTORY_STATE_WIDTH - 1 : 0]        dpr_state;
	logic                          [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] dpr_request;
	logic                                                                  dpr_is_from_owner;
	logic                                                                  dpr_one_sharers;

	directory_protocol_rom_entry_t                                         dpr_output;

	logic                                                                  coherence_update_info_en;

	logic                          [`TILE_COUNT - 1 : 0]                   next_sharers_list;
	tile_address_t                                                         next_owner;
	dcache_line_t                                                          next_data;


	logic                          [`TILE_COUNT - 1 : 0]                   requestor_oh;
	logic                          [`TILE_COUNT - 1 : 0]                   owner_oh;
	logic                          [`TILE_COUNT - 1 : 0]                   memory_oh;

	logic                                                                  current_state_is_stable;
	logic                                                                  next_state_is_stable;

	coherence_forwarded_message_t                                          coherent_forwarded_request;
	logic                          [`TILE_COUNT - 1 : 0]                   coherent_forwarded_request_destinations;
	coherence_forwarded_message_t                                          instr_forwarded_request;
	logic                          [`TILE_COUNT - 1 : 0]                   instr_forwarded_request_destinations;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - Current state selector
//  -----------------------------------------------------------------------

	assign is_replacement = dc2_message_type == REPLACEMENT;

	always_comb begin
		if ( dc2_message_tshr_hit ) begin
			current_address      = dc2_message_address;
			current_state        = dc2_message_tshr_entry_info.state;
			current_sharers_list = dc2_message_tshr_entry_info.sharers_list;
			current_owner        = dc2_message_tshr_entry_info.owner;
		end else if ( dc2_message_cache_hit ) begin
			current_address      = dc2_message_address;
			current_state        = dc2_message_cache_state;
			current_sharers_list = dc2_message_cache_sharers_list;
			current_owner        = dc2_message_cache_owner;
		end else if (is_replacement) begin
			current_address      = dc2_message_address;
			current_state        = dc2_replacement_state;
			current_sharers_list = dc2_replacement_sharers_list;
			current_owner        = dc2_replacement_owner;
		end else begin
			current_address      = dc2_message_address;
			current_state        = {`DIRECTORY_STATE_WIDTH{1'b0}}; // state N
			current_sharers_list = {`TILE_COUNT{1'b0}};
			current_owner        = tile_address_t'(TILE_MEMORY_ID);
		end
	end

	assign dc3_pending      = dc2_message_valid | instr_request_pending,
		dc3_pending_address = ( dc2_message_valid ) ? dc2_message_address : instr_request_address;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - One-hot for sharer list and message
//  -----------------------------------------------------------------------

	idx_to_oh #(
		.NUM_SIGNALS( `TILE_COUNT           ),
		.DIRECTION  ( "LSB0"                ),
		.INDEX_WIDTH( $clog2( `TILE_COUNT ) )
	) u_idx_to_oh (
		.one_hot( requestor_oh       ),
		.index  ( dc2_message_source )
	);

	idx_to_oh #(
		.NUM_SIGNALS( `TILE_COUNT           ),
		.DIRECTION  ( "LSB0"                ),
		.INDEX_WIDTH( $clog2( `TILE_COUNT ) )
	) u_idx_to_oh2 (
		.one_hot( owner_oh      ),
		.index  ( current_owner )
	);

	idx_to_oh #(
		.NUM_SIGNALS( `TILE_COUNT           ),
		.DIRECTION  ( "LSB0"                ),
		.INDEX_WIDTH( $clog2( `TILE_COUNT ) )
	) u_idx_to_oh3 (
		.one_hot( memory_oh                       ),
		.index  ( tile_address_t'(TILE_MEMORY_ID) )
	);

	always_comb begin
		automatic int i       = 0;
		current_sharers_count = 0;
		for ( i = 0; i < `TILE_COUNT; i++ ) begin
			current_sharers_count += current_sharers_list[i];
		end
	end

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - Dir protocol ROM input & Output processing
//  -----------------------------------------------------------------------

	assign dpr_state                                  = current_state,
		dpr_request                                   = dc2_message_type,
		dpr_is_from_owner                             = dc2_message_source == current_owner,
		dpr_one_sharers                               = current_sharers_count == 1;


	directory_protocol_rom protocol_rom (
		.clk                       ( clk               ),
		.input_state               ( dpr_state         ),
		.input_request             ( dpr_request       ),
		.request_valid   		   ( dc2_message_valid ),
		.input_is_from_owner       ( dpr_is_from_owner ),
		.input_there_is_one_sharers( dpr_one_sharers   ),
		.dpr_output                ( dpr_output        )
	);

	assign current_state_is_stable                    = dpr_output.current_state_is_stable,
		next_state_is_stable                          = dpr_output.next_state_is_stable;

	assign
		next_sharers_list                             = 
		( 
			current_sharers_list | 
			( 
				( 
					( {`TILE_COUNT{dpr_output.sharers_add_requestor}} & requestor_oh ) |
					( {`TILE_COUNT{dpr_output.sharers_add_owner}} & owner_oh ) )
				)
			) &
			(
				~( {`TILE_COUNT{dpr_output.sharers_clear}} & {`TILE_COUNT{1'b1}} ) &
				~( {`TILE_COUNT{dpr_output.sharers_remove_requestor}} & requestor_oh ) 
			),
		next_owner                                    = dpr_output.owner_clear ? tile_address_t'(TILE_ID) : dpr_output.owner_set_requestor ? dc2_message_source : current_owner,
		next_data                                     = dpr_output.store_data ? dc2_message_data : dc2_message_cache_data; 

	assign coherence_update_info_en                   =
		( current_state != dpr_output.next_state ) |
		dpr_output.owner_clear | dpr_output.owner_set_requestor | dpr_output.sharers_add_owner |
		dpr_output.sharers_add_requestor | dpr_output.sharers_clear | dpr_output.sharers_remove_requestor;

`ifdef COHERENCE_INJECTION

	state_t 	        current_state_enum;
	directory_message_t current_request_enum;
	state_t 	        next_state_enum;
	
	assign current_state_enum = state_t'(current_state);
	assign current_request_enum = directory_message_t'(dpr_request);
	assign next_state_enum = state_t'(dpr_output.next_state);

	always_ff @(posedge clk)
	begin
		if( dc2_message_valid )
		begin
			$display("[Time %t] [DC] Calling DC-ROM for address 0x%8h with: Current state = %s, current request = %s", $time(), dc2_message_address, current_state_enum.name, current_request_enum.name);
			if( dpr_output.next_state_is_stable )
				$display("[Time %t] [DC] Going into stable state %s for address 0x%8h", $time(), next_state_enum.name, dc2_message_address);
		end
	end
`endif

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - TSHR update signals
//  -----------------------------------------------------------------------
	assign tshr_allocate                              = current_state_is_stable && !next_state_is_stable, 
		tshr_update                                   = !current_state_is_stable & !next_state_is_stable & coherence_update_info_en,
		tshr_deallocate                               = !current_state_is_stable && next_state_is_stable;

	assign dc3_update_tshr_entry_info.valid           = ( tshr_allocate | tshr_update ) & ~tshr_deallocate, 
		dc3_update_tshr_entry_info.state              = directory_state_t'(dpr_output.next_state),
		dc3_update_tshr_entry_info.address.tag        = dc2_message_address.tag, 
		dc3_update_tshr_entry_info.address.index      = dc2_message_address.index,
		dc3_update_tshr_entry_info.address.offset     = dc2_message_address.offset,
		dc3_update_tshr_entry_info.sharers_list       = next_sharers_list,
		dc3_update_tshr_entry_info.owner              = next_owner;

	assign dc3_update_tshr_enable                     = dc2_message_valid && ( tshr_allocate || tshr_deallocate || tshr_update ), 
		dc3_update_tshr_index                         = tshr_allocate ? tshr_empty_index : dc2_message_tshr_index; 

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - Cache update signals
//  -----------------------------------------------------------------------

	assign update_cache                               = dc2_message_cache_hit & current_state_is_stable & next_state_is_stable & ( coherence_update_info_en | dpr_output.store_data );
	assign deallocate_cache                           = ( tshr_allocate & dc2_message_cache_hit) ;
	assign allocate_cache                             = next_state_is_stable & ( coherence_update_info_en | dpr_output.store_data ) & ~(tshr_deallocate & dpr_output.invalidate_cache_way) & ~update_cache;

	assign dc3_update_cache_enable                    = dc2_message_valid && !is_replacement && ( allocate_cache || update_cache || deallocate_cache ),
		dc3_update_cache_validity_bit                 = ~dpr_output.invalidate_cache_way,
		dc3_update_cache_set                          = dc2_message_address.index,
		dc3_update_cache_way                          = dc2_message_cache_way,
		dc3_update_cache_tag                          = dc2_message_address.tag,
		dc3_update_cache_state                        = dpr_output.next_state,
		dc3_update_cache_data                         = next_data,
		dc3_update_cache_sharers_list                 = next_sharers_list,
		dc3_update_cache_owner                        = next_owner;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - Pseudo LRU Update signals
//  -----------------------------------------------------------------------

	assign dc3_update_plru_en   = dc2_message_valid, 
	       dc3_update_plru_set  = dc2_message_address.index,
	       dc3_update_plru_way  = dc2_message_cache_way;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - Message generator
//  -----------------------------------------------------------------------

	assign coherent_forwarded_request.source              = dc2_message_source,
		coherent_forwarded_request.packet_type        = message_forwarded_requests_enum_t'( dpr_output.message_forwarded_type ),
		coherent_forwarded_request.memory_address     = current_address,
		coherent_forwarded_request.req_is_uncoherent  = 1'b0,
		coherent_forwarded_request.requestor          = DCACHE,
		coherent_forwarded_request_destinations       = dpr_output.message_forwarded_to_requestor ? requestor_oh : dpr_output.message_forwarded_to_owner ? owner_oh : dpr_output.message_forwarded_to_memory ? memory_oh : current_sharers_list;

	assign instr_forwarded_request.source             = tile_address_t'(TILE_ID),
		instr_forwarded_request.packet_type       = FWD_GETS,
		instr_forwarded_request.memory_address    = instr_request_address,
		instr_forwarded_request.req_is_uncoherent = 1'b1,
		instr_forwarded_request.requestor         = ICACHE,
		instr_forwarded_request_destinations      = memory_oh;

	always_comb begin
		dc3_instr_request_dequeue = 1'b0;
		if ( dc2_message_valid && dpr_output.message_forwarded_send ) begin
			dc3_forwarded_request_valid        = 1'b1;
			dc3_forwarded_request              = coherent_forwarded_request;
			dc3_forwarded_request_destinations = coherent_forwarded_request_destinations;
		end else if ( instr_request_pending & ni_forwarded_request_network_available ) begin
			dc3_forwarded_request_valid        = 1'b1;
			dc3_forwarded_request              = instr_forwarded_request;
			dc3_forwarded_request_destinations = instr_forwarded_request_destinations;
			dc3_instr_request_dequeue          = 1'b1;
		end else begin
			dc3_forwarded_request_valid        = 1'b0;
			dc3_forwarded_request              = 0;
			dc3_forwarded_request_destinations = 0;
		end
	end

	assign dc3_response_valid                         = dc2_message_valid && dpr_output.message_response_send,
		dc3_response.source                           = dc2_message_source,
		dc3_response.packet_type                      = message_responses_enum_t'( dpr_output.message_response_type ),
		dc3_response.memory_address                   = current_address,
		dc3_response.data                             = dc2_message_cache_hit & !is_replacement? dc2_message_cache_data: dc2_message_data,
		dc3_response.dirty_mask                       = {$bits(dcache_store_mask_t){1'b1}},
		dc3_response.from_directory                   = 1'b1,
		dc3_response.sharers_count                    = current_sharers_count,
		dc3_response.req_is_uncoherent                = 1'b0,
		dc3_response.requestor                        = DCACHE,
		dc3_response_has_data                         = dpr_output.message_response_has_data,
		dc3_response_destinations                     = dpr_output.message_response_to_requestor ? requestor_oh : dpr_output.message_response_to_owner ? owner_oh : dpr_output.message_response_to_memory ? memory_oh : current_sharers_list;


//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - Sleep queue
//  -----------------------------------------------------------------------
	// In case of replacement, this statement fills the FIFO up and then
	// the request is rescheduled
	assign do_replacement                             = dc2_message_valid && ((allocate_cache || update_cache) && !deallocate_cache) && !is_replacement && !dc2_message_cache_hit && dc2_message_cache_valid;

	assign  dc3_replacement_request.source            = dc2_message_source,
		dc3_replacement_request.memory_address.tag    = dc2_message_cache_tag,
		dc3_replacement_request.memory_address.index  = dc2_message_address.index,
		dc3_replacement_request.memory_address.offset = 0,
		dc3_replacement_request.data                  = dc2_message_cache_data, 
		dc3_replacement_request.state                 = directory_state_t'(dc2_message_cache_state),
		dc3_replacement_request.sharers_list          = dc2_message_cache_sharers_list,
		dc3_replacement_request.owner                 = dc2_message_cache_owner;

	// In case of replacement, the request is recycled
	assign dc3_replacement_enqueue = dc2_message_valid && do_replacement;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 3 - WB queue
//  -----------------------------------------------------------------------
	
	// This logic recycles a PutM when the line is in state MN_A, since
	// it might be a race condition when both the CC and the DC are
	// transitioning form M to I/N. If the CC receives the PutAck before
	// the recall message, it sends no WB messagge, stalling the directory
	// which is waiting for a MC_ACK.
	always_ff @ (posedge clk, posedge reset) begin :  WB_GEN_QUEUE_OUT
		if ( reset )
			dc3_wb_enable <= 1'b0;
		else
			dc3_wb_enable <= dpr_output.message_response_add_wb;
	end 

	always_ff @ (posedge clk) begin : WB_GEN_OUT
		dc3_wb_data <= dc2_message_data;
		dc3_wb_addr <= dc2_message_address;
	end 

`ifdef DISPLAY_COHERENCE

	always_ff @( posedge clk )
		if ( ( ( dc3_forwarded_request_valid & ~dc3_forwarded_request.req_is_uncoherent ) | dc3_response_valid ) & ~reset ) begin
			$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
			$fdisplay( `DISPLAY_COHERENCE_VAR, "Directory Controller - [Time %.16d] [TILE %.2h] - Message Sent", $time( ), TILE_ID );

			if ( dc3_forwarded_request_valid ) begin
				$fdisplay( `DISPLAY_COHERENCE_VAR, "Forwarded Destinations: %b", dc3_forwarded_request_destinations);
				print_fwd_req( coherent_forwarded_request );
			end

			if ( dc3_response_valid ) begin
				$fdisplay( `DISPLAY_COHERENCE_VAR, "Response Destinations: %b", dc3_response_destinations);
				print_resp( dc3_response );
			end

			$fflush( `DISPLAY_COHERENCE_VAR );
		end
`endif

endmodule
