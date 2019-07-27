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

`include "npu_defines.sv"

module fp_addsub #(
		parameter DATA_WIDTH = 32 )
	(
		input  logic                      clk,
		input  logic                      rst,
		input  logic                      enable,
		input  logic [DATA_WIDTH - 1 : 0] op0,
		input  logic [DATA_WIDTH - 1 : 0] op1,
		output logic [DATA_WIDTH - 1 : 0] res
	);

	logic [DATA_WIDTH + 1 : 0] op0_fpc, op1_fpc, res_fpc;

	logic op_ce;
	logic [`FP_ADD_LATENCY-1 : 1] shift_ce, shift_ce_next;

	assign op_ce = enable | shift_ce[1];
	assign shift_ce_next = shift_ce >> 1;

	always_ff @(posedge clk) begin
	   if (enable)
	       shift_ce = '1;
	   else
	       shift_ce = shift_ce_next;
    end

	InputIEEE_8_23_to_8_23 u_conv_op0 (
		.clk ( clk     ),
		.rst ( rst     ),
		.ce  ( op_ce   ),
		.X   ( op0     ),
		.R   ( op0_fpc )
	);

	InputIEEE_8_23_to_8_23 u_conv_op1 (
		.clk ( clk     ),
		.rst ( rst     ),
		.ce  ( op_ce   ),
		.X   ( op1     ),
		.R   ( op1_fpc )
	);

	FPAdd_8_23_F270_uid2 u_FPAdd (
		.clk ( clk     ),
		.rst ( rst     ),
		.ce  ( op_ce   ),
		.X   ( op0_fpc ),
		.Y   ( op1_fpc ),
		.R   ( res_fpc )
	);

	OutputIEEE_8_23_to_8_23 u_conv_res (
		.clk ( clk     ),
		.rst ( rst     ),
		.ce  ( op_ce   ),
		.X   ( res_fpc ),
		.R   ( res     )
	);

endmodule
