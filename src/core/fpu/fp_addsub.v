`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    11:00:15 07/31/2015
// Design Name:
// Module Name:    fp_addsub
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
module fp_addsub(
		input          clk,
		input          rst,

		//do_fadd/do_fsub just pluse one clock
		//and wait 'valid' pluse.
		input          do_fadd,
		input          do_fsub,
		input  [31:0]  a,
		input  [31:0]  b,

		output [31:0]  q,
		output         valid
	);

	wire [41:0] x0;
	wire [41:0] y0;
	wire        valid0;

	wire [32:0] x1;
	wire [32:0] y1;
	wire [8:0]  base_e1;
	wire        valid1;

	wire [32:0] x2;
	wire [8:0]  base_e2;
	wire        valid2;

	wire [32:0] x3;
	wire [8:0]  base_e3;
	wire        valid3;

	wire [32:0] x4;
	wire [8:0]  base_e4;
	wire        valid4;

	fp_addsub_pipeline0 u_fp_addsub_pipeline0 (
		.clk( clk ),
		.rst( rst ),

		.do_fadd( do_fadd ),
		.do_fsub( do_fsub ),
		.a( a ),
		.b( b ),

		.x0( x0 ),
		.y0( y0 ),
		.valid( valid0 )
	);

	fp_addsub_pipeline1 u_fp_addsub_pipeline1 (
		.clk( clk ),
		.rst( rst ),

		.x0( x0 ),
		.y0( y0 ),
		.enable( valid0 ),

		.x1( x1 ),
		.y1( y1 ),
		.base_e( base_e1 ),
		.valid( valid1 )
	);

	fp_addsub_pipeline2 u_fp_addsub_pipeline2 (
		.clk( clk ),
		.rst( rst ),

		.x1( x1 ),
		.y1( y1 ),
		.base_ei( base_e1 ),
		.enable( valid1 ),

		.x2( x2 ),
		.base_eo( base_e2 ),
		.valid( valid2 )
	);

	fp_addsub_pipeline3 u_fp_addsub_pipeline3 (
		.clk( clk ),
		.rst( rst ),

		.x2( x2 ),
		.base_ei( base_e2 ),
		.enable( valid2 ),

		.x3( x3 ),
		.base_eo( base_e3 ),
		.valid( valid3 )
	);

	fp_addsub_pipeline4 u_fp_addsub_pipeline4 (
		.clk( clk ),
		.rst( rst ),

		.x3( x3 ),
		.base_ei( base_e3 ),
		.enable( valid3 ),

		.x4( x4 ),
		.base_eo( base_e4 ),
		.valid( valid4 )
	);

	assign q[31:0] = {x4[32], base_e4[7:0], x4[22:0]};
	assign valid   = valid4;

endmodule
