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

/*
 * The LDST unit provides an N-Way set associative cache mechanism, and handles load and store operations from the core.
 * This module is divided in three stages (more details will be furnished inside them).
 * On the core side, It interfaces the Operand Fetch and the Writeback stages. On the bus side, it interfaces the Cache
 * Controller which handles info and data update.
 *
 * Requests from threads are stored into FIFOs and elaborated one per time. In case of cache miss, the control logic stops fetching
 * instruction from these FIFOs until the data is retrieved from main memory. This unit sends to Instruction Buffer unit
 * a signal in order to stop a thread when a those FIFOs are full.
 *
 * The LDST Unit does not handle addresses in the IO memory space, when the current request is to an IO device, it
 * is directly forwarded the Cache Controller which will dispatch the request and write the result back into the third stage.
 *
 */

module load_store_unit #(
		parameter TILE_ID = 0 )
	(
		input  logic                                        clk,
		input  logic                                        reset,

		// Operand Fetch
		input  logic                                        opf_valid,
		input  instruction_decoded_t                        opf_inst_scheduled,
		input  hw_lane_t                                    opf_fecthed_op0,
		input  hw_lane_t                                    opf_fecthed_op1,
		input  hw_lane_mask_t                               opf_hw_lane_mask,

		// Writeback and Cache Controller
		output logic                                        ldst_valid,
		output instruction_decoded_t                        ldst_instruction,
		output dcache_line_t                                ldst_cache_line,
		output hw_lane_mask_t                               ldst_hw_lane_mask,
		output dcache_store_mask_t                          ldst_store_mask,
		output dcache_address_t                             ldst_address,
		output dcache_store_mask_t                          ldst_dirty_mask,
		output logic                                        ldst_miss,
		output logic                                        ldst_evict,
		output logic                                        ldst_flush,
		output logic                                        ldst_dinv,
		input  logic                                        ci_flush_fifo_available,

		// Instruction buffers
		output thread_mask_t                                ldst_almost_full,

		// Synch Core
		output logic                 [`THREAD_NUMB - 1 : 0] no_load_store_pending,

		//Cache Controller - Thread wakeup
		input  logic                                        cc_wakeup,
		input  thread_id_t                                  cc_wakeup_thread_id,

		// Cache Controller - Update Bus
		input  logic                                        cc_update_ldst_valid,
		input  cc_command_t                                 cc_update_ldst_command,
		input  dcache_way_idx_t                             cc_update_ldst_way,
		input  dcache_address_t                             cc_update_ldst_address,
		input  dcache_privileges_t                          cc_update_ldst_privileges,
		input  dcache_line_t                                cc_update_ldst_store_value,

		// Cache Controller - Tag Snoop Bus
		input  logic                                        cc_snoop_tag_valid,
		input  dcache_set_t                                 cc_snoop_tag_set,
		output dcache_privileges_t   [`DCACHE_WAY - 1 : 0]  ldst_snoop_privileges,
		output dcache_tag_t          [`DCACHE_WAY - 1 : 0]  ldst_snoop_tag,

		// Cache Controller - Data Snoop Bus
		input  logic                                        cc_snoop_data_valid,
		input  dcache_set_t                                 cc_snoop_data_set,
		input  dcache_way_idx_t                             cc_snoop_data_way,
		output dcache_line_t                                ldst_snoop_data,

		// Cache Controller Stage 2 - LRU Update Bus
		output logic                                        ldst_lru_update_en,
		output dcache_set_t                                 ldst_lru_update_set,
		output dcache_way_idx_t                             ldst_lru_update_way,

		// Cache Controller - IO Map interface
		input  logic                                        io_intf_available,
		output logic                                        ldst_io_valid,
		output thread_id_t                                  ldst_io_thread,
		output logic [$bits(io_operation_t)-1 : 0]          ldst_io_operation,
		output address_t                                    ldst_io_address,
		output register_t                                   ldst_io_data,

		input  logic                                        io_intf_resp_valid,
		input  thread_id_t                                  io_intf_wakeup_thread,
		input  register_t                                   io_intf_resp_data,
		output logic                                        ldst_io_resp_consumed,

		// Rollback Handler
		input  thread_mask_t                                rollback_valid,

		// will be used in future for raising exception
		output logic                                        ldst_rollback_en,
		output register_t                                   ldst_rollback_pc,
		output thread_id_t                                  ldst_rollback_thread_id,

		// Configuration signal
		input  logic                                        cr_ctrl_cache_wt
	);

//  -----------------------------------------------------------------------
//  -- Load Store Unit Stage 1 - Signals
//  -----------------------------------------------------------------------
	//To Load Store Unit Stage 2
	thread_mask_t                                ldst1_valid;
	instruction_decoded_t [`THREAD_NUMB - 1 : 0] ldst1_instruction;
	dcache_address_t      [`THREAD_NUMB - 1 : 0] ldst1_address;
	dcache_line_t         [`THREAD_NUMB - 1 : 0] ldst1_store_value;
	dcache_store_mask_t   [`THREAD_NUMB - 1 : 0] ldst1_store_mask;
	hw_lane_mask_t        [`THREAD_NUMB - 1 : 0] ldst1_hw_lane_mask;
	thread_mask_t                                ldst1_almost_full;

	thread_mask_t                                ldst1_recycle_valid;
	instruction_decoded_t [`THREAD_NUMB - 1 : 0] ldst1_recycle_instruction;
	dcache_address_t      [`THREAD_NUMB - 1 : 0] ldst1_recycle_address;
	dcache_line_t         [`THREAD_NUMB - 1 : 0] ldst1_recycle_store_value;
	dcache_store_mask_t   [`THREAD_NUMB - 1 : 0] ldst1_recycle_store_mask;
	hw_lane_mask_t        [`THREAD_NUMB - 1 : 0] ldst1_recycle_hw_lane_mask;

	//From Load Store Unit Stage 2
	thread_mask_t                                ldst2_recycled;
	thread_mask_t                                ldst2_dequeue_instruction;

	// To Core Rollback Handler
	logic                                        ldst1_rollback_en;
	register_t                                   ldst1_rollback_pc;
	thread_id_t                                  ldst1_rollback_thread_id;

//  -----------------------------------------------------------------------
//  -- Load Store Unit Stage 2 - Signals
//  -----------------------------------------------------------------------
	// To Load Sore Unit Stage 3 - Instruction
	logic                                        ldst2_valid;
	instruction_decoded_t                        ldst2_instruction;
	dcache_address_t                             ldst2_address;
	dcache_line_t                                ldst2_store_value;
	dcache_store_mask_t                          ldst2_store_mask;
	dcache_store_mask_t   [`DCACHE_WAY - 1 : 0]  ldst2_dirty_mask;
	hw_lane_mask_t                               ldst2_hw_lane_mask;
	dcache_tag_t          [`DCACHE_WAY - 1 : 0]  ldst2_tag_read;
	dcache_privileges_t   [`DCACHE_WAY - 1 : 0]  ldst2_privileges_read;
	logic                                        ldst2_is_flush;
	logic                                        ldst2_is_dinv;
	logic                                        ldst2_io_memspace;
	logic                                        ldst2_io_memspace_has_data;

	// To Load Store Unit Stage 3 - Update signals
	logic                                        ldst2_update_data_valid;
	logic                                        ldst2_update_info_valid;
	dcache_way_idx_t                             ldst2_update_way;

	// Load Store Unit Stage 3 - Evict signals
	logic                                        ldst2_evict_valid;

	// To Cache Controller - Snoop Bus
	dcache_privileges_t   [`DCACHE_WAY - 1 : 0]  ldst2_snoop_request_privileges;
	dcache_tag_t          [`DCACHE_WAY - 1 : 0]  ldst2_snoop_request_tag_data;

	dcache_set_t                                 ldst3_lru_access_set;

//  -----------------------------------------------------------------------
//  -- Load Store Unit Stage 3 - Signals
//  -----------------------------------------------------------------------
	// To Cache Controller Stage 2 - LRU Update Bus
	logic                                        ldst3_lru_update_en;
	dcache_way_idx_t                             ldst3_lru_update_way;
	thread_mask_t                                ldst3_thread_sleep;
	logic                                        ldst3_flush;
	logic                                        ldst3_dinv;

	logic                                        ldst3_update_dirty_mask_valid;
	dcache_set_t                                 ldst3_update_dirty_mask_set;
	dcache_way_idx_t                             ldst3_update_dirty_mask_way;
	dcache_store_mask_t                          ldst3_update_dirty_mask;

	//To Writeback and Cache Controller
	logic                                        ldst3_valid;
	instruction_decoded_t                        ldst3_instruction;
	dcache_line_t                                ldst3_cache_line;
	hw_lane_mask_t                               ldst3_hw_lane_mask;
	dcache_store_mask_t                          ldst3_store_mask;
	dcache_address_t                             ldst3_address;
	dcache_store_mask_t                          ldst3_dirty_mask;
	logic                                        ldst3_miss;
	logic                                        ldst3_evict;
	dcache_line_t                                ldst3_read_data;
	logic                                        ldst3_io_valid;
	logic [$bits(io_operation_t)-1 : 0]          ldst3_io_operation;
	thread_id_t                                  ldst3_io_thread;

	// To Synch Core
	logic                 [`THREAD_NUMB - 1 : 0] s1_no_ls_pending;
	logic                 [`THREAD_NUMB - 1 : 0] s2_no_ls_pending;
	logic                 [`THREAD_NUMB - 1 : 0] s3_no_ls_pending;
	logic                 [`THREAD_NUMB - 1 : 0] miss_no_ls_pending;

//  -----------------------------------------------------------------------
//  -- Load Store Unit Stage 1
//  -----------------------------------------------------------------------
	load_store_unit_stage1 #( 
		.TILE_ID( TILE_ID )
	)
	u_load_store_unit_stage1 (
		.clk                       ( clk                        ),
		.reset                     ( reset                      ),

		// Operand Fetch
		.opf_valid                 ( opf_valid                  ),
		.opf_inst_scheduled        ( opf_inst_scheduled         ),
		.opf_fecthed_op0           ( opf_fecthed_op0            ),
		.opf_fecthed_op1           ( opf_fecthed_op1            ),
		.opf_hw_lane_mask          ( opf_hw_lane_mask           ),

		// Load Store Unit Stage 2
		.ldst2_dequeue_instruction ( ldst2_dequeue_instruction  ),
		.ldst2_recycled            ( ldst2_recycled             ),
		.ldst1_valid               ( ldst1_valid                ),
		.ldst1_instruction         ( ldst1_instruction          ),
		.ldst1_address             ( ldst1_address              ),
		.ldst1_store_value         ( ldst1_store_value          ),
		.ldst1_store_mask          ( ldst1_store_mask           ),
		.ldst1_hw_lane_mask        ( ldst1_hw_lane_mask         ),
		.ldst1_recycle_valid       ( ldst1_recycle_valid        ),
		.ldst1_recycle_instruction ( ldst1_recycle_instruction  ),
		.ldst1_recycle_address     ( ldst1_recycle_address      ),
		.ldst1_recycle_store_value ( ldst1_recycle_store_value  ),
		.ldst1_recycle_store_mask  ( ldst1_recycle_store_mask   ),
		.ldst1_recycle_hw_lane_mask( ldst1_recycle_hw_lane_mask ),

		// Load Store Unit Stage 3
		.ldst3_miss                ( ldst3_miss                 ),
		.ldst3_instruction         ( ldst3_instruction          ),
		.ldst3_cache_line          ( ldst3_cache_line           ),
		.ldst3_hw_lane_mask        ( ldst3_hw_lane_mask         ),
		.ldst3_store_mask          ( ldst3_store_mask           ),
		.ldst3_address             ( ldst3_address              ),

		.ldst3_io_valid            ( ldst3_io_valid             ),
		.ldst3_io_operation        ( ldst3_io_operation         ),
		.ldst3_io_thread           ( ldst3_io_thread            ),

		// Instruction Scheduler
		.ldst1_almost_full         ( ldst1_almost_full          ),

		// To Synch Core
		.s1_no_ls_pending          ( s1_no_ls_pending           ),
		.miss_no_ls_pending        ( miss_no_ls_pending         ),

		// Rollback Handler
		.rollback_valid            ( rollback_valid             ),
		.ldst1_rollback_en         ( ldst1_rollback_en          ),
		.ldst1_rollback_pc         ( ldst1_rollback_pc          ),
		.ldst1_rollback_thread_id  ( ldst1_rollback_thread_id   )
	);

	// Rollback exception are directly connect to the Core Rollback Handler
	assign ldst_rollback_en      = ldst1_rollback_en,
		ldst_rollback_pc         = ldst1_rollback_pc,
		ldst_rollback_thread_id  = ldst1_rollback_thread_id;

	assign ldst_almost_full      = ldst1_almost_full;

//  -----------------------------------------------------------------------
//  -- Load Store Unit Stage 2
//  -----------------------------------------------------------------------
	load_store_unit_stage2 #(
		.TILE_ID( TILE_ID )
	) u_load_store_unit_stage2 (
		.clk                        ( clk                            ),
		.reset                      ( reset                          ),

		// Load Sore Unit Stage 1
		.ldst1_valid                ( ldst1_valid                    ),
		.ldst1_instruction          ( ldst1_instruction              ),
		.ldst1_address              ( ldst1_address                  ),
		.ldst1_store_value          ( ldst1_store_value              ),
		.ldst1_store_mask           ( ldst1_store_mask               ),
		.ldst1_hw_lane_mask         ( ldst1_hw_lane_mask             ),
		.ldst1_recycle_valid        ( ldst1_recycle_valid            ),
		.ldst1_recycle_instruction  ( ldst1_recycle_instruction      ),
		.ldst1_recycle_address      ( ldst1_recycle_address          ),
		.ldst1_recycle_store_value  ( ldst1_recycle_store_value      ),
		.ldst1_recycle_store_mask   ( ldst1_recycle_store_mask       ),
		.ldst1_recycle_hw_lane_mask ( ldst1_recycle_hw_lane_mask     ),
		.ldst2_dequeue_instruction  ( ldst2_dequeue_instruction      ),
		.ldst2_recycled             ( ldst2_recycled                 ),

		// Load Sore Unit Stage 3
		.ldst3_thread_sleep         ( ldst3_thread_sleep             ),
		.ldst3_update_dirty_mask_valid ( ldst3_update_dirty_mask_valid ),
		.ldst3_update_dirty_mask_set   ( ldst3_update_dirty_mask_set   ),
		.ldst3_update_dirty_mask_way   ( ldst3_update_dirty_mask_way   ),
		.ldst3_update_dirty_mask       ( ldst3_update_dirty_mask       ),
		.ldst2_valid                ( ldst2_valid                    ),
		.ldst2_instruction          ( ldst2_instruction              ),
		.ldst2_address              ( ldst2_address                  ),
		.ldst2_store_value          ( ldst2_store_value              ),
		.ldst2_store_mask           ( ldst2_store_mask               ),
		.ldst2_dirty_mask           ( ldst2_dirty_mask               ),
		.ldst2_hw_lane_mask         ( ldst2_hw_lane_mask             ),
		.ldst2_tag_read             ( ldst2_tag_read                 ),
		.ldst2_privileges_read      ( ldst2_privileges_read          ),
		.ldst2_is_flush             ( ldst2_is_flush                 ),
		.ldst2_is_dinv              ( ldst2_is_dinv                  ),
		.ldst2_io_memspace          ( ldst2_io_memspace              ),
		.ldst2_io_memspace_has_data ( ldst2_io_memspace_has_data     ),
		.ldst2_update_data_valid    ( ldst2_update_data_valid        ),
		.ldst2_update_info_valid    ( ldst2_update_info_valid        ),
		.ldst2_update_way           ( ldst2_update_way               ),
		.ldst2_evict_valid          ( ldst2_evict_valid              ),
		.s2_no_ls_pending           ( s2_no_ls_pending               ),

		// From Cache Controller - IO Map interface
		.io_intf_available          ( io_intf_available              ),
		// From Cache Controller - Flush FIFO availability
	  .ci_flush_fifo_available    ( ci_flush_fifo_available        ),

		// To Cache Controller - IO Map interface
		.io_intf_resp_valid         ( io_intf_resp_valid             ),
		.io_intf_wakeup_thread      ( io_intf_wakeup_thread          ),
		.io_intf_resp_data          ( io_intf_resp_data              ),
		.ldst2_io_resp_consumed     ( ldst_io_resp_consumed          ),

		// Cache Controller
		.cc_update_ldst_valid       ( cc_update_ldst_valid           ),
		.cc_update_ldst_command     ( cc_update_ldst_command         ),
		.cc_update_ldst_way         ( cc_update_ldst_way             ),
		.cc_update_ldst_address     ( cc_update_ldst_address         ),
		.cc_update_ldst_privileges  ( cc_update_ldst_privileges      ),
		.cc_update_ldst_store_value ( cc_update_ldst_store_value     ),
		.cc_snoop_tag_valid         ( cc_snoop_tag_valid             ),
		.cc_snoop_tag_set           ( cc_snoop_tag_set               ),
		.cc_wakeup                  ( cc_wakeup                      ),
		.cc_wakeup_thread_id        ( cc_wakeup_thread_id            ),
		.ldst2_snoop_privileges     ( ldst2_snoop_request_privileges ),
		.ldst2_snoop_tag            ( ldst2_snoop_request_tag_data   )
	);

	//assign ldst_lru_access_en    = ldst2_lru_access_en,
	//  ldst_lru_access_set      = ldst2_lru_access_set;

	// To Cache Controller Snoop Bus
	assign ldst_snoop_privileges = ldst2_snoop_request_privileges,
		ldst_snoop_tag           = ldst2_snoop_request_tag_data;

//  -----------------------------------------------------------------------
//  -- Load Store Unit Stage 3
//  -----------------------------------------------------------------------
	load_store_unit_stage3 #( 
		.TILE_ID( TILE_ID )
	) 
	u_load_store_unit_stage3 (
		.clk                  ( clk                   ),
		.reset                ( reset                 ),

		// Load Sore Unit Stage 2
		.ldst2_valid          ( ldst2_valid           ),
		.ldst2_instruction    ( ldst2_instruction     ),
		.ldst2_address        ( ldst2_address         ),
		.ldst2_store_value    ( ldst2_store_value     ),
		.ldst2_store_mask     ( ldst2_store_mask      ),
		.ldst2_dirty_mask     ( ldst2_dirty_mask      ),
		.ldst2_hw_lane_mask   ( ldst2_hw_lane_mask    ),
		.ldst2_tag_read       ( ldst2_tag_read        ),
		.ldst2_privileges_read( ldst2_privileges_read ),
		.ldst2_update_data_valid ( ldst2_update_data_valid    ),
		.ldst2_update_info_valid ( ldst2_update_info_valid    ),
		.ldst2_update_way     ( ldst2_update_way      ),
		.ldst2_evict_valid    ( ldst2_evict_valid     ),
		.ldst3_thread_sleep   ( ldst3_thread_sleep    ),
		.ldst2_is_flush       ( ldst2_is_flush        ),
		.ldst2_is_dinv        ( ldst2_is_dinv         ),
		.ldst2_io_memspace    ( ldst2_io_memspace     ),
		.ldst2_io_memspace_has_data ( ldst2_io_memspace_has_data       ),

		.ldst3_update_dirty_mask_valid ( ldst3_update_dirty_mask_valid ),
		.ldst3_update_dirty_mask_set   ( ldst3_update_dirty_mask_set   ),
		.ldst3_update_dirty_mask_way   ( ldst3_update_dirty_mask_way   ),
		.ldst3_update_dirty_mask       ( ldst3_update_dirty_mask       ),

		// Cache Controller Stage 2
		.ldst3_lru_update_en  ( ldst3_lru_update_en   ),
		.ldst3_lru_update_way ( ldst3_lru_update_way  ),
		.ldst3_lru_access_set ( ldst3_lru_access_set  ),

		// Synch Core
		.s3_no_ls_pending     ( s3_no_ls_pending      ),

		// Load Store Unit Stage1, Writeback and Cache Controller
		.cc_snoop_data_valid  ( cc_snoop_data_valid   ),
		.cc_snoop_data_set    ( cc_snoop_data_set     ),
		.cc_snoop_data_way    ( cc_snoop_data_way     ),
		.ldst3_snoop_data     ( ldst3_read_data       ),
		.ldst3_valid          ( ldst3_valid           ),
		.ldst3_instruction    ( ldst3_instruction     ),
		.ldst3_cache_line     ( ldst3_cache_line      ),
		.ldst3_hw_lane_mask   ( ldst3_hw_lane_mask    ),
		.ldst3_store_mask     ( ldst3_store_mask      ),
		.ldst3_address        ( ldst3_address         ),
		.ldst3_dirty_mask     ( ldst3_dirty_mask      ),
		.ldst3_miss           ( ldst3_miss            ),
		.ldst3_evict          ( ldst3_evict           ),
		.ldst3_flush          ( ldst3_flush           ),
		.ldst3_dinv           ( ldst3_dinv            ),

		// IO
		.ldst3_io_valid       ( ldst3_io_valid        ),
		.ldst3_io_thread      ( ldst3_io_thread       ),
		.ldst3_io_operation   ( ldst3_io_operation    ),
		.ldst3_io_address     ( ldst_io_address       ),
		.ldst3_io_data        ( ldst_io_data          ),

		// Configuration signal
		.cr_ctrl_cache_wt     ( cr_ctrl_cache_wt      )
	);

	// Load Store Stage 3 signals an update on a way to the PseudoLRU in Cache Controller
	assign ldst_lru_update_en    = ldst3_lru_update_en,
		ldst_lru_update_way      = ldst3_lru_update_way,
		ldst_lru_update_set      = ldst3_lru_access_set;


	// Load Store Stage 3 signals go back to the Core Writeback if the request is satisfied, or
	// they are passed to Core Interface
	assign ldst_valid            = ldst3_valid,
		ldst_instruction         = ldst3_instruction,
		ldst_cache_line          = ldst3_cache_line,
		ldst_hw_lane_mask        = ldst3_hw_lane_mask,
		ldst_store_mask          = ldst3_store_mask,
		ldst_address             = ldst3_address,
		ldst_dirty_mask          = ldst3_dirty_mask,
		ldst_miss                = ldst3_miss,
		ldst_evict               = ldst3_evict,
		ldst_flush               = ldst3_flush,
		ldst_dinv                = ldst3_dinv;

	assign ldst_io_valid     = ldst3_io_valid,
	       ldst_io_operation = io_operation_t'(ldst3_io_operation),
	       ldst_io_thread    = ldst3_io_thread;

	assign ldst_snoop_data       = ldst3_read_data;

	// Check if there is a running load/store operation
	assign no_load_store_pending = s1_no_ls_pending & s2_no_ls_pending & s3_no_ls_pending & miss_no_ls_pending;

endmodule
