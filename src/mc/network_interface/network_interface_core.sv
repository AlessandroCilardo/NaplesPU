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
`include "npu_network_defines.sv"
`include "npu_coherence_defines.sv"
`include "npu_message_service_defines.sv"

/*
 * The Network Interface links all the component in a tile that require to communicate with other elements in the NoC.
 * It has several interfaces with the element inside the tile and an interface with the router.
 * Basically, it has to convert a packet from the tile into flit injected in to the network and viceversa.
 * In order to avoid deadlock, four different virtual network are used: request, forwaded request, response and service network.
 *
 * The interface to the tile communicates with directory controller, cache controller and service unit (boot).
 * The units use the VN in this way:
 *
 *              SERVN -----> BOOT ----> SERVN
 *
 *              FWDN ----|-> CC  -|---> REQN
 *                       |        |
 *              RESPN ---|        |---> RESPN
 *                       |        |
 *                       |-> DC  -|---> FWDN
 *
 * The unit is divided in two parts: 
 *  1 - TO router, in which the vn_core2net units buffer and convert the packet in flit;
 *  2 - FROM router, in which the vn_net2core units buffer and convert the flit in packet.
 * 
 * These two units support the multicast, sending k times a packet in unicast as many as the destinations are.
 *
 * The vn_net2core units should be four as well as vn_core2net units, but the response network is linked with the DC and CC at the same time.
 * So the solution is to add another vn_net2core and vn_core2net unit with the same output of the other one. If the output of the NI contains
 * two different output port - so an output arbiter is useless, the two vn_core2net response units, firstly, has to compete among them and,
 * secondly, among all the VN.
 *
 */

module network_interface_core # (
		parameter X_ADDR = 1,
		parameter Y_ADDR = 1 )
	(
		input                                              clk,
		input                                              reset,
		input                                              enable,
		/*SERVICE MESSAGE*/
		//Core to Net
		input  service_message_t                           c2n_mes_service,                      
		input                                              c2n_mes_service_valid,
		input                                              c2n_mes_service_has_data,
		input  logic                 [`TILE_COUNT - 1 : 0] c2n_mes_service_destinations_valid,
		output logic                                       ni_c2n_mes_service_network_available, 

		//Net to Core
		output service_message_t     ni_n2c_mes_service,
		output logic                 ni_n2c_mes_service_valid,
		input                        c2n_mes_service_consumed,

		/* CACHE CONTROLLER INTERFACE */
		// Request
		input  coherence_request_message_t         l1d_request,
		input                                      l1d_request_valid,
		input                                      l1d_request_has_data,
		input  tile_address_t              [1 : 0] l1d_request_destinations,
		input  logic                       [1 : 0] l1d_request_destinations_valid,
		output logic                               ni_request_network_available,

		// Forwarded Request
		output coherence_forwarded_message_t ni_forwarded_request,
		output logic                         ni_forwarded_request_valid,
		input                                l1d_forwarded_request_consumed,

		// Response from Cache Controller
		input  coherence_response_message_t l1d_response,
		input                               l1d_response_valid,
		input  logic                        l1d_response_has_data,
		input  logic                        l1d_response_to_cc_valid,
		input  tile_address_t               l1d_response_to_cc,
		input  logic                        l1d_response_to_dc_valid,
		input  tile_address_t               l1d_response_to_dc,
		output logic                        ni_response_cc_network_available,

		// Forward from Cache Controller
		input  coherence_forwarded_message_t l1d_forwarded_request,
		input                                l1d_forwarded_request_valid,
		input  tile_address_t                l1d_forwarded_request_destination,
		output logic                         ni_forwarded_request_cc_network_available,

		// Response to Cache Controller
		output logic                        ni_response_to_cc_valid,
		output coherence_response_message_t ni_response_to_cc,
		input                               l1d_response_to_cc_consumed,

		/* DIRECTORY CONTROLLER */
		// Forwarded Request
		input  coherence_forwarded_message_t                       dc_forwarded_request,
		input                                                      dc_forwarded_request_valid,
		input  logic                         [`TILE_COUNT - 1 : 0] dc_forwarded_request_destinations_valid,
		output logic                                               ni_forwarded_request_dc_network_available,

		// Request
		output coherence_request_message_t ni_request,
		output logic                       ni_request_valid,
		input                              dc_request_consumed,

		// Response Inject
		input  coherence_response_message_t dc_response,
		input                               dc_response_valid,
		input  logic                        dc_response_has_data,
		input  tile_address_t               dc_response_destination,
		output logic                        ni_response_dc_network_available,

		// Response Eject
		output logic                        ni_response_to_dc_valid,
		output coherence_response_message_t ni_response_to_dc,
		input                               dc_response_to_dc_consumed,

		/* ROUTER INTERFACE */
		output flit_t ni_flit_out,
		output logic  ni_flit_out_valid,

		input flit_t router_flit_in,
		input        router_flit_in_valid,

		input  logic [`VC_PER_PORT - 1 : 0] router_credit,
		output logic [`VC_PER_PORT - 1 : 0] ni_credit

	);

	flit_t [`VC_PER_PORT - 1 : 0] vn_flit_out;
	logic  [`VC_PER_PORT - 1 : 0] vn_flit_valid;

	logic [`VC_PER_PORT - 1 : 0]            vn_packet_pending;
	logic [`VC_PER_PORT - 1 : 0]            vno_requests, vno_granted;
	logic [$clog2 ( `VC_PER_PORT ) - 1 : 0] vco_granted_id;

	logic [`VC_PER_PORT - 1 : 0] vn_packet_fifo_full;
	logic                        vn_ntc_credit_dc, vn_ntc_credit_cc;

    localparam DC_ID  = 0; // l'enum non funziona, non so perch�
    localparam CC_ID  = 1;

//  -----------------------------------------------------------------------
//  -- Network Interface - Response Virtual Network Arbiter
//  -----------------------------------------------------------------------
	// Response Virtual Network access arbiter
	logic                 [1 : 0] response_vn_grant_oh;
	logic                 [1 : 0] response_pending_tmp;
	core_to_net_pending_t [1 : 0] response_in;

	assign response_pending_tmp = { response_in[CC_ID].vn_packet_pending, response_in[DC_ID].vn_packet_pending };

	// Beware in case of multi-core, the requestor number is the number of core per tile!
	// Dato che in uscita non posso mischiare le richieste verso lo stesso VC, devo usare un grant-hold arbiter
	// in modo che venga inviato un intero pacchetto prima che possa essere interrotto da altri
	grant_hold_round_robin_arbiter #(
		.SIZE( 2 )
	)
	response_vn_rr_arbiter (
		.clk         ( clk                  ),
		.reset       ( reset                ),
		.requests    ( response_pending_tmp ),
		.hold_in     ( response_pending_tmp ),
		.decision_oh ( response_vn_grant_oh )
	);

	assign vn_packet_pending[ VC1 ] = |response_vn_grant_oh ;
	assign vn_flit_out[VC1]         = response_vn_grant_oh[0]? response_in[DC_ID].vn_flit_out   : response_in[CC_ID].vn_flit_out;
	assign vn_flit_valid[VC1]       = response_vn_grant_oh[0]? response_in[DC_ID].vn_flit_valid : response_in[CC_ID].vn_flit_valid;

//  -----------------------------------------------------------------------
//  -- Network Interface - Forward Virtual Network Arbiter
//  -----------------------------------------------------------------------
	// Forward Virtual Network access arbiter
	logic                 [1 : 0] forward_vn_grant_oh;
	logic                 [1 : 0] forward_pending_tmp;
	core_to_net_pending_t [1 : 0] forward_in;

	assign forward_pending_tmp = {forward_in[CC_ID].vn_packet_pending, forward_in[DC_ID].vn_packet_pending} ;

	// Beware in case of multi-core, the requestor number is the number of core per tile!
	grant_hold_round_robin_arbiter #(
		.SIZE( 2 )
	)
	forward_vn_rr_arbiter (
		.clk         ( clk                  ),
		.reset       ( reset                ),
		.requests    ( forward_pending_tmp ),
		.hold_in     ( forward_pending_tmp ),
		.decision_oh ( forward_vn_grant_oh )
	);

	assign vn_packet_pending[VC2]   = |forward_vn_grant_oh ;
	assign vn_flit_out[VC2]         = forward_vn_grant_oh[0]? forward_in[DC_ID].vn_flit_out   : forward_in[CC_ID].vn_flit_out;
	assign vn_flit_valid[VC2]       = forward_vn_grant_oh[0]? forward_in[DC_ID].vn_flit_valid : forward_in[CC_ID].vn_flit_valid;

//  -----------------------------------------------------------------------
//  -- Network Interface - To Router Arbiter
//  -----------------------------------------------------------------------
	// The router uses a on/off back pressure mechanism, if the credit signal is high there are no
	// more room in router VC FIFOs.

	assign vno_requests =
		{vn_packet_pending[ VC3 ] & ~router_credit[VC3],
			vn_packet_pending[ VC2 ] & ~router_credit[VC2],
			vn_packet_pending[ VC1 ] & ~router_credit[VC1],
			vn_packet_pending[ VC0 ] & ~router_credit[VC0]};

	round_robin_arbiter # (
		.SIZE ( `VC_PER_PORT )
	)
	ni_request_round_robin_arbiter (
		.clk         ( clk          ),
		.reset       ( reset        ),
		.en          ( 1'b1         ),
		.requests    ( vno_requests ),
		.decision_oh ( vno_granted  )
	) ;

	oh_to_idx # (
		.NUM_SIGNALS ( `VC_PER_PORT ),
		.DIRECTION   ( "LSB0"       )
	)
	ni_request_grant_oh_to_idx (
		.one_hot ( vno_granted    ),
		.index   ( vco_granted_id )
	);

	assign ni_flit_out    = vn_flit_out[vco_granted_id],
		ni_flit_out_valid = vn_flit_valid[vco_granted_id];

//  -----------------------------------------------------------------------
//  -- Network Interface - TO Router
//  -----------------------------------------------------------------------

	// --- Request Virtual Network VC0 --- //

	virtual_network_core_to_net # (
		.DEST_OH                      ( "FALSE"                               ),
		.X_ADDR                       ( X_ADDR                                ),
		.Y_ADDR                       ( Y_ADDR                                ),
		.VCID                         ( VC0                                   ),
		.PACKET_BODY_SIZE             ( $bits ( coherence_request_message_t ) ),
		.DEST_NUMB                    ( 2                                     ), //almost 2 destinations (Directory and Requestor)
		.PACKET_FIFO_SIZE             ( `REQ_FIFO_SIZE                        ),
		.PACKET_ALMOST_FULL_THRESHOLD ( `REQ_ALMOST_FULL                      )
	)
	request_virtual_network_core_to_net (
		.clk                       ( clk                            ),
		.reset                     ( reset                          ),
		.enable                    ( enable                         ),
		//Request from Cache Controller / Directory
		.packet_valid              ( l1d_request_valid              ),
		.packet_body               ( l1d_request                    ),
		.packet_has_data           ( l1d_request_has_data           ),
		.packet_destinations       ( l1d_request_destinations       ),
		.packet_destinations_valid ( l1d_request_destinations_valid ),
		//To the Cache Controller / Directory, cannot receive more packets
		.vn_packet_fifo_full       ( vn_packet_fifo_full[ VC0 ]     ),
		//To NI for arbitration
		.vn_packet_pending         ( vn_packet_pending[ VC0 ]       ),
		//The router is available to receive a FLIT
		.flit_credit               ( vno_granted[ VC0 ]             ),
		//Output to the Router Virtual Channel
		.vn_flit_valid             ( vn_flit_valid[ VC0 ]           ),
		.vn_flit_out               ( vn_flit_out[ VC0 ]             )
	);

	assign ni_request_network_available = ~vn_packet_fifo_full[ VC0 ];


	// --- Response Virtual Network VC1 --- //

	virtual_network_core_to_net # (
		.DEST_OH                      ( "FALSE"                               ),
		.X_ADDR                       ( X_ADDR                                ),
		.Y_ADDR                       ( Y_ADDR                                ),
		.VCID                         ( VC1                                   ),
		.PACKET_BODY_SIZE             ( $bits( coherence_response_message_t ) ),
		.DEST_NUMB                    ( 2                                     ),
		.PACKET_FIFO_SIZE             ( `RESP_FIFO_SIZE                       ),
		.PACKET_ALMOST_FULL_THRESHOLD ( `RESP_ALMOST_FULL                     )
	)
	response_cc_virtual_network_core_to_net (
		.clk                       ( clk                                                   ),
		.reset                     ( reset                                                 ),
		.enable                    ( enable                                                ),
		//Request from Cache Controller / Directory
		.packet_valid              ( l1d_response_valid                                    ),
		.packet_body               ( l1d_response                                          ),
		.packet_has_data           ( l1d_response_has_data                                 ),
		.packet_destinations       ( {l1d_response_to_cc , l1d_response_to_dc}             ),
		.packet_destinations_valid ( {l1d_response_to_cc_valid , l1d_response_to_dc_valid} ),
		//To the Cache Controller / Directory, cannot receive more packets
		.vn_packet_fifo_full       ( response_in[ CC_ID ].vn_packet_fifo_full              ),
		//To NI for arbitration
		.vn_packet_pending         ( response_in[ CC_ID ].vn_packet_pending                ),
		//The router is available to receive a FLIT
		.flit_credit               ( vno_granted [ VC1 ] & response_vn_grant_oh[CC_ID]     ),
		//Output to the Router Virtual Channel
		.vn_flit_valid             ( response_in[ CC_ID ] .vn_flit_valid                   ),
		.vn_flit_out               ( response_in[ CC_ID ].vn_flit_out                      )
	);

	assign ni_response_cc_network_available = ~ response_in[ CC_ID ].vn_packet_fifo_full ;

	virtual_network_core_to_net # (
		.DEST_OH                      ( "FALSE"                               ),
		.X_ADDR                       ( X_ADDR                                ),
		.Y_ADDR                       ( Y_ADDR                                ),
		.VCID                         ( VC1                                   ),
		.PACKET_BODY_SIZE             ( $bits( coherence_response_message_t ) ),
		.DEST_NUMB                    ( 2                                     ),
		.PACKET_FIFO_SIZE             ( `RESP_FIFO_SIZE                       ),
		.PACKET_ALMOST_FULL_THRESHOLD ( `RESP_ALMOST_FULL                     )
	)
	response_dc_virtual_network_core_to_net (
		.clk                       ( clk                                                        ),
		.reset                     ( reset                                                      ),
		.enable                    ( enable                                                     ),
		//Request from Cache Controller / Directory
		.packet_valid              ( dc_response_valid                                          ),
		.packet_body               ( dc_response                                                ),
		.packet_has_data           ( dc_response_has_data                                       ),
		.packet_destinations       ( {dc_response_destination, {$bits( tile_address_t ){1'b0}}} ),
		.packet_destinations_valid ( {1'b1,1'b0}                                                ),
		//To the Cache Controller / Directory, cannot receive more packets
		.vn_packet_fifo_full       ( response_in[ DC_ID ].vn_packet_fifo_full                   ),
		//To NI for arbitration
		.vn_packet_pending         ( response_in[ DC_ID ].vn_packet_pending                     ),
		//The router is available to receive a FLIT
		.flit_credit               ( vno_granted [ VC1 ] & response_vn_grant_oh[DC_ID]          ),
		//Output to the Router Virtual Channel
		.vn_flit_valid             ( response_in[ DC_ID ].vn_flit_valid                         ),
		.vn_flit_out               ( response_in[ DC_ID ].vn_flit_out                           )
	);

	assign ni_response_dc_network_available = ~ response_in[ DC_ID ].vn_packet_fifo_full;

	// --- Forwarded Request Virtual Network VC2 --- //

	virtual_network_core_to_net # (
		.DEST_OH                      ( "TRUE"                                  ),
		.X_ADDR                       ( X_ADDR                                  ),
		.Y_ADDR                       ( Y_ADDR                                  ),
		.VCID                         ( VC2                                     ),
		.PACKET_BODY_SIZE             ( $bits ( coherence_forwarded_message_t ) ),
		.DEST_NUMB                    ( `TILE_COUNT                             ),
		.PACKET_FIFO_SIZE             ( `FWD_FIFO_SIZE                          ),
		.PACKET_ALMOST_FULL_THRESHOLD ( `FWD_ALMOST_FULL                        )
	)
	forwarded_request_dc_virtual_network_core_to_net (
		.clk                       ( clk                                     ),
		.reset                     ( reset                                   ),
		.enable                    ( enable                                  ),
		//Request from Cache Controller / Directory
		.packet_valid              ( dc_forwarded_request_valid              ),
		.packet_body               ( dc_forwarded_request                    ),
		.packet_has_data           ( 1'b0                                    ),
		.packet_destinations       ( '{default : 0}                          ),
		.packet_destinations_valid ( dc_forwarded_request_destinations_valid ),
		//To the Cache Controller / Directory, cannot receive more packets
		.vn_packet_fifo_full       ( forward_in[DC_ID].vn_packet_fifo_full          ),
		//To NI for arbitration
		.vn_packet_pending         ( forward_in[DC_ID].vn_packet_pending            ),
		//The router is available to receive a FLIT
		.flit_credit               ( vno_granted [VC2] & forward_vn_grant_oh[DC_ID] ),
		//Output to the Router Virtual Channel
		.vn_flit_valid             ( forward_in[DC_ID].vn_flit_valid                ),
		.vn_flit_out               ( forward_in[DC_ID].vn_flit_out                  )
	) ;

	assign ni_forwarded_request_dc_network_available = ~forward_in[DC_ID].vn_packet_fifo_full;

	virtual_network_core_to_net # (
		.DEST_OH                      ( "FALSE"                                 ),
		.X_ADDR                       ( X_ADDR                                  ),
		.Y_ADDR                       ( Y_ADDR                                  ),
		.VCID                         ( VC2                                     ),
		.PACKET_BODY_SIZE             ( $bits ( coherence_forwarded_message_t ) ),
		.DEST_NUMB                    ( 2                                       ),
		.PACKET_FIFO_SIZE             ( `FWD_FIFO_SIZE                          ),
		.PACKET_ALMOST_FULL_THRESHOLD ( `FWD_ALMOST_FULL                        )
	)
	forwarded_request_cc_virtual_network_core_to_net (
		.clk                       ( clk                                            ),
		.reset                     ( reset                                          ),
		.enable                    ( enable                                         ),
		//Request from Cache Controller / Directory
		.packet_valid              ( l1d_forwarded_request_valid                    ),
		.packet_body               ( l1d_forwarded_request                          ),
		.packet_has_data           ( 1'b0                                           ),
		.packet_destinations       ( {l1d_forwarded_request_destination, {$bits( tile_address_t ){1'b0}}} ),
		.packet_destinations_valid ( {1'b1, 1'b0}                                   ),
		//To the Cache Controller / Directory, cannot receive more packets
		.vn_packet_fifo_full       ( forward_in[CC_ID].vn_packet_fifo_full          ),
		//To NI for arbitration
		.vn_packet_pending         ( forward_in[CC_ID].vn_packet_pending            ),
		//The router is available to receive a FLIT
		.flit_credit               ( vno_granted [VC2] & forward_vn_grant_oh[CC_ID] ),
		//Output to the Router Virtual Channel
		.vn_flit_valid             ( forward_in[CC_ID].vn_flit_valid                ),
		.vn_flit_out               ( forward_in[CC_ID].vn_flit_out                  )
	) ;

	assign ni_forwarded_request_cc_network_available = ~forward_in[CC_ID].vn_packet_fifo_full;

	// --- Service Virtual Network VC3 --- //

	virtual_network_core_to_net # (
		.DEST_OH                      ( "TRUE"                          ),
		.X_ADDR                       ( X_ADDR                          ),
		.Y_ADDR                       ( Y_ADDR                          ),
		.VCID                         ( VC3                             ),
		.PACKET_BODY_SIZE             ( $bits ( service_message_t )     ),
		.DEST_NUMB                    ( `TILE_COUNT                     ),
		.PACKET_FIFO_SIZE             ( `SERV_FIFO_SIZE                 ),
		.PACKET_ALMOST_FULL_THRESHOLD ( `SERV_ALMOST_FULL               )
	)
	service_virtual_network_core_to_net (
		.clk                       ( clk                                ),
		.reset                     ( reset                              ),
		.enable                    ( enable                             ),
		//Request from Core(componente generico da connettere)
		.packet_valid              ( c2n_mes_service_valid              ),
		.packet_body               ( c2n_mes_service                    ),
		.packet_has_data           ( c2n_mes_service_has_data           ),
		.packet_destinations       ( '{default : 0}                     ),
		.packet_destinations_valid ( c2n_mes_service_destinations_valid ),
		//To Core(generic component), cannot receive more packets
		.vn_packet_fifo_full       ( vn_packet_fifo_full[ VC3 ]         ),
		//To NI for arbitration
		.vn_packet_pending         ( vn_packet_pending[ VC3 ]           ),
		//The router is available to receive a FLIT
		.flit_credit               ( vno_granted [ VC3 ]                ),
		//Output to the Router Virtual Channel
		.vn_flit_valid             ( vn_flit_valid[ VC3 ]               ),
		.vn_flit_out               ( vn_flit_out[ VC3 ]                 )
	);

	assign ni_c2n_mes_service_network_available = ~vn_packet_fifo_full[ VC3 ] ;


//  -----------------------------------------------------------------------
//  -- Network Interface - FROM Router
//  -----------------------------------------------------------------------

	// --- Request Virtual Network VC0 --- //

	virtual_network_net_to_core # (
		.VCID             ( VC0                                   ),
		.PACKET_BODY_SIZE ( $bits ( coherence_request_message_t ) ),
		.PACKET_FIFO_SIZE ( `REQ_FIFO_SIZE                        )
	)
	request_virtual_network_net_to_core (
		.clk                  ( clk                  ),
		.reset                ( reset                ),
		.enable               ( enable               ),
		//Cache Controller interface
		.vn_ntc_packet_out    ( ni_request           ),
		.vn_ntc_packet_valid  ( ni_request_valid     ),
		.core_packet_consumed ( dc_request_consumed  ),
		//Router interface
		.vn_ntc_credit        ( ni_credit[VC0]       ),
		.router_flit_valid    ( router_flit_in_valid ),
		.router_flit_in       ( router_flit_in       )
	);


	// --- Response Virtual Network VC1 --- //

	virtual_network_net_to_core # (
		.TYPE             ( "CC"                                   ),
		.VCID             ( VC1                                    ),
		.PACKET_BODY_SIZE ( $bits ( coherence_response_message_t ) ),
		.PACKET_FIFO_SIZE ( `RESP_FIFO_SIZE                        )
	)
	response_cc_virtual_network_net_to_core (
		.clk                  ( clk                         ),
		.reset                ( reset                       ),
		.enable               ( enable                      ),
		// CC Response Eject
		.vn_ntc_packet_out    ( ni_response_to_cc           ),
		.vn_ntc_packet_valid  ( ni_response_to_cc_valid     ),
		.core_packet_consumed ( l1d_response_to_cc_consumed ),
		//Router interface
		.vn_ntc_credit        ( vn_ntc_credit_cc            ),
		.router_flit_valid    ( router_flit_in_valid        ),
		.router_flit_in       ( router_flit_in              )
	);


	virtual_network_net_to_core # (
		.TYPE             ( "DC"                                   ),
		.VCID             ( VC1                                    ),
		.PACKET_BODY_SIZE ( $bits ( coherence_response_message_t ) ),
		.PACKET_FIFO_SIZE ( `RESP_FIFO_SIZE                        )
	)
	response_dc_virtual_network_net_to_core (
		.clk                  ( clk                        ),
		.reset                ( reset                      ),
		.enable               ( enable                     ),
		// DC Response Eject
		.vn_ntc_packet_out    ( ni_response_to_dc          ),
		.vn_ntc_packet_valid  ( ni_response_to_dc_valid    ),
		.core_packet_consumed ( dc_response_to_dc_consumed ),
		//Router interface
		.vn_ntc_credit        ( vn_ntc_credit_dc           ),
		.router_flit_valid    ( router_flit_in_valid       ),
		.router_flit_in       ( router_flit_in             )
	);

	assign ni_credit[VC1] = vn_ntc_credit_dc | vn_ntc_credit_cc;

	// --- Forwarded Request Virtual Network VC2 --- //

	virtual_network_net_to_core # (
		.VCID             ( VC2                                     ),
		.PACKET_BODY_SIZE ( $bits ( coherence_forwarded_message_t ) ),
		.PACKET_FIFO_SIZE ( `FWD_FIFO_SIZE                          )
	)
	forwarded_virtual_network_net_to_core (
		.clk                  ( clk                            ),
		.reset                ( reset                          ),
		.enable               ( enable                         ),
		//Cache Controller interface
		.vn_ntc_packet_out    ( ni_forwarded_request           ),
		.vn_ntc_packet_valid  ( ni_forwarded_request_valid     ),
		.core_packet_consumed ( l1d_forwarded_request_consumed ),
		//Router interface
		.vn_ntc_credit        ( ni_credit[VC2]                 ),
		.router_flit_valid    ( router_flit_in_valid           ),
		.router_flit_in       ( router_flit_in                 )
	) ;


	// --- Service Virtual Network VC3 --- //

	virtual_network_net_to_core # (
		.VCID             ( VC3                             ),
		.PACKET_BODY_SIZE ( $bits ( service_message_t )     ),
		.PACKET_FIFO_SIZE ( `SERV_FIFO_SIZE                 )
	)
	service_virtual_network_net_to_core (
		.clk                  ( clk                      ),
		.reset                ( reset                    ),
		.enable               ( enable                   ),
		//Cache Controller interface
		.vn_ntc_packet_out    ( ni_n2c_mes_service       ),
		.vn_ntc_packet_valid  ( ni_n2c_mes_service_valid ),
		.core_packet_consumed ( c2n_mes_service_consumed ),
		//Router interface
		.vn_ntc_credit        ( ni_credit[VC3]           ),
		.router_flit_valid    ( router_flit_in_valid     ),
		.router_flit_in       ( router_flit_in           )
	);

endmodule
