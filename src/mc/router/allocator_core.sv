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
/*
 * The virtual channel and switch allocation is logically the same for both, so it is 
 * encased in a unit called allocator core. It is simply a parametrizable number 
 * of parallel arbiters in which the input and output are properly scrambled and 
 * the output are or-ed to obtain a port-granularity grant. 
 * The difference between other stages is that each arbiter is a round-robin 
 * arbiter with a grant-hold circuit. This permits to obtain an uninterrupted use 
 * of the obtained resource, especially requested to respect one of the rule in the 
 * VC allocation.
 */

module allocator_core #(
		parameter N    = 5,
		parameter M    = 4,
		parameter SIZE = 5 )
	(
		input                                             clk,
		input                                             reset,
		input  logic [N - 1 : 0][M - 1 : 0][SIZE - 1 : 0] request,
		input  logic [N - 1 : 0][M - 1 : 0]               on_off,
		output logic [N - 1 : 0][M - 1 : 0]               grant
	);

	logic  [N - 1 : 0][M - 1 : 0][SIZE - 1 : 0] reordered_request;
	logic  [N - 1 : 0][M - 1 : 0][SIZE - 1 : 0] not_ordered_grant;
	logic  [N - 1 : 0][M - 1 : 0][SIZE - 1 : 0] grant_tmp;
	logic  [N - 1 : 0][M - 1 : 0][SIZE - 1 : 0] grant_tmp2;

	genvar                                      i,j,k;
	generate
		for( i=0; i < N; i=i + 1 ) begin : port_loop
			for( j=0; j < M; j=j + 1 ) begin : vc_loop

				grant_hold_round_robin_arbiter #(
					.SIZE( SIZE ) )
				u_grant_hold_rr_arbiter (
					.clk         ( clk                     ),
					.reset       ( reset                   ),
					.requests    ( reordered_request[i][j] ),
					.hold_in     ( reordered_request[i][j] ),
					.decision_oh ( not_ordered_grant[i][j] )
				);

				assign grant[i][j] = |grant_tmp2[i][j];

				for( k=0; k < SIZE; k=k + 1 ) begin : dest_loop
					assign reordered_request[i][j][k] = request[k][j][i] ;
					assign grant_tmp[i][j][k]         = not_ordered_grant[k][j][i] ;
					assign grant_tmp2[i][j][k]         = grant_tmp[i][j][k] & ~on_off[k][j];
				end
			end
			
			
		end
	endgenerate

endmodule
