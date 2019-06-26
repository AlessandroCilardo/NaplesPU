`timescale 1ns / 1ps
module fp_dp_fp2fix #(
		parameter DATA_WIDTH = 64 )
	(
		input                       clk,
		input                       rst,
		input  [DATA_WIDTH - 1 : 0] op0,
		output [DATA_WIDTH - 1 : 0] res
	);

	logic [DATA_WIDTH + 1 : 0] op0_fpc;

	InputIEEE_11_52_to_11_52 u_conv_op0 (
		.clk ( clk     ),
		.rst ( rst     ),
		.X   ( op0     ),
		.R   ( op0_fpc )
	);
	
	FP2Fix_11_52_0_63_S_NT u_FP2Fix_8_23_0_31_S_NT (
		.clk ( clk     ),
		.rst ( rst     ),
		.I   ( op0_fpc ),
		.O   ( res     )
	);

endmodule
