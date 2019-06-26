`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"

/*
 * Instruction Fetch stage schedules the next thread PC from the eligible threads pool handled by the Thread Controller.
 * Available threads are scheduled in a Round Robin fashion. Furthermore, at the boot phase, the Thread Controller may
 * initialize each thread PC through a specific interface.
 *
 * Once an eligible thread is selected, it reads its PC, and determines if the next instruction cache line is already in
 * instruction cache memory or not.
 *
 * In case of hit, the right memory word is fetched to the Decode stage and the PC is incremented by 4.
 * In case of miss an instruction memory transaction is dispatched directly to the Directory Controller and the thread
 * is blocked until the instruction line is not retrieved from main memory.
 *
 * Finally, this module handles the PC restoring in case of rollback. When a rollback occurs and the rollback signals are
 * set by Rollback Handler stage, the Instruction Fetch module overwrites the PC of the thread that issued the rollback.
 *
 */

module instruction_fetch_stage(
		input                                       clk,
		input                                       reset,
		input                                       enable,

		/* Rollback stage interface */
		input  thread_mask_t                        rollback_valid,
		input  register_t    [`THREAD_NUMB - 1 : 0] rollback_pc_value,

		/* Decode stage interface */
		output logic                                if_valid,
		output thread_id_t                          if_thread_selected_id,
		output register_t                           if_pc_scheduled,
		output instruction_t                        if_inst_scheduled,

		/* To Control Register */
		output address_t     [`THREAD_NUMB - 1 : 0] if_current_pc,

		/* Thread controller stage interface */
		input  icache_lane_t                        tc_data_out,
		input  address_t                            tc_addr_update_cache,
		input  logic                                tc_valid_update_cache,
		input  thread_mask_t                        tc_thread_en,

		input  address_t                            tc_job_pc,
		input  thread_id_t                          tc_job_thread_id,
		input  logic                                tc_job_valid,

		output logic                                if_cache_miss,
		output thread_mask_t                        if_thread_miss,
		output address_t                            if_address_miss
	);


//  -----------------------------------------------------------------------
//  -- Signal declaration
//  -----------------------------------------------------------------------
	icache_address_t                                 tc_addr_update;
	logic                                            tc_is_updating_selected_pc;

	/*------ Thread selection ------*/
	thread_mask_t                                    thread_scheduled_bitmap;
	thread_id_t                                      thread_scheduled_id;

	/*------ Pc selection per thread ------*/
	icache_address_t                                 next_pc [`THREAD_NUMB];
	icache_address_t                                 icache_address [`THREAD_NUMB];
	logic            [`ICACHE_OFFSET_LENGTH - 1 : 0] icache_offset [`THREAD_NUMB];
	icache_address_t                                 icache_address_selected;
	logic            [`ICACHE_OFFSET_LENGTH - 1 : 0] icache_offset_selected;
	logic                                            instruction_valid;

	/*----- Cache LRU --------*/
	logic            [`ICACHE_WAY_LENGTH - 1 : 0]    way_lru;

	/*------ Tag Cache  ------*/
	logic            [`ICACHE_TAG_LENGTH - 1 : 0]    tag_read_data [`ICACHE_WAY];
	logic            [`ICACHE_WAY - 1 : 0]           line_valid_selected;

	/*------ Data cache ------*/
	logic            [`ICACHE_WIDTH - 1 : 0]         read_data_way [`ICACHE_WAY];
	logic            [`ICACHE_WIDTH - 1 : 0]         read_data;
	logic            [`INSTRUCTION_LENGTH - 1 : 0]   fetched_word;

	/*------ Stage 1 output logic ------*/
	logic                                            stage1_instruction_valid;
	icache_address_t                                 stage1_pc;
	logic            [`ICACHE_OFFSET_LENGTH - 1 : 0] stage1_icache_offset;
	icache_address_t                                 stage1_icache_address;
	thread_mask_t                                    stage1_thread_scheduled_bitmap;
	thread_id_t                                      stage1_thread_scheduled_id;

	/*------ Tag Cache: Miss detection  ------*/
	logic            [`ICACHE_WAY - 1 : 0]           hit_miss;                      // hit/miss per way
	logic            [`ICACHE_WAY_LENGTH - 1 : 0]    hit_miss_id;
	thread_mask_t                                    stage1_miss;                   // hit/miss per thread

	assign tc_addr_update             = tc_addr_update_cache;

//  -----------------------------------------------------------------------
//  -- Pipeline, stage: 1
//  -----------------------------------------------------------------------
	/*------ Thread selection ------*/
	/*
	 * A thread is selected by all the possible eligible ones using an
	 *  external signal coming from Thread Controller unit. Anyway, an internal round
	 *  robin arbiter selects threads in a fair mode. A different thread is elected at
	 *  each clock cycle.
	 */
	rr_arbiter #(
		.NUM_REQUESTERS( `THREAD_NUMB )
	)
	rr_arbiter_thread (
		.clk       ( clk                     ),
		.reset     ( reset                   ),
		.request   ( tc_thread_en            ),
		.update_lru( 1'b1                    ),
		.grant_oh  ( thread_scheduled_bitmap )
	);

	oh_to_idx #(
		.NUM_SIGNALS( `THREAD_NUMB         ),
		.DIRECTION  ( "LSB0"               ),
		.INDEX_WIDTH( $bits( thread_id_t ) )
	)
	oh_to_idx_thread (
		.one_hot( thread_scheduled_bitmap ),
		.index  ( thread_scheduled_id     )
	);

	/*------ PC selection per thread ------*/
	/*
	 * The elected thread ID selects a specific PC which is modified on the base of some
	 * thread-related events. If a cache miss or a rollback occur the valid signal is
	 * invalidated. The instruction miss decreases the PC by 4, restoring its original
	 * value. Dually, when an hit occurs, the PC is incremented by 4.
	 */

	genvar                                           thread_id;
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin : PC_HANDLING_LOGIC
			// To Control Register
			assign if_current_pc[thread_id]      = next_pc[thread_id];

			always_ff @( posedge clk, posedge reset ) begin
				if ( reset )
					next_pc[thread_id] <= 0;
				else if ( enable ) begin
					if ( tc_job_valid && thread_id == tc_job_thread_id )
						next_pc[thread_id] <= tc_job_pc;
					else if ( rollback_valid[thread_id] )
						next_pc[thread_id] <= rollback_pc_value[thread_id];
					else if ( stage1_miss[thread_id] && stage1_thread_scheduled_id == thread_id )
						// Note that the check is done with the previous thread scheduled
						next_pc[thread_id] <= next_pc[thread_id] - address_t'( 3'd4 );
					else if ( thread_scheduled_bitmap[thread_id] )
						next_pc[thread_id] <= next_pc[thread_id] + address_t'( 3'd4 );
				end
			end

			assign icache_address[thread_id].tag = next_pc[thread_id].tag,
				icache_address[thread_id].index  = next_pc[thread_id].index,
				icache_address[thread_id].offset = {`ICACHE_OFFSET_LENGTH{1'b0}};
			assign icache_offset[thread_id]      = next_pc[thread_id].offset >> 2;
		end
	endgenerate

	assign
		/*
		 * To understand if the current instruction is valid, the rollback and miss signals
		 * must be checked, in order to disable the read enable port of the Instruction Caches.
		 */
		instruction_valid             = ~rollback_valid[thread_scheduled_id] & |tc_thread_en & ~stage1_miss[thread_scheduled_id],// & ~dsu_pipe_flush[thread_scheduled_id],
		icache_address_selected       = icache_address[thread_scheduled_id],
		icache_offset_selected        = icache_offset[thread_scheduled_id];

	/*------ Cache LRU  ------*/

	cache_lru_if #(
		.NUM_WAYS ( `ICACHE_WAY ),
		.NUM_SET  ( `ICACHE_SET )
	)
	u_cache_lru_if (
		.clk           ( clk                                  ),
		.reset         ( reset                                ),
		//[1] Used to move a way to the MRU position when it has been accessed.
		.en_hit        ( |hit_miss & stage1_instruction_valid ),
		.set_hit       ( stage1_icache_address.index          ),
		.way_hit       ( hit_miss                             ),
		//[2] Used to request LRU to replace when filling.
		.en_update     ( tc_valid_update_cache                ),
		.set_update    ( tc_addr_update.index                 ),
		.way_update_lru( way_lru                              )
	);

	/*------ CACHES  ------*/
	/*
	 * The tag and data cache are accessed in mode, using the same input.
	 * The caches are read-enabled only if the current instruction is valid.
	 * The result is validated only if there is one hit.
	 * In order to have the signal about the current scheduled thread aligned
	 * with the available data at the caches output, we need to register
	 * this signals: PC, instruction_valid, line_valid, address, thread_id.
	 */

	/*------ Tag Cache  ------*/
	genvar                                           way;
	generate
		for ( way = 0; way < `ICACHE_WAY; way++ ) begin : INSTRUCTION_TAG_CACHE_GEN
			// line_valis are LUTS instead of SRAM because they need to be cleared at reset.
			logic [`ICACHE_SET - 1 : 0] line_valid;

			memory_bank_1r1w #(
				.COL_WIDTH   ( `ICACHE_TAG_LENGTH ),
				.NB_COL      ( 1                  ),
				.WRITE_FIRST ( "TRUE"             ),
				.SIZE        ( `ICACHE_SET        )
			) sram_l1i_tag(
				.read_enable   ( instruction_valid                       ),
				.read_address  ( icache_address_selected.index           ),
				.read_data     ( tag_read_data[way]                      ),
				.write_enable  ( tc_valid_update_cache && way_lru == way ),
				.write_address ( tc_addr_update.index                    ),
				.write_data    ( tc_addr_update.tag                      ),
				.clock         ( clk                                     )
			);

			/*
			 * A line is set as valid when a data instruction is retrieved from
			 * the main memory and stored in the selected way. It's important to notice
			 * a cut-through for validity check operation: if the instruction updating
			 * is relative to the same address selected by the current thread, the valid
			 * output signal is bypassed.
			 */

			always_ff @( posedge clk, posedge reset ) begin
				if ( reset )
					line_valid <= 0;
				else if ( enable )begin
					if ( tc_valid_update_cache && way_lru == way )
						line_valid[tc_addr_update.index] <= 1;
					// the line_valid is registered per way too.
					if ( tc_valid_update_cache && way_lru == way && tc_addr_update.index == icache_address_selected.index )
						line_valid_selected[way]         <= 1;
					else
						line_valid_selected[way]         <= line_valid[icache_address_selected.index] & instruction_valid;
				end
			end
		end
	endgenerate


	/*------ Data cache ------*/

	generate
		for ( way = 0; way < `ICACHE_WAY; way++ ) begin : INSTRUCTION_DATA_CACHE_GEN

			memory_bank_1r1w #(
				.COL_WIDTH   ( `ICACHE_WIDTH ),
				.NB_COL      ( 1             ),
				.WRITE_FIRST ( "TRUE"        ),
				.SIZE        ( `ICACHE_SET   )
			) sram_l1i_data (
				.read_enable   ( instruction_valid                       ),
				.read_address  ( icache_address_selected.index           ),
				.read_data     ( read_data_way[way]                      ),
				.write_enable  ( tc_valid_update_cache && way_lru == way ),
				.write_address ( tc_addr_update.index                    ),
				.write_data    ( tc_data_out                             ),
				.clock         ( clk                                     )
			);
		end
	endgenerate

	/*------ Stage 1 output logic ------*/

	// In order to have the signal of the current scheduled thread aligned with the available
	// data at the caches output, these signals are registered: PC, instruction_valid, address,
	// thread_id.
	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			stage1_instruction_valid       <= 1'b0;
			stage1_thread_scheduled_id     <= 0;
		end else if ( enable ) begin
			stage1_instruction_valid       <= instruction_valid;
			stage1_thread_scheduled_id     <= thread_scheduled_id;
		end
	end

	always_ff @ ( posedge clk ) begin : IF_TO_NEXT_STAGE
		stage1_pc                      <= next_pc[thread_scheduled_id];
		stage1_icache_address          <= icache_address_selected;
		stage1_icache_offset           <= icache_offset_selected;
		stage1_thread_scheduled_bitmap <= thread_scheduled_bitmap;
	end

//  -----------------------------------------------------------------------
//  -- Pipeline, stage: 2
//  -----------------------------------------------------------------------
	/*------ Tag Cache: Miss detection  ------*/

	// There is a miss when the line is valid but tags do not match.
	// The hit signal is per way (NOT per thread).
	generate
		for ( way = 0; way < `ICACHE_WAY; way++ ) begin : INSTRUCTION_HIT_MISS_LOGIC
			assign hit_miss[way] = tag_read_data[way] == stage1_icache_address.tag & line_valid_selected[way];
		end
	endgenerate

	// Checks which thread issues an instruction miss.
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin : THREAD_INSTRUCTION_HIT_MISS_CHECK
			assign stage1_miss[thread_id] = ( stage1_thread_scheduled_id == thread_id ) ? ~|hit_miss & stage1_instruction_valid : 1'b0;
		end
	endgenerate

	oh_to_idx #(
		.NUM_SIGNALS( `ICACHE_WAY ),
		.DIRECTION  ( "LSB0"      )
	)
	oh_to_idx_miss (
		.one_hot( hit_miss    ),
		.index  ( hit_miss_id )
	);

	// Fetching the correct instruction word
	assign read_data                  = read_data_way[hit_miss_id],
		fetched_word                  = read_data[`INSTRUCTION_LENGTH * stage1_icache_offset +: `INSTRUCTION_LENGTH];

	// If the TC is updating the selected missing Program Counter, the thread does not issue a cache miss and is not stalled.
	// Its Program Counter is rolled back and it will find the data in cache this time.
	assign tc_is_updating_selected_pc = ( tc_addr_update == stage1_pc ) & tc_valid_update_cache;

	/*------ Stage 2 output logic ------*/
	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			if_valid <= 1'b0;
		//if_cache_miss <= 1'b0;
		end else begin
			if_valid <= stage1_instruction_valid & ~rollback_valid[stage1_thread_scheduled_id] & ~stage1_miss[stage1_thread_scheduled_id];
		end

	always_ff @ ( posedge clk ) begin
		/*
		 * The instruction valid is asserted only when the current instruction is valid,
		 * there is no rollback and there is a memory hit on the current thread scheduled.
		 */
		if_thread_selected_id <= stage1_thread_scheduled_id;
		if_pc_scheduled       <= stage1_pc;
		if_inst_scheduled     <= fetched_word;
	end

	always_comb begin
		/*
		 * The cache miss is asserted only when the current instruction is valid,
		 * there is no rollback and there is a miss on the current thread scheduled.
		 */
		if_cache_miss   = stage1_instruction_valid & ~rollback_valid[stage1_thread_scheduled_id] & stage1_miss[stage1_thread_scheduled_id] & ~tc_is_updating_selected_pc;
		if_thread_miss  = stage1_thread_scheduled_bitmap;
		if_address_miss = stage1_pc;
	end

endmodule

/*
 * Pseudo LRU: see http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.217.3594&rep=rep1&type=pdf, page 13
 */
module cache_lru_if #(
		parameter NUM_WAYS      = 4,
		parameter BIT_WAYS      = $clog2( NUM_WAYS ),
		parameter NUM_SET       = 1024,
		parameter BIT_SET       = $clog2( NUM_SET ),
		parameter BIT_HALF_WAYS = $clog2( NUM_WAYS/2 ) )
	(
		input                           clk,
		input                           reset,

		// [1] Used to move a way to the MRU position when it has been accessed.
		input                           en_hit,
		input        [BIT_SET - 1 : 0]  set_hit,
		input        [NUM_WAYS - 1 : 0] way_hit,

		// [2] Used to request LRU to replace when filling.
		input                           en_update,
		input        [BIT_SET - 1 : 0]  set_update,
		output logic [BIT_WAYS - 1 : 0] way_update_lru
	);

	/*
	 * For high associativity (greater than 8), this policy performs as bad as Random.
	 *  Nevertheless, for low associativity, its results are good
	 * (5-10% worse than LRU), rising it up as a credible candidate.
	 */

	logic [NUM_SET - 1 : 0]       lru_bits;
	logic [BIT_HALF_WAYS - 1 : 0] lru_counter;

	// first half = less significative bits
	// second half = most significative bits
	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			lru_counter <= '{default : '0};
			lru_bits    <= '{default : '0};
		end
		else begin // [1]
			if ( en_hit ) begin
				lru_bits[set_hit] <= |way_hit[( NUM_WAYS/2 ) - 1 : 0]; // 0: first half, 1: second half
				lru_counter       <= lru_counter + 1;                  // update the counter
			end else                                                   // [2]
				if ( en_update ) begin
					lru_bits[set_update] <= ~lru_bits[set_update]; // switch to the other half
					lru_counter          <= lru_counter + 1;       // update the counter
				end
		end
	end

	assign way_update_lru[BIT_WAYS - 1]  = lru_bits[set_update],
		way_update_lru[BIT_WAYS - 2 : 0] = lru_counter;

endmodule
