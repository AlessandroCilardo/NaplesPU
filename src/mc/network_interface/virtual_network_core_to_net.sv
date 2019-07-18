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

/*
 * This module splits a packet into flits and sends them to the router local port. It also 
 * supports multicasting, implemented as multiple unicast messages. It is composed of two 
 * parts: a packet queue, and a control unit which handles the outgoing flits. 
 * The conversion in flits starts fetching the packet from an internal queue. The packet is 
 * divided in N flits and send over the network.
 */

module virtual_network_core_to_net # (
		parameter DEST_OH                      = "TRUE",
		parameter X_ADDR                       = 0,
		parameter Y_ADDR                       = 0,
		parameter VCID                         = VC0,
		parameter PACKET_BODY_SIZE             = 256,
		parameter DEST_NUMB                    = 4,
		parameter PACKET_FIFO_SIZE             = 4,
		parameter PACKET_ALMOST_FULL_THRESHOLD = 1 )
	(
		input                                            clk,
		input                                            reset,
		input                                            enable,

		// Request from Cache Controller / Directory
		input  logic                                     packet_valid,
		input  logic          [PACKET_BODY_SIZE - 1 : 0] packet_body,
		input  logic                                     packet_has_data,
		input  tile_address_t [DEST_NUMB - 1 : 0]        packet_destinations,
		input  logic          [DEST_NUMB - 1 : 0]        packet_destinations_valid,

		// To the Cache Controller / Directory, cannot receive more packets
		output logic                                     vn_packet_fifo_full,

		// To NI for arbitration
		output logic                                     vn_packet_pending,

		// The router is available to receive a FLIT
		input  logic                                     flit_credit,

		// Output to the Router Virtual Channel
		output logic                                     vn_flit_valid,
		output flit_t                                    vn_flit_out
	) ;

	localparam FLIT_NUMB = (PACKET_BODY_SIZE+`PAYLOAD_W-1) / `PAYLOAD_W;

	typedef struct packed {
		logic [PACKET_BODY_SIZE - 1 : 0] packet_body;
		logic packet_has_data;
		tile_address_t [DEST_NUMB - 1 : 0 ] packet_destinations;
		logic [DEST_NUMB - 1 : 0 ] packet_destinations_valid;
	} packet_information_t;

	typedef flit_body_t packet_strip_elem_t;
	typedef packet_strip_elem_t [FLIT_NUMB - 1 : 0] flit_array_t;


	flit_array_t                                               flit_body_array;
	logic                                                      packet_fifo_empty, packet_pending;
	packet_information_t                                       packet_information_in, packet_information_out;
	logic                [$clog2 ( PACKET_BODY_SIZE ) - 1 : 0] cu_packet_chunck_sel;
	logic                                                      cu_flit_valid;
	flit_header_t                                              cu_flit_out_header;
	logic                                                      cu_packet_dequeue;

//  -----------------------------------------------------------------------
//  -- Virtual Network Core to Network - Input Packet FIFO
//  -----------------------------------------------------------------------
	// This FIFO stores the packet information from Cache Controller or the Directory. When the
	// requestor has to send a packet, it asserts packed_valid bit, directly connected to the
	// FIFO enqueue_en port. Those informations are used by the Control Unit to translate packet
	// in FLITs for each destination.
	assign packet_information_in.packet_body            = packet_body,
		packet_information_in.packet_has_data           = packet_has_data,
		packet_information_in.packet_destinations       = packet_destinations,
		packet_information_in.packet_destinations_valid = packet_destinations_valid;

	sync_fifo # (
		.WIDTH                 ( $bits ( packet_information_t ) ),
		.SIZE                  ( PACKET_FIFO_SIZE               ),
		.ALMOST_FULL_THRESHOLD ( PACKET_ALMOST_FULL_THRESHOLD   )
	)
	packet_in_fifo (
		.clk          ( clk                    ),
		.reset        ( reset                  ),
		.flush_en     ( 1'b0                   ),
		.full         (                        ),
		.almost_full  ( vn_packet_fifo_full    ),
		.enqueue_en   ( packet_valid           ),
		.value_i      ( packet_information_in  ),
		.empty        ( packet_fifo_empty      ),
		.almost_empty (                        ),
		.dequeue_en   ( cu_packet_dequeue      ),
		.value_o      ( packet_information_out )
	) ;

	assign packet_pending                               = ~packet_fifo_empty;
	assign vn_packet_pending                            = ~packet_fifo_empty;

//  -----------------------------------------------------------------------
//  -- Virtual Network Core to Network - Output Control Unit
//  -----------------------------------------------------------------------
	// The Control Unit strips the packet from he Cache Controller into N flits for the next
	// router. It checks the packet_has_data field, if a packet does not contain data, the CU
	// generates just a flit (HT type), otherwise it generates N flits. It supports multicasting
	// through multiple unicast messages. The signal packet_destinations_valid is a bitmap of
	// destination to reach.
	control_unit_packet_to_flit # (
		.DEST_OH          ( DEST_OH          ),
		.X_ADDR           ( X_ADDR           ),
		.Y_ADDR           ( Y_ADDR           ),
		.VCID             ( VCID             ),
		.PACKET_BODY_SIZE ( PACKET_BODY_SIZE ),
		.DEST_NUMB        ( DEST_NUMB        )
	)
	u_control_unit_packet_to_flit (
		.clk                       ( clk                                              ),
		.reset                     ( reset                                            ),
		.enable                    ( enable                                           ),
		.packet_valid              ( packet_pending                                   ),
		.packet_has_data           ( packet_information_out.packet_has_data           ),
		.packet_destinations       ( packet_information_out.packet_destinations       ),
		.packet_destinations_valid ( packet_information_out.packet_destinations_valid ),
		.flit_credit               ( flit_credit                                      ),
		.cu_packet_chunck_sel      ( cu_packet_chunck_sel                             ),
		.cu_flit_valid             ( cu_flit_valid                                    ),
		.cu_flit_out_header        ( cu_flit_out_header                               ),
		.cu_packet_dequeue         ( cu_packet_dequeue                                )
	);

	assign flit_body_array                              = flit_array_t' ( packet_information_out.packet_body ) ;

	assign vn_flit_valid  = cu_flit_valid,
	  vn_flit_out.header  = cu_flit_out_header,
	  vn_flit_out.payload = flit_body_array[cu_packet_chunck_sel];

endmodule
