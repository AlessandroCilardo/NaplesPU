`timescale 1ns / 1ps
`include "npu_network_defines.sv"
`include "npu_user_defines.sv"
`include "npu_debug_log.sv"

/*
 * The router moves data among two or more terminals, so the interface is standard: 
 * input and output flit, input and output write enable, and backpressure signals.
 * 
 * This is a virtual-channel flow control X-Y look-ahead router for a 2D-mesh topology.
 * 
 * The first choice is to use only input buffering, so this will take one pipe stage.
 * Another technique widely used is the look-ahead routing, that permits the route calculation of the next node.
 * It is possible to merge the virtual channel and switch allocation in just one stage.
 * Recapping, there are 4 stages, two of them working in parallel (routing and allocation stages), for a total of three
 * stages. To further reduce the pipeline stages, the crossbar and link traversal stage is 
 * not buffered, reducing the stages at two and, de facto, merging the last stage to the first one.
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
	// SEGNALE RETROAZIONATO
	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0]                    granted_vc_oh;


	//  -----------------------------------------------------------------------
	//  -- Router - First stage
	//  -----------------------------------------------------------------------
	/* There will be five different port - cardinal directions plus local port -, each one with V 
	 * different queues, where V is the number of virtual channels presented.
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
	 * The second stage has got two units working in parallel: the look-ahead routing unit and allocator unit.
	 * This two units are linked throughout a intermediate logic.
	 * The allocator unit has to accord a grant for each port. This signal is feedback either to first stage and 
	 * to a second-stage multiplexer as selector signal. This mux receives as input all the virtual channel output 
	 * for that port, electing as output only one flit - based on the selection signal. This output flit goes in the 
	 * look-ahead routing to calculate the next-hop port destination.
	 */
	 
	/*
	 * MANAGING OF FLIT
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
	 * NEXT HOP ROUTING CALCULATION
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
	 * The allocation unit grants a  flit to go toward a specific port of a specific 
	 * virtual channel, handling the contention of virtual channels and crossbar ports. 
	 * Each single allocator is a two-stage input-first separable allocator that permits 
	 * a reduced number of component respect to other allocator.
	 * The overall unit receives as many allocation request as the ports are. Each request asks
	 *  to obtain a destination port grant for each of its own virtual channel - the total number
	 *  of request lines is P x V x P. The allocation outputs are two for each port: (1) the winner
	 *  destination port that will go into the crossbar selection; (2) the winner virtual channel 
	 * that is feedback to move the proper flit at the crossbar input.
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
	 /*
	  * The first step for the virtual channel allocator is removed because the hypothesis
	  * is that only one port per time can be requested for each virtual channel. 
	  * Under this condition, a first-stage arbitration is useless, so only the second 
	  * stage is implemented. The use of grant-hold arbiters in the second stage avoids that a packet loses 
	  * its grant when other requests arrive after this grant. 
	  * The on-off input signal is properly used to avoid that a flit is send to a full 
	  * virtual channel in the next node.
	  * 
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
	 /*
	  * The switch allocator receives as input the output signals from VC allocation 
	  * and all the port requests. For each port, there is a signal assertion for each 
	  * winning virtual channel. These winners now compete for a switch allocation. 
	  * Two arbiter stage are necessary. The first stage arbiter has as many round-robin arbiter as the input port are. 
	  * Each round-robin arbiter chooses one VC per port and uses this result to select 
	  * the request port associated at this winning VC. The winning request port goes 
	  * at the input of second stage arbiter as well as the winning requests for the 
	  * other ports. The second stage arbiter is an instantiation of the allocator core 
	  * and chooses what input port can access to the physical links. This signal 
	  * is important for two reasons: (1) it is moved toward the round-robin unit 
	  * previously and-ed with the winning VC for each port; (2) it is registered, 
	  * and-ed with the winning destination port, and used as selection port for the 
	  * crossbar (for each port).
	  */


	logic  [`PORT_NUM - 1 : 0][`VC_PER_PORT - 1 : 0]                    grant_to_mux_ip;
	logic  [`PORT_NUM - 1 : 0][`PORT_NUM - 1 : 0]                       sa_port;
	logic  [`PORT_NUM - 1 : 0]                                          sa_grant ;
	logic  [`PORT_NUM - 1 : 0][`PORT_NUM - 1 : 0]                       grant_to_cr;
	logic  [`PORT_NUM - 1 : 0][`PORT_NUM - 1 : 0]                       buff_grant_to_cr;
	logic  [`PORT_NUM - 1 : 0]                                          buff_valid_out;

	generate
		for( i=0; i < `PORT_NUM; i=i + 1 ) begin : sw_allocation_loop

			assign va_grant_per_port[i] = {`PORT_NUM{| ( va_grant[i] & ~ip_empty[i] )}}; //logicamente si trova in vc alloc

			rr_arbiter #(
				.NUM_REQUESTERS( `VC_PER_PORT ) )
			sa_arbiter (
				.clk       ( clk                               ),
				.reset     ( reset                             ),
				.request   ( va_grant[i] & ~ip_empty[i] ),
				.update_lru( 1'b1                              ),
				.grant_oh  ( grant_to_mux_ip[i]                )
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

	/*
	 *
	 * FINE DEL SECOND STAGE
	 *
	 */

	//crossbar cr
	crossbar crossbar_inst (
		.port_sel     ( buff_grant_to_cr ),
		.flit_in      ( buff_flit_out    ),
		.flit_valid_in( buff_valid_out   ),
		.wr_en_out    ( wr_en_out        ),
		.flit_out     ( flit_out         )
	);

//`ifdef DISPLAY_SIMULATION_LOG
//	// Debug counter
//	integer incoming_flits_cnt[`VC_PER_PORT];
//	integer incoming_msgs_cnt[`VC_PER_PORT];
//	integer outgoing_flits_cnt[`VC_PER_PORT];
//	integer outgoing_msgs_cnt[`VC_PER_PORT];
//	integer injected_flits_cnt[`VC_PER_PORT];
//	integer injected_msgs_cnt[`VC_PER_PORT];
//	integer ejected_flits_cnt[`VC_PER_PORT];
//	integer ejected_msgs_cnt[`VC_PER_PORT];
//
//	always_ff @( posedge clk ) begin
//		if ( reset ) begin
//			for ( int vc = 0; vc < `VC_PER_PORT; vc++ ) begin
//				outgoing_flits_cnt[vc] = 0;
//				outgoing_msgs_cnt[vc] = 0;
//				ejected_flits_cnt[vc] = 0;
//				ejected_msgs_cnt[vc] = 0;
//			end
//		end else begin
//			if ( |wr_en_out ) begin
//				integer vc;
//
//				for ( int port = 0; port < `PORT_NUM; port++ ) begin
//					if ( wr_en_out[port] ) begin
//						vc = flit_out[port].vc_id;
//
//						if ( port == LOCAL ) begin
//							ejected_flits_cnt[vc]++;
//						end else begin
//							outgoing_flits_cnt[vc]++;
//						end
//
//						if ( flit_out[port].flit_type == HEADER || flit_out[port].flit_type == HT ) begin
//							if ( port == LOCAL ) begin
//								ejected_msgs_cnt[vc]++;
//							end else begin
//								outgoing_msgs_cnt[vc]++;
//							end
//						end
//					end
//				end
//			end
//		end
//	end
//
//	always_ff @( posedge clk ) begin
//		if ( reset ) begin
//			for ( int vc = 0; vc < `VC_PER_PORT; vc++ ) begin
//				incoming_flits_cnt[vc] = 0;
//				incoming_msgs_cnt[vc] = 0;
//				injected_flits_cnt[vc] = 0;
//				injected_msgs_cnt[vc] = 0;
//			end
//		end else begin
//			if ( |wr_en_in ) begin
//				integer vc;
//
//				for ( int port = 0; port < `PORT_NUM; port++ ) begin
//					if ( wr_en_in[port] ) begin
//						vc = flit_in[port].vc_id;
//
//						if ( port == LOCAL ) begin
//							injected_flits_cnt[vc]++;
//						end else begin
//							incoming_flits_cnt[vc]++;
//						end
//
//						if ( flit_in[port].flit_type == HEADER || flit_in[port].flit_type == HT ) begin
//							if ( port == LOCAL ) begin
//								injected_msgs_cnt[vc]++;
//							end else begin
//								incoming_msgs_cnt[vc]++;
//							end
//						end
//					end
//				end
//			end
//		end
//	end
//
//	final begin
//		automatic integer incoming_flits = 0;
//		automatic integer incoming_msgs = 0;
//		automatic integer outgoing_flits = 0;
//		automatic integer outgoing_msgs = 0;
//		automatic integer injected_flits = 0;
//		automatic integer injected_msgs = 0;
//		automatic integer ejected_flits = 0;
//		automatic integer ejected_msgs = 0;
//
//		for ( int vc = 0; vc < `VC_PER_PORT; vc++ ) begin
//			incoming_flits += incoming_flits_cnt[vc];
//			incoming_msgs  += incoming_msgs_cnt[vc];
//			outgoing_flits += outgoing_flits_cnt[vc];
//			outgoing_msgs  += outgoing_msgs_cnt[vc];
//			injected_flits += injected_flits_cnt[vc];
//			injected_msgs  += injected_msgs_cnt[vc];
//			ejected_flits  += ejected_flits_cnt[vc];
//			ejected_msgs   += ejected_msgs_cnt[vc];
//		end
//
//		$display( "[Time %t] [TILE %d] ROUTER IN&OUT flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, incoming_flits + injected_flits, incoming_msgs + injected_msgs, incoming_flits_cnt[0] + injected_flits_cnt[0], incoming_msgs_cnt[0] + injected_msgs_cnt[0], incoming_flits_cnt[1] + injected_flits_cnt[1], incoming_msgs_cnt[1] + injected_msgs_cnt[1], incoming_flits_cnt[2] + injected_flits_cnt[2], incoming_msgs_cnt[2] + injected_msgs_cnt[2], incoming_flits_cnt[3] + injected_flits_cnt[3], incoming_msgs_cnt[3] + injected_msgs_cnt[3] );
//		$display( "[Time %t] [TILE %d]      Incoming flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, incoming_flits, incoming_msgs, incoming_flits_cnt[0], incoming_msgs_cnt[0], incoming_flits_cnt[1], incoming_msgs_cnt[1], incoming_flits_cnt[2], incoming_msgs_cnt[2], incoming_flits_cnt[3], incoming_msgs_cnt[3] );
//		$display( "[Time %t] [TILE %d]      Injected flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, injected_flits, injected_msgs, injected_flits_cnt[0], injected_msgs_cnt[0], injected_flits_cnt[1], injected_msgs_cnt[1], injected_flits_cnt[2], injected_msgs_cnt[2], injected_flits_cnt[3], injected_msgs_cnt[3] );
//		$display( "[Time %t] [TILE %d]      --", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR );
//		//$display( "[Time %t] [TILE %d] ROUTER OUTPUT flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, outgoing_flits + ejected_flits, outgoing_msgs + ejected_msgs, outgoing_flits_cnt[0] + ejected_flits_cnt[0], outgoing_msgs_cnt[0] + ejected_msgs_cnt[0], outgoing_flits_cnt[1] + ejected_flits_cnt[1], outgoing_msgs_cnt[1] + ejected_msgs_cnt[1], outgoing_flits_cnt[2] + ejected_flits_cnt[2], outgoing_msgs_cnt[2] + ejected_msgs_cnt[2], outgoing_flits_cnt[3] + ejected_flits_cnt[3], outgoing_msgs_cnt[3] + ejected_msgs_cnt[3] );
//		$display( "[Time %t] [TILE %d]      Outgoing flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, outgoing_flits, outgoing_msgs, outgoing_flits_cnt[0], outgoing_msgs_cnt[0], outgoing_flits_cnt[1], outgoing_msgs_cnt[1], outgoing_flits_cnt[2], outgoing_msgs_cnt[2], outgoing_flits_cnt[3], outgoing_msgs_cnt[3] );
//		$display( "[Time %t] [TILE %d]      Ejected flits  (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, ejected_flits, ejected_msgs, ejected_flits_cnt[0], ejected_msgs_cnt[0], ejected_flits_cnt[1], ejected_msgs_cnt[1], ejected_flits_cnt[2], ejected_msgs_cnt[2], ejected_flits_cnt[3], ejected_msgs_cnt[3] );
//
//		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %d] ROUTER IN&OUT flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, incoming_flits + injected_flits, incoming_msgs + injected_msgs, incoming_flits_cnt[0] + injected_flits_cnt[0], incoming_msgs_cnt[0] + injected_msgs_cnt[0], incoming_flits_cnt[1] + injected_flits_cnt[1], incoming_msgs_cnt[1] + injected_msgs_cnt[1], incoming_flits_cnt[2] + injected_flits_cnt[2], incoming_msgs_cnt[2] + injected_msgs_cnt[2], incoming_flits_cnt[3] + injected_flits_cnt[3], incoming_msgs_cnt[3] + injected_msgs_cnt[3] );
//		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %d]      Incoming flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, incoming_flits, incoming_msgs, incoming_flits_cnt[0], incoming_msgs_cnt[0], incoming_flits_cnt[1], incoming_msgs_cnt[1], incoming_flits_cnt[2], incoming_msgs_cnt[2], incoming_flits_cnt[3], incoming_msgs_cnt[3] );
//		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %d]      Injected flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, injected_flits, injected_msgs, injected_flits_cnt[0], injected_msgs_cnt[0], injected_flits_cnt[1], injected_msgs_cnt[1], injected_flits_cnt[2], injected_msgs_cnt[2], injected_flits_cnt[3], injected_msgs_cnt[3] );
//		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %d]      --", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR );
//		//$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %d] ROUTER OUTPUT flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, outgoing_flits + ejected_flits, outgoing_msgs + ejected_msgs, outgoing_flits_cnt[0] + ejected_flits_cnt[0], outgoing_msgs_cnt[0] + ejected_msgs_cnt[0], outgoing_flits_cnt[1] + ejected_flits_cnt[1], outgoing_msgs_cnt[1] + ejected_msgs_cnt[1], outgoing_flits_cnt[2] + ejected_flits_cnt[2], outgoing_msgs_cnt[2] + ejected_msgs_cnt[2], outgoing_flits_cnt[3] + ejected_flits_cnt[3], outgoing_msgs_cnt[3] + ejected_msgs_cnt[3] );
//		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %d]      Outgoing flits (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, outgoing_flits, outgoing_msgs, outgoing_flits_cnt[0], outgoing_msgs_cnt[0], outgoing_flits_cnt[1], outgoing_msgs_cnt[1], outgoing_flits_cnt[2], outgoing_msgs_cnt[2], outgoing_flits_cnt[3], outgoing_msgs_cnt[3] );
//		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %d]      Ejected flits  (msgs) %d (%d) per VC %d (%d) %d (%d) %d (%d) %d (%d)", $time( ), MY_Y_ADDR * `NoC_X_WIDTH + MY_X_ADDR, ejected_flits, ejected_msgs, ejected_flits_cnt[0], ejected_msgs_cnt[0], ejected_flits_cnt[1], ejected_msgs_cnt[1], ejected_flits_cnt[2], ejected_msgs_cnt[2], ejected_flits_cnt[3], ejected_msgs_cnt[3] );
//	end
//`endif

endmodule
