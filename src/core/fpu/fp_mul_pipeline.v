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
// Create Date:    16:25:07 07/31/2015
// Design Name:
// Module Name:    fp_mul_pipeline0
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
module fp_mul_pipeline0(
		input         clk,
		input         rst,

		input         do_fmul,
		input  [31:0] a,
		input  [31:0] b,

		//s1, exp9, significand32
		output [41:0] x0,
		output [41:0] y0,
		output        valid
	);

////////////////////////////////////////////////////////////
	reg        rX0_s;
	reg [8:0]  rX0_exponent;
	reg [31:0] rX0_significand;

	reg        rY0_s;
	reg [8:0]  rY0_exponent;
	reg [31:0] rY0_significand;

	reg        _valid;

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst ) begin
			rX0_s           <= 0;
			rX0_exponent    <= 0;
			rX0_significand <= 0;
		end
		else if ( do_fmul ) begin
			if ( a[30:0] != 31'h0 ) begin
				rX0_s           <= a[31];
				rX0_exponent    <= {1'b0, a[30:23]};
				rX0_significand <= {8'h0, 1'b1, a[22:0]};
			end
			else begin
				rX0_s           <= 0;
				rX0_exponent    <= 0;
				rX0_significand <= 0;
			end
		end
		else begin
			rX0_s           <= rX0_s;
			rX0_exponent    <= rX0_exponent;
			rX0_significand <= rX0_significand;
		end
	end

	always@( posedge clk )
	begin
		if ( rst ) begin
			rY0_s           <= 0;
			rY0_exponent    <= 0;
			rY0_significand <= 0;
		end
		else if ( do_fmul ) begin
			if ( b[30:0] != 31'h0 ) begin
				rY0_s           <= b[31];
				rY0_exponent    <= {1'b0, b[30:23]};
				rY0_significand <= {8'h0, 1'b1, b[22:0]};
			end
			else begin
				rY0_s           <= 0;
				rY0_exponent    <= 0;
				rY0_significand <= 0;
			end
		end
		else begin
			rY0_s           <= rY0_s;
			rY0_exponent    <= rY0_exponent;
			rY0_significand <= rY0_significand;
		end
	end

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst )
			_valid <= 1'b0;
		else if ( do_fmul )
			_valid <= 1'b1;
		else
			_valid <= 1'b0;
	end

	assign x0[41:0] = {rX0_s, rX0_exponent[8:0], rX0_significand[31:0]};
	assign y0[41:0] = {rY0_s, rY0_exponent[8:0], rY0_significand[31:0]};
	assign valid    = _valid;


endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    17:00:18 07/31/2015
// Design Name:
// Module Name:    fmul_pipeline1
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
module fp_mul_pipeline1(
		input         clk,
		input         rst,

		//s1, exp9, significand32
		input  [41:0] x0,
		input  [41:0] y0,
		input         enable,

		//s1, significand64
		output [64:0] x1,
		output [8:0]  base_e,
		output        valid
	);

////////////////////////////////////////////////////////////
	wire        X0_s;
	wire [8:0]  X0_exponent;
	wire [31:0] X0_significand;

	wire        Y0_s;
	wire [8:0]  Y0_exponent;
	wire [31:0] Y0_significand;

	assign X0_s             = x0[41];
	assign X0_exponent      = x0[40:32];
	assign X0_significand   = x0[31:0];

	assign Y0_s             = y0[41];
	assign Y0_exponent      = y0[40:32];
	assign Y0_significand   = y0[31:0];

////////////////////////////////////////////////////////////
	reg         rX1_s;
	reg  [8:0]  rX1_exponent;
	reg  [63:0] rX1_significand;

	wire [31:0] mul_a;
	wire [31:0] mul_b;
	wire [63:0] mul_p;

	reg         _valid;

////////////////////////////////////////////////////////////
//mult32x32 mult32x32_x1_inst(
//    .a(mul_a),
//    .b(mul_b),
//    .p(mul_p)
//);

	assign mul_p            = mul_a * mul_b;

	assign mul_a[31:0]      = X0_significand[31:0];
	assign mul_b[31:0]      = Y0_significand[31:0];

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst ) begin
			rX1_s           <= 0;
			rX1_exponent    <= 0;
		end
		else if ( enable ) begin
			if ( mul_p[63:0] == 64'h0 ) begin
				rX1_s           <= 0;
				rX1_exponent    <= 0;
			end
			else begin
				rX1_s           <= X0_s ^ Y0_s;
				rX1_exponent    <= X0_exponent + Y0_exponent - 9'd127;
			end
		end
		else begin
			rX1_s           <= rX1_s;
			rX1_exponent    <= rX1_exponent;
		end
	end

	always@( posedge clk )
	begin
		if ( rst )
			rX1_significand <= 0;
		else if ( enable )
			rX1_significand <= mul_p;
		else
			rX1_significand <= rX1_significand;
	end

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst )
			_valid <= 1'b0;
		else
			_valid <= enable;
	end

	assign x1               = {rX1_s, rX1_significand[63:0]};
	assign base_e           = rX1_exponent;
	assign valid            = _valid;


endmodule


//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    17:19:57 07/31/2015
// Design Name:
// Module Name:    fp_mul_pipeline2
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
module fp_mul_pipeline2(
		input         clk,
		input         rst,

		//s1, significand64
		input  [64:0] x1,
		input  [8:0]  base_ei,
		input         enable,

		//s1, significand64
		output [64:0] x2,
		output [8:0]  base_eo,
		output        valid
	);

////////////////////////////////////////////////////////////
	wire        X1_s;
	wire [8:0]  X1_exponent;
	wire [63:0] X1_significand;

	assign X1_s             = x1[64];
	assign X1_exponent      = base_ei;
	assign X1_significand   = x1[63:0];

////////////////////////////////////////////////////////////
	reg         rX2_s;
	reg  [8:0]  rX2_exponent;
	reg  [63:0] rX2_significand;

	reg         _valid;

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst ) begin
			rX2_s           <= 0;
			rX2_exponent    <= 0;
			rX2_significand <= 0;
		end
		else if ( enable ) begin
			if ( X1_significand[23] ) begin
				rX2_s           <= X1_s;
				rX2_exponent    <= X1_exponent;
				rX2_significand <= X1_significand + 64'h0000_0000_0080_0000;
			end
			else begin
				rX2_s           <= X1_s;
				rX2_exponent    <= X1_exponent;
				rX2_significand <= X1_significand;
			end
		end
		else begin
			rX2_s           <= rX2_s;
			rX2_exponent    <= rX2_exponent;
			rX2_significand <= rX2_significand;
		end
	end

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst )
			_valid <= 1'b0;
		else
			_valid <= enable;
	end

	assign x2               = {rX2_s, rX2_significand[63:0]};
	assign base_eo          = rX2_exponent;
	assign valid            = _valid;


endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    17:30:20 07/31/2015
// Design Name:
// Module Name:    fp_mul_pipeline3
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
module fp_mul_pipeline3(
		input         clk,
		input         rst,

		//s1, significand64
		input  [64:0] x2,
		input  [8:0]  base_ei,
		input         enable,

		//s1, significand32
		output [31:0] x3,
		output [8:0]  base_eo,
		output        valid
	);

////////////////////////////////////////////////////////////
	wire        X2_s;
	wire [8:0]  X2_exponent;
	wire [63:0] X2_significand;

	assign X2_s             = x2[64];
	assign X2_exponent      = base_ei;
	assign X2_significand   = x2[63:0];

////////////////////////////////////////////////////////////
	reg         rX3_s;
	reg  [8:0]  rX3_exponent;
	reg  [31:0] rX3_significand;

	reg         _valid;

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst ) begin
			rX3_s           <= 0;
			rX3_exponent    <= 0;
			rX3_significand <= 0;
		end
		else if ( enable ) begin
			if ( X2_significand[47] ) begin
				rX3_s           <= X2_s;
				rX3_exponent    <= X2_exponent + 9'd1;
				rX3_significand <= {8'h0, X2_significand[47:24]};
			end
			else begin
				rX3_s           <= X2_s;
				rX3_exponent    <= X2_exponent;
				rX3_significand <= {8'h0, X2_significand[46:23]};
			end
		end
		else begin
			rX3_s           <= rX3_s;
			rX3_exponent    <= rX3_exponent;
			rX3_significand <= rX3_significand;
		end
	end

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst )
			_valid <= 1'b0;
		else
			_valid <= enable;
	end

	assign x3               = {rX3_s, rX3_significand[30:0]};
	assign base_eo          = rX3_exponent;
	assign valid            = _valid;

endmodule
