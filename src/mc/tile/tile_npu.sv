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
`include "npu_message_service_defines.sv"
`include "npu_synchronization_defines.sv"

`ifdef DISPLAY_CORE
	`include "npu_debug_log.sv"
`endif

/* The NPU tile mainly equipped with a NaplesPU GPGPU core, and components 
 * that interface the core with both networking and coherence systems.
 */ 

module tile_npu # (
		parameter TILE_ID        = 0,
		parameter TILE_MEMORY_ID = 9,
		parameter CORE_ID        = 0,
		parameter SCRATCHPAD     = 0,
		parameter FPU            = 1 )
	(
		input                                                   clk,
		input                                                   reset,
		input                                                   enable,
		// From Network
		input         [`PORT_NUM - 1 : 1]                       tile_wr_en_in,
		input  flit_t [`PORT_NUM - 1 : 1]                       tile_flit_in,
		input         [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_in ,

		// To Network
		output        [`PORT_NUM - 1 : 1]                       tile_flit_out_valid,
		output flit_t [`PORT_NUM - 1 : 1]                       tile_flit_out,
		output        [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_out
	);

    localparam logic [`TOT_X_NODE_W-1 : 0] X_ADDR = TILE_ID[`TOT_X_NODE_W-1 : 0 ];
		localparam logic [`TOT_Y_NODE_W-1 : 0] Y_ADDR = TILE_ID[`TOT_X_NODE_W  +: `TOT_Y_NODE_W];

	//---- Router Signals ----//
	logic                               [`VC_PER_PORT - 1 : 0]                    router_credit;
	logic                               [`VC_PER_PORT - 1 : 0]                    ni_credit;

	logic                               [`PORT_NUM - 1 : 0]                       wr_en_in;
	flit_t                              [`PORT_NUM - 1 : 0]                       flit_in;
	logic                               [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_in;
	logic                               [`PORT_NUM - 1 : 0]                       wr_en_out;
	flit_t                              [`PORT_NUM - 1 : 0]                       flit_out;
	logic                               [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_out;

	//---- Cache controller Signals ----//
	// Request
	coherence_request_message_t                              l1d_request;
	logic                                                    l1d_request_valid;
	logic                                                    l1d_request_has_data;
	tile_address_t [1 : 0]                                   l1d_request_destinations;
	logic          [1 : 0]                                   l1d_request_destinations_valid;
	logic                                                    ni_request_network_available;
	// Forwarded Request
	coherence_forwarded_message_t                            ni_forwarded_request;
	logic                                                    ni_forwarded_request_valid;
	logic                                                    l1d_forwarded_request_consumed;
	// Response from CC
	coherence_response_message_t                             l1d_response;
	logic                                                    l1d_response_valid;
	logic                                                    l1d_response_has_data;
	tile_address_t [1 : 0]                                   l1d_response_destinations;
	logic          [1 : 0]                                   l1d_response_destinations_valid;
	logic                                                    ni_response_to_cc_network_available;
	// Forward from CC
	coherence_forwarded_message_t                            l1d_forwarded_request;
	logic                                                    l1d_forwarded_request_valid;
	tile_address_t                                           l1d_forwarded_request_destination;
	logic                                                    ni_forwarded_request_cc_network_available;
	// Response to CC
	logic                                                    l1d_response_consumed;
	logic                                                    ni_response_to_cc_valid;
	coherence_response_message_t                             ni_response_to_cc;

	//---- Directory controller Signals ----//
	// Forwarded Request
	coherence_forwarded_message_t                            dc_forwarded_request;
	logic                                                    dc_forwarded_request_valid;
	logic          [`TILE_COUNT - 1 : 0]                     dc_forwarded_request_destinations;
	logic                                                    ni_forwarded_request_dc_network_available;
	// Request
	coherence_request_message_t                              ni_request;
	logic                                                    ni_request_valid;
	logic                                                    dc_request_consumed;
	// Response Inject
	coherence_response_message_t                             dc_response;
	logic                                                    dc_response_valid;
	logic                                                    dc_response_has_data;
	logic          [`TILE_COUNT - 1 : 0]                     dc_response_destinations;
	tile_address_t                                           dc_response_destination_idx;
	logic                                                    ni_response_dc_network_available;
	// Response Eject
	logic                                                    ni_response_to_dc_valid;
	coherence_response_message_t                             ni_response_to_dc;
	logic                                                    dc_response_to_dc_consumed;

	//---- Core Signals ----//
	// Instruction Requests
	logic                                                    tc_instr_request_valid;
	address_t                                                tc_instr_request_address;
	logic                                                    mem_instr_request_available;
	// Boot manager
	logic                                                    hi_job_valid;
	address_t                                                hi_job_pc;
	thread_id_t                                              hi_job_thread_id;
	logic          [`THREAD_NUMB - 1 : 0]                    hi_thread_en;

	// ---- Service signals ---- //

	// NI Signal (net) to host requests manager (core)
	service_message_t                                        ni_n2c_mes_service;
	logic                                                    ni_n2c_mes_service_valid;
	logic                                                    c2n_mes_service_consumed;

	sync_account_message_t                                   ni_account_mess;
	logic                                                    ni_account_mess_valid;
	logic                                                    sc_account_consumed;
	// Barrier core
	sync_release_message_t                                   n2c_release_message;
	logic                                                    n2c_release_valid;
	logic                                                    n2c_mes_service_consumed;

	// Boot manager
	logic                                                    bm_n2c_mes_service_valid;
	service_message_t                                        bm_n2c_mes_service;
	logic                                                    bm_c2n_mes_service_consumed;

	// IO Interface
	logic                                                    io_intf_available_to_core;
	logic                                                    ldst_io_valid;
	thread_id_t                                              ldst_io_thread;
	logic [$bits(io_operation_t)-1 : 0]                      ldst_io_operation;
	address_t                                                ldst_io_address;
	register_t                                               ldst_io_data;
	logic                                                    io_intf_resp_valid;
	thread_id_t                                              io_intf_wakeup_thread;
	register_t                                               io_intf_resp_data;
	logic                                                    ldst_io_resp_consumed;
	logic                                                    io_intf_message_consumed;
	io_message_t                                             ni_io_message;
	logic                                                    ni_io_message_valid;

	// NI Signal (core) to net
	service_message_t                                        c2n_mes_service; // message to net service
	logic                                                    c2n_mes_service_valid;
	logic          [`TILE_COUNT - 1 : 0]                     c2n_mes_service_destinations_valid;
	logic                                                    c2n_mes_service_has_data;
	logic                                                    ni_c2n_mes_service_network_available;

	// Signal FIFO Scheduler
    localparam NUM_FIFO   = 4;
    localparam INDEX_FIFO = 2;

	logic             [NUM_FIFO - 1 : 0] c2n_network_available;
	service_message_t [NUM_FIFO - 1 : 0] c2n_message_out;
	logic             [NUM_FIFO - 1 : 0] c2n_message_out_valid;
	tile_mask_t       [NUM_FIFO - 1 : 0] c2n_destination_valid;


//  -----------------------------------------------------------------------
//  -- Tile - Core and Memory Access Interface
//  -----------------------------------------------------------------------

	sync_message_t         c2n_sync_message_wrapped;
	sync_account_message_t c2n_account_message;

	assign c2n_sync_message_wrapped.sync_type              = ACCOUNT;
	assign c2n_sync_message_wrapped.sync_mess.account_mess = c2n_account_message;

	assign c2n_message_out[1].message_type                 = SYNC;
	assign c2n_message_out[1].data                         = service_message_data_t'(c2n_sync_message_wrapped);

`ifdef DIRECTORY_BARRIER
	localparam DISTR_SYNC = 1;
`else
	localparam DISTR_SYNC = 0;
`endif

	// CI - LDST
	instruction_decoded_t                             ldst_instruction;
	dcache_address_t                                  ldst_address;
	logic                                             ldst_miss;
	logic                                             ldst_evict;
	dcache_line_t                                     ldst_cache_line;
	logic                                             ldst_flush;
	logic                                             ldst_dinv;
	dcache_store_mask_t                               ldst_dirty_mask;
	logic                                             ci_flush_fifo_available;

`ifdef COHERENCE_INJECTION

	instruction_decoded_t                             ldst_instruction_inject;
	dcache_address_t                                  ldst_address_inject;
	logic                                             ldst_miss_inject;
	logic                                             ldst_evict_inject;
	dcache_line_t                                     ldst_cache_line_inject;
	logic                                             ldst_flush_inject;
	logic                                             ldst_dinv_inject;
	dcache_store_mask_t                               ldst_dirty_mask_inject;

`endif

	// CC - LDST
	logic                                             cc_update_ldst_valid;
	dcache_way_idx_t                                  cc_update_ldst_way;
	dcache_address_t                                  cc_update_ldst_address;
	dcache_privileges_t                               cc_update_ldst_privileges;
	dcache_line_t                                     cc_update_ldst_store_value;
	cc_command_t                                      cc_update_ldst_command;

	logic                                             cc_snoop_data_valid;
	dcache_set_t                                      cc_snoop_data_set;
	dcache_way_idx_t                                  cc_snoop_data_way;
	dcache_line_t                                     ldst_snoop_data;

	logic                                             cc_wakeup;
	thread_id_t                                       cc_wakeup_thread_id;

	logic                                             cc_snoop_tag_valid;
	dcache_set_t                                      cc_snoop_tag_set;

	dcache_privileges_t   [`DCACHE_WAY - 1 : 0]       ldst_snoop_privileges;
	dcache_tag_t          [`DCACHE_WAY - 1 : 0]       ldst_snoop_tag;

	dcache_set_t                                      ldst_lru_update_set;
	logic                                             ldst_lru_update_en;
	dcache_way_idx_t                                  ldst_lru_update_way;

	// CC - TC
	icache_lane_t                                     mem_instr_request_data_in;
	logic                                             mem_instr_request_valid;

	npu_core # (
		.TILE_ID        ( TILE_ID     ),
		.CORE_ID        ( CORE_ID     ),
		.MANYCORE       ( 1           ),
		.FPU            ( FPU         ),
		.SCRATCHPAD     ( SCRATCHPAD  ),
		.DSU            ( 0           ),
		.DIS_SYNCMASTER ( DISTR_SYNC  ) 
    )
	u_npu_core (
		.clk                             ( clk                                 ),
		.reset                           ( reset                               ),
		.thread_en                       ( hi_thread_en                        ),
		// Host Interface
		.hi_job_valid                    ( hi_job_valid                        ),
		.hi_job_pc                       ( hi_job_pc                           ),
		.hi_job_thread_id                ( hi_job_thread_id                    ),
		.hi_write_cr_data                (                                     ),
		.hi_write_cr_valid               ( 1'b0                                ),
		.hi_read_cr_request              (                                     ),
		.hi_read_cr_valid                ( 1'b0                                ),
		.cr_response                     (                                     ),
		// DSU
		.resume                          (                                     ),
		.ext_freeze                      (                                     ),
		.dsu_enable                      (                                     ),
		.dsu_single_step                 (                                     ),
		.dsu_breakpoint                  (                                     ),
		.dsu_breakpoint_enable           (                                     ),
		.dsu_thread_selection            (                                     ),
		.dsu_thread_id                   (                                     ),
		.dsu_en_vector                   (                                     ),
		.dsu_en_scalar                   (                                     ),
		.dsu_load_shift_reg              (                                     ),
		.dsu_start_shift                 (                                     ),
		.dsu_reg_addr                    (                                     ),
		.dsu_write_scalar                (                                     ),
		.dsu_write_vector                (                                     ),
		.dsu_serial_reg_in               (                                     ),
		//To Host Debug
		.dsu_bp_instruction              (                                     ),
		.dsu_bp_thread_id                (                                     ),
		.dsu_serial_reg_out              (                                     ),
		.dsu_stop_shift                  (                                     ),
		.dsu_hit_breakpoint              (                                     ),
		//Memory interface
		.ldst_instruction                ( ldst_instruction                    ),
		.ldst_address                    ( ldst_address                        ),
		.ldst_miss                       ( ldst_miss                           ),
		.ldst_evict                      ( ldst_evict                          ),
		.ldst_cache_line                 ( ldst_cache_line                     ),
		.ldst_flush                      ( ldst_flush                          ),
		.ldst_dinv                       ( ldst_dinv                           ),
		.ldst_dirty_mask                 ( ldst_dirty_mask                     ),

		.cc_update_ldst_valid            ( cc_update_ldst_valid                ),
		.cc_update_ldst_way              ( cc_update_ldst_way                  ),
		.cc_update_ldst_address          ( cc_update_ldst_address              ),
		.cc_update_ldst_privileges       ( cc_update_ldst_privileges           ),
		.cc_update_ldst_store_value      ( cc_update_ldst_store_value          ),
		.cc_update_ldst_command          ( cc_update_ldst_command              ),
		.ci_flush_fifo_available         ( ci_flush_fifo_available             ),

		.cc_snoop_data_valid             ( cc_snoop_data_valid                 ),
		.cc_snoop_data_set               ( cc_snoop_data_set                   ),
		.cc_snoop_data_way               ( cc_snoop_data_way                   ),
		.ldst_snoop_data                 ( ldst_snoop_data                     ),

		.ldst_lru_update_set             ( ldst_lru_update_set                 ),
		.ldst_lru_update_en              ( ldst_lru_update_en                  ),
		.ldst_lru_update_way             ( ldst_lru_update_way                 ),

		.cc_wakeup                       ( cc_wakeup                           ),
		.cc_wakeup_thread_id             ( cc_wakeup_thread_id                 ),

		.cc_snoop_tag_valid              ( cc_snoop_tag_valid                  ),
		.cc_snoop_tag_set                ( cc_snoop_tag_set                    ),

		.ldst_snoop_privileges           ( ldst_snoop_privileges               ),
		.ldst_snoop_tag                  ( ldst_snoop_tag                      ),

		.io_intf_available               ( io_intf_available_to_core           ),
		.ldst_io_valid                   ( ldst_io_valid                       ),
		.ldst_io_thread                  ( ldst_io_thread                      ),
		.ldst_io_operation               ( ldst_io_operation                   ),
		.ldst_io_address                 ( ldst_io_address                     ),
		.ldst_io_data                    ( ldst_io_data                        ),
		.io_intf_resp_valid              ( io_intf_resp_valid                  ),
		.io_intf_wakeup_thread           ( io_intf_wakeup_thread               ),
		.io_intf_resp_data               ( io_intf_resp_data                   ),
		.ldst_io_resp_consumed           ( ldst_io_resp_consumed               ),

		.mem_instr_request_available     ( mem_instr_request_available         ),
		.tc_instr_request_valid          ( tc_instr_request_valid              ),
		.tc_instr_request_address        ( tc_instr_request_address            ),
		.mem_instr_request_data_in       ( mem_instr_request_data_in           ),
		.mem_instr_request_valid         ( mem_instr_request_valid             ),

		// Service network interface
		.bc2n_account_valid              ( c2n_message_out_valid[1]            ),
		.bc2n_account_message            ( c2n_account_message                 ),
		.bc2n_account_destination_valid  ( c2n_destination_valid[1]            ),
		.n2bc_network_available          ( c2n_network_available[1]            ),

		.n2bc_release_message            ( n2c_release_message                 ),
		.n2bc_release_valid              ( n2c_release_valid                   ),
		.n2bc_mes_service_consumed       ( n2c_mes_service_consumed            )
	);

	l1d_cache #(
		.TILE_ID( TILE_ID ),
		.CORE_ID( CORE_ID ) )
	u_l1d_cache (
		.clk                               ( clk                                       ),
		.reset                             ( reset                                     ),
		// Core
		.ldst_evict                        ( ldst_evict                                ),
`ifndef COHERENCE_INJECTION		
		.ldst_instruction                  ( ldst_instruction                          ),
		.ldst_address                      ( ldst_address                              ),
		.ldst_miss                         ( ldst_miss                                 ),
		
		.ldst_cache_line                   ( ldst_cache_line                           ),
		.ldst_flush                        ( ldst_flush                                ),
		.ldst_dinv                         ( ldst_dinv                                 ),
		.ldst_dirty_mask                   ( ldst_dirty_mask                           ),
`else
		.ldst_instruction                  ( ldst_instruction_inject                   ),
		.ldst_address                      ( (ldst_evict) ? ldst_address : ldst_address_inject ),
		.ldst_miss                         ( ldst_miss_inject                          ),
		.ldst_cache_line                   ( ldst_cache_line_inject                    ),
		.ldst_flush                        ( ldst_flush_inject                         ),
		.ldst_dinv                         ( ldst_dinv_inject                          ),
		.ldst_dirty_mask                   ( ldst_dirty_mask_inject                    ),
`endif

		.cc_update_ldst_valid              ( cc_update_ldst_valid                      ),
		.cc_update_ldst_way                ( cc_update_ldst_way                        ),
		.cc_update_ldst_address            ( cc_update_ldst_address                    ),
		.cc_update_ldst_privileges         ( cc_update_ldst_privileges                 ),
		.cc_update_ldst_store_value        ( cc_update_ldst_store_value                ),
		.cc_update_ldst_command            ( cc_update_ldst_command                    ),
		.ci_flush_fifo_available           ( ci_flush_fifo_available                   ),

		.cc_snoop_data_valid               ( cc_snoop_data_valid                       ),
		.cc_snoop_data_set                 ( cc_snoop_data_set                         ),
		.cc_snoop_data_way                 ( cc_snoop_data_way                         ),
		.ldst_snoop_data                   ( ldst_snoop_data                           ),

		.ldst_lru_update_set               ( ldst_lru_update_set                       ),
		.ldst_lru_update_en                ( ldst_lru_update_en                        ),
		.ldst_lru_update_way               ( ldst_lru_update_way                       ),

		.cc_wakeup                         ( cc_wakeup                                 ),
		.cc_wakeup_thread_id               ( cc_wakeup_thread_id                       ),

		.cc_snoop_tag_valid                ( cc_snoop_tag_valid                        ),
		.cc_snoop_tag_set                  ( cc_snoop_tag_set                          ),

		.ldst_snoop_privileges             ( ldst_snoop_privileges                     ),
		.ldst_snoop_tag                    ( ldst_snoop_tag                            ),

		//From Network Interface
		.ni_request_network_available      ( ni_request_network_available              ),
		.ni_forward_network_available      ( ni_forwarded_request_cc_network_available ),
		.ni_response_network_available     ( ni_response_to_cc_network_available       ),
		.ni_forwarded_request              ( ni_forwarded_request                      ),
		.ni_forwarded_request_valid        ( ni_forwarded_request_valid                ),
		.ni_response                       ( ni_response_to_cc                         ),
		.ni_response_valid                 ( ni_response_to_cc_valid                   ),
		//To Network Interface
		.l1d_forwarded_request_consumed    ( l1d_forwarded_request_consumed            ),
		.l1d_response_consumed             ( l1d_response_consumed                     ),
		.l1d_request_valid                 ( l1d_request_valid                         ),
		.l1d_request                       ( l1d_request                               ),
		.l1d_request_has_data              ( l1d_request_has_data                      ),
		.l1d_request_destinations          ( l1d_request_destinations                  ),
		.l1d_request_destinations_valid    ( l1d_request_destinations_valid            ),
		.l1d_response_valid                ( l1d_response_valid                        ),
		.l1d_response                      ( l1d_response                              ),
		.l1d_response_has_data             ( l1d_response_has_data                     ),
		.l1d_response_destinations         ( l1d_response_destinations                 ),
		.l1d_response_destinations_valid   ( l1d_response_destinations_valid           ),
		.l1d_forwarded_request_valid       ( l1d_forwarded_request_valid               ),
		.l1d_forwarded_request             ( l1d_forwarded_request                     ),
		.l1d_forwarded_request_destination ( l1d_forwarded_request_destination         ),

		.mem_instr_request_data_in         ( mem_instr_request_data_in                 ),
		.mem_instr_request_valid           ( mem_instr_request_valid                   )
	);
	

//  -----------------------------------------------------------------------
//  -- Tile - Network Interface
//  -----------------------------------------------------------------------
	// The local router port is directly connected to the Network Interface. The local port is not
	// propagated to the Tile output

	assign router_credit[VC0]           = on_off_out [LOCAL ][VC0];
	assign router_credit[VC1]           = on_off_out [LOCAL ][VC1];
	assign router_credit[VC2]           = on_off_out [LOCAL ][VC2];
	assign router_credit[VC3]           = on_off_out [LOCAL ][VC3];

	assign on_off_in[LOCAL ] [VC0]      = ni_credit[VC0];
	assign on_off_in[LOCAL ] [VC1]      = ni_credit[VC1];
	assign on_off_in[LOCAL ] [VC2]      = ni_credit[VC2];
	assign on_off_in[LOCAL ] [VC3]      = ni_credit[VC3];

	network_interface_core #(
		.X_ADDR( X_ADDR ),
		.Y_ADDR( Y_ADDR )
	)
	u_network_interface_core (
		.clk                                       ( clk                                       ),
		.reset                                     ( reset                                     ),
		.enable                                    ( enable                                    ),
		//CACHE CONTROLLER INTERFACE
		//Request
		.l1d_request                               ( l1d_request                               ),
		.l1d_request_valid                         ( l1d_request_valid                         ),
		.l1d_request_has_data                      ( l1d_request_has_data                      ),
		.l1d_request_destinations                  ( l1d_request_destinations                  ),
		.l1d_request_destinations_valid            ( l1d_request_destinations_valid            ),
		.ni_request_network_available              ( ni_request_network_available              ),
		//Forwarded Request
		.ni_forwarded_request                      ( ni_forwarded_request                      ),
		.ni_forwarded_request_valid                ( ni_forwarded_request_valid                ),
		.l1d_forwarded_request_consumed            ( l1d_forwarded_request_consumed            ),
		.ni_forwarded_request_cc_network_available ( ni_forwarded_request_cc_network_available ),
		//Response Inject
		.l1d_response                              ( l1d_response                              ),
		.l1d_response_valid                        ( l1d_response_valid                        ),
		.l1d_response_has_data                     ( l1d_response_has_data                     ),
		.l1d_response_to_cc_valid                  ( l1d_response_destinations_valid[CC_ID]    ),
		.l1d_response_to_cc                        ( l1d_response_destinations[CC_ID]          ),
		.l1d_response_to_dc_valid                  ( l1d_response_destinations_valid[DC_ID]    ),
		.l1d_response_to_dc                        ( l1d_response_destinations[DC_ID]          ),
		.ni_response_cc_network_available          ( ni_response_to_cc_network_available       ),
		//Forward Inject
		.l1d_forwarded_request_valid               ( l1d_forwarded_request_valid               ),
		.l1d_forwarded_request                     ( l1d_forwarded_request                     ),
		.l1d_forwarded_request_destination         ( l1d_forwarded_request_destination         ),
		//Response Eject
		.ni_response_to_cc_valid                   ( ni_response_to_cc_valid                   ),
		.ni_response_to_cc                         ( ni_response_to_cc                         ),
		.l1d_response_to_cc_consumed               ( l1d_response_consumed                     ),

		//DIRECTORY CONTROLLER
		//Forwarded Request
		.dc_forwarded_request                      ( dc_forwarded_request                      ),
		.dc_forwarded_request_valid                ( dc_forwarded_request_valid                ),
		.dc_forwarded_request_destinations_valid   ( dc_forwarded_request_destinations         ),
		.ni_forwarded_request_dc_network_available ( ni_forwarded_request_dc_network_available ),
		//Request
		.ni_request                                ( ni_request                                ),
		.ni_request_valid                          ( ni_request_valid                          ),
		.dc_request_consumed                       ( dc_request_consumed                       ),
		//Response Inject
		.dc_response                               ( dc_response                               ),
		.dc_response_valid                         ( dc_response_valid                         ),
		.dc_response_has_data                      ( dc_response_has_data                      ),
		.dc_response_destination                   ( dc_response_destination_idx               ),
		.ni_response_dc_network_available          ( ni_response_dc_network_available          ),
		//Response Eject
		.ni_response_to_dc_valid                   ( ni_response_to_dc_valid                   ),
		.ni_response_to_dc                         ( ni_response_to_dc                         ),
		.dc_response_to_dc_consumed                ( dc_response_to_dc_consumed                ),

		//VC SERVICE INTERFACE
		//Core to Net
		.c2n_mes_service                           ( c2n_mes_service                           ),
		.c2n_mes_service_valid                     ( c2n_mes_service_valid                     ),
		.c2n_mes_service_has_data                  ( c2n_mes_service_has_data                  ),
		.c2n_mes_service_destinations_valid        ( c2n_mes_service_destinations_valid        ),
		.ni_c2n_mes_service_network_available      ( ni_c2n_mes_service_network_available      ),
		//Net to Core
		.ni_n2c_mes_service                        ( ni_n2c_mes_service                        ),
		.ni_n2c_mes_service_valid                  ( ni_n2c_mes_service_valid                  ),
		.c2n_mes_service_consumed                  ( c2n_mes_service_consumed                  ),

		//ROUTER INTERFACE
		// flit in/out
		.ni_flit_out                               ( flit_in [LOCAL]                           ),
		.ni_flit_out_valid                         ( wr_en_in [LOCAL ]                         ),
		.router_flit_in                            ( flit_out [LOCAL ]                         ),
		.router_flit_in_valid                      ( wr_en_out [LOCAL ]                        ),
		// on-off backpressure
		.router_credit                             ( router_credit                             ),
		.ni_credit                                 ( ni_credit                                 )
	);

	generate
		if ( $bits( service_message_t ) > ( `PAYLOAD_W ) )
			assign c2n_mes_service_has_data = 1'b1;
		else
			assign c2n_mes_service_has_data = 1'b0;
	endgenerate

//  -----------------------------------------------------------------------
//  -- Tile - Directory Controller
//  -----------------------------------------------------------------------

	directory_controller #(
		.TILE_ID       ( TILE_ID        ),
		.TILE_MEMORY_ID( TILE_MEMORY_ID )
	)
	u_directory_controller (
		.clk                                   ( clk                                    ),
		.reset                                 ( reset                                  ),
		//From Thread Controller
		.tc_instr_request_valid                ( tc_instr_request_valid                 ),
		.tc_instr_request_address              ( tc_instr_request_address               ),
		//To Thread Controller
		.mem_instr_request_available           ( mem_instr_request_available            ),
		//From Network Interface
		.ni_response_network_available         ( ni_response_dc_network_available       ),
		.ni_forwarded_request_network_available( ni_forwarded_request_dc_network_available ),
		.ni_request_valid                      ( ni_request_valid                       ),
		.ni_request                            ( ni_request                             ),
		.ni_response_valid                     ( ni_response_to_dc_valid                ),
		.ni_response                           ( ni_response_to_dc                      ),
		//To Network Interface
		.dc_request_consumed                   ( dc_request_consumed                    ),
		.dc_response_consumed                  ( dc_response_to_dc_consumed             ),
		.dc_forwarded_request                  ( dc_forwarded_request                   ),
		.dc_forwarded_request_valid            ( dc_forwarded_request_valid             ),
		.dc_forwarded_request_destinations     ( dc_forwarded_request_destinations      ),
		.dc_response                           ( dc_response                            ),
		.dc_response_valid                     ( dc_response_valid                      ),
		.dc_response_has_data                  ( dc_response_has_data                   ),
		.dc_response_destinations              ( dc_response_destinations               )
	);

	oh_to_idx #(
		.NUM_SIGNALS( `TILE_COUNT             ),
		.DIRECTION  ( "LSB0"                  ),
		.INDEX_WIDTH( $bits( tile_address_t ) )
	)
	dc_destination_oh_to_idx (
		.one_hot( dc_response_destinations    ),
		.index  ( dc_response_destination_idx )
	);

//  -----------------------------------------------------------------------
//  -- Tile - Boot Manager
//  -----------------------------------------------------------------------

	boot_manager #(
		.TILE_ID( TILE_ID )
	)
	u_boot_manager (
		.clk                      ( clk                         ),
		.reset                    ( reset                       ),
		// to net
		.network_available        ( c2n_network_available[0]    ),
		.message_out              ( c2n_message_out[0]          ),
		.message_out_valid        ( c2n_message_out_valid[0]    ),
		.destination_valid        ( c2n_destination_valid[0]    ),
		// from net
		.n2c_mes_service_consumed ( bm_c2n_mes_service_consumed ),
		.message_in               ( bm_n2c_mes_service          ),
		.message_in_valid         ( bm_n2c_mes_service_valid    ),
		// to nu+ core
		.hi_thread_en             ( hi_thread_en                ),
		.hi_job_valid             ( hi_job_valid                ),
		.hi_job_pc                ( hi_job_pc                   ),
		.hi_job_thread_id         ( hi_job_thread_id            )
	);

//  -----------------------------------------------------------------------
//  -- Tile - IO Interface
//  -----------------------------------------------------------------------
	io_message_t io_intf_message_out;

	assign c2n_message_out[3].message_type                  = IO_OP;
	assign c2n_message_out[3].data                          = service_message_data_t'(io_intf_message_out);

	io_interface #(
		.TILE_ID ( TILE_ID )
	) u_io_intf (
		.clk                        ( clk                       ),
		.reset                      ( reset                     ),

		.io_intf_available_to_core  ( io_intf_available_to_core ),
		.ldst_io_valid              ( ldst_io_valid             ),
		.ldst_io_thread             ( ldst_io_thread            ),
		.ldst_io_operation          ( ldst_io_operation         ),
		.ldst_io_address            ( ldst_io_address           ),
		.ldst_io_data               ( ldst_io_data              ),
		.io_intf_resp_valid         ( io_intf_resp_valid        ),
		.io_intf_wakeup_thread      ( io_intf_wakeup_thread     ),
		.io_intf_resp_data          ( io_intf_resp_data         ),
		.ldst_io_resp_consumed      ( ldst_io_resp_consumed     ),

		.slave_available_to_io_intf ( ),
		.io_intf_valid              ( ),
		.io_intf_thread             ( ),
		.io_intf_operation          ( ),
		.io_intf_address            ( ),
		.io_intf_data               ( ),
		.slave_resp_valid           ( ),
		.slave_wakeup_thread        ( ),
		.slave_resp_data            ( ),
		.io_intf_resp_consumed      ( ),

		.ni_io_network_available    ( c2n_network_available[3]  ),
		.io_intf_message_out        ( io_intf_message_out       ),
		.io_intf_message_out_valid  ( c2n_message_out_valid[3]  ),
		.io_intf_destination_valid  ( c2n_destination_valid[3]  ),

		.io_intf_message_consumed   ( io_intf_message_consumed  ),
		.ni_io_message              ( ni_io_message             ),
		.ni_io_message_valid        ( ni_io_message_valid       )
	);

//  -----------------------------------------------------------------------
//  -- Tile -  Message service scheduler
//  -----------------------------------------------------------------------
	c2n_service_scheduler #(
		.NUM_FIFO  ( NUM_FIFO   ), 
		.INDEX_FIFO( INDEX_FIFO )
	)
	u_c2n_service_scheduler (
		.clk                  ( clk                                  ),
		.reset                ( reset                                ),
		//From Tile
		.c2n_destination_valid( c2n_destination_valid                ),
		.c2n_message_out      ( c2n_message_out                      ),
		.c2n_message_out_valid( c2n_message_out_valid                ),
		.c2n_network_available( c2n_network_available                ),
		//To Virtual Network
		.destination_valid    ( c2n_mes_service_destinations_valid   ),
		.message_out          ( c2n_mes_service                      ),
		.message_out_valid    ( c2n_mes_service_valid                ),
		.network_available    ( ni_c2n_mes_service_network_available )
	);

//  -----------------------------------------------------------------------
//  -- Tile - Arbiter Service Message
//  -----------------------------------------------------------------------

	sync_message_t n2c_sync_message;

	assign n2c_sync_message = sync_message_t'(ni_n2c_mes_service.data);
	assign ni_io_message = io_message_t'(ni_n2c_mes_service.data);

	always @( ni_n2c_mes_service_valid, ni_n2c_mes_service, n2c_sync_message, bm_c2n_mes_service_consumed, sc_account_consumed, n2c_mes_service_consumed, io_intf_message_consumed ) begin
		bm_n2c_mes_service_valid = 0;
		ni_account_mess_valid    = 0;
		n2c_release_valid        = 0;
		c2n_mes_service_consumed = 0;
		bm_n2c_mes_service       = 0;
		ni_account_mess          = 0;
		n2c_release_message      = 0;
		ni_io_message_valid      = 1'b0;

		if (ni_n2c_mes_service_valid) begin
			if( ni_n2c_mes_service.message_type == HOST ) begin
				bm_n2c_mes_service.data  = ni_n2c_mes_service.data;
				bm_n2c_mes_service_valid = ni_n2c_mes_service_valid;
				c2n_mes_service_consumed = bm_c2n_mes_service_consumed;
			end else if ( ni_n2c_mes_service.message_type == SYNC ) begin
				if ( n2c_sync_message.sync_type == ACCOUNT ) begin
					ni_account_mess          = n2c_sync_message.sync_mess.account_mess;
					ni_account_mess_valid    = ni_n2c_mes_service_valid;
					c2n_mes_service_consumed = sc_account_consumed;
				end else if ( n2c_sync_message.sync_type == RELEASE ) begin
					n2c_release_message      = n2c_sync_message.sync_mess.release_mess;
					n2c_release_valid        = ni_n2c_mes_service_valid;
					c2n_mes_service_consumed = n2c_mes_service_consumed;
				end
			end else if ( ni_n2c_mes_service.message_type == IO_OP ) begin
				ni_io_message_valid        = ni_n2c_mes_service_valid;
				c2n_mes_service_consumed   = io_intf_message_consumed;
			end
		end else begin
			c2n_mes_service_consumed = 1'b0;
		end
	end

//  -----------------------------------------------------------------------
//  -- Tile - Synchronization Core
//  -----------------------------------------------------------------------
	sync_message_t         sc2n_sync_message_wrapped;
	sync_release_message_t sc2n_release_mess;
	tile_mask_t            sc2n_release_dest_valid;

	assign sc2n_sync_message_wrapped.sync_type              = RELEASE;
	assign sc2n_sync_message_wrapped.sync_mess.release_mess = sc2n_release_mess;

`ifndef DIRECTORY_BARRIER
	generate
	if ( TILE_ID == `CENTRAL_SYNCH_ID ) begin
`endif

		assign c2n_message_out[2].message_type                  = SYNC;
		assign c2n_message_out[2].data                          = service_message_data_t'(sc2n_sync_message_wrapped);

		assign c2n_destination_valid[2]                         = sc2n_release_dest_valid;

		synchronization_core #(
			.TILE_ID( TILE_ID ) )
		u_synchronization_core (
			.clk                    ( clk                      ),
			.reset                  ( reset                    ),
			//NETWORK INTERFACE
			//Account
			.ni_account_mess        ( ni_account_mess          ),
			.ni_account_mess_valid  ( ni_account_mess_valid    ),
			.sc_account_consumed    ( sc_account_consumed      ),
			.account_available      (                          ),
			//Release
			.sc_release_mess        ( sc2n_release_mess        ),
			.sc_release_dest_valid  ( sc2n_release_dest_valid  ),
			.sc_release_valid       ( c2n_message_out_valid[2] ),
			.ni_available           ( c2n_network_available[2] )
		);

`ifndef DIRECTORY_BARRIER
		end else begin

			assign c2n_destination_valid[2] = 0;
			assign c2n_message_out[2]       = 0;
			assign c2n_message_out_valid[2] = 0;
		end
	endgenerate
`endif

//  -----------------------------------------------------------------------
//  -- Tile - Router
//  -----------------------------------------------------------------------
	// All router port are directly connected to the tile output. Instead, the local port
	// is connected to the Network Interface.
	assign tile_flit_out_valid          = wr_en_out [`PORT_NUM - 1 : 1];
	assign tile_flit_out                = flit_out[`PORT_NUM - 1 : 1 ];
	assign tile_on_off_out              = on_off_out[`PORT_NUM - 1 : 1];
	assign flit_in[`PORT_NUM - 1 : 1 ]  = tile_flit_in;
	assign wr_en_in[`PORT_NUM - 1 : 1 ] = tile_wr_en_in;
	assign on_off_in[`PORT_NUM - 1 : 1] = tile_on_off_in;

	router # (
		.MY_X_ADDR ( X_ADDR ),
		.MY_Y_ADDR ( Y_ADDR )
	)
	u_router (
		.wr_en_in   ( wr_en_in   ),
		.flit_in    ( flit_in    ),
		.on_off_in  ( on_off_in  ),
		.wr_en_out  ( wr_en_out  ),
		.flit_out   ( flit_out   ),
		.on_off_out ( on_off_out ),
		.clk        ( clk        ),
		.reset      ( reset      )
	);

`ifdef SIMULATION

	always_ff @( posedge clk )
		if ( !reset & dc_response_valid )
			assert( $onehot( dc_response_destinations ) ) else $fatal( 0, "Non OH!" );

`endif

`ifdef COHERENCE_INJECTION
	initial
	begin
		$info( "[NU_TILE #%2d] Using COHERENCE_INJECTION: Nu+ core is physically *disconnected* from the l1d_cache module!", TILE_ID );
	end
`endif

endmodule
