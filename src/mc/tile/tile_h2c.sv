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
`include "npu_message_service_defines.sv"
`include "npu_coherence_defines.sv"

`ifdef DISPLAY_REQUESTS_MANAGER
`include "npu_debug_log.sv"
`endif

/* The H2C tile interfaces the system with the host through the Item interface. 
 * The npu_item_iternface interprets incoming item from the host and builds service 
 * packets marked as HOST type which encapsulates the command sent by the host. 
 * One the packet is ready, the npu_item_interface forwards it to the destination 
 * tile through the service network. Section Item Interface details service packets 
 * sent by this module. 
 */ 

module tile_h2c # (
		parameter TILE_ID        = 0,
		parameter TILE_MEMORY_ID = 0,
		parameter ITEM_w = 32 ) // Input and output item width (control interface)
	(
		input clk,
		input reset,
		input enable,

		// From Network
		input        [`PORT_NUM - 1 : 1]                       tile_wr_en_in,
		input flit_t [`PORT_NUM - 1 : 1]                       tile_flit_in,
		input        [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_in,

		// To Network
		output        [`PORT_NUM - 1 : 1]                       tile_flit_out_valid,
		output flit_t [`PORT_NUM - 1 : 1]                       tile_flit_out,
		output        [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_out,


		// Interface to Host
		input  [ITEM_w - 1 : 0] item_data_i,  // Input: items from outside
		input                   item_valid_i, // Input: valid signal associated with item_data_i port
		output                  item_avail_o, // Output: avail signal to input port item_data_i
		output [ITEM_w - 1 : 0] item_data_o,  // Output: items to outside
		output                  item_valid_o, // Output: valid signal associated with item_data_o port
		input                   item_avail_i  // Input: avail signal to output port item_data_o
	);

    localparam logic [`TOT_X_NODE_W-1 : 0] X_ADDR = TILE_ID[`TOT_X_NODE_W-1 : 0];
	localparam logic [`TOT_Y_NODE_W-1 : 0] Y_ADDR = TILE_ID[`TOT_X_NODE_W  +: `TOT_Y_NODE_W];

	//---- Router Signals ----//
	logic [`VC_PER_PORT - 1 : 0] router_credit;
	logic [`VC_PER_PORT - 1 : 0] ni_credit;

	logic  [`PORT_NUM - 1 : 0]                       wr_en_in;
	flit_t [`PORT_NUM - 1 : 0]                       flit_in;
	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_in;
	logic  [`PORT_NUM - 1 : 0]                       wr_en_out;
	flit_t [`PORT_NUM - 1 : 0]                       flit_out;
	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_out;

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

	//---- Service Signals ----//
	// From Core to NI
	service_message_t     c2n_mes_service;
	logic                 c2n_mes_valid;
	tile_mask_t           c2n_mes_service_destinations_valid;
	logic                 ni_response_network_available;
	// From NI to Core
	service_message_t     ni_n2c_mes_service;
	logic                 ni_n2c_mes_service_valid;
	logic                 c2n_mes_service_consumed;

	//---- NaplesPU Item Interface Signals ----//
	logic                                  nii_n2c_mes_valid;
	logic                                  nii_service_mes_consumed;

	logic                                  c2n_mes_service_has_data;
	logic                                  ni_c2n_mes_service_network_available;

	localparam NUM_FIFO = 2;
	localparam INDEX_FIFO = 1;

	logic             [NUM_FIFO - 1 : 0]   c2n_network_available;
	service_message_t [NUM_FIFO - 1 : 0]   c2n_message_out;
	logic             [NUM_FIFO - 1 : 0]   c2n_message_out_valid;
	tile_mask_t       [NUM_FIFO - 1 : 0]   c2n_destination_valid;

	// IO Interface
	logic                               io_intf_available_to_core;
	logic                               ldst_io_valid;
	thread_id_t                         ldst_io_thread;
	logic [$bits(io_operation_t)-1 : 0] ldst_io_operation;
	address_t                           ldst_io_address;
	register_t                          ldst_io_data;
	logic                               io_intf_resp_valid;
	thread_id_t                         io_intf_wakeup_thread;
	register_t                          io_intf_resp_data;
	logic                               ldst_io_resp_consumed;
	logic                               io_intf_message_consumed;

	io_message_t                        ni_io_message;
	logic                               ni_io_message_valid;

//  -----------------------------------------------------------------------
//  -- Tile -  Message service scheduler
//  -----------------------------------------------------------------------
	c2n_service_scheduler #(
		.NUM_FIFO  ( NUM_FIFO   ), 
		.INDEX_FIFO( INDEX_FIFO )
	)
	u_c2n_service_scheduler (
		.clk                  ( clk                                  ),
		.reset                ( reset                                ),
		//From Tile
		.c2n_destination_valid( c2n_destination_valid                ),
		.c2n_message_out      ( c2n_message_out                      ),
		.c2n_message_out_valid( c2n_message_out_valid                ),
		.c2n_network_available( c2n_network_available                ),
		//To Virtual Network
		.destination_valid    ( c2n_mes_service_destinations_valid   ),
		.message_out          ( c2n_mes_service                      ),
		.message_out_valid    ( c2n_mes_valid                        ),
		.network_available    ( ni_c2n_mes_service_network_available )
	);

//  -----------------------------------------------------------------------
//  -- Tile - Arbiter Service Message
//  -----------------------------------------------------------------------

	generate
		if ( $bits( service_message_t ) > ( `PAYLOAD_W ) )
			assign c2n_mes_service_has_data = 1'b1;
		else
			assign c2n_mes_service_has_data = 1'b0;
	endgenerate

	sync_message_t n2c_sync_message;

	assign ni_io_message = io_message_t'(ni_n2c_mes_service.data);

	always_comb begin
		c2n_mes_service_consumed = 0;
		ni_io_message_valid      = 1'b0;

		if (ni_n2c_mes_service_valid) begin
			if( ni_n2c_mes_service.message_type == HOST ) begin
				nii_n2c_mes_valid        = ni_n2c_mes_service_valid;
				c2n_mes_service_consumed = nii_service_mes_consumed;
			end else if ( ni_n2c_mes_service.message_type == IO_OP ) begin
				ni_io_message_valid      = ni_n2c_mes_service_valid;
				c2n_mes_service_consumed = io_intf_message_consumed;
			end
		end else begin
			c2n_mes_service_consumed = 1'b0;
		end
	end

//  -----------------------------------------------------------------------
//  -- Tile - IO Interface
//  -----------------------------------------------------------------------
	io_message_t io_intf_message_out;

	assign c2n_message_out[1].message_type = IO_OP;
	assign c2n_message_out[1].data         = service_message_data_t'(io_intf_message_out);

	io_interface #(
		.TILE_ID ( TILE_ID )
	) u_io_intf (
		.clk                        ( clk   ),
		.reset                      ( reset ),

		.io_intf_available_to_core  (      ),
		.ldst_io_valid              ( 1'b0 ),
		.ldst_io_thread             (      ),
		.ldst_io_operation          (      ),
		.ldst_io_address            (      ),
		.ldst_io_data               (      ),
		.io_intf_resp_valid         (      ),
		.io_intf_wakeup_thread      (      ),
		.io_intf_resp_data          (      ),
		.ldst_io_resp_consumed      ( 1'b0 ),

		.slave_available_to_io_intf ( io_intf_available_to_core ),
		.io_intf_valid              ( ldst_io_valid             ),
		.io_intf_thread             ( ldst_io_thread            ),
		.io_intf_operation          ( ldst_io_operation         ),
		.io_intf_address            ( ldst_io_address           ),
		.io_intf_data               ( ldst_io_data              ),
		.slave_resp_valid           ( io_intf_resp_valid        ),
		.slave_wakeup_thread        ( io_intf_wakeup_thread     ),
		.slave_resp_data            ( io_intf_resp_data         ),
		.io_intf_resp_consumed      ( ldst_io_resp_consumed     ),

		.ni_io_network_available    ( c2n_network_available[1]  ),
		.io_intf_message_out        ( io_intf_message_out       ),
		.io_intf_message_out_valid  ( c2n_message_out_valid[1]  ),
		.io_intf_destination_valid  ( c2n_destination_valid[1]  ),

		.io_intf_message_consumed   ( io_intf_message_consumed  ),
		.ni_io_message              ( ni_io_message             ),
		.ni_io_message_valid        ( ni_io_message_valid       )
	);

//  -----------------------------------------------------------------------
//  -- Tile H2C - NaplesPU Item Interface
//  -----------------------------------------------------------------------

	npu_item_interface u_npu_item_interface (
		.clk                   ( clk                   ),
		.reset                 ( reset                 ),

		//Interface To NaplesPU for boot
		.hi_thread_en          (                       ),
		.hi_job_valid          (                       ),
		.hi_job_pc             (                       ),
		.hi_job_thread_id      (                       ),
		.hi_read_cr_valid      (                       ),
		.hi_write_cr_valid     (                       ),
		.hi_read_cr_request    (                       ),
		.hi_write_cr_data      (                       ),
		.cr_response           (                       ),

		// From LDST unit - IO Map interface
		.io_intf_available     ( io_intf_available_to_core ),
		.ldst_io_valid         ( ldst_io_valid             ),
		.ldst_io_thread        ( ldst_io_thread            ),
		.ldst_io_operation     ( ldst_io_operation         ),
		.ldst_io_address       ( ldst_io_address           ),
		.ldst_io_data          ( ldst_io_data              ),
		.io_intf_resp_valid    ( io_intf_resp_valid        ),
		.io_intf_wakeup_thread ( io_intf_wakeup_thread     ),
		.io_intf_resp_data     ( io_intf_resp_data         ),
		.ldst_io_resp_consumed ( ldst_io_resp_consumed     ),

		// Service Network
		.c2n_mes_service                   ( c2n_message_out[0]         ),
		.c2n_mes_valid                     ( c2n_message_out_valid[0]   ),
		.n2c_mes_service                   ( ni_n2c_mes_service         ),
		.n2c_mes_valid                     ( nii_n2c_mes_valid          ),
		.n2c_mes_service_consumed          ( nii_service_mes_consumed   ),
		.ni_network_available              ( c2n_network_available[0]   ),
		.c2n_mes_service_destinations_valid( c2n_destination_valid[0]   ),
		//Interface to external items
		.item_data_i           ( item_data_i           ),
		.item_valid_i          ( item_valid_i          ),
		.item_avail_o          ( item_avail_o          ),
		.item_data_o           ( item_data_o           ),
		.item_valid_o          ( item_valid_o          ),
		.item_avail_i          ( item_avail_i          )
	);

//  -----------------------------------------------------------------------
//  -- Tile H2C - Network Interface
//  -----------------------------------------------------------------------
	// The local router port is directly connected to the Network Interface. The local port is not
	// propagated to the Tile output
	assign router_credit[VC0] = on_off_out [LOCAL ][VC0];
	assign router_credit[VC1] = on_off_out [LOCAL ][VC1];
	assign router_credit[VC2] = on_off_out [LOCAL ][VC2];
	assign router_credit[VC3] = on_off_out [LOCAL ][VC3];

	assign on_off_in[LOCAL ] [VC0] = ni_credit[VC0];
	assign on_off_in[LOCAL ] [VC1] = ni_credit[VC1];
	assign on_off_in[LOCAL ] [VC2] = ni_credit[VC2];
	assign on_off_in[LOCAL ] [VC3] = ni_credit[VC3];

	network_interface_core #(
		.X_ADDR( X_ADDR ),
		.Y_ADDR( Y_ADDR )
	)
	u_network_interface_core (
		.clk    ( clk    ),
		.reset  ( reset  ),
		.enable ( enable ),

		// SERVICE
		//Core to Net
		.c2n_mes_service                      ( c2n_mes_service                      ),
		.c2n_mes_service_valid                ( c2n_mes_valid                        ),
		.c2n_mes_service_has_data             ( c2n_mes_service_has_data             ),
		.c2n_mes_service_destinations_valid   ( c2n_mes_service_destinations_valid   ),
		.ni_c2n_mes_service_network_available ( ni_c2n_mes_service_network_available ),
		//Net to Core
		.ni_n2c_mes_service                   ( ni_n2c_mes_service       ),
		.ni_n2c_mes_service_valid             ( ni_n2c_mes_service_valid ),
		.c2n_mes_service_consumed             ( c2n_mes_service_consumed ),

		//CACHE CONTROLLER INTERFACE
		//Request
		.l1d_request                      (      ),
		.l1d_request_valid                ( 1'b0 ),
		.l1d_request_has_data             (      ),
		.l1d_request_destinations         (      ),
		.l1d_request_destinations_valid   (      ),
		.ni_request_network_available     (      ),
		//Forwarded Request
		.ni_forwarded_request             (      ),
		.ni_forwarded_request_valid       (      ),
		.l1d_forwarded_request_consumed   ( 1'b0 ),
		.ni_forwarded_request_cc_network_available ( ),
		//Response Inject
		.l1d_response                     (      ),
		.l1d_response_valid               ( 1'b0 ),
		.l1d_response_has_data            (      ),
		.l1d_response_to_cc_valid         (      ),
		.l1d_response_to_cc               (      ),
		.l1d_response_to_dc_valid         (      ),
		.l1d_response_to_dc               (      ),
		.ni_response_cc_network_available (      ),
		//Forward Inject
		.l1d_forwarded_request_valid       ( 1'b0 ),
		.l1d_forwarded_request             (      ),
		.l1d_forwarded_request_destination (      ),
		//Response Eject
		.ni_response_to_cc_valid          (      ),
		.ni_response_to_cc                (      ),
		.l1d_response_to_cc_consumed      ( 1'b0 ),

		//DIRECTORY CONTROLLER
		//Forwarded Request
		.dc_forwarded_request                   ( dc_forwarded_request                   ),
		.dc_forwarded_request_valid             ( dc_forwarded_request_valid             ),
		.dc_forwarded_request_destinations_valid( dc_forwarded_request_destinations      ),
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

		//ROUTER INTERFACE
		// flit in/out
		.ni_flit_out          ( flit_in [LOCAL]    ),
		.ni_flit_out_valid    ( wr_en_in [LOCAL ]  ),
		.router_flit_in       ( flit_out [LOCAL ]  ),
		.router_flit_in_valid ( wr_en_out [LOCAL ] ),
		// on-off backpressure
		.router_credit        ( router_credit      ),
		.ni_credit            ( ni_credit          )
	);

//  -----------------------------------------------------------------------
//  -- Tile H2C - Directory Controller
//  -----------------------------------------------------------------------
	directory_controller #(
		.TILE_ID       ( TILE_ID        ),
		.TILE_MEMORY_ID( TILE_MEMORY_ID )
	)
	u_directory_controller (
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
//  -- Tile H2C - Router
//  -----------------------------------------------------------------------
	// All router port are directly connected to the tile output. Instead, the local port
	// is connected to the Network Interface.
	assign tile_flit_out_valid          = wr_en_out [`PORT_NUM - 1 : 1];
	assign tile_flit_out                = flit_out[`PORT_NUM - 1 : 1 ];
	assign tile_on_off_out              = on_off_out[`PORT_NUM - 1 : 1];
	assign flit_in[`PORT_NUM - 1 : 1 ]  = tile_flit_in;
	assign wr_en_in[`PORT_NUM - 1 : 1 ] = tile_wr_en_in;
	assign on_off_in[`PORT_NUM - 1 : 1] = tile_on_off_in;

	router #(
		.MY_X_ADDR( X_ADDR ),
		.MY_Y_ADDR( Y_ADDR )
	)
	u_router (
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
