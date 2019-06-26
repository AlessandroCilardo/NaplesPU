`timescale 1ns / 1ps
`include "npu_message_service_defines.sv"

module c2n_service_scheduler # (
		parameter NUM_FIFO   = 3,
		parameter INDEX_FIFO = 2 // XXX: Must be "ceil[log2(NUM_FIFO)]"
	)
	(
		input                                          clk,
		input                                          reset,

		//From Core-Barrier_core
		output logic                 [NUM_FIFO-1 : 0]  c2n_network_available,
		input  service_message_t     [NUM_FIFO-1 : 0]  c2n_message_out,
		input  logic                 [NUM_FIFO-1 : 0]  c2n_message_out_valid,
		input  tile_mask_t           [NUM_FIFO-1 : 0]  c2n_destination_valid,

		//To Virtual Network
		input  logic                                   network_available,
		output service_message_t                       message_out,
		output logic                                   message_out_valid,
		output logic                 [`TILE_COUNT-1:0] destination_valid
	);

	logic                 [NUM_FIFO-1 : 0]     can_issue;
	logic                 [NUM_FIFO-1 : 0]     full;
	logic                 [NUM_FIFO-1 : 0]     empty;
	logic                 [NUM_FIFO-1 : 0]     can_schedule;
	tile_mask_t           [NUM_FIFO-1 : 0]     c2n_destination_valid_tmp;
	service_message_t     [NUM_FIFO-1 : 0]     message_out_tmp;
	generate

		genvar fifo_i;
		for ( fifo_i = 0; fifo_i < NUM_FIFO; fifo_i++ ) begin : fifo_entries

			sync_fifo #(
				.WIDTH                 ( $bits( service_message_t ) + `TILE_COUNT   ),
				.SIZE                  ( 4                                          ),
				.ALMOST_FULL_THRESHOLD ( 2                                          )
			)
			c2n_sync_fifo (
				.almost_empty(                                                                 ),
				.almost_full ( full [fifo_i]                                                   ),
				.clk         ( clk                                                             ),
				.dequeue_en  ( can_schedule[fifo_i]                                            ),
				.empty       ( empty[fifo_i]                                                   ),
				.enqueue_en  ( c2n_message_out_valid[fifo_i]                                   ),
				.flush_en    ( 1'b0                                                            ), 
				.full        (                                                                 ),
				.reset       ( reset                                                           ),
				.value_i     ( { c2n_message_out[fifo_i] , c2n_destination_valid [fifo_i]}     ),
				.value_o     ( { message_out_tmp[fifo_i] , c2n_destination_valid_tmp[fifo_i] } )
			);
			always_comb begin

				c2n_network_available[fifo_i] = ~full[fifo_i];
			end
			assign can_issue[fifo_i] = ~empty[fifo_i] && network_available;



		end
	endgenerate

	//
	// Arbiter FIFO
	//

	rr_arbiter #(
		.NUM_REQUESTERS( NUM_FIFO ) // XXX: Warning, Set for new FIFO Instance VN Service
	)
	u_rr_arbiter (
		.clk       ( clk          ),
		.grant_oh  ( can_schedule ),
		.request   ( can_issue    ),
		.reset     ( reset        ),
		.update_lru( |can_issue   )
	);


	logic                 [INDEX_FIFO - 1 : 0] index_schedule;
	oh_to_idx #(
		.NUM_SIGNALS( NUM_FIFO   ),
		.DIRECTION  ( "LSB0"     ),
		.INDEX_WIDTH( INDEX_FIFO )
	)
	oh_to_idx (
		.one_hot( can_schedule   ),
		.index  ( index_schedule )
	);

	always_comb begin
		message_out       = message_out_tmp[index_schedule];
		message_out_valid = |can_schedule;
		destination_valid = c2n_destination_valid_tmp[index_schedule];

	end

endmodule
