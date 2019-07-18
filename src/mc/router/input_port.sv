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
 * This module is equipped with two queues: one stores flits (FQ) and the other stores only head flits (HQ).
 * Whenever a valid flit enters in this unit, the HQ enqueues its only if the flit type is
 * `head' or `head-tail'. HQ flits are used by the control logic to get
 * information from their header, such as next hop, used in the routing algorithm. 
 */

module input_port
	(
		// Interface to other router
		input  logic                                             wr_en_in,
		input  flit_t                                            flit_in,
		output        [`VC_PER_PORT - 1 : 0]                     on_off_out,

		output flit_t [`VC_PER_PORT - 1 : 0]                     ip_flit_in_mux,
		output        [`VC_PER_PORT - 1 : 0] [`PORT_NUM - 1 : 0] ip_dest_port,
		input         [`VC_PER_PORT - 1 : 0]                     sa_grant,

		output        [`VC_PER_PORT - 1 : 0]                     ip_empty,

		input                                                    clk,
		input                                                    reset
	);

	port_t [`VC_PER_PORT - 1 : 0]                     dest_port;
	logic  [`VC_PER_PORT - 1 : 0]                     request_not_valid;
	logic  [`VC_PER_PORT - 1 : 0] [`PORT_NUM - 1 : 0] dest_port_oh;

	genvar                                            i;
	generate
		for( i=0; i < `VC_PER_PORT; i=i + 1 ) begin : vc_loop
			logic [`PORT_NUM_W - 1 : 0] dest_port_app;

			sync_fifo #(
				.WIDTH ( $bits( flit_t )   ),
				.SIZE  ( `QUEUE_LEN_PER_VC ),
				.ALMOST_FULL_THRESHOLD ( `QUEUE_LEN_PER_VC - 1 ) )
			flit_fifo (
				.clk         ( clk                                  ),
				.reset       ( reset                                ),
				.flush_en    (                                      ),
				.full        (                                      ),
				.almost_full ( on_off_out[i]                        ),
				.enqueue_en  ( wr_en_in & flit_in.header.vc_id == i ),
				.value_i     ( flit_in                              ),
				.empty       ( ip_empty[i]                          ),
				.almost_empty(                                      ),
				.dequeue_en  ( sa_grant[i]                          ),
				.value_o     ( ip_flit_in_mux[i]                    )
			);

			sync_fifo #(
				.WIDTH ( $bits( port_t ) ),
				.SIZE ( `QUEUE_LEN_PER_VC ) )
			header_fifo (
				.clk         ( clk                                                                                                            ),
				.reset       ( reset                                                                                                          ),
				.flush_en    (                                                                                                                ),
				.full        (                                                                                                                ),
				.almost_full (                                                                                                                ),
				.enqueue_en  ( wr_en_in & flit_in.header.vc_id == i & ( flit_in.header.flit_type == HEADER | flit_in.header.flit_type == HT ) ),
				.value_i     ( flit_in.header.next_hop_port                                                                                   ),
				.empty       ( request_not_valid[i]                                                                                           ),
				.almost_empty(                                                                                                                ),
				.dequeue_en  ( ( ip_flit_in_mux[i].header.flit_type == TAIL | ip_flit_in_mux[i].header.flit_type == HT ) & sa_grant[i]        ),
				.value_o     ( dest_port_app                                                                                                  )
			);
			assign dest_port[i]    = port_t'( dest_port_app ); // segnale di appoggio per problemi con i tipi

			idx_to_oh #(
				.NUM_SIGNALS( `PORT_NUM )
			)
			u_idx_to_oh (
				.one_hot( dest_port_oh[i] ),
				.index  ( dest_port[i]    )
			);
			assign ip_dest_port[i] = dest_port_oh[i] & {`PORT_NUM{~request_not_valid[i]}};

		end
	endgenerate

endmodule
