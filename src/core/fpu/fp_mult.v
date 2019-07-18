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
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    16:26:08 07/31/2015
// Design Name:
// Module Name:    FPU_fmul
// Project Name:
// Target Devices:
// Tool versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module fp_mult(
		input          clk,
		input          rst,

		//do_fmul just pluse one clock
		//and wait 'valid' pluse.
		input          do_fmul,
		input  [31:0]  a,
		input  [31:0]  b,

		output [31:0]  q,
		output         valid
	);

	wire [41:0] x0;
	wire [41:0] y0;
	wire        valid0;

	wire [64:0] x1;
	wire [8:0]  base_e1;
	wire        valid1;

	wire [64:0] x2;
	wire [8:0]  base_e2;
	wire        valid2;

	wire [31:0] x3;
	wire [8:0]  base_e3;
	wire        valid3;

	fp_mul_pipeline0 u_fp_mul_pipeline0 (
		.clk( clk ),
		.rst( rst ),

		.do_fmul( do_fmul ),
		.a( a ),
		.b( b ),

		.x0( x0 ),
		.y0( y0 ),
		.valid( valid0 )
	);

	fp_mul_pipeline1 u_fp_mul_pipeline1 (
		.clk( clk ),
		.rst( rst ),

		.x0( x0 ),
		.y0( y0 ),
		.enable( valid0 ),

		.x1( x1 ),
		.base_e( base_e1 ),
		.valid( valid1 )
	);

	fp_mul_pipeline2 u_fp_mul_pipeline2 (
		.clk( clk ),
		.rst( rst ),

		.x1( x1 ),
		.base_ei( base_e1 ),
		.enable( valid1 ),

		.x2( x2 ),
		.base_eo( base_e2 ),
		.valid( valid2 )
	);

	fp_mul_pipeline3 u_fp_mul_pipeline3 (
		.clk( clk ),
		.rst( rst ),

		.x2( x2 ),
		.base_ei( base_e2 ),
		.enable( valid2 ),

		.x3( x3 ),
		.base_eo( base_e3 ),
		.valid( valid3 )
	);


	assign q[31:0] = {x3[31], base_e3[7:0], x3[22:0]};
	assign valid   = valid3;


endmodule
