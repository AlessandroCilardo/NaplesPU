`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"

`ifdef DISPLAY_COHERENCE
`include "npu_debug_log.sv"
`endif

/*
 * This stage selects a pending request from the stage 1 pool, then it fetches tags and privileges from the tag cache.
 *
 * It receives from the previous stage the load/store requests and the recycle request for each thread, the recycling has an
 * higher priority over normal thread requests.
 * An arbiter selects a request from pending ones and it performs the scheduled operation, such as tags and privileges read/update.
 * The Cache Controller has a separate read port which helps during snooping operations.
 *
 * The Cache Controller manages and updates tags and privileges through the cc_update private channel. In particular, the
 * Cache Controller through this bus sends commands in order to manage and update the information in this and the next
 * stages. An incoming request from the Cache Controller has the highest priority and it is always scheduled by the arbiter.
 * The Cache Controller can send three type of commands:
 *  1 - When an UPDATE_INFO occurs, this stage updates info (namely tags and privileges) and nothing is propagated to the next stage.
 *  2 - When an UPDATE_INFO_DATA command is send by Cache Controller, the current stage has to update info, using
 *      index, tag and privileges forwarded by Cache Controller. Furthermore, This stage forwards these information
 *      and the store_value to the next stage.
 *  3 - Finally, when an EVICT occurs the next stage requires the evicted tag and the new index to build up the evicted line address.
 *
 * If the scheduled request targets the IO memory space, it is dequeued when the Cache Controller is available to receive a memory request
 * to that memory space. These kind of requests are not cached and are directly forwarded to the Cache Controller. When the data are back
 * from the IO memory space, the Cache Controller forwards the response to this stage through the updated channel, as a normal load
 * request, although cc_update_is_io_memspace signal prevents tags and privileges update when asserted. These information and data are
 * forwarded to the next stage along with ldst2_io_memspace bit asserted, and then all the way back to the Writeback unit.
 *
 */

module load_store_unit_stage2_par #(
    	parameter TILE_ID      = 0,
        parameter THREAD_NUMB  = 8,
        parameter THREAD_IDX_W = $clog2(THREAD_NUMB),
        parameter L1_WAY_NUMB  = 4, 
        parameter L1_SET_NUMB  = 32
    ) 
    (
		input                                               clk,
		input                                               reset,

		// Load Sore Unit Stage 1
		input  logic [THREAD_NUMB - 1 : 0]                  ldst1_valid,
		input  instruction_decoded_t [THREAD_NUMB - 1 : 0]  ldst1_instruction,
		input  dcache_address_t      [THREAD_NUMB - 1 : 0]  ldst1_address,
		input  dcache_line_t         [THREAD_NUMB - 1 : 0]  ldst1_store_value,
		input  dcache_store_mask_t   [THREAD_NUMB - 1 : 0]  ldst1_store_mask,
		input  hw_lane_mask_t        [THREAD_NUMB - 1 : 0]  ldst1_hw_lane_mask,

		input  logic [THREAD_NUMB - 1 : 0]                  ldst1_recycle_valid,
		input  instruction_decoded_t [THREAD_NUMB - 1 : 0]  ldst1_recycle_instruction,
		input  dcache_address_t      [THREAD_NUMB - 1 : 0]  ldst1_recycle_address,
		input  dcache_line_t         [THREAD_NUMB - 1 : 0]  ldst1_recycle_store_value,
		input  dcache_store_mask_t   [THREAD_NUMB - 1 : 0]  ldst1_recycle_store_mask,
		input  hw_lane_mask_t        [THREAD_NUMB - 1 : 0]  ldst1_recycle_hw_lane_mask,

		output logic [THREAD_NUMB - 1 : 0]                  ldst2_dequeue_instruction,
		output logic [THREAD_NUMB - 1 : 0]                  ldst2_recycled,

		// Load Sore Unit Stage 3
		input  logic [THREAD_NUMB - 1 : 0]                  ldst3_thread_sleep,

		input  logic                                        ldst3_update_dirty_mask_valid,
		input  logic [$clog2(L1_SET_NUMB) - 1 : 0]          ldst3_update_dirty_mask_set,
		input  logic [$clog2(L1_WAY_NUMB) - 1 : 0]          ldst3_update_dirty_mask_way,
		input  dcache_store_mask_t                          ldst3_update_dirty_mask,

		output logic                                        ldst2_valid,
		output instruction_decoded_t                        ldst2_instruction,
		output dcache_address_t                             ldst2_address,
		output dcache_line_t                                ldst2_store_value,
		output dcache_store_mask_t                          ldst2_store_mask,
		output dcache_store_mask_t   [L1_WAY_NUMB - 1 : 0]  ldst2_dirty_mask,
		output hw_lane_mask_t                               ldst2_hw_lane_mask,
		output dcache_tag_t          [L1_WAY_NUMB - 1 : 0]  ldst2_tag_read,
		output dcache_privileges_t   [L1_WAY_NUMB - 1 : 0]  ldst2_privileges_read,
		output logic                                        ldst2_is_flush,
		output logic                                        ldst2_is_dinv,
		output logic                                        ldst2_io_memspace,
		output logic                                        ldst2_io_memspace_has_data,

		output logic                                        ldst2_update_data_valid,
		output logic                                        ldst2_update_info_valid,
		output logic [$clog2(L1_WAY_NUMB) - 1 : 0]          ldst2_update_way,
		output logic                                        ldst2_evict_valid,

		// From Cache Controller - IO Map interface
		input  logic                                        io_intf_available,
		// From Cache Controller - Flush FIFO availability
		input  logic                                        ci_flush_fifo_available,

		// To Cache Controller - IO Map interface
		input  logic                                        io_intf_resp_valid,
		input  logic [THREAD_IDX_W - 1 : 0]                 io_intf_wakeup_thread,
		input  register_t                                   io_intf_resp_data,
		output logic                                        ldst2_io_resp_consumed,

		// Synch Core
		output logic [THREAD_NUMB - 1 : 0]                  s2_no_ls_pending,

		// Cache Controller
		input                                               cc_update_ldst_valid,
		input  cc_command_t                                 cc_update_ldst_command,
		input  logic [$clog2(L1_WAY_NUMB) - 1 : 0]          cc_update_ldst_way,
		input  dcache_address_t                             cc_update_ldst_address,
		input  dcache_privileges_t                          cc_update_ldst_privileges,
		input  dcache_line_t                                cc_update_ldst_store_value,

		input                                               cc_snoop_tag_valid,
		input  logic [$clog2(L1_SET_NUMB) - 1 : 0]          cc_snoop_tag_set,
		input  logic                                        cc_wakeup,
		input  logic [THREAD_IDX_W - 1 : 0]                 cc_wakeup_thread_id,
		output dcache_privileges_t   [L1_WAY_NUMB - 1 : 0]  ldst2_snoop_privileges,
		output dcache_tag_t          [L1_WAY_NUMB - 1 : 0]  ldst2_snoop_tag,
		input  logic                                        cr_ctrl_cache_wt
	);

//  -----------------------------------------------------------------------
//  -- Load Store Unit 2 - Signals
//  -----------------------------------------------------------------------
	logic                                             ldst1_request_valid;
	logic [THREAD_NUMB - 1 : 0]                       ldst1_fifo_requestor;
	logic [THREAD_NUMB - 1 : 0]                       ldst1_fifo_winner;
	logic [$clog2( THREAD_NUMB ) - 1 : 0]             ldst1_fifo_winner_id;
	logic                                             ldst1_fifo_is_flush;
	logic                                             ldst1_fifo_is_dinv;
	logic [THREAD_NUMB - 1 : 0]                       ldst1_fifo_is_io_memspace;
	logic [THREAD_NUMB - 1 : 0]                       ldst1_fifo_is_io_memspace_dequeue_condition;
	logic [THREAD_NUMB - 1 : 0]                       flush_stall_condition;

	logic                                             cc_command_is_evict;
	logic                                             cc_command_is_update_data;
	logic                                             cc_command_is_update_info;
	logic [L1_WAY_NUMB - 1 : 0]                       cc_not_update;

	dcache_request_t                                  ldst1_fifo_request;
	dcache_request_t                                  cc_update_request;
	dcache_request_t                                  next_request;

	logic                                             tag_sram_read1_enable;
	logic [$clog2(L1_SET_NUMB) - 1 : 0]               tag_sram_read1_address;
	dcache_tag_t [L1_WAY_NUMB - 1 : 0]                tag_sram_read1_data;

	logic                                             tag_sram_read2_enable;
	logic [$clog2(L1_SET_NUMB) - 1 : 0]               tag_sram_read2_address;
	dcache_tag_t [L1_WAY_NUMB - 1 : 0]                tag_sram_read2_data;

	logic [L1_WAY_NUMB - 1 : 0]                       tag_sram_write_enable;
	logic [$clog2(L1_SET_NUMB) - 1 : 0]               tag_sram_write_address;
	dcache_tag_t                                      tag_sram_write_data;

	logic [THREAD_NUMB - 1 : 0]                       sleeping_thread_mask;
	logic [THREAD_NUMB - 1 : 0]                       sleeping_thread_mask_next;

	logic [THREAD_NUMB - 1 : 0]                       thread_wakeup_oh;
	logic [THREAD_NUMB - 1 : 0]                       thread_wakeup_mask;

	logic            [L1_WAY_NUMB - 1 : 0]            dirty_mask_sram_write_enable;

	logic [THREAD_NUMB - 1 : 0]                       io_thread_wakeup_oh;

//  -----------------------------------------------------------------------
//  -- Load Store Unit 2 - Arbiter
//  -----------------------------------------------------------------------

	// The Cache Controller has the highest priority when it wants to update
	// tag and data caches
	assign ldst1_request_valid       = |ldst1_fifo_requestor;
	assign ldst1_fifo_requestor      = ( ldst1_valid | ldst1_recycle_valid ) & {THREAD_NUMB{~cc_update_ldst_valid}} & ~sleeping_thread_mask_next & ~flush_stall_condition & ldst1_fifo_is_io_memspace_dequeue_condition;
	assign sleeping_thread_mask_next = ( sleeping_thread_mask | ldst3_thread_sleep ) & ( ~thread_wakeup_mask );
	assign thread_wakeup_mask        = ( thread_wakeup_oh & {THREAD_NUMB{cc_wakeup}} ) | ( io_thread_wakeup_oh & {THREAD_NUMB{io_intf_resp_valid}} );

	// The Cache Controller can send four type of command.
	// If a UPDATE_INFO occurs, this stage updates info (namely tags and privileges) and nothing is propagated to the next stage.
	// If a UPDATE_INFO_DATA command is send by Cache Controller, the current stage has to update info, using
	// index, tag and privileges forwarded by Cache Controller. Furthermore, This stage must forward those information
	// and the store_value to the data cache stage.
	// If an EVICT occurs the next stage requires the evicted tag and the new index to build up the evicted line address.
	assign cc_command_is_update_data                   = cc_update_ldst_valid & ( cc_update_ldst_command == CC_UPDATE_INFO_DATA | cc_update_ldst_command == CC_REPLACEMENT );
	assign cc_command_is_update_info                   = cc_update_ldst_valid & ( cc_update_ldst_command == CC_UPDATE_INFO );
	assign cc_command_is_evict                         = cc_update_ldst_valid & ( cc_update_ldst_command == CC_REPLACEMENT );

	// RR arbiter selects which request from Load Store Unit 1 can access
	// tag and data caches
	rr_arbiter
	#(
		.NUM_REQUESTERS( THREAD_NUMB )
	)
	rr_arbiter
	(
		.clk       ( clk                  ),
		.grant_oh  ( ldst1_fifo_winner    ),
		.request   ( ldst1_fifo_requestor ),
		.reset     ( reset                ),
		.update_lru( ldst1_request_valid  )
	);

	oh_to_idx
	#(
		.NUM_SIGNALS( THREAD_NUMB ),
		.DIRECTION  ( "LSB0"       )
	)
	oh_to_idx
	(
		.index  ( ldst1_fifo_winner_id ),
		.one_hot( ldst1_fifo_winner    )
	);

	idx_to_oh
	#(
		.NUM_SIGNALS( THREAD_NUMB ),
		.DIRECTION  ( "LSB0"       )
	)
	u_idx_to_oh
	(
		.one_hot( thread_wakeup_oh    ),
		.index  ( cc_wakeup_thread_id )
	);

	idx_to_oh
	#(
		.NUM_SIGNALS( THREAD_NUMB ),
		.DIRECTION  ( "LSB0"       )
	)
	u_io_idx_to_oh
	(
		.one_hot( io_thread_wakeup_oh   ),
		.index  ( io_intf_wakeup_thread )
	);

	always_comb begin : REQUEST_WINNER_SELECTOR
		if ( ldst1_recycle_valid[ldst1_fifo_winner_id] ) begin
			ldst1_fifo_request.instruction  = ldst1_recycle_instruction[ldst1_fifo_winner_id];
			ldst1_fifo_request.address      = ldst1_recycle_address[ldst1_fifo_winner_id];

			if ( ldst1_fifo_is_io_memspace[ldst1_fifo_winner_id] )
				ldst1_fifo_request.store_value = {{$bits(dcache_line_t) / $bits(register_t)}{io_intf_resp_data}};
			else
				ldst1_fifo_request.store_value = ldst1_recycle_store_value[ldst1_fifo_winner_id];

			ldst1_fifo_request.store_mask   = ldst1_recycle_store_mask[ldst1_fifo_winner_id];
			ldst1_fifo_request.hw_lane_mask = ldst1_recycle_hw_lane_mask[ldst1_fifo_winner_id];
		end else begin
			ldst1_fifo_request.instruction  = ldst1_instruction[ldst1_fifo_winner_id];
			ldst1_fifo_request.address      = ldst1_address[ldst1_fifo_winner_id];
			ldst1_fifo_request.store_value  = ldst1_store_value[ldst1_fifo_winner_id];
			ldst1_fifo_request.store_mask   = ldst1_store_mask[ldst1_fifo_winner_id];
			ldst1_fifo_request.hw_lane_mask = ldst1_hw_lane_mask[ldst1_fifo_winner_id];
		end

		cc_update_request.address      = cc_update_ldst_address;
		cc_update_request.store_value  = cc_update_ldst_store_value;
		cc_update_request.store_mask   = {$bits( dcache_store_mask_t ){1'b0}};

	end

	// If the memory instruction has a register destination it is a load, otherwise the
	// memory instruction is a store
	assign ldst1_fifo_is_flush                         = ldst1_request_valid & ldst1_fifo_request.instruction.is_control &
		ldst1_fifo_request.instruction.op_code.contr_opcode == FLUSH;

	genvar thread_id;
	generate
		for (thread_id = 0; thread_id < THREAD_NUMB; thread_id++) begin : FLUSH_STALL_CONDITION
			assign flush_stall_condition[thread_id]        = ((ldst1_recycle_valid[thread_id] & ((ldst1_recycle_instruction[thread_id].is_control & (ldst1_recycle_instruction[thread_id].op_code.contr_opcode == FLUSH)) | (~ldst1_recycle_instruction[thread_id].is_load & cr_ctrl_cache_wt))) | (~ldst1_recycle_valid[thread_id] & ldst1_valid[thread_id] & ((ldst1_instruction[thread_id].is_control & (ldst1_instruction[thread_id].op_code.contr_opcode == FLUSH)) | (~ldst1_instruction[thread_id].is_load & cr_ctrl_cache_wt)))) & ~ci_flush_fifo_available;
		end
	endgenerate

	assign ldst1_fifo_is_dinv                          = ldst1_request_valid & ldst1_fifo_request.instruction.is_control &
		ldst1_fifo_request.instruction.op_code.contr_opcode == DCACHE_INV;

//  --------------------------------------------------------------------------------------------------------------------------
//  -- IO Map
//  --------------------------------------------------------------------------------------------------------------------------
	localparam IOM_BASE_ADDR  = `IO_MAP_BASE_ADDR;
	localparam IOM_SIZE       = `IO_MAP_SIZE;

	always_comb begin
		for ( integer i = 0; i < THREAD_NUMB; i++) begin
			if (ldst1_recycle_valid[i]) begin
				ldst1_fifo_is_io_memspace[i]                   = ldst1_recycle_address[i] >= IOM_BASE_ADDR & ldst1_recycle_address[i] <= ( IOM_BASE_ADDR + IOM_SIZE );
				ldst1_fifo_is_io_memspace_dequeue_condition[i] = ( ldst1_fifo_is_io_memspace[i] ) ? ( io_intf_resp_valid & io_intf_wakeup_thread == thread_id_t'(i) ) : 1'b1;
			end else begin
				// controlla su ldst1_address
				ldst1_fifo_is_io_memspace[i]                   = ldst1_valid[i] & ( ldst1_address[i] >= IOM_BASE_ADDR & ldst1_address[i] <= ( IOM_BASE_ADDR + IOM_SIZE ) );
				ldst1_fifo_is_io_memspace_dequeue_condition[i] = ( ldst1_fifo_is_io_memspace[i] ) ? io_intf_available : 1'b1;
			end
		end
	end

//  -----------------------------------------------------------------------
//  -- Load Store Unit 2 - Tag and Privileges
//  -----------------------------------------------------------------------

	// The next stage needs the updated tag in case of EVICT,
	// hence it is forwarded reading it on the first port.
	//assign tag_sram_read1_enable     = ( ldst1_request_valid & ldst1_fifo_is_read ) | cc_update_ldst_valid;
	assign tag_sram_read1_enable                       = ldst1_request_valid | cc_update_ldst_valid;
	assign tag_sram_read1_address                      = ( cc_update_ldst_valid ) ? cc_update_ldst_address.index : ldst1_fifo_request.address.index;

	// Cache controller request valid enables the dedicated read port. If the cache
	// controller update flag is high, the CC accesses to the write port
	assign tag_sram_read2_enable                       = cc_snoop_tag_valid;
	assign tag_sram_read2_address                      = cc_snoop_tag_set;

	assign ldst2_snoop_tag                             = tag_sram_read2_data;

	assign tag_sram_write_data                         = cc_update_ldst_address.tag;
	assign tag_sram_write_address                      = cc_update_ldst_address.index;

	genvar                                            dcache_way;
	generate
		for ( dcache_way = 0; dcache_way < L1_WAY_NUMB; dcache_way++ ) begin : TAG_WAY_ALLOCATOR
			/*   Privileges SRAM    */
			// Only the cache controller (or Protocol FSM) can change these status bits
			dcache_privileges_t [`DCACHE_SET - 1 : 0] dcache_privileges;

			/*   TAG SRAM    */
			memory_bank_2r1w #
			(
				.COL_WIDTH    ( `DCACHE_TAG_LENGTH ),
				.NB_COL       ( 1                  ),
				.SIZE         ( `DCACHE_SET        ),
				.WRITE_FIRST1 ( "FALSE"            ),
				.WRITE_FIRST2 ( "TRUE"             )
			)
			tag_sram (
				.clock        ( clk                               ),
				.read1_address( tag_sram_read1_address            ),
				.read1_data   ( tag_sram_read1_data[dcache_way]   ),
				.read1_enable ( tag_sram_read1_enable             ),
				.read2_address( tag_sram_read2_address            ),
				.read2_data   ( tag_sram_read2_data[dcache_way]   ),
				.read2_enable ( tag_sram_read2_enable             ),
				.write_address( tag_sram_write_address            ),
				.write_data   ( tag_sram_write_data               ),
				.write_enable ( tag_sram_write_enable[dcache_way] )
			);

			assign tag_sram_write_enable[dcache_way] = cc_update_ldst_valid & cc_update_ldst_way == L1_WAY_NUMB'( dcache_way );

			// In case of update from CC, the new tag is stored in SRAM and bypassed to the next stage.
			// The module memory_bank_2r1w has a builtin bypass mechanism.
			assign ldst2_tag_read[dcache_way]        = tag_sram_read1_data[dcache_way];

			/* DIRTY MASK SRAM */

			memory_bank_1r1w #
			(
				.COL_WIDTH     ( $bits(dcache_store_mask_t) ),
				.NB_COL        ( 1                          ),
				.SIZE          ( `DCACHE_SET                ),
				.WRITE_FIRST   ( "TRUE"                     )
			)
			dirty_mask_sram (
				.clock         ( clk                                      ),
				.read_address  ( tag_sram_read1_address                   ),
				.read_data     ( ldst2_dirty_mask[dcache_way]             ),
				.read_enable   ( tag_sram_read1_enable                    ),
				.write_address ( ldst3_update_dirty_mask_set              ),
				.write_data    ( ldst3_update_dirty_mask                  ),
				.write_enable  ( dirty_mask_sram_write_enable[dcache_way] )
			);

			assign dirty_mask_sram_write_enable[dcache_way] = ldst3_update_dirty_mask_valid & ldst3_update_dirty_mask_way == L1_WAY_NUMB'( dcache_way );

			always_ff @ ( posedge clk, posedge reset )
				if ( reset ) begin
					dcache_privileges <= 0;
				end else begin
					// In case of update from Cache Controller, new privileges are stored and
					// bypassed to the next stage
					if ( tag_sram_write_enable[dcache_way] ) begin
						dcache_privileges[tag_sram_write_address] <= cc_update_ldst_privileges;
					end

					if ( tag_sram_read1_enable ) begin
						// Privileges should not be handled in a write-first hasion, as
						// port 1 of the tag sram is not write first
						ldst2_privileges_read[dcache_way]  <= dcache_privileges[tag_sram_read1_address];
					end

					if ( tag_sram_read2_enable ) begin
						if ( tag_sram_write_enable[dcache_way] && tag_sram_write_address == tag_sram_read2_address ) begin
							ldst2_snoop_privileges[dcache_way]     <= cc_update_ldst_privileges;
						end else begin
							ldst2_snoop_privileges[dcache_way]  <= dcache_privileges[tag_sram_read2_address];
						end
					end
				end

`ifdef DISPLAY_COHERENCE
			always_ff @ ( posedge clk, posedge reset ) begin
				if ( tag_sram_write_enable[dcache_way] ) begin
					dcache_address_t block_addr;

					block_addr = cc_update_ldst_address;
					block_addr.offset = 0;

					$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Load Store Unit - [Time %.16d] [TILE %.2h] - Updating Privileges", $time( ), TILE_ID );
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Address   : %08h (block %08h)", cc_update_ldst_address, block_addr );
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Tag       : %h", tag_sram_write_data );
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Set       : %h", tag_sram_write_address );
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Way       : %h", dcache_way );
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Can Read  : %d", cc_update_ldst_privileges.can_read );
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Can Write : %d", cc_update_ldst_privileges.can_write );

					$fflush( `DISPLAY_COHERENCE_VAR );
				end
			end
`endif

		end
	endgenerate

	// A request coming from Cache Controller has the highest priority. If cc_update_ldst_valid is high, the
	// request is served and bypassed to the next stage
	assign next_request                                = ( cc_update_ldst_valid ) ? cc_update_request            : ldst1_fifo_request;

	always_comb begin
		ldst2_dequeue_instruction = ldst1_fifo_winner & {THREAD_NUMB{~cc_update_ldst_valid}} & ~ldst1_recycle_valid;
		ldst2_recycled            = ldst1_fifo_winner & {THREAD_NUMB{~cc_update_ldst_valid}} & ldst1_recycle_valid;

		ldst2_io_resp_consumed    = ldst1_recycle_valid[ldst1_fifo_winner_id] & ldst1_fifo_is_io_memspace[ldst1_fifo_winner_id] & ldst1_fifo_is_io_memspace_dequeue_condition[ldst1_fifo_winner_id];
	end

	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			ldst2_valid                <= 1'b0;
			ldst2_evict_valid          <= 1'b0;
			ldst2_update_data_valid    <= 1'b0;
			ldst2_update_info_valid    <= 1'b0;
			sleeping_thread_mask       <= {THREAD_NUMB{1'b0}};
			ldst2_io_memspace          <= 1'b0;
			ldst2_io_memspace_has_data <= 1'b0;
		end else begin
			ldst2_io_memspace          <= ldst1_fifo_is_io_memspace[ldst1_fifo_winner_id];
			ldst2_io_memspace_has_data <= ldst1_recycle_valid[ldst1_fifo_winner_id] & ldst1_fifo_is_io_memspace[ldst1_fifo_winner_id];
			ldst2_valid                <= ldst1_request_valid;
			ldst2_evict_valid          <= cc_command_is_evict;
			ldst2_update_data_valid    <= cc_command_is_update_data;
			ldst2_update_info_valid    <= cc_command_is_update_info;
			sleeping_thread_mask       <= sleeping_thread_mask_next;
		end

	always_ff @ ( posedge clk ) begin
		ldst2_instruction  <= next_request.instruction;
		ldst2_address      <= next_request.address;
		ldst2_store_value  <= next_request.store_value;
		ldst2_store_mask   <= next_request.store_mask;
		ldst2_hw_lane_mask <= next_request.hw_lane_mask;
		ldst2_update_way   <= cc_update_ldst_way;
		ldst2_is_flush     <= ldst1_fifo_is_flush;
		ldst2_is_dinv      <= ldst1_fifo_is_dinv;
	end

	// Checking if there are no load/store pending running in the 2nd stage
	assign s2_no_ls_pending                            = ~ldst1_fifo_requestor;

`ifdef SIMULATION
	always_ff @( posedge clk )
		if ( !reset )
			assert( |( ldst3_thread_sleep & thread_wakeup_mask ) == 1'b0 ) else $fatal("Cannot wakeup a thread that is not suspended");
`endif

endmodule
