`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    17:41:49 07/30/2015
// Design Name:
// Module Name:    fas_pipeline0
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
module fp_addsub_pipeline0(
		input         clk,
		input         rst,

		input         do_fadd,
		input         do_fsub,
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
		else if ( do_fadd || do_fsub ) begin
			//a >= b, select a
			if ( a[30:0] >= b[30:0] ) begin
				if ( a[30:0] != 31'h0 ) begin
					rX0_s           <= a[31];
					rX0_exponent    <= {1'b0, a[30:23]};
					rX0_significand <= {8'h0, 1'b1, a[22:0]};
				end
				else begin
					rX0_s           <= 0;
					rX0_exponent    <= 9'h0;
					rX0_significand <= 32'h0;
				end
			end
			//a < b, select b
			else begin
				if ( b[30:0] != 31'h0 ) begin
					if ( do_fsub ) begin
						rX0_s           <= ~b[31];
						rX0_exponent    <= {1'b0, b[30:23]};
						rX0_significand <= {8'h0, 1'b1, b[22:0]};
					end
					else begin
						rX0_s           <= b[31];
						rX0_exponent    <= {1'b0, b[30:23]};
						rX0_significand <= {8'h0, 1'b1, b[22:0]};
					end
				end
				else begin
					rX0_s           <= 0;
					rX0_exponent    <= 9'h0;
					rX0_significand <= 32'h0;
				end
			end
		end//end of else if (do_fadd || do_fsub) begin
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
		else if ( do_fadd || do_fsub ) begin
			if ( a[30:0] >= b[30:0] ) begin
				if ( do_fsub ) begin
					rY0_s           <= ~b[31];
					rY0_exponent    <= {1'b0, b[30:23]};
					rY0_significand <= {8'h0, 1'b1, b[22:0]};
				end
				else begin
					rY0_s           <= b[31];
					rY0_exponent    <= {1'b0, b[30:23]};
					rY0_significand <= {8'h0, 1'b1, b[22:0]};
				end
			end
			else begin
				rY0_s           <= a[31];
				rY0_exponent    <= {1'b0, a[30:23]};
				rY0_significand <= {8'h0, 1'b1, a[22:0]};
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
		else if ( do_fadd || do_fsub )
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
// Create Date:    10:03:35 07/31/2015
// Design Name:
// Module Name:    fas_pipline1
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
module fp_addsub_pipeline1(
		input         clk,
		input         rst,

		//s1, exp9, significand32
		input  [41:0] x0,
		input  [41:0] y0,
		input         enable,

		//s1, significand32
		output [32:0] x1,
		output [32:0] y1,
		output [8:0]  base_e,
		output        valid
	);

////////////////////////////////////////////////////////////
	wire         X0_s;
	wire [8:0]   X0_exponent;
	wire [31:0]  X0_significand;

	wire         Y0_s;
	wire [8:0]   Y0_exponent;
	wire [31:0]  Y0_significand;

	assign X0_s             = x0[41];
	assign X0_exponent      = x0[40:32];
	assign X0_significand   = x0[31:0];

	assign Y0_s             = y0[41];
	assign Y0_exponent      = y0[40:32];
	assign Y0_significand   = y0[31:0];

////////////////////////////////////////////////////////////
	reg          rX1_s;
	reg  [8:0]   rX1_exponent;
	reg  [31:0]  rX1_significand;

	reg          rY1_s;
	reg  [31:0]  rY1_significand;

	wire [31:0]  X0_shift_q;
	reg          Y0_shrn_left;   //wire
	reg  [5:0]   Y0_shrn_n;      //wire
	wire [31:0]  Y0_shift_q;

	reg          _valid;

////////////////////////////////////////////////////////////
//instances
	npu_fpu_shift32_left7 shift32_rX0_shl7_inst(
		.v( X0_significand ),
		.q( X0_shift_q )
	);

	npu_fpu_shift32 shift32_rY0_shrn_inst(
		.shift_n( Y0_shrn_n ),
		.shift_left( Y0_shrn_left ),
		.v( Y0_significand ),
		.q( Y0_shift_q )
	);

////////////////////////////////////////////////////////////
	always@(*)
	begin
		if ( X0_exponent - Y0_exponent < 9'h7 ) begin
			Y0_shrn_left = 1;
			Y0_shrn_n    = 9'h7 - ( X0_exponent - Y0_exponent );
		end
		else if ( X0_exponent - Y0_exponent > 9'h23 ) begin
			Y0_shrn_left = 0;
			Y0_shrn_n    = 16;
		end
		else begin
			Y0_shrn_left = 0;
			Y0_shrn_n    = X0_exponent - Y0_exponent - 9'h7;
		end
	end

	always@( posedge clk )
	begin
		if ( rst ) begin
			rX1_s           <= 0;
			rX1_exponent    <= 0;
			rX1_significand <= 0;
		end
		else if ( enable ) begin
			rX1_s           <= X0_s;
			rX1_exponent    <= X0_exponent - 9'h7;
			rX1_significand <= X0_shift_q;
		end
		else begin
			rX1_s           <= rX1_s;
			rX1_exponent    <= rX1_exponent;
			rX1_significand <= rX1_significand;
		end
	end

	always@( posedge clk )
	begin
		if ( rst ) begin
			rY1_s           <= 0;
			rY1_significand <= 0;
		end
		else if ( enable ) begin
			rY1_s           <= Y0_s;
			rY1_significand <= Y0_shift_q;
		end
		else begin
			rY1_s           <= rY1_s;
			rY1_significand <= rY1_significand;
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

	assign x1               = {rX1_s, rX1_significand[31:0]};
	assign y1               = {rY1_s, rY1_significand[31:0]};
	assign base_e           = rX1_exponent;
	assign valid            = _valid;


endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    10:28:21 07/31/2015
// Design Name:
// Module Name:    fp_addsub_pipeline2
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
module fp_addsub_pipeline2(
		input         clk,
		input         rst,

		//s1, significand32
		input  [32:0] x1,
		input  [32:0] y1,
		input  [8:0]  base_ei,
		input         enable,

		//s1, significand32
		output [32:0] x2,
		output [8:0]  base_eo,
		output        valid
	);

////////////////////////////////////////////////////////////
	wire        X1_s;
	wire [31:0] X1_significand;

	wire        Y1_s;
	wire [31:0] Y1_significand;

	assign X1_s             = x1[32];
	assign X1_significand   = x1[31:0];

	assign Y1_s             = y1[32];
	assign Y1_significand   = y1[31:0];

////////////////////////////////////////////////////////////
	reg         rX2_s;
	reg  [31:0] rX2_significand;

	reg  [8:0]  _base_e;
	reg         _valid;

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst ) begin
			rX2_s           <= 0;
			rX2_significand <= 0;
		end
		else if ( enable ) begin
			if ( Y1_significand == 0 ) begin
				rX2_s           <= X1_s;
				rX2_significand <= X1_significand;
			end
			else if ( X1_s == Y1_s ) begin
				rX2_s           <= X1_s;
				rX2_significand <= X1_significand + Y1_significand;
			end
			else begin
				rX2_s           <= X1_s;
				rX2_significand <= X1_significand - Y1_significand;
			end
		end
		else begin
			rX2_s           <= rX2_s;
			rX2_significand <= rX2_significand;
		end
	end

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst ) begin
			_base_e <= 0;
			_valid  <= 0;
		end
		else begin
			_base_e <= base_ei;
			_valid  <= enable;
		end
	end

	assign x2               = {rX2_s, rX2_significand[31:0]};
	assign base_eo          = _base_e;
	assign valid            = _valid;



endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    10:38:22 07/31/2015
// Design Name:
// Module Name:    fas_pipline3
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
module fp_addsub_pipeline3(
		input         clk,
		input         rst,

		//s1, significand32
		input  [32:0] x2,
		input  [8:0]  base_ei,
		input         enable,

		//s1, significand32
		output [32:0] x3,
		output [8:0]  base_eo,
		output        valid
	);

////////////////////////////////////////////////////////////
	wire        X2_s;
	wire [31:0] X2_significand;

	assign X2_s             = x2[32];
	assign X2_significand   = x2[31:0];

////////////////////////////////////////////////////////////
	reg         _sign;
	reg  [31:0] rX3_significand;
	reg  [8:0]  _base_e;
	reg         _valid;

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst )
			rX3_significand <= 0;
		else if ( enable )
			if ( X2_significand[6] ) // <=> (X2_significand & 0x0000_0040)
				rX3_significand <= X2_significand + 32'h0000_0040;
			else
				rX3_significand <= X2_significand;
		else
			rX3_significand <= rX3_significand;
	end

////////////////////////////////////////////////////////////
	always@( posedge clk )
	begin
		if ( rst ) begin
			_base_e <= 0;
			_valid  <= 0;
			_sign   <= 0;
		end
		else begin
			_base_e <= base_ei;
			_valid  <= enable;
			_sign   <= X2_s;
		end
	end

	assign x3               = {_sign, rX3_significand[31:0]};
	assign base_eo          = _base_e;
	assign valid            = _valid;

endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    10:47:48 07/31/2015
// Design Name:
// Module Name:    fas_pipline4
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
module fp_addsub_pipeline4(
		input         clk,
		input         rst,

		//s1, significand32
		input  [32:0] x3,
		input  [8:0]  base_ei,
		input         enable,

		//s1, significand32
		output [32:0] x4,
		output [8:0]  base_eo,
		output        valid
	);

////////////////////////////////////////////////////////////
	wire         X3_s;
	wire [8:0]   X3_exponent;
	wire [31:0]  X3_significand;

	assign X3_s             = x3[32];
	assign X3_exponent      = base_ei;
	assign X3_significand   = x3[31:0];

////////////////////////////////////////////////////////////
	reg          rX4_s;
	reg  [8:0]   rX4_exponent;
	reg  [31:0]  rX4_significand;

	reg          X3_shrn_left;   //wire
	reg  [5:0]   X3_shrn_n;      //wire
	wire [31:0]  X3_shift_q;
	reg  [8:0]   X3_exp_new;     //wire

	reg          _valid;

////////////////////////////////////////////////////////////
	npu_fpu_shift32 shift32_X3_shrn_inst(
		.shift_n( X3_shrn_n ),
		.shift_left( X3_shrn_left ),
		.v( X3_significand ),
		.q( X3_shift_q )
	);

////////////////////////////////////////////////////////////
	always@(*)
	begin
		////////////////////////////////
		//bigger: val = val >> n
		if ( X3_significand[31] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 8;
			X3_exp_new   = X3_exponent + 9'd8;
		end
		else if ( X3_significand[30] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 7;
			X3_exp_new   = X3_exponent + 9'd7;
		end
		else if ( X3_significand[29] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 6;
			X3_exp_new   = X3_exponent + 9'd6;
		end
		else if ( X3_significand[28] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 5;
			X3_exp_new   = X3_exponent + 9'd5;
		end
		else if ( X3_significand[27] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 4;
			X3_exp_new   = X3_exponent + 9'd4;
		end
		else if ( X3_significand[26] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 3;
			X3_exp_new   = X3_exponent + 9'd3;
		end
		else if ( X3_significand[25] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 2;
			X3_exp_new   = X3_exponent + 9'd2;
		end
		else if ( X3_significand[24] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 1;
			X3_exp_new   = X3_exponent + 9'd1;
		end
		////////////////////////////////
		//no need to shift
		else if ( X3_significand[23] ) begin
			X3_shrn_left = 0;
			X3_shrn_n    = 0;
			X3_exp_new   = X3_exponent;
		end
		////////////////////////////////
		//smaller: val = val << n
		else if ( X3_significand[22] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 1;
			X3_exp_new   = X3_exponent - 9'd1;
		end
		else if ( X3_significand[21] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 2;
			X3_exp_new   = X3_exponent - 9'd2;
		end
		else if ( X3_significand[20] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 3;
			X3_exp_new   = X3_exponent - 9'd3;
		end
		else if ( X3_significand[19] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 4;
			X3_exp_new   = X3_exponent - 9'd4;
		end
		else if ( X3_significand[18] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 5;
			X3_exp_new   = X3_exponent - 9'd5;
		end
		else if ( X3_significand[17] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 6;
			X3_exp_new   = X3_exponent - 9'd6;
		end
		else if ( X3_significand[16] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 7;
			X3_exp_new   = X3_exponent - 9'd7;
		end
		else if ( X3_significand[15] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 8;
			X3_exp_new   = X3_exponent - 9'd8;
		end
		else if ( X3_significand[14] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 9;
			X3_exp_new   = X3_exponent - 9'd9;
		end
		else if ( X3_significand[13] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 10;
			X3_exp_new   = X3_exponent - 9'd10;
		end
		else if ( X3_significand[12] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 11;
			X3_exp_new   = X3_exponent - 9'd11;
		end
		else if ( X3_significand[11] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 12;
			X3_exp_new   = X3_exponent - 9'd12;
		end
		else if ( X3_significand[10] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 13;
			X3_exp_new   = X3_exponent - 9'd13;
		end
		else if ( X3_significand[9] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 14;
			X3_exp_new   = X3_exponent - 9'd14;
		end
		else if ( X3_significand[8] ) begin
			X3_shrn_left = 1;
			X3_shrn_n    = 15;
			X3_exp_new   = X3_exponent - 9'd15;
		end
		////////////////////////////////
		//too small
		else begin
			X3_shrn_left = 1;
			X3_shrn_n    = 16;
			X3_exp_new   = 9'd0;
		end
	end

	always@( posedge clk )
	begin
		if ( rst ) begin
			rX4_s           <= 0;
			rX4_exponent    <= 0;
			rX4_significand <= 0;
		end
		else if ( enable ) begin
			if ( X3_significand < 32'h0000_000F ) begin
				rX4_s           <= 0;
				rX4_exponent    <= 0;
				rX4_significand <= 0;
			end
			else begin
				rX4_s           <= X3_s;
				rX4_exponent    <= X3_exp_new;
				rX4_significand <= X3_shift_q;
			end
		end
		else begin
			rX4_s           <= rX4_s;
			rX4_exponent    <= rX4_exponent;
			rX4_significand <= rX4_significand;
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

	assign x4               = {rX4_s, rX4_significand[31:0]};
	assign base_eo          = rX4_exponent;
	assign valid            = _valid;


endmodule
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    11:53:54 07/23/2015
// Design Name:
// Module Name:    shift32
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
module npu_fpu_shift32(
		// 0:shift  0 (not change)
		// 1:shift  1
		//   ...
		//31:shift 31
		//32:shift 32 (set zero)
		input [5:0]   shift_n,
		input         shift_left,
		input [31:0]  v,
		output[31:0]  q
	);

////////////////////////////////////////////////////////////
//== shift left ==
//v:        |3|3|2|2|2|2|2|2|2|2|2|2|1|1|1|1|
//          |1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|
//          .                               |1|1|1|1|1|1| | | | | | | | | | |
//          .                               |5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
//          .                               .                               .
//v<<2: |3|3|2|2|2|2|2|2|2|2|2|2|1|1|1|1| | |                               .
//      |1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6| | |                               .
//                                      |1|1|1|1|1|1| | | | | | | | | | | | |
//                                      |5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0| | |
//
//lo[31:0] = v[15:0]  * 16'h0004;// v[15:0]  << 2
//hi[31:0] = v[31:16] * 16'h0004;// v[31:16] << 2
//q[31:0]  = {hi[15:0], 16'h00} | lo[31:0];
//
//== shift right ==
//v:    |3|3|2|2|2|2|2|2|2|2|2|2|1|1|1|1|
//      |1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|
//      .   .                           |1|1|1|1|1|1| | | | | | | | | | |
//      .   .                           |5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
//      .   .                           .   .                           .
//v>>2: | | |3|3|2|2|2|2|2|2|2|2|2|2|1|1|1|1|                           .
//      | | |1|0|9|8|7|6|5|4|3|2|1|0|9|8|7|6|                           .
//                                          |1|1|1|1|1|1| | | | | | | | | | |
//                                          |5|4|3|2|1|0|9|8|7|6|5|4|3|2|1|0|
//
//lo[31:0] = v[15:0]  * 16'h4000;// v[15:0]  << 14
//hi[31:0] = v[31:16] * 16'h4000;// v[31:16] << 14
//q[31:0]  = hi[31:0] | {16'h00, lo[31:16]};
//
//== summary ==
//n = 0..15
//  q = v << n:=
//    b[15:0]  = 1 << n;
//    lo[31:0] = v[15:0]  * b[15:0];
//    hi[31:0] = v[31:16] * b[15:0];
//    q[31:0]  = {hi[15:0], 16'h00} | lo[31:0];
//
//  q = v >> n:=
//    b[15:0]  = 1 << (16-n);
//    lo[31:0] = v[15:0]  * b[15:0];
//    hi[31:0] = v[31:16] * b[15:0];
//    q[31:0]  = hi[31:0] | {16'h00, lo[31:16]};
//
//n = 16..32
//  q = v << n:=
//    b[15:0]  = 1 << (n-16);
//    lo[31:0] = v[15:0]  * b[15:0];
//    hi[31:0] = v[31:16] * b[15:0];
//    q[31:0]  = {lo[15:0], 16'h00};
//
//  q = v >> n:=
//    b[15:0]  = 1 << (16-(n-16));
//    lo[31:0] = v[15:0]  * b[15:0];
//    hi[31:0] = v[31:16] * b[15:0];
//    q[31:0]  = {16'h00, hi[31:16]};
//

////////////////////////////////////////////////////////////
	wire[15:0]  mul_b;
	wire[31:0]  hi;
	wire[31:0]  lo;

	wire[31:0]  res_shl16;  //n = 0..15
	wire[31:0]  res_shr16;  //n = 0..15
	wire[31:0]  res_shl32;  //n = 16..31
	wire[31:0]  res_shr32;  //n = 16..31
	reg [31:0]  res;

//mult16x16 mult16x16_hi_inst(
//    .a(v[31:16]),
//    .b(mul_b),
//    .p(hi)
//);
	assign hi              = v[31:16] *mul_b;

//mult16x16 mult16x16_lo_inst(
//    .a(v[15:0]),
//    .b(mul_b),
//    .p(lo)
//);
	assign lo              = v[15:0]*mul_b;
////////////////////////////////////////////////////////////
	reg [3:0]   decode_din; //wire
	reg [16:0]  decode_dout;//wire
	always@(*)
	begin
		case ( decode_din )
			4'd0 :decode_dout = 16'h0001;
			4'd1 :decode_dout = 16'h0002;
			4'd2 :decode_dout = 16'h0004;
			4'd3 :decode_dout = 16'h0008;
			4'd4 :decode_dout = 16'h0010;
			4'd5 :decode_dout = 16'h0020;
			4'd6 :decode_dout = 16'h0040;
			4'd7 :decode_dout = 16'h0080;
			4'd8 :decode_dout = 16'h0100;
			4'd9 :decode_dout = 16'h0200;
			4'd10:decode_dout = 16'h0400;
			4'd11:decode_dout = 16'h0800;
			4'd12:decode_dout = 16'h1000;
			4'd13:decode_dout = 16'h2000;
			4'd14:decode_dout = 16'h4000;
			4'd15:decode_dout = 16'h8000;
		endcase
	end

	always@(*)
	begin
		if ( shift_left )
			decode_din = shift_n[3:0];
		else
			decode_din = ~shift_n[3:0] + 4'b0001;
	end

	assign mul_b           = decode_dout;

////////////////////////////////////////////////////////////
	assign res_shl16[31:0] = {hi[15:0], 16'h0000} | lo[31:0];
	assign res_shr16[31:0] =  hi[31:0]            | {16'h0000, lo[31:16]};
	assign res_shl32[31:0] = {lo[15:0], 16'h00};
	assign res_shr32[31:0] = {16'h00,   hi[31:16]};

	always@(*)
	begin
		if ( shift_n == 6'd32 )
			res = 32'h0;
		else if ( shift_n == 6'd0 )
			res = v;
		else if ( shift_n[4] == 0 )//n = 0..15
			if ( shift_left )
				res = res_shl16;
			else
				res = res_shr16;
		else
			if ( shift_left )
				res = res_shl32;
			else
				res = res_shr32;
	end

	assign q               = res;


endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    14:31:25 07/23/2015
// Design Name:
// Module Name:    shift32_left7
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
module npu_fpu_shift32_left7(
		input [31:0]  v,
		output[31:0]  q
	);

	assign q[31:0] = {v[24:0], 7'h0};


endmodule

