`timescale 1ns / 1ps
`include "npu_network_defines.sv"

module tile_none # (
		parameter TILE_ID          = 0	)
	(
		input                                         clk,
		input                                         reset,
		input                                         enable,

		// From Network
		input         [`PORT_NUM - 1 : 1]                       tile_wr_en_in,
		input  flit_t [`PORT_NUM - 1 : 1]                       tile_flit_in,
		input         [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_in ,

		// To Network
		output        [`PORT_NUM - 1 : 1]                       tile_flit_out_valid,
		output flit_t [`PORT_NUM - 1 : 1]                       tile_flit_out,
		output        [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_out
	);

	localparam logic [`TOT_X_NODE_W-1 : 0] X_ADDR = TILE_ID[`TOT_X_NODE_W-1 : 0];
	localparam logic [`TOT_Y_NODE_W-1 : 0] Y_ADDR = TILE_ID[`TOT_X_NODE_W  +: `TOT_Y_NODE_W];

	// Router signals
	logic                         [`PORT_NUM - 1 : 0]                       wr_en_in;
	flit_t                        [`PORT_NUM - 1 : 0]                       flit_in;
	logic                         [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_in;
	logic                         [`PORT_NUM - 1 : 0]                       wr_en_out;
	flit_t                        [`PORT_NUM - 1 : 0]                       flit_out;
	logic                         [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_out;

//  -----------------------------------------------------------------------
//  -- Tile None - Router
//  -----------------------------------------------------------------------

	// All router port are directly connected to the tile output. Instead, the local port
	// is connected to the Network Interface.
	assign tile_flit_out_valid                    = wr_en_out [`PORT_NUM - 1 : 1];
	assign tile_flit_out                          = flit_out[`PORT_NUM - 1 : 1 ];
	assign tile_on_off_out                        = on_off_out[`PORT_NUM - 1 : 1];
	assign flit_in[`PORT_NUM - 1 : 1 ]            = tile_flit_in;
	assign wr_en_in[`PORT_NUM - 1 : 1 ]           = tile_wr_en_in;
	assign on_off_in[`PORT_NUM - 1 : 1]           = tile_on_off_in;
	assign on_off_in[0]							  = 1'b1;

	router #(
		.MY_X_ADDR( X_ADDR ),
		.MY_Y_ADDR( Y_ADDR )
	)
	router (
		.wr_en_in  ( wr_en_in   ),
		.flit_in   ( flit_in    ),
		.on_off_in ( on_off_in  ),
		.wr_en_out ( wr_en_out  ),
		.flit_out  ( flit_out   ),
		.on_off_out( on_off_out ),
		.clk       ( clk        ),
		.reset     ( reset      )
	);

endmodule
