`timescale 1ns / 1ps
module fp_dp_div #(
		parameter DATA_WIDTH = 64 )
	(
		input  logic                      clk,
		input  logic                      rst,
		input  logic [DATA_WIDTH - 1 : 0] op0,
		input  logic [DATA_WIDTH - 1 : 0] op1,
		output logic [DATA_WIDTH - 1 : 0] res
	);

	logic [DATA_WIDTH + 1 : 0] op0_fpc, op1_fpc, res_fpc;
	InputIEEE_11_52_to_11_52 u_conv_op0 (
		.clk ( clk     ),
		.rst ( rst     ),
		.X   ( op0     ),
		.R   ( op0_fpc )
	);

	InputIEEE_11_52_to_11_52 u_conv_op1 (
		.clk ( clk     ),
		.rst ( rst     ),
		.X   ( op1     ),
		.R   ( op1_fpc )
		);
	
	FPDiv_11_52 u_FPDiv (
		.clk ( clk     ),
		.rst ( rst     ),
		.X   ( op0_fpc ),
		.Y   ( op1_fpc ),
		.R   ( res_fpc )
	);


	OutputIEEE_11_52_to_11_52 u_conv_res (
		.clk ( clk     ),
		.rst ( rst     ),
		.X   ( res_fpc ),
		.R   ( res     )
	);



endmodule
