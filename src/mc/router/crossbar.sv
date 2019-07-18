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

/* The crossbar connects 5 input ports to respectively 5 output ports.
 * It has been implemented as a mux for each output port, and selection
 * signals are obtained from the second stage outputs. The output of 
 * this stage is not buffered. This means that in practice, the clock cycles
 * needed to completely process a packet reduce to two. 
 */

module crossbar
	(
		input         [`PORT_NUM-1:0][`PORT_NUM-1 : 0] port_sel,
		input  flit_t [`PORT_NUM-1:0]                  flit_in ,
		input  logic  [`PORT_NUM-1 : 0]                flit_valid_in,
		output logic  [`PORT_NUM-1 : 0]                wr_en_out,
		output flit_t [`PORT_NUM-1:0]                  flit_out
	);

	logic  [`PORT_NUM-1:0][`PORT_NUM-1 : 0]  mux_sel ;
	flit_t [`PORT_NUM-1:0][`PORT_NUM-1:0]    flit_in_mux_array;
	logic  [`PORT_NUM-1 : 0] [`PORT_NUM-1:0] flit_valid_mux_in;

	genvar                                   i,j;
	generate
		for( i=0; i<`PORT_NUM; i=i+1 ) begin : port_loop
			for( j=0; j<`PORT_NUM; j=j+1 ) begin : port_loop2
				assign flit_in_mux_array[i][j] = flit_in[j],
					mux_sel[i][j]              = port_sel[j][i],
					flit_valid_mux_in[i][j]    = flit_valid_in[j];
			end // for j

			mux_npu #(
				.N         ( `PORT_NUM       ),
				.WIDTH     ( $bits( flit_t ) ),
				.HOLD_VALUE( "TRUE"         )
			)
			mux_flit (
				.onehot( mux_sel[i]           ),
				.i_data( flit_in_mux_array[i] ),
				.o_data( flit_out[i]          )
			);

			mux_npu #(
				.N         ( `PORT_NUM ),
				.WIDTH     ( 1         ),
				.HOLD_VALUE( "FALSE"    )
			)
			mux_valid (
				.onehot( mux_sel[i]           ),
				.i_data( flit_valid_mux_in[i] ),
				.o_data( wr_en_out[i]         )
			);

		end//for i
	endgenerate

endmodule
