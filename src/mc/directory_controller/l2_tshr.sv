`timescale 1ns / 1ps
`include "npu_coherence_defines.sv"

module l2_tshr #(
		WRITE_FIRST = "FALSE"
	)(
		input  logic                                       clk,
		input  logic                                       enable,
		input  logic                                       reset,

		input  l2_cache_tag_t [`TSHR_LOOKUP_PORTS - 1 : 0] lookup_tag,
		input  l2_cache_set_t [`TSHR_LOOKUP_PORTS - 1 : 0] lookup_set,
		output logic          [`TSHR_LOOKUP_PORTS - 1 : 0] lookup_hit,
		output tshr_idx_t     [`TSHR_LOOKUP_PORTS - 1 : 0] lookup_index,
		output tshr_entry_t   [`TSHR_LOOKUP_PORTS - 1 : 0] lookup_entry,

		output logic                                       full,
		output tshr_idx_t                                  empty_index,

		input  logic                                       update_en,
		input  tshr_idx_t                                  update_index,
		input  tshr_entry_t                                update_entry
	);

	tshr_entry_t [`TSHR_SIZE - 1 : 0] data;
	tshr_entry_t [`TSHR_SIZE - 1 : 0] data_updated;
	logic        [`TSHR_SIZE - 1 : 0] empty_oh;
	logic                             is_not_full;


	assign full = !is_not_full;

	generate
		genvar tshr_id;
		for ( tshr_id = 0; tshr_id < `TSHR_SIZE; tshr_id++ ) begin : tshr_entries

			logic update_this_index;
			assign update_this_index = update_en & ( update_index == tshr_idx_t'( tshr_id ) );

			if ( WRITE_FIRST == "TRUE" )
				assign data_updated[tshr_id] = ( enable && update_this_index ) ? update_entry : data[tshr_id];
			else
				assign data_updated[tshr_id] = data[tshr_id];

			assign empty_oh[tshr_id] = ~( data_updated[tshr_id].valid );

			always_ff @( posedge clk, posedge reset ) begin
				if ( reset ) begin
					data[tshr_id].valid        <= 1'b0;
					data[tshr_id].owner        <= tile_address_t'( 0 );
					data[tshr_id].sharers_list <= {`TILE_COUNT{1'b0}};
					data[tshr_id].state        <= directory_state_t'({`DIRECTORY_STATE_WIDTH{1'b0}});
					data[tshr_id].address      <= l2_cache_address_t'( 0 );
				end else if ( enable && update_this_index )
					data[tshr_id]              <= update_entry;
			end
		end
	endgenerate


	generate
		genvar lookup_port_idx;
		for ( lookup_port_idx = 0; lookup_port_idx < `TSHR_LOOKUP_PORTS; lookup_port_idx++ ) begin :lookup_ports

			l2_tshr_lookup_unit lookup_unit (
				.tag         ( lookup_tag[lookup_port_idx]   ),
				.index       ( lookup_set[lookup_port_idx]   ),
				.tshr_entries( data_updated                  ),
				.hit         ( lookup_hit[lookup_port_idx]   ),
				.tshr_index  ( lookup_index[lookup_port_idx] ),
				.tshr_entry  ( lookup_entry[lookup_port_idx] )
			);

		end
	endgenerate

	priority_encoder_npu #(
		.INPUT_WIDTH ( `TSHR_SIZE ),
		.MAX_PRIORITY( "LSB"      )
	)
	u_priority_encoder (
		.decode( empty_oh    ),
		.encode( empty_index ),
		.valid ( is_not_full )
	);

endmodule


module l2_tshr_lookup_unit (
		input  l2_cache_tag_t                      tag,
		input  l2_cache_set_t                      index,
		input  tshr_entry_t   [`TSHR_SIZE - 1 : 0] tshr_entries,

		output logic                               hit,
		output tshr_idx_t                          tshr_index,
		output tshr_entry_t                        tshr_entry
	);

	logic  [`TSHR_SIZE - 1 : 0]           hit_map;
	logic  [$clog2( `TSHR_SIZE ) - 1 : 0] selected_index;

	genvar                                i;
	generate
		for ( i = 0; i < `TSHR_SIZE; i++ ) begin : lookup_logic
			assign hit_map[i] = ( tshr_entries[i].address.tag == tag ) &&( tshr_entries[i].address.index == index ) && tshr_entries[i].valid;
		end
	endgenerate


	oh_to_idx #(
		.NUM_SIGNALS( `TSHR_SIZE ),
		.DIRECTION  ( "LSB0"     )
	)
	u_oh_to_idx (
		.index  ( selected_index ),
		.one_hot( hit_map        )
	);

	assign tshr_entry = tshr_entries[selected_index];
	assign hit        = |hit_map;
	assign tshr_index = selected_index;

endmodule
