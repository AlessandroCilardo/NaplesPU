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

/* The Directory controller manages the L2 cache and the ownership of 
 * memory lines, it is organized in a distributed directory structure. 
 */ 

module directory_controller #(
		parameter TILE_ID        = 0,
		parameter TILE_MEMORY_ID = 1)
	(
		input                                                      clk,
		input                                                      reset,

		// From Thread Controller
		input  logic                                               tc_instr_request_valid,
		input  address_t                                           tc_instr_request_address,

		// To Thread Controller
		output logic                                               mem_instr_request_available,

		// From Network Interface
		input  logic                                               ni_response_network_available,
		input  logic                                               ni_forwarded_request_network_available,

		input  logic                                               ni_request_valid,
		input  coherence_request_message_t                         ni_request,

		input  logic                                               ni_response_valid,
		input  coherence_response_message_t                        ni_response,

		// To Network Interface
		output logic                                               dc_request_consumed,
		output logic                                               dc_response_consumed,

		output coherence_forwarded_message_t                       dc_forwarded_request,
		output logic                                               dc_forwarded_request_valid,
		output logic                         [`TILE_COUNT - 1 : 0] dc_forwarded_request_destinations,

		output coherence_response_message_t                        dc_response,
		output logic                                               dc_response_valid,
		output logic                                               dc_response_has_data,
		output logic                         [`TILE_COUNT - 1 : 0] dc_response_destinations
	);

	// Stage 1
	l2_cache_tag_t        [`TSHR_LOOKUP_PORTS - 1 : 0]                            dc1_tshr_lookup_tag;
	l2_cache_set_t        [`TSHR_LOOKUP_PORTS - 1 : 0]                            dc1_tshr_lookup_set;
	logic                                                                         dc1_message_valid;
	logic                 [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0]                 dc1_message_type;
	logic                                                                         dc1_message_tshr_hit;
	tshr_idx_t                                                                    dc1_message_tshr_index;
	tshr_entry_t                                                                  dc1_message_tshr_entry_info;
	l2_cache_address_t                                                            dc1_message_address;
	dcache_line_t                                                                 dc1_message_data;
	tile_address_t                                                                dc1_message_source;
	logic                 [`L2_CACHE_WAY - 1 : 0]                                 dc1_message_cache_valid;
	logic                 [`L2_CACHE_WAY - 1 : 0][`DIRECTORY_STATE_WIDTH - 1 : 0] dc1_message_cache_state;
	l2_cache_tag_t        [`L2_CACHE_WAY - 1 : 0]                                 dc1_message_cache_tag;
	logic                                                                         dc1_repl_queue_dequeue;
	logic                 [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc1_replacement_state;
	logic                 [`TILE_COUNT - 1 : 0]                                   dc1_replacement_sharers_list;
	tile_address_t                                                                dc1_replacement_owner;
	logic                                                                         dc1_wb_request_dequeue;

	// Stage 2
	logic                                                                         dc2_pending;
	l2_cache_address_t                                                            dc2_pending_address;
	logic                                                                         dc2_message_valid;
	logic                 [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0]                 dc2_message_type;
	l2_cache_address_t                                                            dc2_message_address;
	dcache_line_t                                                                 dc2_message_data;
	tile_address_t                                                                dc2_message_source;
	logic                                                                         dc2_message_tshr_hit;
	tshr_idx_t                                                                    dc2_message_tshr_index;
	tshr_entry_t                                                                  dc2_message_tshr_entry_info;
	logic                                                                         dc2_message_cache_hit;
	logic                                                                         dc2_message_cache_valid;
	logic                 [`TILE_COUNT - 1 : 0]                                   dc2_message_cache_sharers_list;
	tile_address_t                                                                dc2_message_cache_owner;
	logic                 [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc2_message_cache_state;
	l2_cache_tag_t                                                                dc2_message_cache_tag;
	dcache_line_t                                                                 dc2_message_cache_data;
	l2_cache_way_idx_t                                                            dc2_message_cache_way;
	logic                 [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc2_replacement_state;
	logic                 [`TILE_COUNT - 1 : 0]                                   dc2_replacement_sharers_list;
	tile_address_t                                                                dc2_replacement_owner;

	// Stage 3
	logic                                                                         dc3_instr_request_dequeue;
	logic                                                                         dc3_pending;
	l2_cache_address_t                                                            dc3_pending_address;
	logic                                                                         dc3_update_cache_enable;
	logic                                                                         dc3_update_cache_validity_bit;
	l2_cache_set_t                                                                dc3_update_cache_set;
	l2_cache_way_idx_t                                                            dc3_update_cache_way;
	l2_cache_tag_t                                                                dc3_update_cache_tag;
	logic                 [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc3_update_cache_state;
	logic                 [`TILE_COUNT - 1 : 0]                                   dc3_update_cache_sharers_list;
	tile_address_t                                                                dc3_update_cache_owner;
	dcache_line_t                                                                 dc3_update_cache_data;
	logic                                                                         dc3_update_tshr_enable;
	tshr_idx_t                                                                    dc3_update_tshr_index;
	tshr_entry_t                                                                  dc3_update_tshr_entry_info;
	logic                                                                         dc3_update_plru_en;
	l2_cache_set_t                                                                dc3_update_plru_set;
	l2_cache_way_idx_t                                                            dc3_update_plru_way;
	logic                                                                         dc3_replacement_enqueue;
	replacement_request_t                                                         dc3_replacement_request;
	logic                                                                         dc3_wb_enable;
	dcache_line_t                                                                 dc3_wb_data;
	address_t                                                                     dc3_wb_addr;

	// Instruction Request FIFO
	logic                                                                         instr_fifo_empty, instr_fifo_full;
	logic                                                                         instr_fifo_pending;
	address_t                                                                     instr_fifo_request_out;

	// THSR
	logic                 [`TSHR_LOOKUP_PORTS - 1 : 0]                            tshr_lookup_hit;
	tshr_idx_t            [`TSHR_LOOKUP_PORTS - 1 : 0]                            tshr_lookup_index;
	tshr_entry_t          [`TSHR_LOOKUP_PORTS - 1 : 0]                            tshr_lookup_entry_info;
	logic                                                                         tshr_full;
	tshr_idx_t                                                                    tshr_empty_index;

	// Replacement Queue
	logic                                                                         rp_empty;
	replacement_request_t                                                         rp_request;

	// WB Gen Queue
	logic                                                                         wb_gen_empty;
	dcache_line_t                                                                 wb_gen_data;
	address_t                                                                     wb_gen_addr;

	l2_tshr #(
		.WRITE_FIRST( "FALSE" )
	)
	u_l2_tshr (
		.clk         ( clk                        ),
		.enable      ( 1'b1                       ),
		.reset       ( reset                      ),
		.lookup_tag  ( dc1_tshr_lookup_tag        ),
		.lookup_set  ( dc1_tshr_lookup_set        ),
		.lookup_hit  ( tshr_lookup_hit            ),
		.lookup_index( tshr_lookup_index          ),
		.lookup_entry( tshr_lookup_entry_info     ),
		.full        ( tshr_full                  ),
		.empty_index ( tshr_empty_index           ),
		.update_en   ( dc3_update_tshr_enable     ),
		.update_index( dc3_update_tshr_index      ),
		.update_entry( dc3_update_tshr_entry_info )
	);

	assign mem_instr_request_available = ~instr_fifo_full;
	assign instr_fifo_pending          = ~instr_fifo_empty;

	sync_fifo #(
		.WIDTH                ( $bits( address_t ) ),
		.SIZE                 ( 2                  ),
		.ALMOST_FULL_THRESHOLD( 1                  )
	)
	instr_request_fifo (
		.clk         ( clk                       ),
		.reset       ( reset                     ),
		.flush_en    ( 1'b0                      ), 
		.full        (                           ),
		.almost_full ( instr_fifo_full           ),
		.enqueue_en  ( tc_instr_request_valid    ),
		.value_i     ( tc_instr_request_address  ),
		.empty       ( instr_fifo_empty          ),
		.almost_empty(                           ),
		.dequeue_en  ( dc3_instr_request_dequeue ),
		.value_o     ( instr_fifo_request_out    )
	);

	sync_fifo #(
		.WIDTH ( $bits( replacement_request_t ) ),
		.SIZE  ( `TSHR_SIZE                     )
	) replacement_queue (
		.clk         ( clk                     ),
		.reset       ( reset                   ),
		.flush_en    ( 1'b0                    ),
		.full        (                         ),
		.almost_full (                         ),
		.enqueue_en  ( dc3_replacement_enqueue ),
		.value_i     ( dc3_replacement_request ),
		.empty       ( rp_empty                ),
		.almost_empty(                         ),
		.dequeue_en  ( dc1_repl_queue_dequeue  ),
		.value_o     ( rp_request              )
	);

	// WB Generated FIFO - in case of PutM <-> PutAck-recall 
	// the directory recycles the putM for rescheduling it later on, 
	// in order to generate a WB to the main memory. 
	// This is done due a race condition in which the CC turns into 
	// MIa->I state because it receives the PutAck before the recall,
	// thus no WB is generated by the CC. 
	sync_fifo #(
		.WIDTH                ( $bits( dcache_line_t ) + $bits( address_t ) ),
		.SIZE                 ( 4                                         )
	)
	wb_gen_request_fifo (
		.clk         ( clk                        ),
		.reset       ( reset                      ),
		.flush_en    ( 1'b0                       ),
		.full        (                            ),
		.almost_full (                            ),
		.enqueue_en  ( dc3_wb_enable              ),
		.value_i     ( {dc3_wb_addr, dc3_wb_data} ),
		.empty       ( wb_gen_empty               ),
		.almost_empty(                            ),
		.dequeue_en  ( dc1_wb_request_dequeue     ),
		.value_o     ( {wb_gen_addr, wb_gen_data} )
	);

	directory_controller_stage1 #(
		.TILE_ID( TILE_ID )
	) u_directory_controller_stage1 (
		.clk                                   ( clk                                    ),
		.reset                                 ( reset                                  ),
		//From Network Interface
		.ni_response_network_available         ( ni_response_network_available          ),
		.ni_forwarded_request_network_available( ni_forwarded_request_network_available ),
		.ni_request_valid                      ( ni_request_valid                       ),
		.ni_request                            ( ni_request                             ),
		.ni_response_valid                     ( ni_response_valid                      ),
		.ni_response                           ( ni_response                            ),
		//From Replacement Queue
		.rp_empty                              ( rp_empty                               ),
		.rp_request                            ( rp_request                             ),
		//From Directory Controller Stage 2
		.dc2_pending                           ( dc2_pending                            ),
		.dc2_pending_address                   ( dc2_pending_address                    ),
		//From Directory Controller Stage 3
		.dc3_pending                           ( dc3_pending                            ),
		.dc3_pending_address                   ( dc3_pending_address                    ),
		.dc3_update_cache_enable               ( dc3_update_cache_enable                ),
		.dc3_update_cache_validity_bit         ( dc3_update_cache_validity_bit          ),
		.dc3_update_cache_set                  ( dc3_update_cache_set                   ),
		.dc3_update_cache_way                  ( dc3_update_cache_way                   ),
		.dc3_update_cache_tag                  ( dc3_update_cache_tag                   ),
		.dc3_update_cache_state                ( dc3_update_cache_state                 ),
		//From TSHR
		.tshr_full                             ( tshr_full                              ),
		.tshr_lookup_hit                       ( tshr_lookup_hit                        ),
		.tshr_lookup_index                     ( tshr_lookup_index                      ),
		.tshr_lookup_entry_info                ( tshr_lookup_entry_info                 ),
		//From WB Gen Queue
		.wb_gen_pending                        ( ~wb_gen_empty                          ),
		.wb_gen_data                           ( wb_gen_data                            ),
		.wb_gen_addr                           ( wb_gen_addr                            ),
		//To WB Gen Queue
		.dc1_wb_request_dequeue                ( dc1_wb_request_dequeue                 ),
		//To TSHR
		.dc1_tshr_lookup_tag                   ( dc1_tshr_lookup_tag                    ),
		.dc1_tshr_lookup_set                   ( dc1_tshr_lookup_set                    ),
		//To Network Interface
		.dc1_request_consumed                  ( dc_request_consumed                    ),
		.dc1_response_inject_consumed          ( dc_response_consumed                   ),
		//To Replacement Queue
		.dc1_repl_queue_dequeue                ( dc1_repl_queue_dequeue                 ),
		//To Directory Controller Stage 2
		.dc1_message_valid                     ( dc1_message_valid                      ),
		.dc1_message_type                      ( dc1_message_type                       ),
		.dc1_message_tshr_hit                  ( dc1_message_tshr_hit                   ),
		.dc1_message_tshr_index                ( dc1_message_tshr_index                 ),
		.dc1_message_tshr_entry_info           ( dc1_message_tshr_entry_info            ),
		.dc1_message_address                   ( dc1_message_address                    ),
		.dc1_message_data                      ( dc1_message_data                       ),
		.dc1_message_source                    ( dc1_message_source                     ),
		.dc1_message_cache_valid               ( dc1_message_cache_valid                ),
		.dc1_message_cache_state               ( dc1_message_cache_state                ),
		.dc1_message_cache_tag                 ( dc1_message_cache_tag                  ),
		.dc1_replacement_state                 ( dc1_replacement_state                  ),
		.dc1_replacement_sharers_list          ( dc1_replacement_sharers_list           ),
		.dc1_replacement_owner                 ( dc1_replacement_owner                  )
	);

	directory_controller_stage2 u_directory_controller_stage2 (
		.clk                           ( clk                            ),
		.reset                         ( reset                          ),
		//From Directory Controller Stage 1
		.dc1_message_valid             ( dc1_message_valid              ),
		.dc1_message_type              ( dc1_message_type               ),
		.dc1_message_tshr_hit          ( dc1_message_tshr_hit           ),
		.dc1_message_tshr_index        ( dc1_message_tshr_index         ),
		.dc1_message_tshr_entry_info   ( dc1_message_tshr_entry_info    ),
		.dc1_message_address           ( dc1_message_address            ),
		.dc1_message_data              ( dc1_message_data               ),
		.dc1_message_source            ( dc1_message_source             ),
		.dc1_message_cache_valid       ( dc1_message_cache_valid        ),
		.dc1_message_cache_state       ( dc1_message_cache_state        ),
		.dc1_message_cache_tag         ( dc1_message_cache_tag          ),
		.dc1_replacement_state         ( dc1_replacement_state          ),
		.dc1_replacement_sharers_list  ( dc1_replacement_sharers_list   ),
		.dc1_replacement_owner         ( dc1_replacement_owner          ) ,
		//From Directory Controller Stage 3
		.dc3_update_cache_enable       ( dc3_update_cache_enable        ),
		.dc3_update_cache_set          ( dc3_update_cache_set           ),
		.dc3_update_cache_way          ( dc3_update_cache_way           ),
		.dc3_update_cache_sharers_list ( dc3_update_cache_sharers_list  ),
		.dc3_update_cache_owner        ( dc3_update_cache_owner         ),
		.dc3_update_cache_data         ( dc3_update_cache_data          ),
		.dc3_update_plru_en            ( dc3_update_plru_en             ),
		.dc3_update_plru_set           ( dc3_update_plru_set            ),
		.dc3_update_plru_way           ( dc3_update_plru_way            ),
		//To Directory Controller Stage 1
		.dc2_pending                   ( dc2_pending                    ),
		.dc2_pending_address           ( dc2_pending_address            ),
		//To Directory Controller Stage 3
		.dc2_message_valid             ( dc2_message_valid              ),
		.dc2_message_type              ( dc2_message_type               ),
		.dc2_message_address           ( dc2_message_address            ),
		.dc2_message_data              ( dc2_message_data               ),
		.dc2_message_source            ( dc2_message_source             ),
		.dc2_replacement_state         ( dc2_replacement_state          ),
		.dc2_replacement_sharers_list  ( dc2_replacement_sharers_list   ),
		.dc2_replacement_owner         ( dc2_replacement_owner          ) ,
		.dc2_message_tshr_hit          ( dc2_message_tshr_hit           ),
		.dc2_message_tshr_index        ( dc2_message_tshr_index         ),
		.dc2_message_tshr_entry_info   ( dc2_message_tshr_entry_info    ),
		.dc2_message_cache_hit         ( dc2_message_cache_hit          ),
		.dc2_message_cache_valid       ( dc2_message_cache_valid        ),
		.dc2_message_cache_sharers_list( dc2_message_cache_sharers_list ),
		.dc2_message_cache_owner       ( dc2_message_cache_owner        ),
		.dc2_message_cache_state       ( dc2_message_cache_state        ),
		.dc2_message_cache_tag         ( dc2_message_cache_tag          ),
		.dc2_message_cache_data        ( dc2_message_cache_data         ),
		.dc2_message_cache_way         ( dc2_message_cache_way          )
	);

	directory_controller_stage3 #(
		.TILE_ID       ( TILE_ID        ),
		.TILE_MEMORY_ID( TILE_MEMORY_ID )
	) u_directory_controller_stage3 (
		.clk                                   ( clk                                    ),
		.reset                                 ( reset                                  ),
		// From NI
		.ni_forwarded_request_network_available( ni_forwarded_request_network_available ),
		.instr_request_pending                 ( instr_fifo_pending                     ),
		.instr_request_address                 ( instr_fifo_request_out                 ),
		// To Instruction Request Buffer
		.dc3_instr_request_dequeue             ( dc3_instr_request_dequeue              ),
		//From Directory Controller Stage 2
		.dc2_message_valid                     ( dc2_message_valid                      ),
		.dc2_message_type                      ( dc2_message_type                       ),
		.dc2_message_address                   ( dc2_message_address                    ),
		.dc2_message_data                      ( dc2_message_data                       ),
		.dc2_message_source                    ( dc2_message_source                     ),
		.dc2_replacement_state                 ( dc2_replacement_state                  ),
		.dc2_replacement_sharers_list          ( dc2_replacement_sharers_list           ),
		.dc2_replacement_owner                 ( dc2_replacement_owner                  ) ,
		.dc2_message_tshr_hit                  ( dc2_message_tshr_hit                   ),
		.dc2_message_tshr_index                ( dc2_message_tshr_index                 ),
		.dc2_message_tshr_entry_info           ( dc2_message_tshr_entry_info            ),
		.dc2_message_cache_hit                 ( dc2_message_cache_hit                  ),
		.dc2_message_cache_valid               ( dc2_message_cache_valid                ),
		.dc2_message_cache_state               ( dc2_message_cache_state                ),
		.dc2_message_cache_sharers_list        ( dc2_message_cache_sharers_list         ),
		.dc2_message_cache_owner               ( dc2_message_cache_owner                ),
		.dc2_message_cache_tag                 ( dc2_message_cache_tag                  ),
		.dc2_message_cache_data                ( dc2_message_cache_data                 ),
		.dc2_message_cache_way                 ( dc2_message_cache_way                  ),
		//From TSHR
		.tshr_empty_index                      ( tshr_empty_index                       ),
		//To Directory Controller Stage 1 and Directory Controller Stage 2
		.dc3_pending                           ( dc3_pending                            ),
		.dc3_pending_address                   ( dc3_pending_address                    ),
		.dc3_update_cache_enable               ( dc3_update_cache_enable                ),
		.dc3_update_cache_validity_bit         ( dc3_update_cache_validity_bit          ),
		.dc3_update_cache_set                  ( dc3_update_cache_set                   ),
		.dc3_update_cache_way                  ( dc3_update_cache_way                   ),
		.dc3_update_cache_tag                  ( dc3_update_cache_tag                   ),
		.dc3_update_cache_state                ( dc3_update_cache_state                 ),
		.dc3_update_cache_sharers_list         ( dc3_update_cache_sharers_list          ),
		.dc3_update_cache_owner                ( dc3_update_cache_owner                 ),
		.dc3_update_cache_data                 ( dc3_update_cache_data                  ),
		.dc3_update_plru_en                    ( dc3_update_plru_en                     ),
		.dc3_update_plru_set                   ( dc3_update_plru_set                    ),
		.dc3_update_plru_way                   ( dc3_update_plru_way                    ),
		//To TSHR
		.dc3_update_tshr_enable                ( dc3_update_tshr_enable                 ),
		.dc3_update_tshr_index                 ( dc3_update_tshr_index                  ),
		.dc3_update_tshr_entry_info            ( dc3_update_tshr_entry_info             ),
		//To WB Gen FIFO
		.dc3_wb_enable                         ( dc3_wb_enable                          ),                          
		.dc3_wb_data                           ( dc3_wb_data                            ),                          
		.dc3_wb_addr                           ( dc3_wb_addr                            ),
		//To Replacement Queue
		.dc3_replacement_enqueue               ( dc3_replacement_enqueue                ),
		.dc3_replacement_request               ( dc3_replacement_request                ),
		.dc3_forwarded_request                 ( dc_forwarded_request                   ),
		.dc3_forwarded_request_valid           ( dc_forwarded_request_valid             ),
		.dc3_forwarded_request_destinations    ( dc_forwarded_request_destinations      ),
		.dc3_response                          ( dc_response                            ),
		.dc3_response_valid                    ( dc_response_valid                      ),
		.dc3_response_has_data                 ( dc_response_has_data                   ),
		.dc3_response_destinations             ( dc_response_destinations               )
	);

endmodule
