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
`include "npu_system_defines.sv"
`include "npu_coherence_defines.sv"
`include "npu_message_service_defines.sv"
`include "npu_synchronization_defines.sv"
`include "npu_debug_log.sv"

// Single-cored version of the NPU system.

module npu_system #(
		parameter ADDRESS_WIDTH = 32,
		parameter DATA_WIDTH    = 512,
		parameter ITEM_w        = 32 )
	(
		input                                clk,
		input                                reset,
		output logic [`THREAD_NUMB - 1 : 0]  hi_thread_en,

		// From Memory
		input  logic                         mem2nup_request_available,
		input  logic                         mem2nup_response_valid,
		input  logic [ADDRESS_WIDTH - 1 : 0] mem2nup_response_address,
		input  logic [DATA_WIDTH - 1 : 0]    mem2nup_response_data,

		// To Memory
		output logic [ADDRESS_WIDTH - 1 : 0] nup2mem_request_address,
		output logic [63 : 0]                nup2mem_request_dirty_mask,
		output logic [DATA_WIDTH - 1 : 0]    nup2mem_request_data,
		output logic                         nup2mem_request_read,
		output logic                         nup2mem_request_write,
		output logic                         nup_available,

		// Item Interface
		input        [ITEM_w - 1 : 0]        item_data_i,               // Input: items from outside
		input                                item_valid_i,              // Input: valid signal associated with item_data_i port
		output logic                         item_avail_o,              // Output: avail signal to input port item_data_i
		output logic [ITEM_w - 1 : 0]        item_data_o,               // Output: items to outside
		output logic                         item_valid_o,              // Output: valid signal associated with item_data_o port
		input                                item_avail_i
	);

    localparam NUM_MASTER = `BUS_MASTER;
    localparam NUM_SLAVE  = 2;

	// Bus signals
	address_t             [NUM_MASTER - 1 : 0]        m_n2m_request_address;
	dcache_line_t         [NUM_MASTER - 1 : 0]        m_n2m_request_data;
	dcache_store_mask_t   [NUM_MASTER - 1 : 0]        m_n2m_request_dirty_mask;
	logic                 [NUM_MASTER - 1 : 0]        m_n2m_request_read;
	logic                 [NUM_MASTER - 1 : 0]        m_n2m_request_write;
	logic                 [NUM_MASTER - 1 : 0]        m_mc_avail_o;

	logic                 [NUM_MASTER - 1 : 0]        m_m2n_request_available;
	logic                 [NUM_MASTER - 1 : 0]        m_m2n_response_valid;
	address_t             [NUM_MASTER - 1 : 0]        m_m2n_response_address;
	dcache_line_t         [NUM_MASTER - 1 : 0]        m_m2n_response_data;

	// Core interface memory controller
	address_t                                         n2m_request_address;
	dcache_line_t                                     n2m_request_data;
	logic                 [NUM_SLAVE - 1 : 0]         n2m_request_read;
	logic                 [NUM_SLAVE - 1 : 0]         n2m_request_write;
	logic                                             mc_avail_o;

	logic                 [NUM_SLAVE - 1 : 0]         m2n_request_available;
	logic                 [NUM_SLAVE - 1 : 0]         m2n_response_valid;
	address_t             [NUM_SLAVE - 1 : 0]         m2n_response_address;
	dcache_line_t         [NUM_SLAVE - 1 : 0]         m2n_response_data;

	// Interface To NaplesPU
	logic                                             hi_job_valid;
	address_t                                         hi_job_pc;
	thread_id_t                                       hi_job_thread_id;
	logic                                             hi_read_cr_valid;
	register_t                                        hi_read_cr_request;
	logic                                             hi_write_cr_valid;
	register_t                                        hi_write_cr_data;
	register_t                                        cr_response;
	logic                                             ext_freeze;
	logic                                             resume;
	logic                                             dsu_enable;
	logic                                             dsu_single_step;
	address_t             [7 : 0]                     dsu_breakpoint;
	logic                 [7 : 0]                     dsu_breakpoint_enable;
	logic                                             dsu_thread_selection;
	thread_id_t                                       dsu_thread_id;
	logic                                             dsu_en_vector;
	logic                                             dsu_en_scalar;
	logic                                             dsu_load_shift_reg;
	logic                                             dsu_start_shift;
	logic                 [`REGISTER_ADDRESS - 1 : 0] dsu_reg_addr;
	logic                                             dsu_write_scalar;
	logic                                             dsu_write_vector;
	logic                                             dsu_serial_reg_in;
	address_t             [`THREAD_NUMB - 1 : 0]      dsu_bp_instruction;
	thread_id_t                                       dsu_bp_thread_id;
	logic                                             dsu_serial_reg_out;
	logic                                             dsu_stop_shift;
	logic                                             dsu_hit_breakpoint;
	logic                                             c2n_account_valid;
	sync_account_message_t                            c2n_account_message;
	logic                                             network_available;

	// From Network Interface
	sync_release_message_t                            n2c_release_message;
	logic                                             n2c_release_valid;
	logic                                             account_available;

	// Core Logger
	logic                                             nii_snoop_valid_o;
	log_snoop_req_t                                   nii_snoop_request_o;
	logic                 [`ADDRESS_SIZE - 1 : 0]     nii_snoop_addr_o;
	logic                                             cl_valid_o;
	logic                 [`CACHE_LINE_WIDTH - 1 : 0] cl_req_data_o;
	logic                 [`ADDRESS_SIZE - 1 : 0]     cl_req_addr_o;
	logic                 [`ADDRESS_SIZE - 1 : 0]     cl_req_id_o;
	logic                                             cl_req_is_write_o;
	logic                                             cl_req_is_read_o;

	// CC - LDST
	instruction_decoded_t                             ldst_instruction;
	dcache_address_t                                  ldst_address;
	logic                                             ldst_miss;
	logic                                             ldst_evict;
	dcache_line_t                                     ldst_cache_line;
	logic                                             ldst_flush;
	logic                                             ldst_dinv;
	dcache_store_mask_t                               ldst_dirty_mask;

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

	logic                                             io_intf_available;
	logic                                             ldst_io_valid;
	thread_id_t                                       ldst_io_thread;
	logic [$bits(io_operation_t)-1 : 0]               ldst_io_operation;
	address_t                                         ldst_io_address;
	register_t                                        ldst_io_data;
	logic                                             io_intf_resp_valid;
	thread_id_t                                       io_intf_wakeup_thread;
	register_t                                        io_intf_resp_data;
	logic                                             ldst_io_resp_consumed;

	logic                                             mem_instr_request_available;
	logic                                             tc_instr_request_valid;
	address_t                                         tc_instr_request_address;
	icache_lane_t                                     mem_instr_request_data_in;
	logic                                             mem_instr_request_valid;

	// CI - CC
	logic                                             cc_dequeue_store_request;
	logic                                             cc_dequeue_load_request;
	logic                                             cc_dequeue_replacement_request;
	logic                                             cc_dequeue_flush_request;
	logic                                             cc_dequeue_dinv_request;

	logic                                             ci_store_request_valid;
	thread_id_t                                       ci_store_request_thread_id;
	dcache_address_t                                  ci_store_request_address;
	logic                                             ci_store_request_coherent;
	logic                                             ci_load_request_valid;
	thread_id_t                                       ci_load_request_thread_id;
	dcache_address_t                                  ci_load_request_address;
	logic                                             ci_load_request_coherent;
	logic                                             ci_replacement_request_valid;
	thread_id_t                                       ci_replacement_request_thread_id;
	dcache_address_t                                  ci_replacement_request_address;
	dcache_line_t                                     ci_replacement_request_cache_line;
	dcache_store_mask_t                               ci_replacement_request_dirty_mask;
	logic                                             ci_flush_request_valid;
	dcache_address_t                                  ci_flush_request_address;
	dcache_line_t                                     ci_flush_request_cache_line;
	logic                                             ci_flush_request_coherent;
	dcache_store_mask_t                               ci_flush_request_dirty_mask;
	logic                                             ci_flush_fifo_available;
	logic                                             ci_dinv_request_valid;
	dcache_address_t                                  ci_dinv_request_address;
	thread_id_t                                       ci_dinv_request_thread_id;
	dcache_line_t                                     ci_dinv_request_cache_line;
	logic                                             ci_dinv_request_coherent;
	dcache_store_mask_t                               ci_dinv_request_dirty_mask;

	assign network_available     = 1'b1;
	assign ni_account_mess_valid = c2n_account_valid;

//  -----------------------------------------------------------------------
//  -- UART Controller and Host Interface Unit
//  -----------------------------------------------------------------------

	npu_item_interface u_npu_item_interface (
		.clk                   ( clk                   ),
		.reset                 ( reset                 ),

		//Interface To NaplesPU for boot
		.hi_thread_en          ( hi_thread_en          ),
		.hi_job_valid          ( hi_job_valid          ),
		.hi_job_pc             ( hi_job_pc             ),
		.hi_job_thread_id      ( hi_job_thread_id      ),
		.hi_read_cr_valid      ( hi_read_cr_valid      ),
		.hi_write_cr_valid     ( hi_write_cr_valid     ),
		.hi_read_cr_request    ( hi_read_cr_request    ),
		.hi_write_cr_data      ( hi_write_cr_data      ),
		.cr_response           ( cr_response           ),

		// From LDST unit - IO Map interface
		.io_intf_available     ( io_intf_available     ),
		.ldst_io_valid         ( ldst_io_valid         ),
		.ldst_io_thread        ( ldst_io_thread        ),
		.ldst_io_operation     ( ldst_io_operation     ),
		.ldst_io_address       ( ldst_io_address       ),
		.ldst_io_data          ( ldst_io_data          ),
		.io_intf_resp_valid    ( io_intf_resp_valid    ),
		.io_intf_wakeup_thread ( io_intf_wakeup_thread ),
		.io_intf_resp_data     ( io_intf_resp_data     ),
		.ldst_io_resp_consumed ( ldst_io_resp_consumed ),

		// Not used in single core
		.c2n_mes_service                   (      ),
		.c2n_mes_valid                     (      ),
		.n2c_mes_service                   (      ),
		.n2c_mes_valid                     ( 1'b0 ),
		.n2c_mes_service_consumed          (      ),
		.ni_network_available              ( 1'b1 ),
		.c2n_mes_service_destinations_valid(      ),

		//Interface to external items
		.item_data_i           ( item_data_i           ),
		.item_valid_i          ( item_valid_i          ),
		.item_avail_o          ( item_avail_o          ),
		.item_data_o           ( item_data_o           ),
		.item_valid_o          ( item_valid_o          ),
		.item_avail_i          ( item_avail_i          )
	);

//  -----------------------------------------------------------------------
//  -- Core Logger
//  -----------------------------------------------------------------------

    // Output signals not connected, used only in simulation.
	npu_core_logger #(
		.DATA_WIDTH( `CACHE_LINE_WIDTH ),
		.ADDR_WIDTH( `ADDRESS_SIZE     )
	)
	u_npu_core_logger (
		.clk              ( clk                       ),
		.reset            ( reset                     ),
		.enable           ( 1'b1                      ),
		// From the Memory
		.mc_valid_i       ( m_m2n_response_valid[1]   ),
		.mc_address_i     ( m_m2n_response_address[1] ),
		.mc_block_i       ( m_m2n_response_data[1]    ),
		// From the Core
		.core_write_i     ( m_n2m_request_write[1]    ),
		.core_read_i      ( m_n2m_request_read[1]     ),
		.core_address_i   ( m_n2m_request_address[1]  ),
		.core_block_i     ( m_n2m_request_data[1]     ),
		// Snoop Request
		.snoop_valid_i    ( nii_snoop_valid_o         ),
		.snoop_request_i  ( nii_snoop_request_o       ),
		.snoop_addr_i     ( nii_snoop_addr_o          ),
		// Log Output
		.cl_valid_o       ( cl_valid_o                ),
		.cl_req_data_o    ( cl_req_data_o             ),
		.cl_req_id_o      ( cl_req_id_o               ),
		.cl_req_is_write_o( cl_req_is_write_o         ),
		.cl_req_is_read_o ( cl_req_is_read_o          ),
		.cl_req_addr_o    ( cl_req_addr_o             )
	);

//  -----------------------------------------------------------------------
//  -- NaplesPU Core
//  -----------------------------------------------------------------------

	npu_core # (
		.TILE_ID  ( 0 ),
		.CORE_ID  ( 0 ),
		.DSU      ( 0 ),
		.MANYCORE ( 0 )
	)
	npu_core (
		.clk                              ( clk                                 ) ,
		.reset                            ( reset                               ),
		.ext_freeze                       ( ext_freeze                          ),
		.resume                           ( resume                              ),
		.thread_en                        ( hi_thread_en                        ),
		// Host Interface
		.hi_read_cr_valid                 ( hi_read_cr_valid                    ),
		.hi_read_cr_request               ( hi_read_cr_request                  ),
		.hi_write_cr_valid                ( hi_write_cr_valid                   ),
		.hi_write_cr_data                 ( hi_write_cr_data                    ),
		.cr_response                      ( cr_response                         ),
		.hi_job_valid                     ( hi_job_valid                        ),
		.hi_job_pc                        ( hi_job_pc                           ),
		.hi_job_thread_id                 ( hi_job_thread_id                    ),
		// DSU Interface
		.dsu_enable                       ( dsu_enable                          ),
		.dsu_single_step                  ( dsu_single_step                     ),
		.dsu_breakpoint                   ( dsu_breakpoint                      ),
		.dsu_breakpoint_enable            ( dsu_breakpoint_enable               ),
		.dsu_thread_selection             ( dsu_thread_selection                ),
		.dsu_thread_id                    ( dsu_thread_id                       ),
		.dsu_en_vector                    ( dsu_en_vector                       ),
		.dsu_en_scalar                    ( dsu_en_scalar                       ),
		.dsu_load_shift_reg               ( dsu_load_shift_reg                  ),
		.dsu_start_shift                  ( dsu_start_shift                     ),
		.dsu_reg_addr                     ( dsu_reg_addr                        ),
		.dsu_write_scalar                 ( dsu_write_scalar                    ),
		.dsu_write_vector                 ( dsu_write_vector                    ),
		.dsu_serial_reg_in                ( dsu_serial_reg_in                   ),
		.dsu_bp_instruction               ( dsu_bp_instruction                  ),
		.dsu_bp_thread_id                 ( dsu_bp_thread_id                    ),
		.dsu_serial_reg_out               ( dsu_serial_reg_out                  ),
		.dsu_stop_shift                   ( dsu_stop_shift                      ),
		.dsu_hit_breakpoint               ( dsu_hit_breakpoint                  ),
		// Synch Interface
		.bc2n_account_valid               ( c2n_account_valid                   ),
		.bc2n_account_message             ( c2n_account_message                 ),
		.bc2n_account_destination_valid   (                                     ) ,
		.n2bc_network_available           ( account_available                   ),
		.n2bc_release_message             ( n2c_release_message                 ),
		.n2bc_release_valid               ( n2c_release_valid                   ),
		.n2bc_mes_service_consumed        (                                     ),
		// Memory Access Interface
		.ldst_instruction                 ( ldst_instruction                    ),
		.ldst_address                     ( ldst_address                        ),
		.ldst_miss                        ( ldst_miss                           ),
		.ldst_evict                       ( ldst_evict                          ),
		.ldst_flush                       ( ldst_flush                          ),
		.ldst_dinv                        ( ldst_dinv                           ),
		.ldst_dirty_mask                  ( ldst_dirty_mask                     ),
		.ldst_cache_line                  ( ldst_cache_line                     ),

		.cc_update_ldst_valid             ( cc_update_ldst_valid                ),
		.cc_update_ldst_way               ( cc_update_ldst_way                  ),
		.cc_update_ldst_address           ( cc_update_ldst_address              ),
		.cc_update_ldst_privileges        ( cc_update_ldst_privileges           ),
		.cc_update_ldst_store_value       ( cc_update_ldst_store_value          ),
		.cc_update_ldst_command           ( cc_update_ldst_command              ),
		.cc_wakeup                        ( cc_wakeup                           ),
		.cc_wakeup_thread_id              ( cc_wakeup_thread_id                 ),
		.cc_snoop_tag_valid               ( cc_snoop_tag_valid                  ),
		.cc_snoop_tag_set                 ( cc_snoop_tag_set                    ),
		.cc_snoop_data_valid              ( cc_snoop_data_valid                 ),
		.cc_snoop_data_set                ( cc_snoop_data_set                   ),
		.cc_snoop_data_way                ( cc_snoop_data_way                   ),
		.ldst_snoop_data                  ( ldst_snoop_data                     ),
		.ldst_snoop_privileges            ( ldst_snoop_privileges               ),
		.ldst_snoop_tag                   ( ldst_snoop_tag                      ),
		.ci_flush_fifo_available          ( ci_flush_fifo_available             ),
		.ldst_lru_update_set              (                                     ),
		.ldst_lru_update_en               (                                     ),
		.ldst_lru_update_way              (                                     ),
		// IO Map interface
		.io_intf_available                ( io_intf_available                   ),
		.ldst_io_valid                    ( ldst_io_valid                       ),
		.ldst_io_thread                   ( ldst_io_thread                      ),
		.ldst_io_operation                ( ldst_io_operation                   ),
		.ldst_io_address                  ( ldst_io_address                     ),
		.ldst_io_data                     ( ldst_io_data                        ),
		.io_intf_resp_valid               ( io_intf_resp_valid                  ),
		.io_intf_wakeup_thread            ( io_intf_wakeup_thread               ),
		.io_intf_resp_data                ( io_intf_resp_data                   ),
		.ldst_io_resp_consumed            ( ldst_io_resp_consumed               ),
		// Memory Interface - For Many-Core implementation
		.mem_instr_request_available      ( mem_instr_request_available         ),
		.tc_instr_request_valid           ( tc_instr_request_valid              ),
		.tc_instr_request_address         ( tc_instr_request_address            ),
		.mem_instr_request_data_in        ( mem_instr_request_data_in           ),
		.mem_instr_request_valid          ( mem_instr_request_valid             )
	);

//  -----------------------------------------------------------------------
//  -- Memory Access Interface
//  -----------------------------------------------------------------------

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
		.ci_flush_request_cache_line      ( ci_flush_request_cache_line       ),
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

	sc_cache_controller u_sc_cache_controller (
		.clk                        ( clk                            ),
		.reset                      ( reset                          ),

		// Load Store Unit
		.cc_dequeue_store_request ( cc_dequeue_store_request ),
		.cc_dequeue_load_request ( cc_dequeue_load_request ),
		.cc_dequeue_replacement_request ( cc_dequeue_replacement_request ),
		.cc_dequeue_flush_request ( cc_dequeue_flush_request ),
		.cc_dequeue_dinv_request ( cc_dequeue_dinv_request ),

		.ci_store_request_valid ( ci_store_request_valid ),
		.ci_store_request_thread_id ( ci_store_request_thread_id ),
		.ci_store_request_address ( ci_store_request_address ),
		.ci_store_request_coherent ( ci_store_request_coherent ),
		.ci_load_request_valid ( ci_load_request_valid ),
		.ci_load_request_thread_id ( ci_load_request_thread_id ),
		.ci_load_request_address ( ci_load_request_address ),
		.ci_load_request_coherent ( ci_load_request_coherent ),
		.ci_replacement_request_valid ( ci_replacement_request_valid ),
		.ci_replacement_request_thread_id ( ci_replacement_request_thread_id ),
		.ci_replacement_request_address ( ci_replacement_request_address ),
		.ci_replacement_request_cache_line ( ci_replacement_request_cache_line ),
		.ci_replacement_request_dirty_mask ( ci_replacement_request_dirty_mask ),
		.ci_flush_request_valid ( ci_flush_request_valid ),
		.ci_flush_request_address ( ci_flush_request_address ),
		.ci_flush_request_cache_line ( ci_flush_request_cache_line ),
		.ci_flush_request_coherent ( ci_flush_request_coherent ),
		.ci_flush_request_dirty_mask ( ci_flush_request_dirty_mask ),
		.ci_dinv_request_valid ( ci_dinv_request_valid ),
		.ci_dinv_request_address ( ci_dinv_request_address ),
		.ci_dinv_request_thread_id ( ci_dinv_request_thread_id ),
		.ci_dinv_request_cache_line ( ci_dinv_request_cache_line ),
		.ci_dinv_request_coherent ( ci_dinv_request_coherent ),
		.ci_dinv_request_dirty_mask ( ci_dinv_request_dirty_mask ),

		.cc_update_ldst_valid       ( cc_update_ldst_valid           ),
		.cc_update_ldst_way         ( cc_update_ldst_way             ),
		.cc_update_ldst_address     ( cc_update_ldst_address         ),
		.cc_update_ldst_privileges  ( cc_update_ldst_privileges      ),
		.cc_update_ldst_store_value ( cc_update_ldst_store_value     ),
		.cc_update_ldst_command     ( cc_update_ldst_command         ),
		.cc_wakeup                  ( cc_wakeup                      ),
		.cc_wakeup_thread_id        ( cc_wakeup_thread_id            ),
		.cc_snoop_tag_valid         ( cc_snoop_tag_valid             ),
		.cc_snoop_tag_set           ( cc_snoop_tag_set               ),
		.cc_snoop_data_valid        ( cc_snoop_data_valid            ),
		.cc_snoop_data_set          ( cc_snoop_data_set              ),
		.cc_snoop_data_way          ( cc_snoop_data_way              ),
		.ldst_snoop_data            ( ldst_snoop_data                ),
		.ldst_snoop_privileges      ( ldst_snoop_privileges          ),
		.ldst_snoop_tag             ( ldst_snoop_tag                 ),
		// To LDST unit - IO Map interface
		.io_intf_available          (                                ),
		// From LDST unit - IO Map interface
		.ldst_io_valid              ( 1'b0                           ),
		.ldst_io_thread             (                                ),
		.ldst_io_operation          (                                ),
		.ldst_io_address            (                                ),
		.ldst_io_data               (                                ),
		.io_intf_resp_valid         (                                ),
		.io_intf_wakeup_thread      (                                ),
		.io_intf_resp_data          (                                ),
		.ldst_io_resp_consumed      ( 1'b0                           ),
		// Memory controller
		.n2m_request_address        ( m_n2m_request_address[1]       ),
		.n2m_request_data           ( m_n2m_request_data[1]          ),
		.n2m_request_dirty_mask     ( m_n2m_request_dirty_mask[1]    ),
		.n2m_request_read           ( m_n2m_request_read[1]          ),
		.n2m_request_write          ( m_n2m_request_write[1]         ),
		.mc_avail_o                 ( m_mc_avail_o[1]                ),
		.m2n_request_available      ( m_m2n_request_available[1]     ),
		.m2n_response_valid         ( m_m2n_response_valid[1]        ),
		.m2n_response_address       ( m_m2n_response_address[1]      ),
		.m2n_response_data          ( m_m2n_response_data[1]         ),
		// Thread Controller - Instruction cache interface
		.mem_instr_request_available( mem_instr_request_available    ),
		.mem_instr_request_data_in  ( mem_instr_request_data_in      ),
		.mem_instr_request_valid    ( mem_instr_request_valid        ),
		.tc_instr_request_valid     ( tc_instr_request_valid         ),
		.tc_instr_request_address   ( tc_instr_request_address       )
	);

//  -----------------------------------------------------------------------
//  -- Bus and a Dummy IO Device
//  -----------------------------------------------------------------------

	mux_multimaster # (
		.NUM_MASTER ( NUM_MASTER ),
		.NUM_SLAVE  ( NUM_SLAVE  )
	)
	u_mux_n2m (
		.clk                     ( clk                     ) ,
		.reset                   ( reset                   ),
		.m_n2m_request_address   ( m_n2m_request_address   ),
		.m_n2m_request_data      ( m_n2m_request_data      ),
		.m_n2m_request_read      ( m_n2m_request_read      ),
		.m_n2m_request_write     ( m_n2m_request_write     ),
		.m_mc_avail_o            ( m_mc_avail_o            ),
		.m_m2n_request_available ( m_m2n_request_available ),
		.m_m2n_response_valid    ( m_m2n_response_valid    ),
		.m_m2n_response_address  ( m_m2n_response_address  ),
		.m_m2n_response_data     ( m_m2n_response_data     ),

		.s_n2m_request_address   ( n2m_request_address     ),
		.s_n2m_request_data      ( n2m_request_data        ),
		.s_n2m_request_read      ( n2m_request_read        ),
		.s_n2m_request_write     ( n2m_request_write       ),
		.s_mc_avail_o            ( mc_avail_o              ),
		.s_m2n_request_available ( m2n_request_available   ),
		.s_m2n_response_valid    ( m2n_response_valid      ),
		.s_m2n_response_address  ( m2n_response_address    ),
		.s_m2n_response_data     ( m2n_response_data       )
	);

	io_device_test u_io_device_test (
		.clk                  ( clk                      ),
		.reset                ( reset                    ),
		// From System Bus
		.n2m_request_address  ( n2m_request_address      ),
		.n2m_request_data     ( n2m_request_data         ),
		.n2m_request_read     ( n2m_request_read[0]      ),
		.n2m_request_write    ( n2m_request_write[0]     ),
		.mc_avail_o           ( mc_avail_o               ),
		// To System Bus
		.m2n_request_available( m2n_request_available[0] ),
		.m2n_response_valid   ( m2n_response_valid[0]    ),
		.m2n_response_address ( m2n_response_address[0]  ),
		.m2n_response_data    ( m2n_response_data[0]     )
	);

//  -----------------------------------------------------------------------
//  -- Synchronization Core
//  -----------------------------------------------------------------------

	synchronization_core u_synchronization_core (
		.clk                    ( clk                 ),
		.reset                  ( reset               ),
		//Account
		.ni_account_mess        ( c2n_account_message ),
		.ni_account_mess_valid  ( c2n_account_valid   ),
		.sc_account_consumed    (                     ),
		.account_available      ( account_available   ),
		//Release
		.sc_release_mess        ( n2c_release_message ),
		.sc_release_dest_valid  (                     ),
		.sc_release_valid       ( n2c_release_valid   ),
		.ni_available           ( network_available   )
	);

//  -----------------------------------------------------------------------
//  -- Memory Outputs
//  -----------------------------------------------------------------------

	assign m2n_request_available[1]                             = mem2nup_request_available;
	assign m2n_response_valid[1]                                = mem2nup_response_valid;
	assign m2n_response_address[1]                              = mem2nup_response_address;
	assign m2n_response_data[1]                                 = mem2nup_response_data;

	assign nup2mem_request_address                              = m_n2m_request_address[1];
	assign nup2mem_request_data                                 = m_n2m_request_data[1];
	assign nup2mem_request_dirty_mask                           = m_n2m_request_dirty_mask[1];
	assign nup2mem_request_read                                 = m_n2m_request_read[1];
	assign nup2mem_request_write                                = m_n2m_request_write[1];
	assign nup_available                                        = m_mc_avail_o[1];

endmodule
