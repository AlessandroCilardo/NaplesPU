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
 * This module splits a packet into flits and sends them to the router local port.
 * It also supports multicasting, implemented as multiple unicast messages. It is 
 * composed of two parts: a packet queue, and a control unit which handles the outgoing flits. 
 * A priority encoder selects from a mask which destination has to be served.
 * All the information of the header flit are straightway filled, but the flit type.
 * The units performs the multicast throughout k unicast: when a destination is served (a packet
 * is completed), the corresponding bit in the destination mask is deasserted.
 */

module control_unit_packet_to_flit # (
		parameter DEST_OH          = "TRUE",
		parameter X_ADDR           = 0,
		parameter Y_ADDR           = 0,
		parameter VCID             = VC0,
		parameter PACKET_BODY_SIZE = 256,
		parameter DEST_NUMB        = 4 )
	(
		input                                                       clk,
		input                                                       reset,
		input                                                       enable,

		input  logic                                                packet_valid,
		input  logic                                                packet_has_data,
		input  tile_address_t [DEST_NUMB - 1 : 0]                   packet_destinations,
		input  logic          [DEST_NUMB - 1 : 0]                   packet_destinations_valid,

		input  logic                                                flit_credit,

		output logic          [$clog2 ( PACKET_BODY_SIZE ) - 1 : 0] cu_packet_chunck_sel,
		output logic                                                cu_flit_valid,
		output flit_header_t                                        cu_flit_out_header,
		output logic                                                cu_packet_dequeue

	) ;

	localparam FLIT_NUMB = (PACKET_BODY_SIZE+`PAYLOAD_W-1) / `PAYLOAD_W;

	typedef enum logic {IDLE, GEN_FLIT} state_t;

	localparam COUNTER_WIDTH = $clog2 ( PACKET_BODY_SIZE );

	tile_address_t                                       packet_destination_sel, real_dest;
	logic          [COUNTER_WIDTH - 1 : 0]               count;
	logic          [DEST_NUMB - 1 : 0]                   destination_grant_oh, packet_dest_pending, dest_served;
	logic          [$clog2 ( DEST_NUMB ) - 1 : 0]        destination_grant_id;
	logic                                                packet_has_dest_pending;
	state_t                                              state;
	logic          [`PORT_NUM_W - 1 : 0 ]                next_port;

	assign packet_dest_pending                 = packet_destinations_valid & ~dest_served;
	assign packet_has_dest_pending             = |packet_dest_pending;

	round_robin_arbiter # (
		.SIZE ( DEST_NUMB )
	)
	u_round_robin_arbiter (
		.clk          ( clk                  ),
		.reset        ( reset                ),
		.en           ( 1'b0                 ),
		.requests     ( packet_dest_pending  ),
		.decision_oh  ( destination_grant_oh )
	);

	oh_to_idx # (
		.NUM_SIGNALS ( DEST_NUMB )
	)
	oh_to_idx (
		.one_hot ( destination_grant_oh ),
		.index   ( destination_grant_id )
	);


	// The mesh topology has to be power of two!
	generate
		if ( DEST_OH == "TRUE" ) begin
			assign
				real_dest.x  = destination_grant_id[ `TOT_X_NODE_W - 1 : 0 ],
				real_dest.y  = destination_grant_id[ `TOT_X_NODE_W    +: `TOT_Y_NODE_W ];
		end else begin
			assign real_dest = packet_destinations[destination_grant_id];
		end
		
	endgenerate

	assign cu_flit_out_header.core_destination = tile_destination_t'( destination_grant_oh[`DEST_TILE_W -1 : 0] ); 
	assign cu_flit_out_header.vc_id            = vc_id_t' ( VCID ) ;
	assign cu_flit_out_header.destination      = packet_destination_sel;
	assign cu_flit_out_header.next_hop_port    = port_t' ( next_port );
	

	routing_xy # (
		.MY_X_ADDR ( X_ADDR ) ,
		.MY_Y_ADDR ( Y_ADDR )
	)
	routing_xy (
		.dest_x_node ( packet_destination_sel.x ) ,
		.dest_y_node ( packet_destination_sel.y ) ,
		.next_port   ( next_port                )
	);


	assign cu_flit_valid                       = state == GEN_FLIT & flit_credit & enable,
		cu_packet_dequeue                      = state == IDLE & ( ~packet_has_dest_pending & packet_valid );
	assign cu_packet_chunck_sel                = count,
		cu_flit_out_header.flit_type           = cu_flit_valid? ( count == COUNTER_WIDTH'(0) ? 
			( packet_has_data? HEADER :
				HT ) :
			( count == COUNTER_WIDTH'(FLIT_NUMB - 1) ? TAIL :
				BODY ) ) : HEADER;

	//  -----------------------------------------------------------------------
	//  -- Control Unit - Next State Block
	//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			packet_destination_sel       <= '{default : '0};
			dest_served                  <= '{default : '0};
			state                        <= IDLE;
			count                        <= '{default : '0};
		end else begin
			unique case ( state )
				IDLE : begin
					// In IDLE, the CU checks if there is a valid packet and if it
					// has some destination. In this state there are no destinations already served.
					count       <= '{default : '0};
					if ( packet_has_dest_pending & packet_valid ) begin
						packet_destination_sel <= real_dest;
						state                  <= GEN_FLIT;
					end else begin
						dest_served            <= '{default : '0};
						state                  <= IDLE;
					end
				end

				GEN_FLIT : begin
					if ( flit_credit ) begin
						count                  <= count + 1'b1;
						if ( count == 0 ) begin
							if ( ~packet_has_data ) begin
								dest_served <= dest_served | destination_grant_oh;
								state       <= IDLE;
							end else begin
								state       <= GEN_FLIT;
							end
						end else if ( ( count > COUNTER_WIDTH'(0) ) && ( count < COUNTER_WIDTH'(FLIT_NUMB - 1) ) ) begin
							state       <= GEN_FLIT;
						end else begin
							state       <= IDLE;
							dest_served <= dest_served | destination_grant_oh;
						end
					end else
						state                  <= GEN_FLIT;

				end

				default : state <= IDLE;
			endcase
		end
	end


endmodule
