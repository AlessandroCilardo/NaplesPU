`timescale 1ns / 1ps
module fp_dp_fix2fp #(
		parameter DATA_WIDTH = 64 )
	(
		input                       clk,
		input                       rst,
		input  [DATA_WIDTH - 1 : 0] op0,
		output [DATA_WIDTH - 1 : 0] res
	);

	logic [DATA_WIDTH + 1 : 0] op0_fpc;
	
	Fix2FP_0_63_S_11_52 u_Fix2FP_0_31_S_8_23 (
		.clk ( clk     ),
		.rst ( rst     ),
		.I   ( op0     ),
		.O   ( op0_fpc )
	);

	OutputIEEE_11_52_to_11_52 u_conv_res (
		.clk ( clk     ),
		.rst ( rst     ),
		.X   ( op0_fpc ),
		.R   ( res     )
	);

endmodule
