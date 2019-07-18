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
`include "npu_network_defines.sv"
`include "npu_coherence_defines.sv"

// Empty tile, a NONE tile allocates only shared network- and coherence-related components. 

module tile_none # (
		parameter TILE_ID        = 0,
		parameter TILE_MEMORY_ID = 0 )
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
	logic                         [`VC_PER_PORT - 1 : 0]                    router_credit;
	logic                         [`VC_PER_PORT - 1 : 0]                    ni_credit;

	logic                         [`PORT_NUM - 1 : 0]                       wr_en_in;
	flit_t                        [`PORT_NUM - 1 : 0]                       flit_in;
	logic                         [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_in;
	logic                         [`PORT_NUM - 1 : 0]                       wr_en_out;
	flit_t                        [`PORT_NUM - 1 : 0]                       flit_out;
	logic                         [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_out;

	//---- Directory controller Signals ----//
	// Forwarded Request
	coherence_forwarded_message_t                       dc_forwarded_request;
	logic                                               dc_forwarded_request_valid;
	logic                         [`TILE_COUNT - 1 : 0] dc_forwarded_request_destinations;
	logic                                               ni_forwarded_request_network_available;
	// Request
	coherence_request_message_t                         ni_request;
	logic                                               ni_request_valid;
	logic                                               dc_request_consumed;
	// Response Inject
	coherence_response_message_t                        dc_response;
	logic                                               dc_response_valid;
	logic                                               dc_response_has_data;
	logic                         [`TILE_COUNT - 1 : 0] dc_response_destinations;
	tile_address_t                                      dc_response_destination_idx;
	logic                                               ni_response_dc_network_available;
	// Response Eject
	logic                                               ni_response_to_dc_valid;
	coherence_response_message_t                        ni_response_to_dc;
	logic                                               dc_response_to_dc_consumed;

//  -----------------------------------------------------------------------
//  -- Tile None - Network Interface
//  -----------------------------------------------------------------------
	network_interface_core #(
		.X_ADDR( X_ADDR ),
		.Y_ADDR( Y_ADDR )
	)
	network_interface_core (
		.clk                                    ( clk                                    ),
		.reset                                  ( reset                                  ),
		.enable                                 ( enable                                 ),

		//CACHE CONTROLLER INTERFACE
		//Request
		.l1d_request                            (                                        ),
		.l1d_request_valid                      ( 1'b0                                   ),
		.l1d_request_has_data                   (                                        ),
		.l1d_request_destinations               (                                        ),
		.l1d_request_destinations_valid         (                                        ),
		.ni_request_network_available           (                                        ),
		//Forwarded Request
		.ni_forwarded_request                   (                                        ),
		.ni_forwarded_request_valid             (                                        ),
		.l1d_forwarded_request_consumed         ( 1'b0                                   ),
		.ni_forwarded_request_cc_network_available (                                     ),
		//Response Inject
		.l1d_response                           ( ),
		.l1d_response_valid                     ( 1'b0                                   ),
		.l1d_response_has_data                  ( 1'b0                                   ),
		.l1d_response_to_cc_valid               ( 1'b0                                   ),
		.l1d_response_to_cc                     (                                        ),
		.l1d_response_to_dc_valid               ( 1'b0                                   ),
		.l1d_response_to_dc                     (                                        ),
		.ni_response_cc_network_available       (                                        ),
		//Forward Inject
		.l1d_forwarded_request_valid            ( 1'b0                                   ),
		.l1d_forwarded_request                  (                                        ),
		.l1d_forwarded_request_destination      (                                        ),
		//Response Eject
		.ni_response_to_cc_valid                (                                        ),
		.ni_response_to_cc                      (                                        ),
		.l1d_response_to_cc_consumed            ( 1'b0                                   ),

		//DIRECTORY CONTROLLER
		//Forwarded Request
		.dc_forwarded_request                      ( dc_forwarded_request                   ),
		.dc_forwarded_request_valid                ( dc_forwarded_request_valid             ),
		.dc_forwarded_request_destinations_valid   ( dc_forwarded_request_destinations      ),
		.ni_forwarded_request_dc_network_available ( ni_forwarded_request_network_available ),
		//Request
		.ni_request                             ( ni_request                             ),
		.ni_request_valid                       ( ni_request_valid                       ),
		.dc_request_consumed                    ( dc_request_consumed                    ),
		//Response Inject
		.dc_response                            ( dc_response                            ),
		.dc_response_valid                      ( dc_response_valid                      ),
		.dc_response_has_data                   ( dc_response_has_data                   ),
		.dc_response_destination                ( dc_response_destination_idx            ),
		.ni_response_dc_network_available       ( ni_response_dc_network_available       ),
		//Response Eject
		.ni_response_to_dc_valid                ( ni_response_to_dc_valid                ),
		.ni_response_to_dc                      ( ni_response_to_dc                      ),
		.dc_response_to_dc_consumed             ( dc_response_to_dc_consumed             ),

		//VC SERVICE INTERFACE
		//Core to Net
		.c2n_mes_service                        (                                        ),
		.c2n_mes_service_valid                  ( 1'b0                                   ),
		.c2n_mes_service_has_data               (                                        ),
		.c2n_mes_service_destinations_valid     (                                        ),
		.ni_c2n_mes_service_network_available   (                                        ),
		//Net to Core
		.ni_n2c_mes_service                     (                                        ),
		.ni_n2c_mes_service_valid               (                                        ),
		.c2n_mes_service_consumed               ( 1'b0                                   ),

		//ROUTER INTERFACE
		// flit in/out
		.ni_flit_out                            ( flit_in [LOCAL]                        ),
		.ni_flit_out_valid                      ( wr_en_in [LOCAL ]                      ),
		.router_flit_in                         ( flit_out [LOCAL ]                      ),
		.router_flit_in_valid                   ( wr_en_out [LOCAL ]                     ),
		// on-off backpressure
		.router_credit                          ( router_credit                          ),
		.ni_credit                              ( ni_credit                              )

	);

//  -----------------------------------------------------------------------
//  -- Tile - Directory Controller
//  -----------------------------------------------------------------------

	directory_controller #(
		.TILE_ID       ( TILE_ID        ),
		.TILE_MEMORY_ID( TILE_MEMORY_ID )
	)
	directory_controller (
		.clk                                   ( clk                                    ),
		.reset                                 ( reset                                  ),
		//From Thread Controller
		.tc_instr_request_valid                ( 1'b0                                   ),
		.tc_instr_request_address              (                                        ),
		//To Thread Controller
		.mem_instr_request_available           (                                        ),
		//From Network Interface
		.ni_response_network_available         ( ni_response_dc_network_available       ),
		.ni_forwarded_request_network_available( ni_forwarded_request_network_available ),
		.ni_request_valid                      ( ni_request_valid                       ),
		.ni_request                            ( ni_request                             ),
		.ni_response_valid                     ( ni_response_to_dc_valid                ),
		.ni_response                           ( ni_response_to_dc                      ),
		//To Network Interface
		.dc_request_consumed                   ( dc_request_consumed                    ),
		.dc_response_consumed                  ( dc_response_to_dc_consumed             ),
		.dc_forwarded_request                  ( dc_forwarded_request                   ),
		.dc_forwarded_request_valid            ( dc_forwarded_request_valid             ),
		.dc_forwarded_request_destinations     ( dc_forwarded_request_destinations      ),
		.dc_response                           ( dc_response                            ),
		.dc_response_valid                     ( dc_response_valid                      ),
		.dc_response_has_data                  ( dc_response_has_data                   ),
		.dc_response_destinations              ( dc_response_destinations               )
	);

	oh_to_idx #(
		.NUM_SIGNALS( `TILE_COUNT             ),
		.DIRECTION  ( "LSB0"                  ),
		.INDEX_WIDTH( $bits( tile_address_t ) )
	)
	dc_destination_oh_to_idx (
		.one_hot( dc_response_destinations    ),
		.index  ( dc_response_destination_idx )
	);

//  -----------------------------------------------------------------------
//  -- Tile None - Router
//  -----------------------------------------------------------------------

	assign router_credit[VC0]           = on_off_out [LOCAL ][VC0];
	assign router_credit[VC1]           = on_off_out [LOCAL ][VC1];
	assign router_credit[VC2]           = on_off_out [LOCAL ][VC2];
	assign router_credit[VC3]           = on_off_out [LOCAL ][VC3];

	assign on_off_in[LOCAL ] [VC0]      = ni_credit[VC0];
	assign on_off_in[LOCAL ] [VC1]      = ni_credit[VC1];
	assign on_off_in[LOCAL ] [VC2]      = ni_credit[VC2];
	assign on_off_in[LOCAL ] [VC3]      = ni_credit[VC3];

	// All router port are directly connected to the tile output. Instead, the local port
	// is connected to the Network Interface.
	assign tile_flit_out_valid                    = wr_en_out [`PORT_NUM - 1 : 1];
	assign tile_flit_out                          = flit_out[`PORT_NUM - 1 : 1 ];
	assign tile_on_off_out                        = on_off_out[`PORT_NUM - 1 : 1];
	assign flit_in[`PORT_NUM - 1 : 1 ]            = tile_flit_in;
	assign wr_en_in[`PORT_NUM - 1 : 1 ]           = tile_wr_en_in;
	assign on_off_in[`PORT_NUM - 1 : 1]           = tile_on_off_in;

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
