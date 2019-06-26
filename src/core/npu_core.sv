`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"
`include "npu_synchronization_defines.sv"
`include "npu_message_service_defines.sv"

module npu_core # (
		parameter TILE_ID        = 0,
		parameter CORE_ID        = 0,
		parameter SCRATCHPAD     = 0,
		parameter FPU            = 1,
		parameter DSU            = 0,
		parameter MANYCORE       = 0,
		parameter DIS_SYNCMASTER = 1 )
	(
		input                                                            clk,
		input                                                            reset,
		input                                                            ext_freeze,
		input                                                            resume,
		input                                [`THREAD_NUMB - 1 : 0]      thread_en,

		// From Host Controller
		input  logic                                                     hi_read_cr_valid,
		input  register_t                                                hi_read_cr_request,
		input  logic                                                     hi_write_cr_valid,
		input  register_t                                                hi_write_cr_data,
		output register_t                                                cr_response,

		// Host Interface
		input  logic                                                     hi_job_valid,
		input  address_t                                                 hi_job_pc,
		input  thread_id_t                                               hi_job_thread_id,

		//From Host Debug
		input  logic                                                     dsu_enable,
		input  logic                                                     dsu_single_step,
		input  address_t                     [7 : 0]                     dsu_breakpoint,
		input  logic                         [7 : 0]                     dsu_breakpoint_enable,
		input  logic                                                     dsu_thread_selection,
		input  thread_id_t                                               dsu_thread_id,
		input  logic                                                     dsu_en_vector,
		input  logic                                                     dsu_en_scalar,
		input  logic                                                     dsu_load_shift_reg,
		input  logic                                                     dsu_start_shift,
		input  logic                         [`REGISTER_ADDRESS - 1 : 0] dsu_reg_addr,

		input  logic                                                     dsu_write_scalar,
		input  logic                                                     dsu_write_vector,
		input  logic                                                     dsu_serial_reg_in,

		//To Host Debug
		output address_t                     [`THREAD_NUMB - 1 : 0]      dsu_bp_instruction,
		output thread_id_t                                               dsu_bp_thread_id,
		output logic                                                     dsu_serial_reg_out,
		output logic                                                     dsu_stop_shift,
		output logic                                                     dsu_hit_breakpoint,

		// Memory Access Interface
		output instruction_decoded_t                                     ldst_instruction,
		output dcache_address_t                                          ldst_address,
		output logic                                                     ldst_miss,
		output logic                                                     ldst_evict,
		output dcache_line_t                                             ldst_cache_line,
		output logic                                                     ldst_flush,
		output logic                                                     ldst_dinv,
		output dcache_store_mask_t                                       ldst_dirty_mask,

		input  logic                                                     cc_update_ldst_valid,
		input  dcache_way_idx_t                                          cc_update_ldst_way,
		input  dcache_address_t                                          cc_update_ldst_address,
		input  dcache_privileges_t                                       cc_update_ldst_privileges,
		input  dcache_line_t                                             cc_update_ldst_store_value,
		input  cc_command_t                                              cc_update_ldst_command,
		input  logic                                                     ci_flush_fifo_available,

		input  logic                                                     cc_snoop_data_valid,
		input  dcache_set_t                                              cc_snoop_data_set,
		input  dcache_way_idx_t                                          cc_snoop_data_way,
		output dcache_line_t                                             ldst_snoop_data,
		output dcache_set_t                                              ldst_lru_update_set,
		output logic                                                     ldst_lru_update_en,
		output dcache_way_idx_t                                          ldst_lru_update_way,

		input  logic                                                     cc_wakeup,
		input  thread_id_t                                               cc_wakeup_thread_id,

		input  logic                                                     cc_snoop_tag_valid,
		input  dcache_set_t                                              cc_snoop_tag_set,

		output dcache_privileges_t   [`DCACHE_WAY - 1 : 0]               ldst_snoop_privileges,
		output dcache_tag_t          [`DCACHE_WAY - 1 : 0]               ldst_snoop_tag,

		input  logic                                                     io_intf_available,
		output logic                                                     ldst_io_valid,
		output thread_id_t                                               ldst_io_thread,
		output logic [$bits(io_operation_t)-1 : 0]                       ldst_io_operation,
		output address_t                                                 ldst_io_address,
		output register_t                                                ldst_io_data,
		input  logic                                                     io_intf_resp_valid,
		input  thread_id_t                                               io_intf_wakeup_thread,
		input  register_t                                                io_intf_resp_data,
		output logic                                                     ldst_io_resp_consumed,

		// Instruction Cache
		input                                                            mem_instr_request_available,
		output logic                                                     tc_instr_request_valid,
		output address_t                                                 tc_instr_request_address,
		input  icache_lane_t                                             mem_instr_request_data_in,
		input  logic                                                     mem_instr_request_valid,

		//Synchronize Barrier
		output                                                           bc2n_account_valid,
		output sync_account_message_t                                    bc2n_account_message,
		// -- Only for Many-Core implementation ---
		output tile_mask_t                                               bc2n_account_destination_valid,
		// --- End --
		input  logic                                                     n2bc_network_available,

		//From Network Interface
		input  sync_release_message_t                                    n2bc_release_message,
		input                                                            n2bc_release_valid,
		output logic                                                     n2bc_mes_service_consumed
	);

//  -----------------------------------------------------------------------
//  -- Signals
//  -----------------------------------------------------------------------
	// Thread Control Stage - Signals
	thread_id_t                                  tc_job_thread_id;
	address_t                                    tc_job_pc;
	logic                                        tc_job_valid;
	icache_lane_t                                tc_if_data_out;
	address_t                                    tc_if_addr_update_cache;
	logic                                        tc_if_valid_update_cache;
	thread_mask_t                                tc_if_thread_en;

	// IF Stage - Signals
	logic                                        if_valid;
	thread_id_t                                  if_thread_selected_id;
	register_t                                   if_pc_scheduled;
	instruction_t                                if_inst_scheduled;
	logic                                        if_cache_miss;
	thread_mask_t                                if_thread_miss;
	address_t                                    if_address_miss;
	address_t             [`THREAD_NUMB - 1 : 0] if_current_pc;

	// Decode Stage - Signals
	logic                                        dec_valid;
	instruction_decoded_t                        dec_instr;

	// Instruction Buffer Stage - Signals
	thread_mask_t                                ib_fifo_full;
	thread_mask_t                                ib_instructions_valid;
	instruction_decoded_t [`THREAD_NUMB - 1 : 0] ib_instructions;

	// Instruction Scheduler Stage - Signals
	logic                                        is_instruction_valid;
	thread_id_t                                  is_thread_id;
	instruction_decoded_t                        is_instruction;
	thread_mask_t                                is_thread_scheduled_mask;
	scoreboard_t                                 is_destination_mask;

	// Operand Fetch Stage - Signals
	logic                                        opf_valid;
	instruction_decoded_t                        opf_inst_scheduled;
	hw_lane_t                                    opf_fetched_op0;
	hw_lane_t                                    opf_fetched_op1;
	hw_lane_mask_t                               opf_hw_lane_mask;
	scoreboard_t                                 opf_destination_bitmap;
	register_t                                   effective_address;
	logic                                        uncoherent_area_hit;

	// INT Pipe Stage - Signals
	logic                                        int_valid;
	instruction_decoded_t                        int_inst_scheduled;
	hw_lane_t                                    int_result;
	hw_lane_mask_t                               int_hw_lane_mask;

	// Control Registers - Signals
	register_t                                   cr_result;
	logic                                        cr_ctrl_cache_wt;

	// Branch Control Stage - Signals
	logic                                        bc_rollback_enable;
	logic                                        bc_rollback_valid;
	address_t                                    bc_rollback_pc;
	thread_id_t                                  bc_rollback_thread_id;
	scoreboard_t                                 bc_scoreboard;

	// FP Pipe Stage - Signals
	logic                                        fpu_valid;
	instruction_decoded_t                        fpu_inst_scheduled;
	hw_lane_mask_t                               fpu_fetched_mask;
	hw_lane_t                                    fpu_result_sp;

	// LDST Pipe Stage - Signals
	logic                                        l1d_valid;
	instruction_decoded_t                        l1d_instruction;
	dcache_line_t                                l1d_result;
	hw_lane_mask_t                               l1d_hw_lane_mask;
	dcache_store_mask_t                          l1d_store_mask;
	dcache_address_t                             l1d_address;
	thread_mask_t                                l1d_almost_full;
	logic                                        l1d_miss;
	logic                 [`THREAD_NUMB - 1 : 0] no_load_store_pending;
	logic                                        l1d_rollback_en;
	register_t                                   l1d_rollback_pc;
	thread_id_t                                  l1d_rollback_thread_id;

	// Scratchpad Memory Stage - Signals
	logic                                        spm_valid;
	instruction_decoded_t                        spm_inst_scheduled;
	hw_lane_t                                    spm_result;
	hw_lane_mask_t                               spm_hw_lane_mask;
	logic                                        spm_can_issue;
	logic                                        spm_rollback_en;
	register_t                                   spm_rollback_pc;
	thread_id_t                                  spm_rollback_thread_id;

	// Rollback Handler Stage - Signals
	logic                 [`THREAD_NUMB - 1 : 0] rollback_valid;
	address_t             [`THREAD_NUMB - 1 : 0] rollback_pc_value;
	scoreboard_t          [`THREAD_NUMB - 1 : 0] rollback_clear_bitmap;
	logic                                        rollback_trap_en;
	thread_id_t                                  rollback_thread_id;
	register_t                                   rollback_trap_reason;

	// Writeback Stage - Signals
	logic                                        wb_valid;
	thread_id_t                                  wb_thread_id;
	wb_result_t                                  wb_result;
	logic                 [`NUM_EX_PIPE - 1 : 0] wb_fifo_full;

	logic                 [`THREAD_NUMB - 1 : 0] scoreboard_empty;
	logic                 [`THREAD_NUMB - 1 : 0] bc_release_val;

	// DSU - Signals
	logic                                        freeze;
	logic                                        nfreeze;
	logic                 [`THREAD_NUMB - 1 : 0] dsu_stop_issue;

	logic                                        instr_request_valid_to_uc, instr_request_valid_from_tc;
	address_t                                    instr_request_address_to_uc, instr_request_address_from_tc;

	// Memory interface
	logic                                        mem_instr_request_available_uc;
	logic                                        mem_instr_request_available_tc;
	// --- End ---

//-------------------------------------------------------------
//  -- Thread Controller
//  -----------------------------------------------------------------------

    always_comb begin : FREEZE_SIGNAL_DEF 
        nfreeze = ~freeze;
    end

	thread_controller u_thread_controller (
		.clk                         ( clk                            ),
		.reset                       ( reset                          ),
		.enable                      ( nfreeze                        ),
		// Host Interface
		.hi_job_valid                ( hi_job_valid                   ),
		.hi_job_pc                   ( hi_job_pc                      ),
		.hi_job_thread_id            ( hi_job_thread_id               ),
		//Instruction fetch stage
		.if_cache_miss               ( if_cache_miss                  ),
		.if_thread_miss              ( if_thread_miss                 ),
		.if_address_miss             ( if_address_miss                ),
		.tc_if_data_out              ( tc_if_data_out                 ),
		.tc_if_addr_update_cache     ( tc_if_addr_update_cache        ),
		.tc_if_valid_update_cache    ( tc_if_valid_update_cache       ),
		.tc_if_thread_en             ( tc_if_thread_en                ),
		.thread_en                   ( thread_en                      ), //external signal from user
		.ib_fifo_full                ( ib_fifo_full                   ), //from instruction buffer
		.tc_job_pc                   ( tc_job_pc                      ),
		.tc_job_thread_id            ( tc_job_thread_id               ),
		.tc_job_valid                ( tc_job_valid                   ),
		.dsu_stop_issue              ( dsu_stop_issue                 ),
		//Memory interface
		.mem_instr_request_available ( mem_instr_request_available    ),
		.mem_instr_request_data_in   ( mem_instr_request_data_in      ),
		.mem_instr_request_valid     ( mem_instr_request_valid        ),
		.tc_instr_request_address    ( tc_instr_request_address       ),
		.tc_instr_request_valid      ( tc_instr_request_valid         )
	);

//  -----------------------------------------------------------------------
//  -- Instruction Fetch
//  -----------------------------------------------------------------------

	instruction_fetch_stage u_instruction_fetch_stage (
		.clk                   ( clk                      ),
		.reset                 ( reset                    ),
		.enable                ( nfreeze                  ),
		// Rollback stage interface
		.rollback_valid        ( rollback_valid           ),
		.rollback_pc_value     ( rollback_pc_value        ),
		// Instruction fetch stage interface
		.if_valid              ( if_valid                 ),
		.if_thread_selected_id ( if_thread_selected_id    ),
		.if_pc_scheduled       ( if_pc_scheduled          ),
		.if_inst_scheduled     ( if_inst_scheduled        ),
		// To Control Register
		.if_current_pc         ( if_current_pc            ),
		// Thread controller stage interface
		.tc_data_out           ( tc_if_data_out           ),
		.tc_addr_update_cache  ( tc_if_addr_update_cache  ),
		.tc_valid_update_cache ( tc_if_valid_update_cache ),
		.tc_thread_en          ( tc_if_thread_en          ),
		.if_cache_miss         ( if_cache_miss            ),
		.if_thread_miss        ( if_thread_miss           ),
		.if_address_miss       ( if_address_miss          ),
		.tc_job_pc             ( tc_job_pc                ),
		.tc_job_thread_id      ( tc_job_thread_id         ),
		.tc_job_valid          ( tc_job_valid             )
	);

//  -----------------------------------------------------------------------
//  -- Decode
//  -----------------------------------------------------------------------

	decode u_decode (
		.clk                   ( clk                   ),
		.reset                 ( reset                 ),
		.enable                ( nfreeze               ),
		.if_valid              ( if_valid              ),
		.if_thread_selected_id ( if_thread_selected_id ),
		.if_pc_scheduled       ( if_pc_scheduled       ),
		.if_inst_scheduled     ( if_inst_scheduled     ),
		.rollback_valid        ( rollback_valid        ),
		.dec_valid             ( dec_valid             ),
		.dec_instr             ( dec_instr             )
	);

//  -----------------------------------------------------------------------
//  -- Instruction Buffer
//  -----------------------------------------------------------------------

	instruction_buffer # (
		.THREAD_FIFO_LENGTH ( `INSTRUCTION_FIFO_SIZE )
	)
	u_instruction_buffer (
		.clk                      ( clk                      ),
		.reset                    ( reset                    ),
		.enable                   ( nfreeze                  ),
		.dec_valid                ( dec_valid                ),
		.dec_instr                ( dec_instr                ),
		.l1d_full                 ( l1d_almost_full          ),
		.is_thread_scheduled_mask ( is_thread_scheduled_mask ),
		.rb_valid                 ( rollback_valid           ),
		.ib_fifo_full             ( ib_fifo_full             ),
		.ib_instructions_valid    ( ib_instructions_valid    ),
		.ib_instructions          ( ib_instructions          )
	);

//  -----------------------------------------------------------------------
//  -- Instruction Scheduler
//  -----------------------------------------------------------------------

	instruction_scheduler #(
		.TILE_ID( TILE_ID )
	)
	u_instruction_scheduler (
		.clk                      ( clk                      ),
		.reset                    ( reset                    ),
		.enable                   ( nfreeze                  ),
		.ib_instructions_valid    ( ib_instructions_valid    ),
		.ib_instructions          ( ib_instructions          ),
		.wb_valid                 ( wb_valid                 ),
		.wb_thread_id             ( wb_thread_id             ),
		.wb_result                ( wb_result                ),
		.wb_fifo_full             ( wb_fifo_full             ),
		.rb_valid                 ( rollback_valid           ),
		.rb_destination_mask      ( rollback_clear_bitmap    ),
		.dsu_stop_issue           ( dsu_stop_issue           ),
		.spm_can_issue            ( spm_can_issue            ),
		.is_instruction_valid     ( is_instruction_valid     ),
		.is_thread_id             ( is_thread_id             ),
		.is_instruction           ( is_instruction           ),
		.is_destination_mask      ( is_destination_mask      ),
		.scoreboard_empty         ( scoreboard_empty         ),
		.bc_release_val           ( bc_release_val           ),
		.is_thread_scheduled_mask ( is_thread_scheduled_mask )
	);

//  -----------------------------------------------------------------------
//  -- Operand Fetch
//  -----------------------------------------------------------------------

	operand_fetch u_operand_fetch (
		.clk                      ( clk                    ),
		.reset                    ( reset                  ),
		.enable                   ( nfreeze                ),
		.issue_valid              ( is_instruction_valid   ),
		.issue_thread_id          ( is_thread_id           ),
		.issue_inst_scheduled     ( is_instruction         ),
		.issue_destination_bitmap ( is_destination_mask    ),
		.rollback_valid           ( rollback_valid         ),
		.wb_valid                 ( wb_valid               ),
		.wb_thread_id             ( wb_thread_id           ),
		.wb_result                ( wb_result              ),
		//To Ex Pipes
		.opf_valid                ( opf_valid              ),
		.opf_inst_scheduled       ( opf_inst_scheduled     ),
		.opf_fetched_op0          ( opf_fetched_op0        ),
		.opf_fetched_op1          ( opf_fetched_op1        ),
		.opf_hw_lane_mask         ( opf_hw_lane_mask       ),
		.opf_destination_bitmap   ( opf_destination_bitmap ),
		// Coherency bit lookup
		.effective_address        ( effective_address      ),
		.uncoherent_area_hit      ( uncoherent_area_hit    )
	);

//  -----------------------------------------------------------------------
//  -- Ex Pipes
//  -----------------------------------------------------------------------

//  -----------------------------------------------------------------------
//  -- INT Pipe
//  -----------------------------------------------------------------------

	int_pipe #(
		.TILE_ID( TILE_ID )
	)
	u_int_pipe (
		.clk                ( clk                ),
		.reset              ( reset              ),
		.enable             ( nfreeze            ),
		//From Operand Fetch
		.opf_valid          ( opf_valid          ),
		.opf_inst_scheduled ( opf_inst_scheduled ),
		.opf_fetched_op0    ( opf_fetched_op0    ),
		.opf_fetched_op1    ( opf_fetched_op1    ),
		.opf_hw_lane_mask   ( opf_hw_lane_mask   ),
		// From Control Register
		.cr_result          ( cr_result          ),
		//To Writeback
		.int_valid          ( int_valid          ),
		.int_inst_scheduled ( int_inst_scheduled ),
		.int_result         ( int_result         ),
		.int_hw_lane_mask   ( int_hw_lane_mask   )
	);

//  -----------------------------------------------------------------------
//  -- Control Register
//  -----------------------------------------------------------------------

	control_register #(
		.TILE_ID_PAR( TILE_ID ),
		.CORE_ID_PAR( CORE_ID )
	)
	u_control_register (
		.clk                 ( clk                    ),
		.reset               ( reset                  ),
		.enable              ( nfreeze                ),
		// From Host Controller
		.hi_read_cr_valid    ( hi_read_cr_valid       ),
		.hi_read_cr_request  ( hi_read_cr_request     ),
		.hi_write_cr_valid   ( hi_write_cr_valid      ),
		.hi_write_cr_data    ( hi_write_cr_data       ),
		.cr_response         ( cr_response            ),
		// From Instruction Fetch
		.if_current_pc       ( if_current_pc          ),
		// From Barrier Core
		.bc_release_thread   ( bc_release_val         ),
		// From Thread Controller
		.tc_thread_en        ( tc_if_thread_en        ),
		.tc_inst_miss        ( tc_instr_request_valid ),
		// From Operand Fetch
		.opf_valid           ( opf_valid              ),
		.opf_inst_scheduled  ( opf_inst_scheduled     ),
		.opf_fetched_op0     ( opf_fetched_op0        ),
		.opf_fetched_op1     ( opf_fetched_op1        ),
		.effective_address   ( effective_address      ),
		// To Operand Fetch
		.uncoherent_area_hit ( uncoherent_area_hit    ),
		// From LDST
		.ldst_miss           ( l1d_miss               ),
		.ldst_almost_full    ( l1d_almost_full        ),
		// From Rollback Handler
		.rollback_trap_en    ( rollback_trap_en       ),
		.rollback_thread_id  ( rollback_thread_id     ),
		.rollback_trap_reason( rollback_trap_reason   ),
		// To Writeback
		.cr_result           ( cr_result              ),
		// Configuration signals
		.cr_ctrl_cache_wt    ( cr_ctrl_cache_wt       )
	);

//  -----------------------------------------------------------------------
//  -- Branch Control Pipe
//  -----------------------------------------------------------------------

	branch_control u_branch_control (
		//From Operand Fetch
		.opf_valid              ( opf_valid              ),
		.opf_inst_scheduled     ( opf_inst_scheduled     ),
		.opf_fetched_op0        ( opf_fetched_op0        ),
		.opf_fetched_op1        ( opf_fetched_op1        ),
		.opf_destination_bitmap ( opf_destination_bitmap ),

		//To Rollback Handler
		.bc_rollback_enable     ( bc_rollback_enable     ),
		.bc_rollback_valid      ( bc_rollback_valid      ),
		.bc_rollback_pc         ( bc_rollback_pc         ),
		.bc_rollback_thread_id  ( bc_rollback_thread_id  ),
		.bc_scoreboard          ( bc_scoreboard          )
	);

//  -----------------------------------------------------------------------
//  -- FPU Pipe
//  -----------------------------------------------------------------------

    generate
    if (FPU) begin : FPU_GEN
        fp_pipe #(
            .ADDER_FP_INST  ( 1 ),
            .MUL_FP_INST    ( 1 ),
            .DIV_FP_INST    ( 1 ),
            .FIX2FP_FP_INST ( 1 ),
            .FP2FIX_FP_INST ( 1 ),
            .ADDER_DP_INST  ( 0 ),
            .MUL_DP_INST    ( 0 ),
            .DIV_DP_INST    ( 0 ),
            .FIX2FP_DP_INST ( 0 ),
            .FP2FIX_DP_INST ( 0 )
        )
        u_fp_pipe (
            .clk               ( clk                ),
            .reset             ( reset              ),
            .enable            ( nfreeze            ),
            // To Writeback
            .fpu_fecthed_mask  ( fpu_fetched_mask   ),
            .fpu_inst_scheduled( fpu_inst_scheduled ),
            .fpu_result_sp     ( fpu_result_sp      ),
            .fpu_valid         ( fpu_valid          ),
            // From Operand Fetch
            .opf_fecthed_mask  ( opf_hw_lane_mask   ),
            .opf_fetched_op0   ( opf_fetched_op0    ),
            .opf_fetched_op1   ( opf_fetched_op1    ),
            .opf_inst_scheduled( opf_inst_scheduled ),
            .opf_valid         ( opf_valid          )
        );
        end
        else begin : NO_FPU_GEN
            assign fpu_valid          = 1'b0;
            assign fpu_inst_scheduled = instruction_decoded_t'(0);
            assign fpu_fetched_mask   = hw_lane_mask_t'(0);
            assign fpu_result_sp      = hw_lane_t'(0);
        end
    endgenerate

//  -----------------------------------------------------------------------
//  -- SFU Pipe
//  -----------------------------------------------------------------------

//  -----------------------------------------------------------------------
//  -- Load Store Unit
//  -----------------------------------------------------------------------
	load_store_unit u_load_store_unit (
		.clk                        ( clk                        ),
		.reset                      ( reset                      ),
		// Operand Fetch
		.opf_valid                  ( opf_valid                  ),
		.opf_inst_scheduled         ( opf_inst_scheduled         ),
		.opf_fecthed_op0            ( opf_fetched_op0            ),
		.opf_fecthed_op1            ( opf_fetched_op1            ),
		.opf_hw_lane_mask           ( opf_hw_lane_mask           ),
		.no_load_store_pending      ( no_load_store_pending      ),
		// Writeback and Cache Controller
		.ldst_valid                 ( l1d_valid                  ),
		.ldst_instruction           ( l1d_instruction            ),
		.ldst_cache_line            ( l1d_result                 ),
		.ldst_hw_lane_mask          ( l1d_hw_lane_mask           ),
		.ldst_store_mask            (                            ),
		.ldst_address               ( l1d_address                ),
		.ldst_dirty_mask            ( ldst_dirty_mask            ),
		.ldst_miss                  ( l1d_miss                   ),
		.ldst_evict                 ( ldst_evict                 ),
		.ldst_flush                 ( ldst_flush                 ),
		.ldst_dinv                  ( ldst_dinv                  ),
		.ci_flush_fifo_available    ( ci_flush_fifo_available    ),
		// Instruction Scheduler
		.ldst_almost_full           ( l1d_almost_full            ),
		// Cache Controller - Thread Wake-Up
		.cc_wakeup                  ( cc_wakeup                  ),
		.cc_wakeup_thread_id        ( cc_wakeup_thread_id        ),
		// Cache Controller - Update Bus
		.cc_update_ldst_valid       ( cc_update_ldst_valid       ),
		.cc_update_ldst_command     ( cc_update_ldst_command     ),
		.cc_update_ldst_way         ( cc_update_ldst_way         ),
		.cc_update_ldst_address     ( cc_update_ldst_address     ),
		.cc_update_ldst_privileges  ( cc_update_ldst_privileges  ),
		.cc_update_ldst_store_value ( cc_update_ldst_store_value ),
		// Cache Controller - Tag Snoop Bus
		.cc_snoop_tag_valid         ( cc_snoop_tag_valid         ),
		.cc_snoop_tag_set           ( cc_snoop_tag_set           ),
		.ldst_snoop_privileges      ( ldst_snoop_privileges      ),
		.ldst_snoop_tag             ( ldst_snoop_tag             ),
		// Cache Controller - Data Snoop Bus
		.cc_snoop_data_valid        ( cc_snoop_data_valid        ),
		.cc_snoop_data_set          ( cc_snoop_data_set          ),
		.cc_snoop_data_way          ( cc_snoop_data_way          ),
		.ldst_snoop_data            ( ldst_snoop_data            ),
		// Cache Controller - LRU Access Bus
		.ldst_lru_update_set        ( ldst_lru_update_set        ),
		// Cache Controller Stage 2 - LRU Update Bus
		.ldst_lru_update_en         ( ldst_lru_update_en         ),
		.ldst_lru_update_way        ( ldst_lru_update_way        ),
		// From Cache Controller - IO Map interface
		.io_intf_available          ( io_intf_available          ),
		// To Cache Controller - IO Map interface
		.ldst_io_valid              ( ldst_io_valid              ),
		.ldst_io_thread             ( ldst_io_thread             ),
		.ldst_io_operation          ( ldst_io_operation          ),
		.ldst_io_address            ( ldst_io_address            ),
		.ldst_io_data               ( ldst_io_data               ),
		.io_intf_resp_valid         ( io_intf_resp_valid         ),
		.io_intf_wakeup_thread      ( io_intf_wakeup_thread      ),
		.io_intf_resp_data          ( io_intf_resp_data          ),
		.ldst_io_resp_consumed      ( ldst_io_resp_consumed      ),
		// Rollback Handler
		.rollback_valid             ( rollback_valid             ),
		.ldst_rollback_en           ( l1d_rollback_en            ),
		.ldst_rollback_pc           ( l1d_rollback_pc            ),
		.ldst_rollback_thread_id    ( l1d_rollback_thread_id     ),
		// Configuration signal
		.cr_ctrl_cache_wt           ( cr_ctrl_cache_wt           )
	);

    always_comb begin : L1D_SIGNAL_DEF
        ldst_instruction = l1d_instruction;
        ldst_address     = l1d_address;
        ldst_miss        = l1d_miss;
        ldst_cache_line  = l1d_result;
    end

//  -----------------------------------------------------------------------
//  -- Scratchpad Memory
//  -----------------------------------------------------------------------

    generate 
        if (SCRATCHPAD) begin : SCRATCH_GEN
            scratchpad_memory_pipe u_scratchpad_memory_pipe (
                .clk                    ( clk                    ),
                .reset                  ( reset                  ),

                //From Operand Fetch
                .opf_valid              ( opf_valid              ),
                .opf_inst_scheduled     ( opf_inst_scheduled     ),
                .opf_fetched_op0        ( opf_fetched_op0        ),
                .opf_fetched_op1        ( opf_fetched_op1        ),
                .opf_hw_lane_mask       ( opf_hw_lane_mask       ),

                //To Writeback
                .spm_valid              ( spm_valid              ),
                .spm_inst_scheduled     ( spm_inst_scheduled     ),
                .spm_result             ( spm_result             ),
                .spm_hw_lane_mask       ( spm_hw_lane_mask       ),

                //To Dynamic Scheduler
                .spm_can_issue          ( spm_can_issue          ),

                //To RollbackController
                .spm_rollback_en        ( spm_rollback_en        ),
                .spm_rollback_pc        ( spm_rollback_pc        ),
                .spm_rollback_thread_id ( spm_rollback_thread_id )
            );
        end
        else begin : NO_SCRATCH_GEN
            assign spm_valid              = 1'b0;
            assign spm_result             = hw_lane_t'(0);
            assign spm_inst_scheduled     = instruction_decoded_t'(0);
            assign smp_pwr_o              = {25{1'b0}};
            assign spm_hw_lane_mask       = hw_lane_mask_t'(0);
            assign spm_can_issue          = 1'b1;
            assign spm_rollback_en        = 1'b0;
            assign spm_rollback_pc        = register_t'(0);
            assign spm_rollback_thread_id = thread_id_t'(0);
        end
    endgenerate

//  -----------------------------------------------------------------------
//  -- Rollback Handler
//  -----------------------------------------------------------------------

	rollback_handler u_rollback_handler (
		.clk                    ( clk                    ),
		.reset                  ( reset                  ),
		.enable                 ( 1'b1                   ),
		.is_instruction_valid   ( is_instruction_valid   ),
		.is_thread_id           ( is_thread_id           ),
		.is_destination_mask    ( is_destination_mask    ),
		.bc_scoreboard          ( bc_scoreboard          ),
		.bc_rollback_enable     ( bc_rollback_enable     ),
		.bc_rollback_valid      ( bc_rollback_valid      ),
		.bc_rollback_pc         ( bc_rollback_pc         ),
		.bc_rollback_thread_id  ( bc_rollback_thread_id  ),
		// From SPM
		.spm_rollback_en        ( spm_rollback_en        ),
		.spm_rollback_pc        ( spm_rollback_pc        ),
		.spm_rollback_thread_id ( spm_rollback_thread_id ),
		// From LDST
		.l1d_rollback_en        ( l1d_rollback_en        ),
		.l1d_rollback_pc        ( l1d_rollback_pc        ),
		.l1d_rollback_thread_id ( l1d_rollback_thread_id ),
		// To Control Register
		.rollback_trap_en       ( rollback_trap_en       ),
		.rollback_thread_id     ( rollback_thread_id     ),
		.rollback_trap_reason   ( rollback_trap_reason   ),
		.rollback_pc_value      ( rollback_pc_value      ),
		.rollback_valid         ( rollback_valid         ),
		.rollback_clear_bitmap  ( rollback_clear_bitmap  )
	);

//  -----------------------------------------------------------------------
//  -- WriteBack
//  -----------------------------------------------------------------------

	writeback #(
		.TILE_ID( TILE_ID )
	)
	u_writeback (
		.clk                 ( clk                ),
		.reset               ( reset              ),
		.enable              ( 1'b1               ),
		//From FP Ex Pipe
		.fp_valid            ( fpu_valid          ),
		.fp_inst_scheduled   ( fpu_inst_scheduled ),
		.fp_result           ( fpu_result_sp      ),
		.fp_mask_reg         ( fpu_fetched_mask   ),

		//From INT Ex Pipe
		.int_valid           ( int_valid          ),
		.int_inst_scheduled  ( int_inst_scheduled ),
		.int_result          ( int_result         ),
		.int_hw_lane_mask    ( int_hw_lane_mask   ),

		//From Scrathpad Memory Pipe
		.spm_valid           ( spm_valid          ),
		.spm_inst_scheduled  ( spm_inst_scheduled ),
		.spm_result          ( spm_result         ),
		.spm_hw_lane_mask    ( spm_hw_lane_mask   ),

		//From Cache L1 Pipe
		.ldst_valid          ( l1d_valid          ),
		.ldst_inst_scheduled ( l1d_instruction    ),
		.ldst_result         ( l1d_result         ),
		.ldst_hw_lane_mask   ( l1d_hw_lane_mask   ),
		.ldst_address        ( l1d_address        ),
		//To Operand Fetch
		.wb_valid            ( wb_valid           ),
		.wb_thread_id        ( wb_thread_id       ),
		.wb_result           ( wb_result          ),

		//TO Dynamic Scheduler
		.wb_fifo_full        ( wb_fifo_full       )
	);

//  -----------------------------------------------------------------------
//  -- Debug Support Unit
//  -----------------------------------------------------------------------

	generate 
        if ( DSU ) begin : DSU_GEN
			debug_controller u_debug_controller (
				.clk                   ( clk                   ),
				.reset                 ( reset                 ),
				.resume                ( resume                ),
				.ext_freeze            ( ext_freeze            ),
				.dsu_enable            ( dsu_enable            ),
				.dsu_single_step       ( dsu_single_step       ),
				.dsu_breakpoint        ( dsu_breakpoint        ),
				.dsu_breakpoint_enable ( dsu_breakpoint_enable ),
				.dsu_thread_selection  ( dsu_thread_selection  ),
				.dsu_thread_id         ( dsu_thread_id         ),
				//From Instruction Scheduler
				.is_instruction_valid  ( is_instruction_valid  ),
				.is_instruction        ( is_instruction        ),
				.is_thread_id          ( is_thread_id          ),
				.scoreboard_empty      ( scoreboard_empty      ),
				//From LDST
				.no_load_store_pending ( no_load_store_pending ),
				//From Rollback Handler
				.rollback_valid        ( rollback_valid        ),
				.dsu_bp_instruction    ( dsu_bp_instruction    ),
				.dsu_bp_thread_id      ( dsu_bp_thread_id      ),
				.dsu_hit_breakpoint    ( dsu_hit_breakpoint    ),
				//From SX stage
				.dsu_stop_issue        ( dsu_stop_issue        ),
				.freeze                ( freeze                )
			);
        end
		else begin : NO_DSU_GEN
			assign freeze             = 1'b0;
			assign dsu_bp_instruction = 0;
			assign dsu_bp_thread_id   = 0;
			assign dsu_serial_reg_out = 1'b0;
			assign dsu_stop_shift     = 1'b0;
			assign dsu_hit_breakpoint = 1'b0;
			assign dsu_stop_issue     = {`THREAD_NUMB{1'b0}};
		end
	endgenerate

	barrier_core #(
		.TILE_ID        ( TILE_ID        ),
		.MANYCORE       ( MANYCORE       ),
		.DIS_SYNCMASTER ( DIS_SYNCMASTER )
	)
	u_barrier_core (
		.clk                           ( clk                            ),
		.reset                         ( reset                          ),
		//Operand Fetch
		.opf_valid                     ( opf_valid                      ),
		.opf_inst_scheduled            ( opf_inst_scheduled             ),
		//To ThreadScheduler
		.bc_release_val                ( bc_release_val                 ),
		.scoreboard_empty              ( scoreboard_empty               ),
		//Id_Barrier
		.opf_fetched_op0               ( opf_fetched_op0                ),
		//Destination Barrier
		.opf_fetched_op1               ( opf_fetched_op1                ),

		//to Network Interface
		.c2n_account_destination_valid ( bc2n_account_destination_valid ),
		.c2n_account_valid             ( bc2n_account_valid             ),
		.c2n_account_message           ( bc2n_account_message           ),
		.network_available             ( n2bc_network_available         ),
		//From Network Interface
		.n2c_release_message           ( n2bc_release_message           ),
		.n2c_release_valid             ( n2bc_release_valid             ),
		.n2c_mes_service_consumed      ( n2bc_mes_service_consumed      ),

		//Load Store Unit
		.no_load_store_pending         ( no_load_store_pending          )
	);

endmodule
