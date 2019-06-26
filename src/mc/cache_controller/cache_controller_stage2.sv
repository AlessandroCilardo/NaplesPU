`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"

/*
 * This stage manages the following elements:
 *  - 1 : the pseudo LRU
 *  - 2 : a SRAM bank for coherence state and MSHR data
 *  - 3 : the MSHR handler (contains the entries), that it is separated from the MSHR data
 */

module cache_controller_stage2 (

		input                                                   clk,
		input                                                   reset,

		//From Cache Controller Stage 1
		input  logic                                            cc1_request_valid,
		input  coherence_request_t                              cc1_request,
		input  logic                                            cc1_request_mshr_hit,
		input  mshr_idx_t                                       cc1_request_mshr_index,
		input  mshr_entry_t                                     cc1_request_mshr_entry_info,
		input  thread_id_t                                      cc1_request_thread_id,
		input  dcache_address_t                                 cc1_request_address,
		input  dcache_line_t                                    cc1_request_data,
		input  dcache_store_mask_t                              cc1_request_dirty_mask,
		input  tile_address_t                                   cc1_request_source,
		input  sharer_count_t                                   cc1_request_sharers_count,
		input  message_response_t                               cc1_request_packet_type,
		input  logic                                            cc1_request_from_dir,   

		input  dcache_tag_t        [`MSHR_LOOKUP_PORTS - 2 : 0] cc1_mshr_lookup_tag,
		input  dcache_set_t        [`MSHR_LOOKUP_PORTS - 2 : 0] cc1_mshr_lookup_set,

		// From Cache Controller Stage 3
		input  logic                                            cc3_update_mshr_en,
		input  mshr_idx_t                                       cc3_update_mshr_index,
		input  mshr_entry_t                                     cc3_update_mshr_entry_info,
		input  dcache_line_t                                    cc3_update_mshr_entry_data,

		input  logic                                            cc3_update_coherence_state_en,
		input  dcache_set_t                                     cc3_update_coherence_state_index,
		input  dcache_way_idx_t                                 cc3_update_coherence_state_way,
		input  coherence_state_t                                cc3_update_coherence_state_entry,

		input  logic                                            cc3_update_lru_fill_en,

		// From Load Store Unit
		input  dcache_tag_t        [`DCACHE_WAY - 1 : 0]        ldst_snoop_tag,
		input  dcache_privileges_t [`DCACHE_WAY - 1 : 0]        ldst_snoop_privileges,
		input  dcache_set_t                                     ldst_lru_update_set,
		input                                                   ldst_lru_update_en,
		input  dcache_way_idx_t                                 ldst_lru_update_way,

		// To Cache Controller Stage 1
		output logic                                            cc2_pending_valid,
		output dcache_address_t                                 cc2_pending_address,

		output logic               [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_hit,
		output logic               [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_hit_set,
		output mshr_idx_t          [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_index,
		output mshr_entry_t        [`MSHR_LOOKUP_PORTS - 1 : 0] cc2_mshr_lookup_entry_info,


		// To Cache Controller Stage 3
		output logic                                            cc2_request_valid,
		output coherence_request_t                              cc2_request,
		output thread_id_t                                      cc2_request_thread_id,
		output dcache_address_t                                 cc2_request_address,
		output dcache_line_t                                    cc2_request_data,
		output dcache_store_mask_t                              cc2_request_dirty_mask,
		output tile_address_t                                   cc2_request_source,
		output sharer_count_t                                   cc2_request_sharers_count,
		output message_response_t                               cc2_request_packet_type,
		output logic                                            cc2_request_from_dir,   

		output logic                                            cc2_request_mshr_hit,
		output mshr_idx_t                                       cc2_request_mshr_index,
		output mshr_entry_t                                     cc2_request_mshr_entry_info,
		output dcache_line_t                                    cc2_request_mshr_entry_data,
		output mshr_idx_t                                       cc2_request_mshr_empty_index,
		output logic                                            cc2_request_mshr_full,

		output logic                                            cc2_request_replacement_is_collision,
		output dcache_way_idx_t                                 cc2_request_lru_way_idx,
		output dcache_way_idx_t                                 cc2_request_snoop_way_idx,
		output logic                                            cc2_request_snoop_hit,
		output dcache_tag_t        [`DCACHE_WAY - 1 : 0]        cc2_request_snoop_tag,
		output dcache_privileges_t [`DCACHE_WAY - 1 : 0]        cc2_request_snoop_privileges,
		output coherence_state_t   [`DCACHE_WAY - 1 : 0]        cc2_request_coherence_states
	);

	localparam MSHR_COLLISION_PORT = `MSHR_COLLISION_PORT;

	logic             snoop_tag_hit;
	dcache_way_mask_t snoop_tag_way_oh;
	dcache_way_idx_t  snoop_tag_way_id;

	logic             replacement_tag_is_valid;
	logic             replacement_is_collision;
	dcache_tag_t      replacement_snoop_tag;
	dcache_set_t	  replacement_snoop_index;

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 2 - LRU
//  -----------------------------------------------------------------------

	dcache_way_idx_t  request_lru_way_idx;
	dcache_set_t      lru_update_set;
	dcache_way_idx_t  lru_update_way;
	
	// In case of replacement collision, these signals update the pLRU in
	// order to get a different way the next time.
	assign lru_update_set = (cc3_update_lru_fill_en) ? cc3_update_coherence_state_index : ldst_lru_update_set;
	assign lru_update_way = (cc3_update_lru_fill_en) ? cc3_update_coherence_state_way : ldst_lru_update_way;

	tree_plru #(
		.NUM_SETS ( `DCACHE_SET ),
		.NUM_WAYS ( `DCACHE_WAY )
	) prlu (
		.clk        ( clk                                         ),
		.read_en    ( cc1_request_valid                           ),
		.read_set   ( cc1_request_address.index                   ),
		.read_valids( {`DCACHE_WAY{cc1_request_valid}}            ),
		.update_en  ( ldst_lru_update_en | cc3_update_lru_fill_en ),
		.update_set ( lru_update_set                              ),
		.update_way ( lru_update_way                              ),
		.read_way   ( request_lru_way_idx                         )
	);

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 2 - Cache Tag and Privileges Lookup
//  -----------------------------------------------------------------------
	genvar            dcache_way;
	generate
		for ( dcache_way = 0; dcache_way < `DCACHE_WAY; dcache_way++ ) begin : SNOOP_HIT_LOGIC
			// There is an hit if the tag is in cache L1 and it is valid (can_read or can_write is high)
			assign snoop_tag_way_oh[dcache_way] = ( ldst_snoop_tag[dcache_way] == cc1_request_address.tag ) &
				( ldst_snoop_privileges[dcache_way].can_read | ldst_snoop_privileges[dcache_way].can_write );
		end
	endgenerate

	// The next stage needs to know if there is a tag hit and the way that has that tag
	assign snoop_tag_hit       = |snoop_tag_way_oh;

	oh_to_idx
	#(
		.NUM_SIGNALS( `DCACHE_WAY ),
		.DIRECTION  ( "LSB0"      )
	)
	hit_oh_to_idx
	(
		.index  ( snoop_tag_way_id ),
		.one_hot( snoop_tag_way_oh )
	);

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 2 - MSHR Handler
//  -----------------------------------------------------------------------

	// Check if a replacement issues a collision in the MSHR.
	always_comb begin : SNOOP_COLLISION_GEN
		replacement_tag_is_valid = ( ldst_snoop_privileges[request_lru_way_idx].can_read | ldst_snoop_privileges[request_lru_way_idx].can_write );
		replacement_snoop_tag    = (replacement_tag_is_valid) ? ldst_snoop_tag[request_lru_way_idx] : 0;
	end 
	assign replacement_snoop_index = cc1_request_address.index;

	// Replacement collision checking requires an additional lookup port in the MSHR. The
	// elected way to evict by the pLRU is calculated in this stage, and the additional 
	// lookup port is fed with this address. If a conflict occurs with a valid entry, 
	// the hit value states the possiblity of collision.
	mshr_cc #(
		.WRITE_FIRST( "FALSE" )
	)
	u_mshr_cc (
		.clk            ( clk                                            ),
		.enable         ( 1'b1                                           ),
		.reset          ( reset                                          ),
		.lookup_tag     ( {replacement_snoop_tag, cc1_mshr_lookup_tag}   ),
		.lookup_set     ( {replacement_snoop_index, cc1_mshr_lookup_set} ),
		.lookup_hit     ( cc2_mshr_lookup_hit                            ),
		.lookup_hit_set ( cc2_mshr_lookup_hit_set                        ),
		.lookup_index   ( cc2_mshr_lookup_index                          ),
		.lookup_entry   ( cc2_mshr_lookup_entry_info                     ),
		.full           ( cc2_request_mshr_full                          ),
		.empty_index    ( cc2_request_mshr_empty_index                   ),
		.update_en      ( cc3_update_mshr_en                             ),
		.update_index   ( cc3_update_mshr_index                          ),
		.update_entry   ( cc3_update_mshr_entry_info                     )
	);

	// Whenever an hit for the replacement address is high, in the MSHR an entry with 
	// the same set is pending, hence a collision is raised 
	assign replacement_is_collision = cc2_mshr_lookup_hit[MSHR_COLLISION_PORT];

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 2 - Coherence State and Data
//  -----------------------------------------------------------------------
	// Every cached lines state are stored in this SRAM. At each scheduled request, the cache line
	// state is read and dispatched to the next stage. Only the Protocol Unit can update the cache
	// line state. If a read and a write occurs in the same time, the requestor read the new value.

	generate
		for ( dcache_way = 0; dcache_way < `DCACHE_WAY; dcache_way++ ) begin : COHERENCE_STATE_SRAM
			memory_bank_1r1w
			#(
				.SIZE      ( `DCACHE_SET                ),
				.COL_WIDTH ( $bits( coherence_state_t ) ),
				.NB_COL    ( 1                          )
			)
			coherence_state_sram
			(
				.clock        ( clk                                                                                                   ),
				.read_address ( cc1_request_address.index                                                                             ),
				.read_data    ( cc2_request_coherence_states[dcache_way]                                                              ),
				.read_enable  ( cc1_request_valid                                                                                     ),
				.write_address( cc3_update_coherence_state_index                                                                      ),
				.write_data   ( cc3_update_coherence_state_entry                                                                      ),
				.write_enable ( cc3_update_coherence_state_en & ( cc3_update_coherence_state_way == dcache_way_idx_t'( dcache_way ) ) )
			);
		end
	endgenerate

	// An MSHR entry has a Data field stored in this SRAM, the previous stage issues a request and
	// an MSHR entry id, this is used to read the stored data. As the MSHR, only the Protocol Unit
	// can update this MSHR data SRAM.

	memory_bank_1r1w
	#(
		.SIZE      ( `MSHR_SIZE             ),
		.COL_WIDTH ( $bits( dcache_line_t ) ),
		.NB_COL    ( 1                      )
	)
	mshr_data_sram
	(
		.clock        ( clk                         ),
		.read_address ( cc1_request_mshr_index      ),
		.read_data    ( cc2_request_mshr_entry_data ),
		.read_enable  ( cc1_request_valid           ),
		.write_address( cc3_update_mshr_index       ),
		.write_data   ( cc3_update_mshr_entry_data  ),
		.write_enable ( cc3_update_mshr_en          )
	);

//  -----------------------------------------------------------------------
//  -- Cache Controller Stage 2 - Output
//  -----------------------------------------------------------------------
	// The scheduled address request is fed back to the Fetch Unit stage, no request can
	// be scheduled on the pending address
	assign cc2_pending_address = cc1_request_address;
	assign cc2_pending_valid   = cc1_request_valid;

	always_ff @( posedge clk ) begin
		cc2_request_snoop_way_idx    <= snoop_tag_way_id;
		cc2_request                  <= cc1_request;
		cc2_request_mshr_index       <= cc1_request_mshr_index;
		cc2_request_mshr_entry_info  <= cc1_request_mshr_entry_info;
		cc2_request_thread_id        <= cc1_request_thread_id;
		cc2_request_address          <= cc1_request_address;
		cc2_request_data             <= cc1_request_data;
		cc2_request_dirty_mask       <= cc1_request_dirty_mask;
		cc2_request_source           <= cc1_request_source;
		cc2_request_sharers_count    <= cc1_request_sharers_count;
		cc2_request_packet_type      <= cc1_request_packet_type;
        	cc2_request_from_dir         <= cc1_request_from_dir;
		cc2_request_snoop_tag        <= ldst_snoop_tag;
		cc2_request_snoop_privileges <= ldst_snoop_privileges;
		cc2_request_lru_way_idx      <= request_lru_way_idx;
	end

	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			cc2_request_snoop_hit                <= 1'b0;
			cc2_request_valid                    <= 1'b0;
			cc2_request_mshr_hit                 <= 1'b0;
			cc2_request_replacement_is_collision <= 1'b0;
		end else begin
			cc2_request_snoop_hit                <= snoop_tag_hit;
			cc2_request_valid                    <= cc1_request_valid;
			cc2_request_mshr_hit                 <= cc1_request_mshr_hit;
			cc2_request_replacement_is_collision <= replacement_is_collision;
		end

endmodule
