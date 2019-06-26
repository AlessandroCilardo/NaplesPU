`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"

module cache_controller # (
		parameter TILE_ID = 0,
		parameter CORE_ID = 0 )
	(

		input                                                      clk,
		input                                                      reset,

		// From Core Interface
		input  logic                                               ci_store_request_valid,
		input  thread_id_t                                         ci_store_request_thread_id,
		input  dcache_address_t                                    ci_store_request_address,
		input  logic                                               ci_store_request_coherent,
		input  logic                                               ci_load_request_valid,
		input  thread_id_t                                         ci_load_request_thread_id,
		input  dcache_address_t                                    ci_load_request_address,
		input  logic                                               ci_load_request_coherent,
		input  logic                                               ci_replacement_request_valid,
		input  thread_id_t                                         ci_replacement_request_thread_id,
		input  dcache_address_t                                    ci_replacement_request_address,
		input  dcache_line_t                                       ci_replacement_request_cache_line,
		input  dcache_store_mask_t                                 ci_replacement_request_dirty_mask,
		input  logic                                               ci_flush_request_valid,
		input  dcache_address_t                                    ci_flush_request_address,
		input  dcache_store_mask_t                                 ci_flush_request_dirty_mask,
		input  logic                                               ci_flush_request_coherent,
		input  logic                                               ci_dinv_request_valid,
		input  dcache_address_t                                    ci_dinv_request_address,
		input  thread_id_t                                         ci_dinv_request_thread_id,
		input  dcache_line_t                                       ci_dinv_request_cache_line,
		input  dcache_store_mask_t                                 ci_dinv_request_dirty_mask,
		input  logic                                               ci_dinv_request_coherent,

		// From Network Interface
		input  logic                                               ni_request_network_available,
		input  logic                                               ni_forward_network_available,
		input  logic                                               ni_response_network_available,
		input  coherence_forwarded_message_t                       ni_forwarded_request,
		input  logic                                               ni_forwarded_request_valid,
		input  coherence_response_message_t                        ni_response_eject,
		input  logic                                               ni_response_eject_valid,

		// From Load Store Unit
		input  dcache_tag_t                  [`DCACHE_WAY - 1 : 0] ldst_snoop_tag,
		input  dcache_privileges_t           [`DCACHE_WAY - 1 : 0] ldst_snoop_privileges,
		input  dcache_set_t                                        ldst_lru_update_set,
		input                                                      ldst_lru_update_en,
		input  dcache_way_idx_t                                    ldst_lru_update_way,
		input  dcache_line_t                                       ldst_snoop_data,

		// To Core Interface
		output logic                                               cc_dequeue_store_request,
		output logic                                               cc_dequeue_load_request,
		output logic                                               cc_dequeue_replacement_request,
		output logic                                               cc_dequeue_flush_request,
		output logic                                               cc_dequeue_dinv_request,

		// To Network Interface
		output logic                                               cc_forwarded_request_consumed,
		output logic                                               cc_response_eject_consumed,

		output logic                                               cc_request_valid,
		output coherence_request_message_t                         cc_request,
		output logic                                               cc_request_has_data,
		output tile_address_t                [1 : 0]               cc_request_destinations,
		output logic                         [1 : 0]               cc_request_destinations_valid,

		output logic                                               cc_response_inject_valid,
		output coherence_response_message_t                        cc_response_inject,
		output logic                                               cc_response_inject_has_data,
		output tile_address_t                [1 : 0]               cc_response_inject_destinations,
		output logic                         [1 : 0]               cc_response_inject_destinations_valid,

		output logic                                               cc_forwarded_request_valid,
		output coherence_forwarded_message_t                       cc_forwarded_request,
		output tile_address_t                                      cc_forwarded_request_destination,

		// To Load Store Unit
		output logic                                               cc_snoop_tag_valid,
		output dcache_set_t                                        cc_snoop_tag_set,

		output logic                                               cc_update_ldst_valid,
		output cc_command_t                                        cc_update_ldst_command,
		output dcache_way_idx_t                                    cc_update_ldst_way,
		output dcache_address_t                                    cc_update_ldst_address,
		output dcache_privileges_t                                 cc_update_ldst_privileges,
		output dcache_line_t                                       cc_update_ldst_store_value,

		output logic                                               cc_snoop_data_valid,
		output dcache_set_t                                        cc_snoop_data_set,
		output dcache_way_idx_t                                    cc_snoop_data_way,

		output logic                                               cc_wakeup,
		output thread_id_t                                         cc_wakeup_thread_id,

		// To Thread Controller
		output icache_lane_t                                       mem_instr_request_data_in,
		output logic                                               mem_instr_request_valid

	);

	logic                                            cc1_request_valid;
	coherence_request_t                              cc1_request;
	logic                                            cc1_request_mshr_hit;
	mshr_idx_t                                       cc1_request_mshr_index;
	mshr_entry_t                                     cc1_request_mshr_entry_info;
	thread_id_t                                      cc1_request_thread_id;
	dcache_address_t                                 cc1_request_address;
	dcache_line_t                                    cc1_request_data;
	dcache_store_mask_t                              cc1_request_dirty_mask;
	tile_address_t                                   cc1_request_source;
	sharer_count_t                                   cc1_request_sharers_count;
	dcache_tag_t        [`MSHR_LOOKUP_PORTS - 2 : 0] cc1_mshr_lookup_tag;
	dcache_set_t        [`MSHR_LOOKUP_PORTS - 2 : 0] cc1_mshr_lookup_set;
	message_response_t                               cc1_request_packet_type;
	logic                                            cc1_request_from_dir;   
	logic                                            cc1_response_recycled_consumed;

	logic                                            cc2_pending_valid;
	dcache_address_t                                 cc2_pending_address;
	logic               [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_hit;
	logic               [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_hit_set;
	mshr_idx_t          [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_index;
	mshr_entry_t        [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_entry_info;
	logic                                            cc2_request_valid;
	coherence_request_t                              cc2_request;
	thread_id_t                                      cc2_request_thread_id;
	dcache_address_t                                 cc2_request_address;
	dcache_line_t                                    cc2_request_data;
	dcache_store_mask_t                              cc2_request_dirty_mask;
	tile_address_t                                   cc2_request_source;
	sharer_count_t                                   cc2_request_sharers_count;
	logic                                            cc2_request_mshr_hit;
	mshr_idx_t                                       cc2_request_mshr_index;
	mshr_entry_t                                     cc2_request_mshr_entry_info;
	dcache_line_t                                    cc2_request_mshr_entry_data;
	mshr_idx_t                                       cc2_request_mshr_empty_index;
	logic                                            cc2_request_mshr_full;
	dcache_way_idx_t                                 cc2_request_lru_way_idx;
	logic                                            cc2_request_replacement_is_collision;
	dcache_way_idx_t                                 cc2_request_snoop_way_idx;
	logic                                            cc2_request_snoop_hit;
	dcache_tag_t        [`DCACHE_WAY - 1 : 0]        cc2_request_snoop_tag;
	dcache_privileges_t [`DCACHE_WAY - 1 : 0]        cc2_request_snoop_privileges;
	coherence_state_t   [`DCACHE_WAY - 1 : 0]        cc2_request_coherence_states;
	message_response_t                               cc2_request_packet_type;
	logic                                            cc2_request_from_dir;   

	logic                                            cc3_pending_valid;
	dcache_address_t                                 cc3_pending_address;
	logic                                            cc3_update_mshr_en;
	mshr_idx_t                                       cc3_update_mshr_index;
	mshr_entry_t                                     cc3_update_mshr_entry_info;
	dcache_line_t                                    cc3_update_mshr_entry_data;
	logic                                            cc3_update_coherence_state_en;
	dcache_set_t                                     cc3_update_coherence_state_index;
	dcache_way_idx_t                                 cc3_update_coherence_state_way;
	coherence_state_t                                cc3_update_coherence_state_entry;
	logic                                            cc3_update_lru_fill_en;
	logic                                            cc3_message_valid;
	logic                                            cc3_message_is_response;
	logic                                            cc3_message_is_forward;
	message_request_t                                cc3_message_request_type;
	message_response_t                               cc3_message_response_type;
	message_forwarded_request_t                      cc3_message_forwarded_request_type;
	dcache_address_t                                 cc3_message_address;
	dcache_line_t                                    cc3_message_data;
	dcache_store_mask_t                              cc3_message_dirty_mask;
	logic                                            cc3_message_has_data;
	logic                                            cc3_message_send_data_from_cache;
	logic                                            cc3_message_is_receiver_dir;
	logic                                            cc3_message_is_receiver_req;
	logic                                            cc3_message_is_receiver_mc;
	tile_address_t                                   cc3_message_requestor;
	logic                                            cc3_request_is_flush;
	logic                                     	 cc3_response_recycled_valid;
	coherence_response_message_t              	 cc3_responce_recycled;

	logic                                            rrb_empty;
	logic                                            rrb_response_valid;
	coherence_response_message_t                     rrb_response;

	// Response Recycle Buffer, when a replacement due a response causes a collision, 
	// this is detected in the third stage, which recycles the response message in this buffer. 
	// The arbiter in the first stage reschedules it when no others entries in the MSHR 
	// have the same set of the recycled response, in order to avoid further collisions.
	sync_fifo #(
		.WIDTH ( $bits( coherence_response_message_t ) ),
		.SIZE  ( `MSHR_SIZE                            )
	)
	u_response_recycle_buffer
	(
		.clk         ( clk                            ),
		.reset       ( reset                          ),		
		.almost_empty(                                ),
		.almost_full (                                ),
		.dequeue_en  ( cc1_response_recycled_consumed ),
		.empty       ( rrb_empty                      ),
		.enqueue_en  ( cc3_response_recycled_valid    ),
		.flush_en    ( 1'b0                           ),
		.full        (                                ),
		.value_i     ( cc3_responce_recycled          ),
		.value_o     ( rrb_response                   )
	);

	assign rrb_response_valid = ~rrb_empty;

	cache_controller_stage1 #(
		.TILE_ID ( TILE_ID ),
		.CORE_ID ( CORE_ID )
	) u_cache_controller_stage1 (
		.clk                               ( clk                               ),
		.reset                             ( reset                             ),
		// From Core Interface
		.ci_store_request_valid            ( ci_store_request_valid            ),
		.ci_store_request_thread_id        ( ci_store_request_thread_id        ),
		.ci_store_request_address          ( ci_store_request_address          ),
		.ci_store_request_coherent         ( ci_store_request_coherent         ),
		.ci_load_request_valid             ( ci_load_request_valid             ),
		.ci_load_request_thread_id         ( ci_load_request_thread_id         ),
		.ci_load_request_address           ( ci_load_request_address           ),
		.ci_load_request_coherent          ( ci_load_request_coherent          ),
		.ci_replacement_request_valid      ( ci_replacement_request_valid      ),
		.ci_replacement_request_thread_id  ( ci_replacement_request_thread_id  ),
		.ci_replacement_request_address    ( ci_replacement_request_address    ),
		.ci_replacement_request_cache_line ( ci_replacement_request_cache_line ),
		.ci_replacement_request_dirty_mask ( ci_replacement_request_dirty_mask ),
		.ci_flush_request_valid            ( ci_flush_request_valid            ),
		.ci_flush_request_address          ( ci_flush_request_address          ),
		.ci_flush_request_dirty_mask       ( ci_flush_request_dirty_mask       ),
		.ci_flush_request_coherent         ( ci_flush_request_coherent         ),
		.ci_dinv_request_valid             ( ci_dinv_request_valid             ),
		.ci_dinv_request_address           ( ci_dinv_request_address           ),
		.ci_dinv_request_thread_id         ( ci_dinv_request_thread_id         ),
		.ci_dinv_request_cache_line        ( ci_dinv_request_cache_line        ),
		.ci_dinv_request_dirty_mask        ( ci_dinv_request_dirty_mask        ),
		.ci_dinv_request_coherent          ( ci_dinv_request_coherent          ),
		// From Response Recycled Buffer
		.rrb_response_valid                ( rrb_response_valid                ),
		.rrb_response                      ( rrb_response                      ),
		// From Network Interface
		.ni_forwarded_request              ( ni_forwarded_request              ),
		.ni_forwarded_request_valid        ( ni_forwarded_request_valid        ),
		.ni_response                       ( ni_response_eject                 ),
		.ni_response_valid                 ( ni_response_eject_valid           ),
		.ni_request_network_available      ( ni_request_network_available      ),
		.ni_forward_network_available      ( ni_forward_network_available      ),
		.ni_response_network_available     ( ni_response_network_available     ),
		// From Cache Controller Stage 2
		.cc2_pending_valid                 ( cc2_pending_valid                 ),
		.cc2_pending_address               ( cc2_pending_address               ),
		.cc2_mshr_lookup_hit               ( cc2_mshr_lookup_hit               ),
		.cc2_mshr_lookup_hit_set           ( cc2_mshr_lookup_hit_set           ),
		.cc2_mshr_lookup_index             ( cc2_mshr_lookup_index             ),
		.cc2_mshr_lookup_entry_info        ( cc2_mshr_lookup_entry_info        ),
		.cc2_request_mshr_full             ( cc2_request_mshr_full             ),
		// From Cache Controller Stage 3
		.cc3_pending_valid                 ( cc3_pending_valid                 ),
		.cc3_pending_address               ( cc3_pending_address               ),
		// To Core Interface
		.cc1_dequeue_store_request         ( cc_dequeue_store_request          ),
		.cc1_dequeue_load_request          ( cc_dequeue_load_request           ),
		.cc1_dequeue_replacement_request   ( cc_dequeue_replacement_request    ),
		.cc1_dequeue_flush_request         ( cc_dequeue_flush_request          ),
		.cc1_dequeue_dinv_request          ( cc_dequeue_dinv_request           ),
		// To Network Interface
		.cc1_forwarded_request_consumed    ( cc_forwarded_request_consumed     ),
		.cc1_response_eject_consumed       ( cc_response_eject_consumed        ),
		// To Response Recycled Buffer
		.cc1_response_recycled_consumed    ( cc1_response_recycled_consumed    ),
		// To Cache Controller Stage 2
		.cc1_request_valid                 ( cc1_request_valid                 ),
		.cc1_request                       ( cc1_request                       ),
		.cc1_request_mshr_hit              ( cc1_request_mshr_hit              ),
		.cc1_request_mshr_index            ( cc1_request_mshr_index            ),
		.cc1_request_mshr_entry_info       ( cc1_request_mshr_entry_info       ),
		.cc1_request_thread_id             ( cc1_request_thread_id             ),
		.cc1_request_address               ( cc1_request_address               ),
		.cc1_request_data                  ( cc1_request_data                  ),
		.cc1_request_dirty_mask            ( cc1_request_dirty_mask            ),
		.cc1_request_source                ( cc1_request_source                ),
		.cc1_request_sharers_count         ( cc1_request_sharers_count         ),
		.cc1_request_packet_type           ( cc1_request_packet_type           ),
	        .cc1_request_from_dir              ( cc1_request_from_dir              ),
		.cc1_mshr_lookup_tag               ( cc1_mshr_lookup_tag               ),
		.cc1_mshr_lookup_set               ( cc1_mshr_lookup_set               ),
		// To Load Store Unit
		.cc1_snoop_tag_valid               ( cc_snoop_tag_valid                ),
		.cc1_snoop_tag_set                 ( cc_snoop_tag_set                  ),
		// To Thread Controller
		.mem_instr_request_data_in         ( mem_instr_request_data_in         ),
		.mem_instr_request_valid           ( mem_instr_request_valid           )
	);

	cache_controller_stage2 u_cache_controller_stage2 (
		.clk                                  ( clk                                  ),
		.reset                                ( reset                                ),
		//From Cache Controller Stage 1
		.cc1_request_valid                    ( cc1_request_valid                    ),
		.cc1_request                          ( cc1_request                          ),
		.cc1_request_mshr_hit                 ( cc1_request_mshr_hit                 ),
		.cc1_request_mshr_index               ( cc1_request_mshr_index               ),
		.cc1_request_mshr_entry_info          ( cc1_request_mshr_entry_info          ),
		.cc1_request_thread_id                ( cc1_request_thread_id                ),
		.cc1_request_address                  ( cc1_request_address                  ),
		.cc1_request_data                     ( cc1_request_data                     ),
		.cc1_request_dirty_mask               ( cc1_request_dirty_mask               ),
		.cc1_request_source                   ( cc1_request_source                   ),
		.cc1_request_sharers_count            ( cc1_request_sharers_count            ),
		.cc1_request_packet_type              ( cc1_request_packet_type              ),
	    	.cc1_request_from_dir                 ( cc1_request_from_dir                 ),
		.cc1_mshr_lookup_tag                  ( cc1_mshr_lookup_tag                  ),
		.cc1_mshr_lookup_set                  ( cc1_mshr_lookup_set                  ),
		//From Cache Controller Stage 3
		.cc3_update_mshr_en                   ( cc3_update_mshr_en                   ),
		.cc3_update_mshr_index                ( cc3_update_mshr_index                ),
		.cc3_update_mshr_entry_info           ( cc3_update_mshr_entry_info           ),
		.cc3_update_mshr_entry_data           ( cc3_update_mshr_entry_data           ),
		.cc3_update_coherence_state_en        ( cc3_update_coherence_state_en        ),
		.cc3_update_coherence_state_index     ( cc3_update_coherence_state_index     ),
		.cc3_update_coherence_state_way       ( cc3_update_coherence_state_way       ),
		.cc3_update_coherence_state_entry     ( cc3_update_coherence_state_entry     ),
		.cc3_update_lru_fill_en               ( cc3_update_lru_fill_en               ),
		//From Load Store Unit
		.ldst_snoop_tag                       ( ldst_snoop_tag                       ),
		.ldst_snoop_privileges                ( ldst_snoop_privileges                ),
		.ldst_lru_update_set                  ( ldst_lru_update_set                  ),
		.ldst_lru_update_en                   ( ldst_lru_update_en                   ),
		.ldst_lru_update_way                  ( ldst_lru_update_way                  ),
		//To Cache Controller Stage 1
		.cc2_pending_valid                    ( cc2_pending_valid                    ),
		.cc2_pending_address                  ( cc2_pending_address                  ),
		.cc2_mshr_lookup_hit                  ( cc2_mshr_lookup_hit                  ),
		.cc2_mshr_lookup_hit_set              ( cc2_mshr_lookup_hit_set              ),
		.cc2_mshr_lookup_index                ( cc2_mshr_lookup_index                ),
		.cc2_mshr_lookup_entry_info           ( cc2_mshr_lookup_entry_info           ),
		//To Cache Controller Stage 3
		.cc2_request_valid                    ( cc2_request_valid                    ),
		.cc2_request                          ( cc2_request                          ),
		.cc2_request_thread_id                ( cc2_request_thread_id                ),
		.cc2_request_address                  ( cc2_request_address                  ),
		.cc2_request_data                     ( cc2_request_data                     ),
		.cc2_request_dirty_mask               ( cc2_request_dirty_mask               ),
		.cc2_request_source                   ( cc2_request_source                   ),
		.cc2_request_sharers_count            ( cc2_request_sharers_count            ),
		.cc2_request_packet_type              ( cc2_request_packet_type              ),
	    	.cc2_request_from_dir                 ( cc2_request_from_dir                 ),
		.cc2_request_mshr_hit                 ( cc2_request_mshr_hit                 ),
		.cc2_request_mshr_index               ( cc2_request_mshr_index               ),
		.cc2_request_mshr_entry_info          ( cc2_request_mshr_entry_info          ),
		.cc2_request_mshr_entry_data          ( cc2_request_mshr_entry_data          ),
		.cc2_request_mshr_empty_index         ( cc2_request_mshr_empty_index         ),
		.cc2_request_mshr_full                ( cc2_request_mshr_full                ),
		.cc2_request_replacement_is_collision ( cc2_request_replacement_is_collision ),
		.cc2_request_lru_way_idx              ( cc2_request_lru_way_idx              ),
		.cc2_request_snoop_way_idx            ( cc2_request_snoop_way_idx            ),
		.cc2_request_snoop_hit                ( cc2_request_snoop_hit                ),
		.cc2_request_snoop_tag                ( cc2_request_snoop_tag                ),
		.cc2_request_snoop_privileges         ( cc2_request_snoop_privileges         ),
		.cc2_request_coherence_states         ( cc2_request_coherence_states         )
	);

	cache_controller_stage3 u_cache_controller_stage3 (
		.clk                              ( clk                              ),
		.reset                            ( reset                            ),
		//From Cache Controller Stage 2
		.cc2_request_valid                ( cc2_request_valid                ),
		.cc2_request                      ( cc2_request                      ),
		.cc2_request_thread_id            ( cc2_request_thread_id            ),
		.cc2_request_address              ( cc2_request_address              ),
		.cc2_request_data                 ( cc2_request_data                 ),
		.cc2_request_dirty_mask           ( cc2_request_dirty_mask           ),
		.cc2_request_source               ( cc2_request_source               ),
		.cc2_request_sharers_count        ( cc2_request_sharers_count        ),
		.cc2_request_packet_type          ( cc2_request_packet_type          ),
	    	.cc2_request_from_dir             ( cc2_request_from_dir             ),
		.cc2_request_mshr_hit             ( cc2_request_mshr_hit             ),
		.cc2_request_mshr_index           ( cc2_request_mshr_index           ),
		.cc2_request_mshr_entry_info      ( cc2_request_mshr_entry_info      ),
		.cc2_request_mshr_entry_data      ( cc2_request_mshr_entry_data      ),
		.cc2_request_mshr_empty_index     ( cc2_request_mshr_empty_index     ),
		.cc2_request_mshr_full            ( cc2_request_mshr_full            ),
		.cc2_request_lru_way_idx          ( cc2_request_lru_way_idx          ),
		.cc2_request_replacement_is_collision ( cc2_request_replacement_is_collision ),
		.cc2_request_snoop_way_idx        ( cc2_request_snoop_way_idx        ),
		.cc2_request_snoop_hit            ( cc2_request_snoop_hit            ),
		.cc2_request_snoop_tag            ( cc2_request_snoop_tag            ),
		.cc2_request_snoop_privileges     ( cc2_request_snoop_privileges     ),
		.cc2_request_coherence_states     ( cc2_request_coherence_states     ),
		//To Load Store Unit
		.cc3_update_ldst_valid            ( cc_update_ldst_valid             ),
		.cc3_update_ldst_command          ( cc_update_ldst_command           ),
		.cc3_update_ldst_way              ( cc_update_ldst_way               ),
		.cc3_update_ldst_address          ( cc_update_ldst_address           ),
		.cc3_update_ldst_privileges       ( cc_update_ldst_privileges        ),
		.cc3_update_ldst_store_value      ( cc_update_ldst_store_value       ),
		.cc3_snoop_data_valid             ( cc_snoop_data_valid              ),
		.cc3_snoop_data_set               ( cc_snoop_data_set                ),
		.cc3_snoop_data_way               ( cc_snoop_data_way                ),
		.cc3_wakeup                       ( cc_wakeup                        ),
		.cc3_wakeup_thread_id             ( cc_wakeup_thread_id              ),
		//To Cache Controller Stage 1
		.cc3_pending_valid                ( cc3_pending_valid                ),
		.cc3_pending_address              ( cc3_pending_address              ),
		//To Cache Controller Stage 2
		.cc3_update_mshr_en               ( cc3_update_mshr_en               ),
		.cc3_update_mshr_index            ( cc3_update_mshr_index            ),
		.cc3_update_mshr_entry_info       ( cc3_update_mshr_entry_info       ),
		.cc3_update_mshr_entry_data       ( cc3_update_mshr_entry_data       ),
		.cc3_update_coherence_state_en    ( cc3_update_coherence_state_en    ),
		.cc3_update_coherence_state_index ( cc3_update_coherence_state_index ),
		.cc3_update_coherence_state_way   ( cc3_update_coherence_state_way   ),
		.cc3_update_coherence_state_entry ( cc3_update_coherence_state_entry ),
		.cc3_update_lru_fill_en           ( cc3_update_lru_fill_en           ),
		//To Cache Controller Stage 4
		.cc3_request_is_flush             ( cc3_request_is_flush             ),
		.cc3_message_valid                ( cc3_message_valid                ),
		.cc3_message_is_response          ( cc3_message_is_response          ),
		.cc3_message_is_forward           ( cc3_message_is_forward           ),
		.cc3_message_request_type         ( cc3_message_request_type         ),
		.cc3_message_response_type        ( cc3_message_response_type        ),
		.cc3_message_forwarded_request_type ( cc3_message_forwarded_request_type ),
		.cc3_message_address              ( cc3_message_address              ),
		.cc3_message_data                 ( cc3_message_data                 ),
		.cc3_message_dirty_mask           ( cc3_message_dirty_mask           ),
		.cc3_message_has_data             ( cc3_message_has_data             ),
		.cc3_message_send_data_from_cache ( cc3_message_send_data_from_cache ),
		.cc3_message_is_receiver_dir      ( cc3_message_is_receiver_dir      ),
		.cc3_message_is_receiver_req      ( cc3_message_is_receiver_req      ),
		.cc3_message_is_receiver_mc       ( cc3_message_is_receiver_mc       ),
		.cc3_message_requestor            ( cc3_message_requestor            ),
		// To Response Recycle Buffer
		.cc3_response_recycled_valid      ( cc3_response_recycled_valid      ),
		.cc3_responce_recycled            ( cc3_responce_recycled            )
	);

	cache_controller_stage4 #(
		.TILE_ID ( TILE_ID ),
		.CORE_ID ( CORE_ID )
	) u_cache_controller_stage4 (
		.clk                              ( clk                                   ),
		.reset                            ( reset                                 ),
		//From Cache Controller Stage 3
		.cc3_request_is_flush             ( cc3_request_is_flush                  ),
		.cc3_message_valid                ( cc3_message_valid                     ),
		.cc3_message_is_response          ( cc3_message_is_response               ),
		.cc3_message_is_forward           ( cc3_message_is_forward                ),
		.cc3_message_request_type         ( cc3_message_request_type              ),
		.cc3_message_response_type        ( cc3_message_response_type             ),
		.cc3_message_forwarded_request_type ( cc3_message_forwarded_request_type  ),
		.cc3_message_address              ( cc3_message_address                   ),
		.cc3_message_data                 ( cc3_message_data                      ),
		.cc3_message_dirty_mask           ( cc3_message_dirty_mask                ),
		.cc3_message_has_data             ( cc3_message_has_data                  ),
		.cc3_message_send_data_from_cache ( cc3_message_send_data_from_cache      ),
		.cc3_message_is_receiver_dir      ( cc3_message_is_receiver_dir           ),
		.cc3_message_is_receiver_req      ( cc3_message_is_receiver_req           ),
		.cc3_message_is_receiver_mc       ( cc3_message_is_receiver_mc            ),
		.cc3_message_requestor            ( cc3_message_requestor                 ),
		//From Load Store Unit
		.ldst_snoop_data                  ( ldst_snoop_data                       ),
		//To Network Interface
		.cc4_request_valid                ( cc_request_valid                      ),
		.cc4_request                      ( cc_request                            ),
		.cc4_request_has_data             ( cc_request_has_data                   ),
		.cc4_request_destinations         ( cc_request_destinations               ),
		.cc4_request_destinations_valid   ( cc_request_destinations_valid         ),
		.cc4_response_valid               ( cc_response_inject_valid              ),
		.cc4_response                     ( cc_response_inject                    ),
		.cc4_response_has_data            ( cc_response_inject_has_data           ),
		.cc4_response_destinations        ( cc_response_inject_destinations       ),
		.cc4_response_destinations_valid  ( cc_response_inject_destinations_valid ),
		.cc4_forwarded_request_valid        ( cc_forwarded_request_valid       ),
		.cc4_forwarded_request              ( cc_forwarded_request             ),
		.cc4_forwarded_request_destination  ( cc_forwarded_request_destination )
	);

endmodule
