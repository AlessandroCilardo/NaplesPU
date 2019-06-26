`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    12:09:23 09/01/2015
// Design Name:
// Module Name:    FPU_f2int
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
module fp_ftoi(
		input                clk,
		input                rst,

		//do_f2int just pluse one clock
		//and wait 'valid' pluse.
		input  logic         do_f2int,
		input  logic [31:0]  b,
		output logic [31:0]  q,
		output logic         valid
	);

////////////////////////////////////////////////////////////
localparam ST_IDLE   = 4'd0;
localparam ST_SHIFT  = 4'd1;
localparam ST_ZERO   = 4'd2;
localparam ST_OVFL   = 4'd3;
localparam ST_DONE   = 4'd4;

//
//Stage 1
//

	logic        s1_valid;
	logic [3:0]  type_numb, s1_type_numb;

	logic        s2_rY_s,s1_rY_s, rY_s_tmp;
	logic [8:0]  s2_rY_exponent,s1_rY_exponent, rY_exponent_tmp;
	logic [31:0] s2_rY_significand,s1_rY_significand, rY_significand_tmp;

	always_comb begin
		type_numb          =ST_IDLE;
		rY_s_tmp           = 0;
		rY_exponent_tmp    = 0;
		rY_significand_tmp = 0;
		if( do_f2int )begin
			rY_s_tmp           = b[31];
			rY_exponent_tmp    = {1'b0, b[30:23]};
			rY_significand_tmp = {8'h0, 1'b1, b[22:0]};
			if ( b[30:23] <= 8'd126 )
				type_numb = ST_ZERO;
			else if ( b[30:23] >= 8'd159 )
				type_numb = ST_OVFL;
			else
				type_numb = ST_SHIFT;
		end
	end

	always_ff@( posedge clk )begin
		s1_type_numb      <=type_numb;
		s1_valid          <=do_f2int;
		s1_rY_s           <= rY_s_tmp;
		s1_rY_exponent    <= rY_exponent_tmp;
		s1_rY_significand <= rY_significand_tmp;
	end



//
// Stage 2
//

	logic        s2_valid;
	logic [3:0]  s2_type_numb_tmp, s2_type_numb;
	logic [31:0] s1_result, s1_result_tmp;
	logic [8:0]  s2_shift_n_tmp, s2_shift_n;
	logic        s2_shift_left_tmp, s2_shift_left;
	always_comb begin
		s2_type_numb_tmp=ST_IDLE;
		s1_result_tmp   =0;
		if( s1_valid )begin
			if ( s1_type_numb == ST_ZERO )begin
				s1_result_tmp <= 32'h0;
				s2_type_numb_tmp = ST_IDLE;
			end else if ( s1_type_numb == ST_OVFL ) begin
				s1_result_tmp <= 32'h7FFFFFFF;
				s2_type_numb_tmp = ST_IDLE;
			end else if ( s1_type_numb == ST_SHIFT ) begin
				if ( s1_rY_exponent > 9'd150 ) begin
					s2_shift_left_tmp  <= 1;
					s2_shift_n_tmp     <= s1_rY_exponent - 9'd150;
				end
				else begin
					s2_shift_left_tmp  <= 0;
					s2_shift_n_tmp     <= 9'd150 - s1_rY_exponent;
				end
				s2_type_numb_tmp = ST_DONE;
			end
		end
	end


	always_ff@( posedge clk )begin
		s1_result        <= s1_result_tmp;
		s2_type_numb     <= s2_type_numb_tmp;
		s2_shift_n       <= s2_shift_n_tmp;
		s2_shift_left    <= s2_shift_left_tmp;
		s2_valid         <= s1_valid;

		s2_rY_s          <=   s1_rY_s;
		s2_rY_exponent   <=s1_rY_exponent;
		s2_rY_significand<=s1_rY_significand;
	end


//
// Stage 3
//
	logic        s3_sign, s3_valid;
	logic [3:0]  s3_type_numb;
	logic [31:0] s3_result, s3_result_tmp, Y_shift_q;

	always_comb begin
		s3_result_tmp=0;
		if( s2_valid )begin
			if ( s2_type_numb == ST_IDLE )begin
				s3_result_tmp = s1_result;
			end else if ( s2_type_numb == ST_DONE ) begin
				s3_result_tmp = Y_shift_q;
			end
		end
	end

	npu_fpu_shift32 shift32_rY0_shrn_inst(
		.shift_n( s2_shift_n[5:0] ),
		.shift_left( s2_shift_left ),
		.v( s2_rY_significand ),
		.q( Y_shift_q )
	);

	always_ff@( posedge clk )begin
		s3_type_numb<=s2_type_numb;
		s3_sign     <=s2_rY_s;
		s3_result   <=s3_result_tmp;
		s3_valid    <=s2_valid;
	end

//
//  stage4
//

	logic [31:0] s4_result_tmp;
	always_comb begin
		s4_result_tmp=0;
		if( s3_valid )begin
			if ( s3_type_numb == ST_IDLE )begin
				s4_result_tmp = s3_result;
			end else if ( s3_type_numb == ST_DONE ) begin
				if( s3_sign )
					s4_result_tmp = ( ~s3_result )+1;
				else
					s4_result_tmp = s3_result;
			end
		end
	end

	always_ff@( posedge clk )begin
		q    <=s4_result_tmp;
		valid<=s3_valid;
	end

endmodule
