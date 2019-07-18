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
`include "npu_network_defines.sv"

 
/* Stage 3 is responsible for the actual execution of requests. Once a request is processed, 
 * this stage issues signals to the units in the above stages in order to update data properly.
 * In particular, this stage drives datapath to perform one of these functions:
 *
 *  -  block replacement evaluation;
 *  -  MSHR update;
 *  -  cache memory (both data and coherence info) update.
 *  -  preparing outgoing coherence messages.
 */  

module cache_controller_stage3 (

		input                                            clk,
		input                                            reset,

		// From Cache Controller Stage 2
		input  logic                                     cc2_request_valid,
		input  coherence_request_t                       cc2_request,
		input  thread_id_t                               cc2_request_thread_id,
		input  dcache_address_t                          cc2_request_address,
		input  dcache_line_t                             cc2_request_data,
		input  dcache_store_mask_t                       cc2_request_dirty_mask,
		input  tile_address_t                            cc2_request_source,
		input  sharer_count_t                            cc2_request_sharers_count,
		input  message_response_t                        cc2_request_packet_type,
		input  logic                                     cc2_request_from_dir,

		input  logic                                     cc2_request_mshr_hit,
		input  mshr_idx_t                                cc2_request_mshr_index,
		input  mshr_entry_t                              cc2_request_mshr_entry_info,
		input  dcache_line_t                             cc2_request_mshr_entry_data,
		input  mshr_idx_t                                cc2_request_mshr_empty_index,
		input  logic                                     cc2_request_mshr_full,

		input  logic                                     cc2_request_replacement_is_collision,
		input  dcache_way_idx_t                          cc2_request_lru_way_idx,
		input  dcache_way_idx_t                          cc2_request_snoop_way_idx,
		input  logic                                     cc2_request_snoop_hit,
		input  dcache_tag_t        [`DCACHE_WAY - 1 : 0] cc2_request_snoop_tag,
		input  dcache_privileges_t [`DCACHE_WAY - 1 : 0] cc2_request_snoop_privileges,
		input  coherence_state_t   [`DCACHE_WAY - 1 : 0] cc2_request_coherence_states,

		// To Load Store Unit
		output logic                                     cc3_update_ldst_valid,
		output cc_command_t                              cc3_update_ldst_command,
		output dcache_way_idx_t                          cc3_update_ldst_way,
		output dcache_address_t                          cc3_update_ldst_address,
		output dcache_privileges_t                       cc3_update_ldst_privileges,
		output dcache_line_t                             cc3_update_ldst_store_value,

		output logic                                     cc3_snoop_data_valid,
		output dcache_set_t                              cc3_snoop_data_set,
		output dcache_way_idx_t                          cc3_snoop_data_way,

		output logic                                     cc3_wakeup,
		output thread_id_t                               cc3_wakeup_thread_id,


		// To Cache Controller Stage 1
		output logic                                     cc3_pending_valid,
		output dcache_address_t                          cc3_pending_address,

		// To Cache Controller Stage 2
		output logic                                     cc3_update_mshr_en,
		output mshr_idx_t                                cc3_update_mshr_index,
		output mshr_entry_t                              cc3_update_mshr_entry_info,
		output dcache_line_t                             cc3_update_mshr_entry_data,

		output logic                                     cc3_update_coherence_state_en,
		output dcache_set_t                              cc3_update_coherence_state_index,
		output dcache_way_idx_t                          cc3_update_coherence_state_way,
		output coherence_state_t                         cc3_update_coherence_state_entry,
		output logic                                     cc3_update_lru_fill_en,

		// To Cache Controller Stage 4
		output logic                                     cc3_request_is_flush,
		output logic                                     cc3_message_valid,
		output logic                                     cc3_message_is_response,
		output logic                                     cc3_message_is_forward,
		output message_request_t                         cc3_message_request_type,
		output message_response_t                        cc3_message_response_type,
		output message_forwarded_request_t               cc3_message_forwarded_request_type,
		output dcache_address_t                          cc3_message_address,
		output dcache_line_t                             cc3_message_data,
		output dcache_store_mask_t                       cc3_message_dirty_mask,
		output logic                                     cc3_message_has_data,
		output logic                                     cc3_message_send_data_from_cache,
		output logic                                     cc3_message_is_receiver_dir,
		output logic                                     cc3_message_is_receiver_req,
		output logic                                     cc3_message_is_receiver_mc,
		output tile_address_t                            cc3_message_requestor,

		// To Response Recycle Buffer
		output logic                                     cc3_response_recycled_valid,
		output coherence_response_message_t              cc3_responce_recycled
	);

	localparam MAX_PEND_REQ_NUMB = `DCACHE_WAY - 2;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - Signals declaration
//  -----------------------------------------------------------------------

	coherence_state_t              current_state;
	logic                          do_replacement;
	logic                          is_replacement_collision;
	logic                          replaced_way_valid;
	dcache_address_t               replaced_way_address;
	coherence_state_t              replaced_way_state;
	protocol_rom_entry_t		   pr_output;
	coherence_response_message_t   output_response_recycled;
	logic                          request_is_valid;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - State selector
//  -----------------------------------------------------------------------

	// If there is a MSHR hit, it means that the request is already pending, and the
	// most up to date state is stored in MSHR. If there is no entry in MSHR and there is a Snoop hit,
	// it means that the state is stored in Coherence State SRAM. If there is neither a MSHR hit nor a
	// Snoop hit, it means that the line is in Invalid state.

	always_comb begin : current_state_selector
		if ( cc2_request_mshr_hit )
			current_state = cc2_request_mshr_entry_info.state;
		else if ( cc2_request_snoop_hit )
			current_state = cc2_request_coherence_states[cc2_request_snoop_way_idx];
		else
			current_state = I;
	end

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - Protocol ROM instantiation
//  -----------------------------------------------------------------------

	// This module handles the control unit behavior. The CU has elementary action defined in
	// this ROM. It takes in input the current state and the request and decodes the next
	// actions.

	cc_protocol_rom u_cc_protocol_rom (
		.clk            ( clk               ),
		.current_state  ( current_state     ),
		.current_request( cc2_request       ),
		.request_valid  ( cc2_request_valid ),
		.pr_output      ( pr_output         )
	);

`ifdef COHERENCE_INJECTION

	coherence_states_enum_t current_state_enum;
	coherence_requests_enum_t current_request_enum;
	coherence_states_enum_t next_state_enum;
	
	assign current_state_enum = coherence_states_enum_t'(current_state);
	assign current_request_enum = coherence_requests_enum_t'(cc2_request);
	assign next_state_enum = coherence_states_enum_t'(pr_output.next_state);

	always_ff @(posedge clk)
	begin
		if( cc2_request_valid )
		begin
			$display("[Time %t] [CC] Calling CC-ROM for address 0x%8h with: Current state = %s, current request = %s", $time(), cc2_request_address, current_state_enum.name, current_request_enum.name);
			if( pr_output.next_state_is_stable )
				$display("[Time %t] [CC] Going into stable state %s for address 0x%8h", $time(), next_state_enum.name, cc2_request_address);
		end
	end
`endif

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - Replacement evalutation
//  -----------------------------------------------------------------------
    // A cache block replacement might occur whenever a new block has to be stored into the L1 and all the sets are busy. 
    // In case of available sets, the control logic will select them avoiding replacement. Hence, an eviction occurs only 
    // when the selected block has valid information. Block validity is assured by privilege bits associated with it. 
    // These privilege bits (one for each way) come from Stage 2 that in turn has received them from load/store unit. 
    // The pseudo-LRU module, in Stage 2, selects the block to replace pointing least used way.
	always_comb begin
		replaced_way_valid          = cc2_request_snoop_privileges[cc2_request_lru_way_idx].can_read | cc2_request_snoop_privileges[cc2_request_lru_way_idx].can_write;

		replaced_way_address.tag    = cc2_request_snoop_tag[cc2_request_lru_way_idx];
		replaced_way_address.index  = cc2_request_address.index;
		replaced_way_address.offset = {`DCACHE_OFFSET_LENGTH{1'b0}};

		replaced_way_state          = cc2_request_coherence_states[cc2_request_lru_way_idx];
		do_replacement              = pr_output.write_data_on_cache && !cc2_request_snoop_hit && replaced_way_valid;
		is_replacement_collision    = cc2_request_valid && do_replacement && cc2_request_replacement_is_collision;
		cc3_update_lru_fill_en      = do_replacement;
	end

	always_comb begin : RESPONSE_REC_BUILD
		output_response_recycled.data              = cc2_request_data;
		output_response_recycled.dirty_mask        = {$bits(dcache_line_t){1'b1}};
		output_response_recycled.source            = 0;
		output_response_recycled.packet_type       = message_responses_enum_t'(cc2_request_packet_type);
		output_response_recycled.memory_address    = cc2_request_address;
		output_response_recycled.sharers_count     = cc2_request_sharers_count;
		output_response_recycled.from_directory    = cc2_request_from_dir;
		output_response_recycled.req_is_uncoherent = 1'b0;
		output_response_recycled.requestor         = DCACHE;
	end

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - MSHR info update calculation
//  -----------------------------------------------------------------------

	always_comb begin : MSHR_UPDATE_LOGIC

		if ( do_replacement ) begin
			cc3_update_mshr_entry_info.valid                = 1'b1;
			cc3_update_mshr_entry_info.address              = replaced_way_address;
			cc3_update_mshr_entry_info.state                = coherence_states_enum_t'(replaced_way_state);
			cc3_update_mshr_entry_info.thread_id            = 0;					
			cc3_update_mshr_entry_info.ack_count            = 0;
			cc3_update_mshr_entry_info.waiting_for_eviction = 1'b1;
			cc3_update_mshr_entry_info.wakeup_thread        = 1'b0;
			cc3_update_mshr_entry_info.ack_count_received   = 1'b0;
			cc3_update_mshr_entry_info.inv_ack_received     = 0;
		end else begin
			cc3_update_mshr_entry_info.valid                = ( pr_output.allocate_mshr_entry || pr_output.update_mshr_entry ) && !pr_output.deallocate_mshr_entry;
			cc3_update_mshr_entry_info.address              = cc2_request_address;
			cc3_update_mshr_entry_info.state                = coherence_states_enum_t'(pr_output.next_state);
			cc3_update_mshr_entry_info.thread_id            = cc2_request_mshr_hit ? cc2_request_mshr_entry_info.thread_id         : cc2_request_thread_id;
			cc3_update_mshr_entry_info.ack_count            =  pr_output.req_has_ack_count ? cc2_request_sharers_count : cc2_request_mshr_entry_info.ack_count;
			cc3_update_mshr_entry_info.waiting_for_eviction = 1'b0;
			cc3_update_mshr_entry_info.wakeup_thread        = cc2_request_mshr_hit ? cc2_request_mshr_entry_info.wakeup_thread     : ( cc2_request == load || cc2_request == store || cc2_request == replacement || cc2_request == load_uncoherent || cc2_request == store_uncoherent || cc2_request == replacement_uncoherent || cc2_request == dinv || cc2_request == dinv_uncoherent );
			cc3_update_mshr_entry_info.ack_count_received   = (pr_output.req_has_ack_count) ? 1'b1 : 
				((cc2_request_mshr_entry_info.address == cc2_request_address) ? cc2_request_mshr_entry_info.ack_count_received : 1'b0);

			if ( cc2_request_mshr_hit ) begin
				cc3_update_mshr_entry_info.inv_ack_received     = pr_output.incr_ack_count ? (cc2_request_mshr_entry_info.inv_ack_received + 1) : cc2_request_mshr_entry_info.inv_ack_received;
			end else begin
				cc3_update_mshr_entry_info.inv_ack_received     = 0;
			end
		end

		cc3_update_mshr_entry_data = pr_output.req_has_data ? cc2_request_data     : cc2_request_mshr_entry_data;
		cc3_update_mshr_index      = cc2_request_mshr_hit ? cc2_request_mshr_index : cc2_request_mshr_empty_index; 
	end

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - LDST information & data update
//  -----------------------------------------------------------------------

	assign cc3_update_ldst_command          = do_replacement ? CC_REPLACEMENT : ( pr_output.write_data_on_cache ? CC_UPDATE_INFO_DATA : CC_UPDATE_INFO );
	assign cc3_update_ldst_way              = cc2_request_snoop_hit ? cc2_request_snoop_way_idx                        : cc2_request_lru_way_idx;
	assign cc3_update_ldst_address          = cc2_request_address;
	assign cc3_update_ldst_store_value      = ( pr_output.ack_count_eqz && pr_output.req_has_data ) ? cc2_request_data : cc2_request_mshr_entry_data;
	assign cc3_update_ldst_privileges       = pr_output.next_privileges;
	assign cc3_wakeup_thread_id             = (cc2_request_mshr_hit &&  pr_output.deallocate_mshr_entry) ? cc2_request_mshr_entry_info.thread_id             : cc2_request_thread_id;
	
	assign cc3_update_coherence_state_index = cc2_request_address.index;
	assign cc3_update_coherence_state_way   = cc2_request_snoop_hit ? cc2_request_snoop_way_idx                        : cc2_request_lru_way_idx;
	assign cc3_update_coherence_state_entry = pr_output.next_state;
	
	assign cc3_pending_valid                = cc3_update_mshr_en;
	assign cc3_pending_address              = cc3_update_mshr_entry_info.address;

	assign cc3_snoop_data_valid             = cc2_request_valid && pr_output.send_data_from_cache;
	assign cc3_snoop_data_set               = cc2_request_address.index;
	assign cc3_snoop_data_way               = cc2_request_snoop_way_idx;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - Enable signals assignment
//  -----------------------------------------------------------------------
	
	// In case of collision into the MSHR due a replacement, 
	// the response message is recycled and the request has no effect.
	assign request_is_valid = cc2_request_valid & ~is_replacement_collision;
	
	always_comb begin
		// Update privilages only in case of snoop hit
		if ( request_is_valid ) begin
			cc3_update_mshr_en            = ( pr_output.allocate_mshr_entry || pr_output.update_mshr_entry || pr_output.deallocate_mshr_entry || do_replacement );
			cc3_update_ldst_valid         = (( pr_output.update_privileges && cc2_request_snoop_hit ) || pr_output.write_data_on_cache);
			cc3_update_coherence_state_en = (( pr_output.next_state_is_stable && cc2_request_snoop_hit ) || ( pr_output.next_state_is_stable && !cc2_request_snoop_hit && pr_output.write_data_on_cache ));
			cc3_wakeup                    = (pr_output.hit || ( pr_output.deallocate_mshr_entry && cc2_request_mshr_entry_info.wakeup_thread ));			
		end else begin
			cc3_update_ldst_valid         = 1'b0;
			cc3_wakeup                    = 1'b0;
			cc3_update_mshr_en            = 1'b0;
			cc3_update_coherence_state_en = 1'b0;
		end
	end

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 3 - Output registration
//  -----------------------------------------------------------------------
	always_ff @( posedge clk ) begin
		cc3_message_is_response            <= pr_output.send_response;
		cc3_message_is_forward             <= pr_output.send_forward;
		cc3_message_request_type           <= pr_output.request;
		cc3_message_response_type          <= pr_output.response;
		cc3_message_forwarded_request_type <= pr_output.forward;
		cc3_message_address                <= cc2_request_address;
		cc3_message_requestor              <= cc2_request_source;
		cc3_message_is_receiver_dir        <= pr_output.is_receiver_dir;
		cc3_message_is_receiver_req        <= pr_output.is_receiver_req;
		cc3_message_is_receiver_mc         <= pr_output.is_receiver_mc;
		cc3_message_send_data_from_cache   <= pr_output.send_data_from_cache;
		cc3_message_has_data               <= pr_output.send_data_from_cache || pr_output.send_data_from_mshr || pr_output.send_data_from_request;
		cc3_message_data                   <= pr_output.send_data_from_mshr ? cc2_request_mshr_entry_data : cc2_request_data;
		cc3_message_dirty_mask             <= state_is_uncoherent(current_state) ? cc2_request_dirty_mask : {$bits(dcache_store_mask_t){1'b1}};
		cc3_responce_recycled              <= output_response_recycled; 
	end

	always_ff @( posedge clk, posedge reset )
		if ( reset ) begin
			cc3_message_valid           <= 1'b0;
			cc3_request_is_flush        <= 1'b0;
			cc3_response_recycled_valid <= 1'b0;
		end else begin
			cc3_message_valid           <= cc2_request_valid && ( pr_output.send_response || pr_output.send_request || pr_output.send_forward );
			cc3_request_is_flush        <= cc2_request == flush;
			cc3_response_recycled_valid <= is_replacement_collision;
		end
		
endmodule
