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
`include "npu_debug_log.sv"

/* The final stage handles data caches and sends load request to the Writeback unit when fulfilled. It receives
 * tags and privileges information from the previous stage, and checks if a cache hit or miss occurs for the
 * current request. In case of cache misses, this module forwarded miss requests to the Cache Controller
 * asserting the ldst3_miss bit. The Cache Controller retrieves address information from the ldst3_address
 * output signal. Furthermore, when a miss occurs, this module freezes the requesting thread until the data
 * is retrieved from the main memory and the thread is waken up by the Cache Controller.
 *
 * As in the previous stage, this module has to fulfill Cache Controller commands forwarded by the previous stage.
 * When a UPDATE_INFO_DATA is propagated from the stage 2, this unit updates the respective value in data Cache.
 *
 * Furthermore, either in case of eviction or flush requests this stage fetches data and passes it to the Cache
 * Controller which sends it back to the main memory.
 *
 */

module load_store_unit_stage3_par #(
		parameter TILE_ID      = 0, 
        parameter THREAD_NUMB  = 8,
        parameter THREAD_IDX_W = $clog2(THREAD_NUMB),
        parameter L1_WAY_NUMB  = 4,
        parameter L1_SET_NUMB  = 32
    )
	(
		input  logic                                        clk,
		input  logic                                        reset,

		// Load Sore Unit Stage 2
		input  logic                                        ldst2_valid,
		input  instruction_decoded_t                        ldst2_instruction,
		input  dcache_address_t                             ldst2_address,
		input  dcache_line_t                                ldst2_store_value,
		input  dcache_store_mask_t                          ldst2_store_mask,
		input  dcache_store_mask_t   [L1_WAY_NUMB - 1 : 0]  ldst2_dirty_mask,
		input  hw_lane_mask_t                               ldst2_hw_lane_mask,
		input  dcache_tag_t          [L1_WAY_NUMB - 1 : 0]  ldst2_tag_read,
		input  dcache_privileges_t   [L1_WAY_NUMB - 1 : 0]  ldst2_privileges_read,
		input  logic                                        ldst2_is_flush,
		input  logic                                        ldst2_is_dinv,
		input  logic                                        ldst2_io_memspace,
		input  logic                                        ldst2_io_memspace_has_data,

		output logic                                        ldst3_update_dirty_mask_valid,
		output logic [$clog2(L1_SET_NUMB) - 1 : 0]          ldst3_update_dirty_mask_set,
		output logic [$clog2(L1_WAY_NUMB) - 1 : 0]          ldst3_update_dirty_mask_way,
		output dcache_store_mask_t                          ldst3_update_dirty_mask,

		input  logic                                        ldst2_update_data_valid,
		input  logic                                        ldst2_update_info_valid,
		input  logic [$clog2(L1_WAY_NUMB) - 1 : 0]          ldst2_update_way,
		input  logic                                        ldst2_evict_valid,

		output logic[THREAD_NUMB - 1 : 0]                   ldst3_thread_sleep,

		// Cache Controller Stage 2
		output                                              ldst3_lru_update_en,
		output logic [$clog2(L1_WAY_NUMB) - 1 : 0]          ldst3_lru_update_way,
		output logic [$clog2(L1_SET_NUMB) - 1 : 0]          ldst3_lru_access_set,

		// Synch Core
		output logic                 [THREAD_NUMB - 1 : 0]  s3_no_ls_pending,

		// Load Store Unit Stage1, Writeback and Cache Controller
		input  logic                                        cc_snoop_data_valid,
		input  logic [$clog2(L1_SET_NUMB) - 1 : 0]          cc_snoop_data_set,
		input  logic [$clog2(L1_WAY_NUMB) - 1 : 0]          cc_snoop_data_way,
		output dcache_line_t                                ldst3_snoop_data,

		output logic                                        ldst3_valid,
		output instruction_decoded_t                        ldst3_instruction,
		output dcache_line_t                                ldst3_cache_line,
		output hw_lane_mask_t                               ldst3_hw_lane_mask,
		output dcache_store_mask_t                          ldst3_store_mask,
		output dcache_address_t                             ldst3_address,

		output dcache_store_mask_t                          ldst3_dirty_mask,
		output logic                                        ldst3_flush,
		output logic                                        ldst3_dinv,
		output logic                                        ldst3_miss,
		output logic                                        ldst3_evict,

		output logic                                        ldst3_io_valid,
		output logic [THREAD_IDX_W - 1 : 0]                 ldst3_io_thread,
		output logic [$bits(io_operation_t)-1 : 0]          ldst3_io_operation,
		output address_t                                    ldst3_io_address,
		output register_t                                   ldst3_io_data,

		// Configuration signal
		input  logic                                        cr_ctrl_cache_wt
	);

//  -----------------------------------------------------------------------
//  -- Load Store Unit 3 - Signals
//  -----------------------------------------------------------------------
	logic                                        is_hit;
	logic                                        is_instruction;
	logic                                        is_replacement;
	logic                                        is_data_update;
	logic                                        is_info_update;
	logic                                        is_flush;
	logic                                        is_dinv;
	logic                                        is_write_through;

	logic                                        is_store;
	logic                                        is_load;
	logic                                        is_io_load;
	logic                                        is_store_hit;
	logic                                        is_store_miss;
	logic                                        is_load_hit;
	logic                                        is_load_miss;
	logic                                        is_io_load_hit;
	logic                                        is_io_load_miss;
	logic                                        is_io_mem_space;

	dcache_way_mask_t                            way_matched_oh;
	logic [$clog2(L1_WAY_NUMB) - 1 : 0]          way_matched_idx;
	dcache_line_t                                ldst2_store_value_next;
	logic                                        store_mask_in_dirty_mask;

//  -----------------------------------------------------------------------
//  -- Load Store Unit 3 - Hit/Miss Detection Logic
//  -----------------------------------------------------------------------

	genvar                                       dcache_way;
	generate
		for ( dcache_way = 0; dcache_way < L1_WAY_NUMB; dcache_way++ ) begin : HIT_MISS_CHECK
			assign way_matched_oh[dcache_way] = ( ldst2_tag_read[dcache_way] == ldst2_address.tag ) &
						( ldst2_privileges_read[dcache_way].can_write | ldst2_privileges_read[dcache_way].can_read ) & ( ldst2_valid | ldst2_update_data_valid );
		end
	endgenerate

	oh_to_idx
	#(
		.NUM_SIGNALS( L1_WAY_NUMB ),
		.DIRECTION  ( "LSB0"      )
	)
	u_oh_to_idx
	(
		.index  ( way_matched_idx ),
		.one_hot( way_matched_oh  )
	);
	
	// The control bit "CACHE WT MODE" (cr_ctrl_cache_wt input bit) disables the write-back mechanism. When it is enabled, 
	// every store produces a flush to the main memory, consequently either explicit flushes operations and evictions 
	// caused by replacements are no more needed and disabled. 
	assign is_hit               = |way_matched_oh;
	assign is_instruction       = ldst2_valid & ~ldst2_is_flush & ~ldst2_is_dinv;
	assign is_replacement       = ldst2_update_data_valid && ldst2_evict_valid;
	assign is_data_update       = ldst2_update_data_valid && !ldst2_evict_valid;
	assign is_info_update       = ldst2_update_info_valid;
	assign is_flush             = ldst2_valid & ldst2_is_flush & ~cr_ctrl_cache_wt;
	assign is_dinv              = ldst2_valid & ldst2_is_dinv & is_hit;

	assign is_store             = ~ldst2_io_memspace & is_instruction && !ldst2_instruction.is_load;
	assign is_load              = ~ldst2_io_memspace & is_instruction && ldst2_instruction.is_load;
	assign is_store_hit         = is_store && ldst2_privileges_read[way_matched_idx].can_write && is_hit;
	assign is_store_miss        = is_store && ~is_store_hit;
	assign is_load_hit          = is_load && is_hit && ( ldst2_privileges_read[way_matched_idx].can_read || ( ldst2_privileges_read[way_matched_idx].can_write && store_mask_in_dirty_mask )) ;
	assign is_load_miss         = is_load && ~is_load_hit;
	assign is_write_through     = is_store & cr_ctrl_cache_wt;

	assign is_io_load           = ldst2_io_memspace & is_instruction && ldst2_instruction.is_load;
	assign is_io_load_hit       = is_io_load & ldst2_io_memspace_has_data;
	assign is_io_load_miss      = is_io_load & ~is_io_load_hit;

	assign ldst3_lru_update_en  = ~is_load_miss & ~is_store_miss & is_instruction ;
	assign ldst3_lru_update_way = way_matched_idx;
	assign ldst3_lru_access_set = ldst2_address.index;

	assign store_mask_in_dirty_mask = (ldst2_store_mask & ldst2_dirty_mask[way_matched_idx]) == ldst2_store_mask;

//  -----------------------------------------------------------------------
//  -- Load Store Unit 3 - Data Cache
//  -----------------------------------------------------------------------

    localparam SIZE                    = L1_SET_NUMB * L1_WAY_NUMB;
    localparam ADDR_WIDTH              = `DCACHE_SET_LENGTH + $clog2( L1_WAY_NUMB );
    localparam COL_WIDTH               = 8;
    localparam NB_COL                  = `DCACHE_WIDTH/8;


	logic                                        data_sram_read_enable;
	logic             [ADDR_WIDTH - 1 : 0]       data_sram_read_address;
	logic             [NB_COL - 1 : 0]           data_sram_write_enable;
	logic             [ADDR_WIDTH - 1 : 0]       data_sram_write_address;
	logic             [NB_COL*COL_WIDTH - 1 : 0] data_sram_write_data;
	logic             [NB_COL*COL_WIDTH - 1 : 0] data_sram_read_data;

	always_comb begin : OPERATION_CHECKER
		data_sram_read_address  = 0;
		data_sram_read_enable   = 0;
		data_sram_write_address = 0;
		data_sram_write_data    = 0;
		data_sram_write_enable  = 0;
		if ( is_instruction ) begin
			data_sram_read_address  = {ldst2_address.index, way_matched_idx};
			data_sram_read_enable   = is_load_hit | is_write_through;
			data_sram_write_address = {ldst2_address.index, way_matched_idx};
			data_sram_write_data    = ldst2_store_value;
			data_sram_write_enable  = ldst2_store_mask & {( `DCACHE_WIDTH/8 ){is_store_hit}};
		end else if ( is_data_update ) begin
			data_sram_read_enable   = 1'b0;
			data_sram_write_address = {ldst2_address.index, ldst2_update_way};
			data_sram_write_data    = ldst2_store_value;
			data_sram_write_enable  = is_hit ? ~ldst2_dirty_mask[way_matched_idx] : {( `DCACHE_WIDTH/8 ){1'b1}};
		end else if ( is_replacement ) begin
			data_sram_read_enable   = 1'b1;
			data_sram_read_address  = {ldst2_address.index, ldst2_update_way};
			data_sram_write_address = {ldst2_address.index, ldst2_update_way};
			data_sram_write_data    = ldst2_store_value;
			data_sram_write_enable  = {( `DCACHE_WIDTH/8 ){1'b1}};
		end else if ( is_flush | is_dinv ) begin
			data_sram_read_address  = {ldst2_address.index, way_matched_idx};
			data_sram_read_enable   = 1'b1;
		end
	end

	/* This memory bank implements the L1 data cache.
	 *
	 * The first read port is used by the instructions and the replacement commands execution flows.
	 * Therefore it is READ FIRST in order to retrieve the evicted data before the new data replace it.
	 *
	 * The second read port is used by the Cache Controller in order to handle messages coming from the network.
	 * This port is WRITE FIRST so the Cache Controller receives the last version of data also when a
	 * store instruction is performed concurrently on the requested cache line.
	 */
	memory_bank_2r1w
	#(
		.SIZE        ( SIZE       ),
		.ADDR_WIDTH  ( ADDR_WIDTH ),
		.COL_WIDTH   ( COL_WIDTH  ),
		.NB_COL      ( NB_COL     ),
		.WRITE_FIRST1( "TRUE"     ),
		.WRITE_FIRST2( "TRUE"     )
	)
	l1_data_cache_sram (
		.clock         ( clk                                    ),
		.read1_address ( data_sram_read_address                 ),
		.read1_data    ( data_sram_read_data                    ),
		.read1_enable  ( data_sram_read_enable                  ),
		.read2_enable  ( cc_snoop_data_valid                    ),
		.read2_address ( {cc_snoop_data_set, cc_snoop_data_way} ),
		.read2_data    ( ldst3_snoop_data                       ),
		.write_address ( data_sram_write_address                ),
		.write_data    ( data_sram_write_data                   ),
		.write_enable  ( data_sram_write_enable                 )
	);

//  -----------------------------------------------------------------------
//  -- Load Store Unit 3 - Dirty Mask handling
//  -----------------------------------------------------------------------

	dcache_store_mask_t data_cache_dirty_mask[SIZE];

	assign ldst3_update_dirty_mask_valid = (is_instruction & is_hit) | is_replacement | is_info_update | is_data_update;
	assign ldst3_update_dirty_mask_set   = ldst2_address.index;
	assign ldst3_update_dirty_mask_way   = is_instruction ? way_matched_idx : ldst2_update_way;
	assign ldst3_update_dirty_mask       = is_instruction ? (ldst2_dirty_mask[way_matched_idx] | (ldst2_store_mask & {( `DCACHE_WIDTH/8 ){is_store_hit}})) : dcache_store_mask_t'(0);

//  -----------------------------------------------------------------------
//  -- Load Store Unit 3 - Outputs Generation
//  -----------------------------------------------------------------------

	genvar                                       thread_idx;
	generate
		for ( thread_idx = 0; thread_idx < THREAD_NUMB; thread_idx++ ) begin : THREAD_SLEEPING_LOGIC
			assign s3_no_ls_pending[thread_idx]   = !( ldst2_valid && ldst2_instruction.thread_id == thread_id_t'( thread_idx ) );
			assign ldst3_thread_sleep[thread_idx] = ( is_load_miss || is_store_miss || is_dinv || is_io_load_miss ) && ldst2_instruction.thread_id == thread_id_t'( thread_idx );
		end
	endgenerate

	// In case of store, the recycle store value is propagated from the previous stage. In order to
	// align the data on the same cycle, the previous store value is buffered.
	assign ldst3_cache_line     = ( ldst3_miss | is_io_mem_space ) ? ldst2_store_value_next : data_sram_read_data;

	// A load request from the IO memory space must be directly forwarded to the Writeback module
	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			ldst3_valid     <= 1'b0;
			ldst3_miss      <= 1'b0;
			ldst3_evict     <= 1'b0;
			ldst3_flush     <= 1'b0;
			ldst3_dinv      <= 1'b0;
			is_io_mem_space <= 1'b0;
		end else begin
			ldst3_valid     <= ldst2_valid && ldst2_instruction.is_load && (( !is_io_load && !is_load_miss ) | (is_io_load && is_io_load_hit));
			ldst3_miss      <= ( is_load_miss || is_store_miss );
			ldst3_evict     <= is_replacement & ~cr_ctrl_cache_wt;
			ldst3_flush     <= is_flush | (cr_ctrl_cache_wt & is_store_hit);
			ldst3_dinv      <= is_dinv;
			is_io_mem_space <= ldst2_io_memspace;
		end
	end

	always_ff @ ( posedge clk ) begin
		ldst3_instruction      <= ldst2_instruction;
		ldst3_hw_lane_mask     <= ldst2_hw_lane_mask;
		ldst3_store_mask       <= ldst2_store_mask;
		ldst2_store_value_next <= ldst2_store_value;
		if ( is_instruction | is_flush | is_dinv ) begin
			ldst3_address        <= ldst2_address;
			ldst3_dirty_mask     <= ldst2_dirty_mask[way_matched_idx];
		end else if ( is_replacement ) begin
			ldst3_address.tag    <= ldst2_tag_read[ldst2_update_way];
			ldst3_address.index  <= ldst2_address.index;
			ldst3_address.offset <= dcache_offset_t'( 0 );
			ldst3_dirty_mask     <= ldst2_dirty_mask[ldst2_update_way];
		end else begin
			ldst3_address.tag    <= ldst2_address.tag;
			ldst3_address.index  <= ldst2_address.index;
			ldst3_address.offset <= dcache_offset_t'( 0 );
		end
	end

	always_ff @ ( posedge clk, posedge reset ) begin : IO_MAP_CONTROL_OUT
		if ( reset )
			ldst3_io_valid <= 1'b0;
		else
			ldst3_io_valid <= ldst2_valid & ldst2_io_memspace & ~ldst2_io_memspace_has_data;
	end

	always_ff @ ( posedge clk ) begin : IO_MAP_OUTPUT
		if ( ldst2_io_memspace ) begin
			ldst3_io_thread    <= ldst2_instruction.thread_id;
			ldst3_io_operation <= ldst2_instruction.op_code.mem_opcode == STORE_32 ? IO_WRITE : IO_READ;
			ldst3_io_address   <= ldst2_address;
			ldst3_io_data      <= ldst2_store_value[$bits(register_t)-1 : 0];
		end
	end

`ifdef DISPLAY_LDST

	always_ff @( posedge clk ) begin
		print_ldst3_result(TILE_ID, ldst3_flush, ldst3_dinv, ldst3_evict, ldst3_miss, ldst3_instruction, ldst3_address, ldst3_cache_line);
	end

`endif

endmodule
