`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"

module lsu_het_wrapper  #(
		parameter TILE_ID       = 0,
        parameter THREAD_NUMB   = 8,
        parameter THREAD_IDX_W  = $clog2(THREAD_NUMB),
        parameter ADDRESS_WIDTH = 32,
        parameter DATA_WIDTH    = 512,
        parameter WORDS_PERLINE = DATA_WIDTH/32,
        parameter L1_WAY_NUMB   = 4,
        parameter L1_SET_NUMB   = 32
    )
	(
		input  logic                                        clk,
		input  logic                                        reset,

		// From Heterogeneous accelerator
		input  logic                                        req_in_valid,
        input  logic [31 : 0]                               req_in_id,
        input  logic [$clog2(THREAD_NUMB) - 1 : 0]          req_in_thread_id,
		input  logic [7 : 0]                                req_in_op,
		input  logic [ADDRESS_WIDTH - 1 : 0]                req_in_address,
		input  logic [DATA_WIDTH - 1    : 0]                req_in_data,
		input  logic [WORDS_PERLINE - 1 : 0]                req_in_hw_lane_mask,

		// To Heterogeneous accelerator
		output logic                                        req_out_valid,
        output logic [31 : 0]                               req_out_id,
        output logic [$clog2(THREAD_NUMB) - 1 : 0]          req_out_thread_id,
		output logic [7 : 0]                                req_out_op,
		output logic [DATA_WIDTH - 1    : 0]                req_out_cache_line,
		output logic [WORDS_PERLINE - 1 : 0]                req_out_hw_lane_mask,
		output dcache_store_mask_t                          req_out_store_mask,
		output logic [ADDRESS_WIDTH - 1 : 0]                req_out_address,
		output dcache_store_mask_t                          req_out_dirty_mask,
		output logic                                        req_out_miss,
		output logic                                        req_out_evict,
		output logic                                        req_out_flush,
		output logic                                        req_out_dinv,
		input  logic                                        req_in_flush_fifo_available,

		// To Heterogeneous accelerator - Backpressure signals
		output logic [THREAD_NUMB - 1 : 0]                  lsu_het_almost_full,
		output logic [THREAD_NUMB - 1 : 0]                  lsu_het_no_load_store_pending,

        // Fromt Heterogeneous accelerator - Flush and Error signals
		input  logic                                        lsu_het_ctrl_cache_wt,
		input  [THREAD_NUMB - 1 : 0]                        req_in_rollback_valid,
		output logic                                        lsu_het_error_valid,
		output logic [31 : 0]                               lsu_het_error_id,
		output logic [THREAD_IDX_W - 1 : 0]                 lsu_het_error_thread_id,

		//Cache Controller - Thread wakeup
		input  logic                                        cc_wakeup,
		input  logic [THREAD_IDX_W - 1 : 0]                 cc_wakeup_thread_id,

		// Cache Controller - Update Bus
		input  logic                                        cc_update_ldst_valid,
		input  cc_command_t                                 cc_update_ldst_command,
		input  logic [$clog2(L1_WAY_NUMB) - 1 : 0]          cc_update_ldst_way,
		input  dcache_address_t                             cc_update_ldst_address,
		input  dcache_privileges_t                          cc_update_ldst_privileges,
		input  dcache_line_t                                cc_update_ldst_store_value,
		output instruction_decoded_t                        req_out_instruction,

		// Cache Controller - Tag Snoop Bus
		input  logic                                        cc_snoop_tag_valid,
		input  logic [$clog2(L1_SET_NUMB) - 1 : 0]          cc_snoop_tag_set,
		output dcache_privileges_t   [L1_WAY_NUMB - 1 : 0]  ldst_snoop_privileges,
		output dcache_tag_t          [L1_WAY_NUMB - 1 : 0]  ldst_snoop_tag,

		// Cache Controller - Data Snoop Bus
		input  logic                                        cc_snoop_data_valid,
		input  logic [$clog2(L1_SET_NUMB) - 1 : 0]          cc_snoop_data_set,
		input  logic [$clog2(L1_WAY_NUMB) - 1 : 0]          cc_snoop_data_way,
		output dcache_line_t                                ldst_snoop_data,

		// Cache Controller Stage 2 - LRU Update Bus
		output logic                                        ldst_lru_update_en,
		output logic [$clog2(L1_SET_NUMB) - 1 : 0]          ldst_lru_update_set,
		output logic [$clog2(L1_WAY_NUMB) - 1 : 0]          ldst_lru_update_way,

		// Cache Controller - IO Map interface
		input  logic                                        io_intf_available,
		output logic                                        ldst_io_valid,
		output logic [THREAD_IDX_W - 1 : 0]                 ldst_io_thread,
		output logic [$bits(io_operation_t)-1 : 0]          ldst_io_operation,
		output address_t                                    ldst_io_address,
		output register_t                                   ldst_io_data,

		input  logic                                        io_intf_resp_valid,
		input  logic [THREAD_IDX_W - 1 : 0]                 io_intf_wakeup_thread,
		input  register_t                                   io_intf_resp_data,
		output logic                                        ldst_io_resp_consumed
	);

//  -----------------------------------------------------------------------
//  -- Wrapping instruction
//  -----------------------------------------------------------------------
    instruction_decoded_t tmp_instruct;

    always_comb begin
        tmp_instruct.pc                        = req_in_id;
        tmp_instruct.thread_id                 = thread_id_t'(req_in_thread_id);
        tmp_instruct.is_valid                  = 1'b1;
        tmp_instruct.mask_enable               = 1'b0;
        tmp_instruct.source0                   = reg_addr_t'(1'b0);
        tmp_instruct.source1                   = reg_addr_t'(1'b0);
        tmp_instruct.destination               = reg_addr_t'(1'b0);
        tmp_instruct.has_source0               = 1'b0; 
        tmp_instruct.has_source1               = 1'b0;
        tmp_instruct.has_destination           = 1'b0;
        tmp_instruct.is_source0_vectorial      = 1'b0;
		tmp_instruct.is_source1_vectorial      = ( ( req_in_op[5 : 0] >= LOAD_V_8 & req_in_op[5 : 0] <= LOAD_V_32_U ) | ( req_in_op[5 : 0] >= STORE_V_8 & req_in_op[5 : 0] <= STORE_V_64 ) );
		tmp_instruct.is_destination_vectorial  = ( ( req_in_op[5 : 0] >= LOAD_V_8 & req_in_op[5 : 0] <= LOAD_V_32_U ) | ( req_in_op[5 : 0] >= STORE_V_8 & req_in_op[5 : 0] <= STORE_V_64 ) );
        tmp_instruct.immediate                 = {`IMMEDIATE_SIZE{1'b0}};
        tmp_instruct.is_source1_immediate      = 1'b0;
        tmp_instruct.pipe_sel                  = PIPE_MEM;
        tmp_instruct.op_code                   = opcode_t'(req_in_op[6 : 0]);
        tmp_instruct.is_memory_access          = 1'b1;
        tmp_instruct.is_memory_access_coherent = 1'b1;
        tmp_instruct.is_int                    = 1'b0;
        tmp_instruct.is_fp                     = 1'b0;
        tmp_instruct.is_movei                  = 1'b0;
        tmp_instruct.is_branch                 = 1'b0;
        tmp_instruct.is_conditional            = 1'b0;
        tmp_instruct.is_long                   = 1'b0;
        tmp_instruct.is_control                = req_in_op[7]; // XXX: control operation, namely FLUSH and DCACHE INVALIDATE, are mapped on the high values.
        tmp_instruct.is_load                   = !req_in_op[5];

        req_out_id                             = req_out_instruction.pc;
        req_out_thread_id                      = req_out_instruction.thread_id;
        req_out_op                             = req_out_instruction.op_code;
    end

//  -----------------------------------------------------------------------
//  -- Load Store Unit
//  -----------------------------------------------------------------------
	load_store_unit_par #(
		.TILE_ID      ( TILE_ID      ),
        .THREAD_NUMB  ( THREAD_NUMB  ),
        .THREAD_IDX_W ( THREAD_IDX_W ),
        .L1_WAY_NUMB  ( L1_WAY_NUMB  ),
        .L1_SET_NUMB  ( L1_SET_NUMB  )
    )
    u_load_store_unit (
		.clk                        ( clk                           ),
		.reset                      ( reset                         ),
		// Operand Fetch
		.opf_valid                  ( req_in_valid                  ),
		.opf_inst_scheduled         ( tmp_instruct                  ),
		.opf_fecthed_op0            ( req_in_address                ),
		.opf_fecthed_op1            ( req_in_data                   ),
		.opf_hw_lane_mask           ( req_in_hw_lane_mask           ),
		.no_load_store_pending      ( lsu_het_no_load_store_pending ),
		// Writeback and Cache Controller
		.ldst_valid                 ( req_out_valid                 ),
		.ldst_instruction           ( req_out_instruction           ),
		.ldst_cache_line            ( req_out_cache_line            ),
		.ldst_hw_lane_mask          ( req_out_hw_lane_mask          ),
		.ldst_store_mask            ( req_out_store_mask            ),
		.ldst_address               ( req_out_address               ),
		.ldst_dirty_mask            ( req_out_dirty_mask            ),
		.ldst_miss                  ( req_out_miss                  ),
		.ldst_evict                 ( req_out_evict                 ),
		.ldst_flush                 ( req_out_flush                 ),
		.ldst_dinv                  ( req_out_dinv                  ),
		.ci_flush_fifo_available    ( req_in_flush_fifo_available   ),
		// Instruction Scheduler
		.ldst_almost_full           ( lsu_het_almost_full           ),
		// Cache Controller - Thread Wake-Up
		.cc_wakeup                  ( cc_wakeup                     ),
		.cc_wakeup_thread_id        ( cc_wakeup_thread_id           ),
		// Cache Controller - Update Bus
		.cc_update_ldst_valid       ( cc_update_ldst_valid          ),
		.cc_update_ldst_command     ( cc_update_ldst_command        ),
		.cc_update_ldst_way         ( cc_update_ldst_way            ),
		.cc_update_ldst_address     ( cc_update_ldst_address        ),
		.cc_update_ldst_privileges  ( cc_update_ldst_privileges     ),
		.cc_update_ldst_store_value ( cc_update_ldst_store_value    ),
		// Cache Controller - Tag Snoop Bus
		.cc_snoop_tag_valid         ( cc_snoop_tag_valid            ),
		.cc_snoop_tag_set           ( cc_snoop_tag_set              ),
		.ldst_snoop_privileges      ( ldst_snoop_privileges         ),
		.ldst_snoop_tag             ( ldst_snoop_tag                ),
		// Cache Controller - Data Snoop Bus
		.cc_snoop_data_valid        ( cc_snoop_data_valid           ),
		.cc_snoop_data_set          ( cc_snoop_data_set             ),
		.cc_snoop_data_way          ( cc_snoop_data_way             ),
		.ldst_snoop_data            ( ldst_snoop_data               ),
		// Cache Controller - LRU Access Bus
		.ldst_lru_update_set        ( ldst_lru_update_set           ),
		// Cache Controller Stage 2 - LRU Update Bus
		.ldst_lru_update_en         ( ldst_lru_update_en            ),
		.ldst_lru_update_way        ( ldst_lru_update_way           ),
		// From Cache Controller - IO Map interface
		.io_intf_available          ( io_intf_available             ),
		// To Cache Controller - IO Map interface
		.ldst_io_valid              ( ldst_io_valid                 ),
		.ldst_io_thread             ( ldst_io_thread                ),
		.ldst_io_operation          ( ldst_io_operation             ),
		.ldst_io_address            ( ldst_io_address               ),
		.ldst_io_data               ( ldst_io_data                  ),
		.io_intf_resp_valid         ( io_intf_resp_valid            ),
		.io_intf_wakeup_thread      ( io_intf_wakeup_thread         ),
		.io_intf_resp_data          ( io_intf_resp_data             ),
		.ldst_io_resp_consumed      ( ldst_io_resp_consumed         ),
		// Rollback Handler
		.rollback_valid             ( req_in_rollback_valid         ),
		.ldst_rollback_en           ( lsu_het_error_valid           ),
		.ldst_rollback_pc           ( lsu_het_error_id              ),
		.ldst_rollback_thread_id    ( lsu_het_error_thread_id       ),
		// Configuration signal
		.cr_ctrl_cache_wt           ( lsu_het_ctrl_cache_wt         )
	);

endmodule
