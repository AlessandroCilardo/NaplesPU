`timescale 1ns / 1ps
`include "npu_coherence_defines.sv"

module directory_controller_stage2 (
		input                                                                             clk,
		input                                                                             reset,

		// From Directory Controller Stage 1
		input  logic                                                                      dc1_message_valid,
		input  logic              [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0]                 dc1_message_type,
		input  logic                                                                      dc1_message_tshr_hit,
		input  tshr_idx_t                                                                 dc1_message_tshr_index,
		input  tshr_entry_t                                                               dc1_message_tshr_entry_info,
		input  l2_cache_address_t                                                         dc1_message_address,
		input  dcache_line_t                                                              dc1_message_data,
		input  tile_address_t                                                             dc1_message_source,
		input  logic              [`L2_CACHE_WAY - 1 : 0]                                 dc1_message_cache_valid,
		input  logic              [`L2_CACHE_WAY - 1 : 0][`DIRECTORY_STATE_WIDTH - 1 : 0] dc1_message_cache_state,
		input  l2_cache_tag_t     [`L2_CACHE_WAY - 1 : 0]                                 dc1_message_cache_tag,

		input  logic              [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc1_replacement_state,
		input  logic              [`TILE_COUNT - 1 : 0]                                   dc1_replacement_sharers_list,
		input  tile_address_t                                                             dc1_replacement_owner,

		// From Directory Controller Stage 3
		input  logic                                                                      dc3_update_cache_enable,
		input  l2_cache_set_t                                                             dc3_update_cache_set,
		input  l2_cache_way_idx_t                                                         dc3_update_cache_way,
		input  logic              [`TILE_COUNT - 1 : 0]                                   dc3_update_cache_sharers_list,
		input  tile_address_t                                                             dc3_update_cache_owner,
		input  dcache_line_t                                                              dc3_update_cache_data,

		input  logic                                                                      dc3_update_plru_en,
		input  l2_cache_set_t                                                             dc3_update_plru_set,
		input  l2_cache_way_idx_t                                                         dc3_update_plru_way,


		// To Directory Controller Stage 1
		output logic                                                                      dc2_pending,
		output l2_cache_address_t                                                         dc2_pending_address,

		// To Directory Controller Stage 3
		output logic                                                                      dc2_message_valid,
		output logic              [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0]                 dc2_message_type,
		output l2_cache_address_t                                                         dc2_message_address,
		output dcache_line_t                                                              dc2_message_data,
		output tile_address_t                                                             dc2_message_source,

		output logic              [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc2_replacement_state,
		output logic              [`TILE_COUNT - 1 : 0]                                   dc2_replacement_sharers_list,
		output tile_address_t                                                             dc2_replacement_owner,

		output logic                                                                      dc2_message_tshr_hit,
		output tshr_idx_t                                                                 dc2_message_tshr_index,
		output tshr_entry_t                                                               dc2_message_tshr_entry_info,

		output logic                                                                      dc2_message_cache_hit,
		output logic                                                                      dc2_message_cache_valid,
		output logic              [`TILE_COUNT - 1 : 0]                                   dc2_message_cache_sharers_list,
		output tile_address_t                                                             dc2_message_cache_owner,
		output logic              [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc2_message_cache_state,
		output l2_cache_tag_t                                                             dc2_message_cache_tag,
		output dcache_line_t                                                              dc2_message_cache_data,
		output l2_cache_way_idx_t                                                         dc2_message_cache_way

	);

	logic                                      hit;
	logic              [`L2_CACHE_WAY - 1 : 0] hit_oh;
	l2_cache_way_idx_t                         hit_idx;

	l2_cache_way_idx_t                         lru_way;
	l2_cache_way_idx_t                         selected_way;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 2 - Cache Hit/miss detection
//  -----------------------------------------------------------------------

	generate
		genvar way_idx;
		for ( way_idx = 0; way_idx < `L2_CACHE_WAY; way_idx++ ) begin
			assign hit_oh[way_idx] = dc1_message_cache_valid[way_idx] && ( dc1_message_cache_tag[way_idx] == dc1_message_address.tag );
		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 2 - Pseudo LRU
//  -----------------------------------------------------------------------

	tree_plru #(
		.NUM_SETS ( `L2_CACHE_SET ),
		.NUM_WAYS ( `L2_CACHE_WAY )
	) prlu (
		.clk        ( clk                       ),
		.read_en    ( dc1_message_valid         ),
		.read_set   ( dc1_message_address.index ),
		.read_valids( dc1_message_cache_valid   ),
		.update_en  ( dc3_update_plru_en        ),
		.update_set ( dc3_update_plru_set       ),
		.update_way ( dc3_update_plru_way       ),
		.read_way   ( lru_way                   )
	);

	oh_to_idx #(
		.NUM_SIGNALS( `L2_CACHE_WAY           ),
		.DIRECTION  ( "LSB0"                  ),
		.INDEX_WIDTH( $clog2( `L2_CACHE_WAY ) )
	) u_oh_to_idx (
		.one_hot( hit_oh  ),
		.index  ( hit_idx )
	);

	assign hit              = |hit_oh;

	// Whenever an hit occurs, the control logic fetches the next line to use form the LRU, in order to use it 
	// in case of replacement 
	assign selected_way     = hit ? hit_idx : lru_way;
	
//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 2 - Data cache
//  -----------------------------------------------------------------------
	
	memory_bank_1r1w #(
		.SIZE       ( `L2_CACHE_SET * `L2_CACHE_WAY                           ),
		.ADDR_WIDTH ( `L2_CACHE_SET_LENGTH + `L2_CACHE_WAY_LENGTH             ),
		.COL_WIDTH  ( `TILE_COUNT + $bits( tile_address_t ) + `L2_CACHE_WIDTH ),
		.NB_COL     ( 1                                                       ),
		.WRITE_FIRST( "FALSE"                                                 )
	) u_memory_bank_1r1w (
		.clock        ( clk                                                                               ),
		.read_enable  ( dc1_message_valid                                                                 ),
		.read_address ( {dc1_message_address.index, selected_way}                                         ),
		.write_enable ( dc3_update_cache_enable                                                           ),
		.write_address( {dc3_update_cache_set, dc3_update_cache_way}                                      ),
		.write_data   ( {dc3_update_cache_sharers_list, dc3_update_cache_owner, dc3_update_cache_data}    ),
		.read_data    ( {dc2_message_cache_sharers_list, dc2_message_cache_owner, dc2_message_cache_data} )
	);

	assign dc2_pending      = dc1_message_valid,
		dc2_pending_address = dc1_message_address;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 2 - Output registers
//  -----------------------------------------------------------------------

	always_ff @( posedge clk ) begin

		dc2_message_type             <= dc1_message_type;
		dc2_message_address          <= dc1_message_address;
		dc2_message_data             <= dc1_message_data;
		dc2_message_source           <= dc1_message_source;

		dc2_replacement_state        <= dc1_replacement_state;
		dc2_replacement_sharers_list <= dc1_replacement_sharers_list;
		dc2_replacement_owner        <= dc1_replacement_owner;

		dc2_message_tshr_hit         <= dc1_message_tshr_hit;
		dc2_message_tshr_index       <= dc1_message_tshr_index;
		dc2_message_tshr_entry_info  <= dc1_message_tshr_entry_info;

		dc2_message_cache_hit        <= hit;
		dc2_message_cache_valid      <= dc1_message_cache_valid[selected_way];
		dc2_message_cache_state      <= dc1_message_cache_state[selected_way];
		dc2_message_cache_tag        <= dc1_message_cache_tag[selected_way];
		dc2_message_cache_way        <= selected_way;
	end

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			dc2_message_valid <= 1'b0;
		end else begin
			dc2_message_valid <= dc1_message_valid;
		end

	end

endmodule
