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
`include "npu_user_defines.sv"
`include "npu_debug_log.sv"

/*
 * The router moves data among two or more tiles.
 * The router is part of a mesh network, it has an I/O port for each cardinal direction, 
 * plus the local injection/ejection port. Each port exchanges FLITs with neighbour 
 * routers. FLITs are routed using the XY-DOR protocol with look-ahead. Every router 
 * calculates the next hop as if it were the next router along the path. This optimization 
 * allows us to reduce the pipeline length of the router, improving latencies. 
 */

module router #(
		parameter MY_X_ADDR = 2,
		parameter MY_Y_ADDR = 1 )
	(
		input         [`PORT_NUM - 1 : 0]                       wr_en_in,
		input  flit_t [`PORT_NUM - 1 : 0]                       flit_in ,
		input         [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_in ,

		output        [`PORT_NUM - 1 : 0]                       wr_en_out,
		output flit_t [`PORT_NUM - 1 : 0]                       flit_out ,
		output        [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0] on_off_out,

		input                                                   clk,
		input                                                   reset
	);

	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0]                    granted_vc_oh;


//  -----------------------------------------------------------------------
//  -- Router - First stage
//  -----------------------------------------------------------------------
	/* There are five different ports - one per cardinal directions plus the local port -
     * each one with V different queues, where V is the number of virtual channels.
	 */
	 
	flit_t [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0]                    ip_flit_in_mux;
	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0][`PORT_NUM - 1 : 0] ip_dest_port;

	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0]                    ip_empty;

	genvar                                                              i;
	generate
		for( i=0; i < `PORT_NUM; i=i + 1 ) begin : FIRST_STAGE_LOOP

			// input_port ip
			input_port input_port_inst (
				// interface to other router
				.wr_en_in       ( wr_en_in[i]       ),
				.flit_in        ( flit_in[i]        ),
				.on_off_out     ( on_off_out[i]     ),

				.ip_flit_in_mux ( ip_flit_in_mux[i] ),
				.ip_dest_port   ( ip_dest_port[i]   ),
				.sa_grant       ( granted_vc_oh[i]  ),
				.ip_empty       ( ip_empty[i]       ),
				// General
				.clk            ( clk               ),
				.reset          ( reset             )
			);
		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- Router - Second stage
//  -----------------------------------------------------------------------
	/*
	 * The second stage has two units working in parallel: the look-ahead routing unit and allocator unit.
	 * The allocator unit gives the grant permission for each port. This signal is feedback either to first stage and 
	 * to a second-stage multiplexer as selector signal. This mux receives as input all the virtual channel output 
	 * for that port, electing as output only one flit - based on the selection signal. This output flit goes in the 
	 * look-ahead routing to calculate the next-hop port destination.
	 */
	 
	/*
	 * FLITs Manager
	 */

	flit_t [`PORT_NUM - 1 : 0]                                          buff_flit_out;
	flit_t [`PORT_NUM - 1 : 0]                                          flit_in_granted;
	flit_t [`PORT_NUM - 1 : 0]                                          flit_in_granted_mod;
	logic  [`PORT_NUM - 1 : 0] [`PORT_NUM_W - 1 : 0 ]                   lk_next_port;

	generate
		for( i=0; i < `PORT_NUM; i=i + 1 ) begin : flit_loop
			mux_npu #(
				.N ( `VC_PER_PORT ),
				.WIDTH( $bits( flit_t ) ) )
			u_mux (
				.onehot( granted_vc_oh[i]   ),
				.i_data( ip_flit_in_mux[i]  ),
				.o_data( flit_in_granted[i] )
			);
			always_comb begin
				flit_in_granted_mod[i] = flit_in_granted[i];
				if ( flit_in_granted[i].header.flit_type == HEADER || flit_in_granted[i].header.flit_type == HT )
					flit_in_granted_mod[i].header.next_hop_port = port_t'( lk_next_port[i] );
			end

			always_ff @( posedge clk, posedge reset ) begin
				if ( reset )
					buff_flit_out[i] <= 0;
				else
					buff_flit_out[i] <= flit_in_granted_mod[i];
			end

		end
	endgenerate

	/*
	 * Next Hop routing calculation
	 */

	generate
		for( i=0; i < `PORT_NUM; i=i + 1 ) begin : routing_loop

			//look ahead routing module  lk
			look_ahead_routing #(
				.MY_X_ADDR ( MY_X_ADDR ),
				.MY_Y_ADDR ( MY_Y_ADDR ) )
			look_ahead_routing_inst (
				.dest_x_node ( flit_in_granted[i].header.destination.x ),
				.dest_y_node ( flit_in_granted[i].header.destination.y ),
				.next_port   ( lk_next_port[i]                         )
			);
		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- Router - Virtual channel and switch allocation
//  -----------------------------------------------------------------------
	/*
	 * The allocation unit grants a flit to go toward a specific port of a specific 
	 * virtual channel, handling the contention of virtual channels and crossbar ports. 
	 * The unit receives as many allocation requests as the number of ports. Each request selects
	 * a destination port and the arbiter selects one request per output port.
	 * The allocation unit has to respect the following rules: 
	 * - the packets can move only in their respective virtual channel; 
	 * - a virtual channel can request only one port per time; 
	 * - the physical link can be interleaved by flits belonging to different flows; 
	 * - when a packet acquires a virtual channel on an output port, no other packets on 
	 *   different input ports can acquire that virtual channel on that output port.
	 */

	/*
	 * VIRUAL CHANNEL ALLOCATION
	 */

	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0]                    va_grant;           // � il grant: quel porto x quel vc
	logic  [`PORT_NUM - 1 : 0][`PORT_NUM - 1 : 0]                       va_grant_per_port;  // � il grant: quel porto

	allocator_core #(
		.N   ( `PORT_NUM    ),
		.M   ( `VC_PER_PORT ),
		.SIZE( `PORT_NUM    )
	)
	vc_allocator (
		.clk    ( clk          ),
		.reset  ( reset        ),
		.request( ip_dest_port ), //  vc_request
		.on_off ( on_off_in    ),
		.grant  ( va_grant     )
	);

	/*
	 * SWITCH ALLOCATION
	 */

	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0]                    grant_to_mux_ip;
	logic  [`PORT_NUM - 1 : 0][`PORT_NUM - 1 : 0]                       sa_port;
	logic  [`PORT_NUM - 1 : 0]                                          sa_grant ;
	logic  [`PORT_NUM - 1 : 0][`PORT_NUM - 1 : 0]                       grant_to_cr;
	logic  [`PORT_NUM - 1 : 0][`PORT_NUM - 1 : 0]                       buff_grant_to_cr;
	logic  [`PORT_NUM - 1 : 0]                                          buff_valid_out;

	generate
		for( i=0; i < `PORT_NUM; i=i + 1 ) begin : sw_allocation_loop

			assign va_grant_per_port[i] = {`PORT_NUM{| ( va_grant[i] & ~ip_empty[i] )}}; 

			round_robin_arbiter #(
				.SIZE( `VC_PER_PORT ) )
			sa_arbiter (
				.clk         ( clk                         ),
				.reset       ( reset                       ),
				.en          ( 1'b1                        ),
				.requests    ( va_grant[i] & ~ip_empty[i]  ),
				.decision_oh ( grant_to_mux_ip[i]          )
			);

			mux_npu #(
				.N    ( `VC_PER_PORT ),
				.WIDTH( `PORT_NUM    )
			)
			sa_mux (
				.onehot( grant_to_mux_ip[i] ),
				.i_data( ip_dest_port[i]    ),
				.o_data( sa_port[i]         )
			);
		end
	endgenerate

	allocator_core #(
		.N   ( `PORT_NUM ),
		.M   ( 1         ),
		.SIZE( `PORT_NUM )
	)
	switch_allocator (
		.clk    ( clk                         ),
		.reset  ( reset                       ),
		.request( sa_port & va_grant_per_port ),
		.on_off ( '{default : '0}             ),
		.grant  ( sa_grant                    )
	);

	generate
		for( i=0; i < `PORT_NUM; i=i + 1 ) begin : output_loop
			assign granted_vc_oh[i] = {`VC_PER_PORT{sa_grant[i]}} & grant_to_mux_ip[i];
			assign grant_to_cr[i]   = {`PORT_NUM{sa_grant[i]}} & sa_port[i];

			always_ff @( posedge clk, posedge reset ) begin
				if ( reset )
					buff_valid_out[i] <= 0;
				else
					buff_valid_out[i] <= | grant_to_cr[i];
			end

		end
	endgenerate


	always_ff @( posedge clk, posedge reset ) begin
		if ( reset )
			buff_grant_to_cr <= 0;
		else
			buff_grant_to_cr <= grant_to_cr;
	end

	crossbar crossbar_inst (
		.port_sel     ( buff_grant_to_cr ),
		.flit_in      ( buff_flit_out    ),
		.flit_valid_in( buff_valid_out   ),
		.wr_en_out    ( wr_en_out        ),
		.flit_out     ( flit_out         )
	);

endmodule
