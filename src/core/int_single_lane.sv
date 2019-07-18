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

/* 
 * This module relizes a single integer ALU used in the integer pipeline. 
 */ 

module int_single_lane (
		input  register_t op0,
		input  register_t op1,
		input  opcode_t   op_code,

		output register_t result
	);

	int                                      op0_signed;
	int                                      op1_signed;
	logic [`REGISTER_SIZE * 2 - 1 : 0]       aritm_shift;
	logic [`REGISTER_SIZE * 2 - 1 : 0]       mult_res;
	logic [`REGISTER_SIZE * 2 - 1 : 0]       unsigned_mult_res;
	logic                                    is_greater_uns;
	logic                                    is_equal;
	logic                                    is_greater;

	assign op0_signed        = int'( op0 );
	assign op1_signed        = int'( op1 );
	assign mult_res          = op0_signed * op1_signed;
	assign unsigned_mult_res = op0 * op1;

	assign is_equal       = op0_signed == op1_signed;
	assign is_greater     = op0_signed > op1_signed;
	assign is_greater_uns = op0 > op1;
	assign aritm_shift    = {{32{op0[31]}}, op0};

	logic                                    is_not_null;
	logic [$clog2( `REGISTER_SIZE ) - 1 : 0] encode;
	logic [`REGISTER_SIZE - 1 : 0]           clz_ctz_in, inverted_op0;
	always_comb begin
		for ( int i=0; i < `REGISTER_SIZE; i = i + 1 )
			inverted_op0[i] = op0[`REGISTER_SIZE - i - 1];
		clz_ctz_in = ( op_code == CLZ ) ? op0 : inverted_op0;
	end

	priority_encoder_npu #(
		.INPUT_WIDTH ( `REGISTER_SIZE ),
		.MAX_PRIORITY( "MSB"          )
	)
	u_priority_encoder_npu (
		.decode( clz_ctz_in  ),
		.encode( encode      ),
		.valid ( is_not_null )
	);

	always_comb begin
		case ( op_code )
			ADD : result     = op0 + op1;
			SUB : result     = op0 - op1;
			MOVE : result    = op0;
			GETLANE : result = op0;
			ASHR : result    = register_t'( aritm_shift >> op1 );
			SHR : result     = ( op0 >> op1 );
			SHL : result     = ( op0 << op1 );
			CLZ,
			CTZ : result     = is_not_null ? (`REGISTER_SIZE - `REGISTER_SIZE'(encode) - 1) : `REGISTER_SIZE;
			MULHU : result   = unsigned_mult_res[`REGISTER_SIZE*2 - 1 : `REGISTER_SIZE];
			MULHI : result   = mult_res[`REGISTER_SIZE*2 - 1 : `REGISTER_SIZE];
			MULLO : result   = mult_res[`REGISTER_SIZE - 1 : 0               ];
			NOT : result     = ~op0;
			OR : result      = op0 | op1;
			AND : result     = op0 & op1;
			XOR : result     = op0 ^ op1;

			CMPEQ : result   = register_t'( is_equal );
			CMPNE : result   = register_t'( ~is_equal );
			CMPGT : result   = register_t'( is_greater );
			CMPGE : result   = register_t'( is_greater | is_equal );
			CMPLE : result   = register_t'( ~is_greater | is_equal );
			CMPLT : result   = register_t'( ~is_greater & ~is_equal );
			CMPGT_U : result = register_t'( is_greater_uns );
			CMPGE_U : result = register_t'( is_greater_uns | is_equal );
			CMPLT_U : result = register_t'( ~is_greater_uns & ~is_equal );
			CMPLE_U : result = register_t'( ~is_greater_uns | is_equal );

			SEXT8 : result   = {{24{op0[7]}}, op0[7 : 0]};
			SEXT16 : result  = {{16{op0[15]}}, op0[15 : 0]};
			SEXT32 : result  = op0;

			default :
			`ifdef SIMULATION
				result = {`REGISTER_SIZE{1'bx}};
			`else
				result = {`REGISTER_SIZE{1'b0}};
			`endif
		endcase
	end

endmodule
