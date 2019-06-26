`timescale 1ns / 1ps
//Integer to IEEE Floating Point Converter (Single Precision)
//Copyright (C) Jonathan P Dawson 2013
//2013-12-12

module fp_itof (
		input     logic        clk,
		input     logic        rst,

		input     logic [31:0] input_a,
		input     logic        input_valid,

		output    logic [31:0] output_z,
		output    logic        output_valid_z
	);

    localparam idle          = 3'd0;
    localparam cltz          = 3'd1;
    localparam conv_shift    = 3'd2;
    localparam round         = 3'd3;
    localparam pack          = 3'd4;

//
// Stage 1
//
	logic       [31:0] s1_value_tmp, s1_value;
	logic       [2:0]  type_state, s1_type_state;
	logic              s1_z_s_tmp, s1_z_s, s1_valid;

	always_comb  begin
		s1_value_tmp = 0;
		s1_z_s_tmp   = 0;
		type_state   = idle;
		if( input_valid ) begin
			if ( input_a == 0 ) begin
				s1_value_tmp = {1'b0,8'h81, 23'h0};
				type_state   <= pack;
			end else begin
				s1_value_tmp <= input_a[31] ? -input_a : input_a;
				s1_z_s_tmp   <= input_a[31];
				type_state   <= cltz;
			end
		end
	end

	always_ff @(  posedge clk ,posedge rst )begin
		if( rst )
			s1_valid <= 0;
		else if( input_valid )
			s1_valid <= 1;
		else
			s1_valid <= 0;
	end

	always_ff @( posedge clk )
	begin
		if( input_valid ) begin
			s1_value      <= s1_value_tmp;
			s1_type_state <=type_state;
			s1_z_s        <=s1_z_s_tmp;
		end
	end

//
//  Stage 2 counting leadind zero
//
	logic       [4:0]  s2_lz, lz;
	logic       [31:0] s2_value;
	logic       [2:0]  s2_type_state;
	logic              s2_valid, s2_z_s;
	always_comb
	begin
		unique casez ( s1_value )
			32'b1???????????????????????????????: lz = 0;
			32'b01??????????????????????????????: lz = 1;
			32'b001?????????????????????????????: lz = 2;
			32'b0001????????????????????????????: lz = 3;
			32'b00001???????????????????????????: lz = 4;
			32'b000001??????????????????????????: lz = 5;
			32'b0000001?????????????????????????: lz = 6;
			32'b00000001????????????????????????: lz = 7;
			32'b000000001???????????????????????: lz = 8;
			32'b0000000001??????????????????????: lz = 9;
			32'b00000000001?????????????????????: lz = 10;
			32'b000000000001????????????????????: lz = 11;
			32'b0000000000001???????????????????: lz = 12;
			32'b00000000000001??????????????????: lz = 13;
			32'b000000000000001?????????????????: lz = 14;
			32'b0000000000000001????????????????: lz = 15;
			32'b00000000000000001???????????????: lz = 16;
			32'b000000000000000001??????????????: lz = 17;
			32'b0000000000000000001?????????????: lz = 18;
			32'b00000000000000000001????????????: lz = 19;
			32'b000000000000000000001???????????: lz = 20;
			32'b0000000000000000000001??????????: lz = 21;
			32'b00000000000000000000001?????????: lz = 22;
			32'b000000000000000000000001????????: lz = 23;
			32'b0000000000000000000000001???????: lz = 24;
			32'b00000000000000000000000001??????: lz = 25;
			32'b000000000000000000000000001?????: lz = 26;
			32'b0000000000000000000000000001????: lz = 27;
			32'b00000000000000000000000000001???: lz = 28;
			32'b000000000000000000000000000001??: lz = 29;
			32'b0000000000000000000000000000001?: lz = 30;
			32'b00000000000000000000000000000001: lz = 31;
			default: lz                              = 0;
		endcase
	end

	always_ff @(  posedge clk ,posedge rst )begin
		if( rst )
			s2_valid <= 0;
		else
			s2_valid <= s1_valid;
	end
	always @( posedge clk )
	begin
		if( s1_valid ) begin
			s2_value      <= s1_value;
			s2_type_state <=s1_type_state;
			s2_z_s        <=s1_z_s;
			s2_lz         <=lz;
		end
	end

//
//  Stage 3 shift
//
	logic              s3_valid, s3_z_s;
	logic       [2:0]  s3_type_state_tmp, s3_type_state;
	logic       [31:0] s3_value_tmp, s3_value;
	logic       [4:0]  s3_lz;

	always_comb begin
		if( s2_type_state== cltz )begin
			s3_value_tmp      =s2_value<<s2_lz;
			s3_type_state_tmp =conv_shift;
		end else begin
			s3_type_state_tmp<=pack;
			s3_value_tmp      =s2_value;
		end
	end


	always_ff @(  posedge clk ,posedge rst )begin
		if( rst )
			s3_valid <= 0;
		else
			s3_valid <= s2_valid;
	end


	always @( posedge clk )
	begin
		if( s2_valid ) begin
			s3_value      <= s3_value_tmp;
			s3_type_state <=s3_type_state_tmp;
			//s3_valid <= s2_valid;
			s3_z_s        <=s2_z_s;
			s3_lz         <=s2_lz;
		end
	end

//
// Stage 4 Prepare Round
//
	logic s4_guard_tmp, s4_round_bit_tmp, s4_sticky_tmp,
	s4_guard, s4_round_bit, s4_sticky,
	s4_valid, s4_z_s;
	logic       [7:0]  s4_z_e_tmp, s4_z_e;
	logic       [23:0] s4_z_m_tmp, s4_z_m;
	logic       [2:0]  s4_type_state_tmp, s4_type_state;
	always_comb begin
		if( s3_type_state==conv_shift )begin
			s4_z_e_tmp        = 31-s3_lz;
			s4_z_m_tmp        = s3_value[31:8];
			s4_guard_tmp      = s3_value[7];
			s4_round_bit_tmp  = s3_value[6];
			s4_sticky_tmp     = s3_value[5:0] != 0;
			s4_type_state_tmp = round;
		end else begin
			s4_z_e_tmp        =s3_value[30:23];
			s4_z_m_tmp        =s3_value[22:0];
			s4_guard_tmp      =0;
			s4_round_bit_tmp  =0;
			s4_sticky_tmp     =0;
			s4_type_state_tmp = pack;
		end
	end

	always_ff @(  posedge clk ,posedge rst )begin
		if( rst )
			s4_valid <= 0;
		else
			s4_valid <= s3_valid;
	end

	always @( posedge clk )
	begin
		if( s3_valid ) begin
			s4_z_e        <= s4_z_e_tmp;
			s4_z_m        <=s4_z_m_tmp;
			s4_type_state <=s4_type_state_tmp;
			s4_z_s        <=s3_z_s;
			s4_sticky     <=s4_sticky_tmp;
			s4_guard      <=s4_guard_tmp;
			s4_round_bit  <=s4_round_bit_tmp;
		end
	end

//
// Stage 5 - Round
//

	logic       [7:0]  s5_z_e_tmp, s5_z_e;
	logic       [23:0] s5_z_m_tmp, s5_z_m;
	logic              s5_valid, s5_z_s;
	always_comb begin
		if( s4_type_state==round )begin
			if ( s4_guard && ( s4_round_bit || s4_sticky || s4_z_m[0] ) ) begin
				s5_z_m_tmp = s4_z_m + 1;
				if ( s4_z_m == 24'hfffffe ) begin
					s5_z_e_tmp =s4_z_e + 1;
				end else begin
					s5_z_e_tmp<=s4_z_e;
				end
			end else begin
				s5_z_m_tmp =s4_z_m;
				s5_z_e_tmp<=s4_z_e;
			end
		end else begin
			s5_z_m_tmp=s4_z_m;
			s5_z_e_tmp<=s4_z_e;
		end
	end

	always_ff @(  posedge clk ,posedge rst )begin
		if( rst )
			s5_valid <= 0;
		else
			s5_valid <= s4_valid;
	end


	always @( posedge clk )
	begin
		if( s4_valid ) begin
			s5_z_e <= s5_z_e_tmp;
			s5_z_s <=s4_z_s;
			s5_z_m <=s5_z_m_tmp;
		end
	end

//
// 6 - End Stage
//
	logic       [31:0] z_o_t;
	always_comb begin
		begin
			z_o_t[22 : 0]  = s5_z_m[22:0];
			z_o_t[30 : 23] = s5_z_e + 127;
			z_o_t[31]      = s5_z_s;
		end
	end

	always_ff @ ( posedge clk ,posedge rst ) begin
		if( rst )
			output_valid_z <= 0;
		else
			output_valid_z <= s5_valid;
	end

	always_ff @ ( posedge clk ) begin
		if( s5_valid ) begin
			output_z <= z_o_t;
		end
	end

endmodule
