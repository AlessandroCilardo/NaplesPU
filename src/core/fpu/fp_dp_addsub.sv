`timescale 1ns / 1ps
//IEEE Floating Point Adder (Double Precision)
//Copyright (C) Jonathan P Dawson 2013
//2013-12-12

module fp_dp_addsub(
		input     logic        clk,
		input     logic        rst,

		input     logic [63:0] a,
		input     logic [63:0] b,
		input     logic        in_valid,

		output    logic [63:0] z,
		output    logic        out_valid
	);

  localparam idle         = 4'd0;
  localparam special_cases        = 4'd1;
  localparam align         = 4'd2;
  localparam add_0         = 4'd3;
  localparam add_1         = 4'd4;
  localparam prepare_normalise   = 4'd5;
  localparam normalise   = 4'd6;
  localparam round         = 4'd7;
  localparam pack         = 4'd8;
  localparam final_stage = 4'd9;

//
//   Stage 1 - prepare operand
//
	logic       [3:0]   s1_state;
	logic       [55:0]  s1_a_m, s1_b_m;
	logic       [12:0]  s1_a_e, s1_b_e;
	logic               s1_a_s, s1_b_s, s1_valid;
	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s1_valid<=0;
			s1_state<=idle;
		end else begin
			if( in_valid ) begin
				s1_a_m   <= {a[51 : 0], 3'd0};
				s1_b_m   <= {b[51 : 0], 3'd0};
				s1_a_e   <= a[62 : 52] - 1023;
				s1_b_e   <= b[62 : 52] - 1023;
				s1_a_s   <= a[63];
				s1_b_s   <= b[63];
				s1_valid <=1'b1;
				s1_state <= special_cases;
			end else begin
				s1_state <=idle;

				s1_valid <=1'b0;
			end
		end
	end

//
// Stage 2 - Special Case
//
	logic       [3:0]   s2_state, s2_state_tmp;
	logic       [55:0]  s2_a_m, s2_b_m, s2_a_m_tmp, s2_b_m_tmp;
	logic       [12:0]  s2_a_e, s2_b_e, s2_a_e_tmp, s2_b_e_tmp;
	logic               s2_a_s, s2_b_s, s2_valid, s2_op_eq_tmp, s2_op_eq, s2_bshift_tmp, s2_bshift;
	logic       [63:0]  s2_z_tmp, s2_z;
	always_comb begin
		//if a is NaN or b is NaN return NaN
		s2_state_tmp=idle;
		if( s1_valid )begin
			if ( ( s1_a_e == 1024 && s1_a_m != 0 ) || ( s1_b_e == 1024 && s1_b_m != 0 ) ) begin
				s2_z_tmp[63]    = 1;
				s2_z_tmp[62:52] = 2047;
				s2_z_tmp[51]    = 1;
				s2_z_tmp[50:0]  = 0;
				s2_state_tmp    = final_stage;
			//if a is inf return inf
			end else if ( s1_a_e == 1024 ) begin
				s2_z_tmp[63]    = s1_a_s;
				s2_z_tmp[62:52] = 2047;
				s2_z_tmp[51:0]  = 0;
				//if a is inf and signs don't match return nan
				if ( ( s1_b_e == 1024 ) && ( s1_a_s != s1_b_s ) ) begin
					s2_z_tmp[63]    = 1;
					s2_z_tmp[62:52] = 2047;
					s2_z_tmp[51]    = 1;
					s2_z_tmp[50:0]  = 0;
				end
				s2_state_tmp    = final_stage;
			//if b is inf return inf
			end else if ( s1_b_e == 1024 ) begin
				s2_z_tmp[63]    = s1_b_s;
				s2_z_tmp[62:52] = 2047;
				s2_z_tmp[51:0]  = 0;
				s2_state_tmp    = final_stage;
			//if a is zero return b
			end else if ( ( ( $signed( s1_a_e ) == -1023 ) && ( s1_a_m == 0 ) ) && ( ( $signed( s1_b_e ) == -1023 ) && ( s1_b_m == 0 ) ) ) begin
				s2_z_tmp[63]    = s1_a_s & s1_b_s;
				s2_z_tmp[62:52] = s1_b_e[10:0] + 1023;
				s2_z_tmp[51:0]  = s1_b_m[55:3];
				s2_state_tmp    = final_stage;
			//if a is final_stage return b
			end else if ( ( $signed( s1_a_e ) == -1023 ) && ( s1_a_m == 0 ) ) begin
				s2_z_tmp[63]    = s1_b_s;
				s2_z_tmp[62:52] = s1_b_e[10:0] + 1023;
				s2_z_tmp[51:0]  = s1_b_m[55:3];
				s2_state_tmp    = final_stage;
			//if b is zero return a
			end else if ( ( $signed( s1_b_e ) == -1023 ) && ( s1_b_m == 0 ) ) begin
				s2_z_tmp[63]    = s1_a_s;
				s2_z_tmp[62:52] = s1_a_e[10:0] + 1023;
				s2_z_tmp[51:0]  = s1_a_m[55:3];
				s2_state_tmp    = final_stage;
			end else begin
				//Denormalised Number
				if ( $signed( s1_a_e ) == -1023 ) begin
					s2_a_e_tmp      = -1022;
					s2_a_m_tmp      = s1_a_m;
				end else begin
					s2_a_e_tmp      = s1_a_e;
					s2_a_m_tmp[55:0]={1'b1, s1_a_m[54:0]};

				end
				//Denormalised Number
				if ( $signed( s1_b_e ) == -1023 ) begin
					s2_b_e_tmp      = -1022;
					s2_b_m_tmp      = s1_b_m;
				end else begin
					s2_b_e_tmp      = s1_b_e;
					s2_b_m_tmp[55:0]={1'b1, s1_b_m[54:0]};
				end

				s2_bshift_tmp   =$signed( s2_a_e_tmp ) > $signed( s2_b_e_tmp );
				s2_op_eq_tmp    =s2_a_e_tmp==s2_b_e_tmp;
				s2_state_tmp    = align;
			end
		end
	end

	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s2_valid <=0;

		end else if( s1_valid )begin
			s2_valid <=1'b1;
			s2_state <=s2_state_tmp;

			s2_a_s   <=s1_a_s;
			s2_a_e   <=s2_a_e_tmp;
			s2_a_m   <=s2_a_m_tmp;

			s2_b_s   <=s1_b_s;
			s2_b_e   <=s2_b_e_tmp;
			s2_b_m   <=s2_b_m_tmp;

			s2_bshift<=s2_bshift_tmp;
			s2_op_eq <=s2_op_eq_tmp;
			s2_z     <=s2_z_tmp;
		end else begin
			s2_valid <=0;
		end
	end

//
// Stage 3 - prepare allign
//

	logic       [3:0]   s3_state, s3_state_tmp;
	logic       [55:0]  s3_a_m, s3_b_m, s3_a_m_tmp, s3_b_m_tmp;
	logic       [12:0]  s3_a_e, s3_b_e, s3_a_e_tmp, s3_b_e_tmp;
	logic               s3_a_s, s3_b_s, s3_valid;
	logic       [63:0]  s3_z;

	logic       [12:0]  s3_n_shift_tmp;
	always_comb begin
		if( s2_valid )begin
			if( s2_state==align )begin
				s3_state_tmp <= add_0;
				if ( s2_bshift && ( ~s2_op_eq ) ) begin
					s3_n_shift_tmp=$signed( s2_a_e ) - $signed( s2_b_e );
					s3_b_e_tmp    = s2_a_e;
					s3_a_e_tmp    = s2_a_e;
					s3_b_m_tmp    = s2_b_m >> s3_n_shift_tmp;
					s3_b_m_tmp[0] = s3_b_m_tmp[1] | s3_b_m_tmp[0];

					s3_a_m_tmp    = s2_a_m;
				end else if ( ( ~s2_bshift ) && ( ~s2_op_eq ) ) begin
					s3_n_shift_tmp=$signed( s2_a_e ) - $signed( s2_b_e );
					s3_a_e_tmp    = s2_b_e;
					s3_b_e_tmp    = s2_b_e;
					s3_a_m_tmp    = s2_a_m >> s3_n_shift_tmp;
					s3_a_m_tmp[0] = s3_a_m_tmp[1] | s3_a_m_tmp[0];

					s3_b_m_tmp    = s2_b_m;
				end else begin
					s3_a_e_tmp    = s2_a_e;
					s3_a_m_tmp    = s2_a_m;
					s3_b_e_tmp    = s2_b_e;
					s3_b_m_tmp    = s2_b_m;
				end
			end else begin
				s3_state_tmp <=final_stage;
			end
		end
	end


	always_ff @( posedge clk, posedge rst ) begin
		if( rst ) begin
			s3_valid<=0;

		end else if( s2_valid )begin
			s3_valid<=1'b1;
			s3_state<=s3_state_tmp;

			s3_a_s  <=s2_a_s;
			s3_a_e  <=s3_a_e_tmp;
			s3_a_m  <=s3_a_m_tmp;

			s3_b_s  <=s2_b_s;
			s3_b_e  <=s3_b_e_tmp;
			s3_b_m  <=s3_b_m_tmp;

			s3_z    <=s2_z;
		end else begin
			s3_valid<=0;
		end
	end

//
// Stage 4 - add 0
//

	logic       [56:0]  s4_sum_tmp, s4_sum;
	logic       [3:0]   s4_state, s4_state_tmp;

	logic       [12:0]  s4_z_e_tmp, s4_z_e;
	logic               s4_z_s_tmp, s4_z_s, s4_valid;
	logic       [63:0]  s4_z;

	always_comb begin
		s4_sum_tmp=0;
		if( s3_valid )begin
			if( s3_state==add_0 )begin
				s4_z_e_tmp = s3_a_e;
				if ( s3_a_s == s3_b_s ) begin
					s4_sum_tmp = {1'd0, s3_a_m} + s3_b_m;
					s4_z_s_tmp = s3_a_s;
				end else begin
					if ( s3_a_m > s3_b_m ) begin
						s4_sum_tmp <= {1'd0, s3_a_m} - s3_b_m;
						s4_z_s_tmp <= s3_a_s;
					end else begin
						s4_sum_tmp <= {1'd0, s3_b_m} - s3_a_m;
						s4_z_s_tmp <= s3_b_s;
					end
				end
				s4_state_tmp <= add_1;
			end else begin
				s4_state_tmp <= final_stage;
			end
		end
	end


	always_ff @( posedge clk, posedge rst ) begin
		if( rst ) begin
			s4_valid<=0;

		end else if( s3_valid )begin
			s4_valid<=1'b1;
			s4_state<=s4_state_tmp;


			s4_sum  <=s4_sum_tmp;
			s4_z_s  <=s4_z_s_tmp;
			s4_z_e  <=s4_z_e_tmp;

			s4_z    <=s3_z;
		end else begin
			s4_valid<=0;
		end
	end

//
// Stage 5 - add 1
//
	logic       [3:0]   s5_state, s5_state_tmp;
	logic       [52:0]  s5_z_m_tmp, s5_z_m;
	logic       [12:0]  s5_z_e_tmp, s5_z_e;
	logic        s5_z_s, s5_valid,
	s5_sticky_tmp,s5_round_bit_tmp, s5_guard_tmp,
	s5_sticky,s5_round_bit, s5_guard;
	logic       [63:0]  s5_z;

	always_comb begin

		if( s4_valid )begin
			if( s4_state==add_1 )begin
				if ( s4_sum[56] ) begin
					s5_z_m_tmp       = s4_sum[56:4];
					s5_guard_tmp     = s4_sum[3];
					s5_round_bit_tmp = s4_sum[2];
					s5_sticky_tmp    = s4_sum[1] | s4_sum[0];
					s5_z_e_tmp       = s4_z_e + 1;
				end else begin
					s5_z_e_tmp       = s4_z_e;
					s5_z_m_tmp       = s4_sum[55:3];
					s5_guard_tmp     = s4_sum[2];
					s5_round_bit_tmp = s4_sum[1];
					s5_sticky_tmp    = s4_sum[0];
				end
				s5_state_tmp = prepare_normalise;
			end else
				s5_state_tmp =final_stage;
		end
	end


	always_ff @( posedge clk, posedge rst ) begin
		if( rst ) begin
			s5_valid    <=0;

		end else if( s4_valid )begin
			s5_valid    <=1'b1;
			s5_state    <=s5_state_tmp;



			s5_z_s      <=s4_z_s;
			s5_z_e      <=s5_z_e_tmp;
			s5_z_m      <=s5_z_m_tmp;
			;
			s5_guard    <=s5_guard_tmp;
			s5_round_bit<=s5_round_bit_tmp;
			s5_sticky   <=s5_sticky_tmp;
			s5_z        <=s4_z;
		end else begin
			s5_valid    <=0;
		end
	end

//
// stage 6 - prepare to normalise
//

	logic       [3:0]   s6_state, s6_state_tmp;

	logic       [52:0]  s6_z_m;
	logic       [12:0]  s6_z_e, s6_exp_sum_tmp, s6_exp_sum2_tmp, s6_exp_sum2, s6_exp_sum;
	logic      s6_z_s, s6_valid,
	s6_sticky,s6_round_bit, s6_guard;
	logic       [63:0]  s6_z;
	logic       [5:0]   s6_lz_tmp, s6_lz;
	always_comb
	begin
		if( s5_valid )begin
			unique casez ( s5_z_m )
				53'b1????????????????????????????????????????????????????: s6_lz_tmp = 0;
				53'b01???????????????????????????????????????????????????: s6_lz_tmp = 1;
				53'b001??????????????????????????????????????????????????: s6_lz_tmp = 2;
				53'b0001?????????????????????????????????????????????????: s6_lz_tmp = 3;
				53'b00001????????????????????????????????????????????????: s6_lz_tmp = 4;
				53'b000001???????????????????????????????????????????????: s6_lz_tmp = 5;
				53'b0000001??????????????????????????????????????????????: s6_lz_tmp = 6;
				53'b00000001?????????????????????????????????????????????: s6_lz_tmp = 7;
				53'b000000001????????????????????????????????????????????: s6_lz_tmp = 8;
				53'b0000000001???????????????????????????????????????????: s6_lz_tmp = 9;
				53'b00000000001??????????????????????????????????????????: s6_lz_tmp = 10;
				53'b000000000001?????????????????????????????????????????: s6_lz_tmp = 11;
				53'b0000000000001????????????????????????????????????????: s6_lz_tmp = 12;
				53'b00000000000001???????????????????????????????????????: s6_lz_tmp = 13;
				53'b000000000000001??????????????????????????????????????: s6_lz_tmp = 14;
				53'b0000000000000001?????????????????????????????????????: s6_lz_tmp = 15;
				53'b00000000000000001????????????????????????????????????: s6_lz_tmp = 16;
				53'b000000000000000001???????????????????????????????????: s6_lz_tmp = 19;
				53'b0000000000000000001??????????????????????????????????: s6_lz_tmp = 17;
				53'b00000000000000000001?????????????????????????????????: s6_lz_tmp = 18;
				53'b000000000000000000001????????????????????????????????: s6_lz_tmp = 20;
				53'b0000000000000000000001???????????????????????????????: s6_lz_tmp = 21;
				53'b00000000000000000000001??????????????????????????????: s6_lz_tmp = 22;
				53'b000000000000000000000001?????????????????????????????: s6_lz_tmp = 23;
				53'b0000000000000000000000001????????????????????????????: s6_lz_tmp = 24;
				53'b00000000000000000000000001???????????????????????????: s6_lz_tmp = 25;
				53'b000000000000000000000000001??????????????????????????: s6_lz_tmp = 26;
				53'b0000000000000000000000000001?????????????????????????: s6_lz_tmp = 27;
				53'b00000000000000000000000000001????????????????????????: s6_lz_tmp = 28;
				53'b000000000000000000000000000001???????????????????????: s6_lz_tmp = 29;
				53'b0000000000000000000000000000001??????????????????????: s6_lz_tmp = 30;
				53'b00000000000000000000000000000001?????????????????????: s6_lz_tmp = 31;
				53'b000000000000000000000000000000001????????????????????: s6_lz_tmp = 32;
				53'b0000000000000000000000000000000001???????????????????: s6_lz_tmp = 33;
				53'b00000000000000000000000000000000001??????????????????: s6_lz_tmp = 34;
				53'b000000000000000000000000000000000001?????????????????: s6_lz_tmp = 35;
				53'b0000000000000000000000000000000000001????????????????: s6_lz_tmp = 36;
				53'b00000000000000000000000000000000000001???????????????: s6_lz_tmp = 37;
				53'b000000000000000000000000000000000000001??????????????: s6_lz_tmp = 38;
				53'b0000000000000000000000000000000000000001?????????????: s6_lz_tmp = 39;
				53'b00000000000000000000000000000000000000001????????????: s6_lz_tmp = 40;
				53'b000000000000000000000000000000000000000001???????????: s6_lz_tmp = 41;
				53'b0000000000000000000000000000000000000000001??????????: s6_lz_tmp = 42;
				53'b00000000000000000000000000000000000000000001?????????: s6_lz_tmp = 43;
				53'b000000000000000000000000000000000000000000001????????: s6_lz_tmp = 44;
				53'b0000000000000000000000000000000000000000000001???????: s6_lz_tmp = 45;
				53'b00000000000000000000000000000000000000000000001??????: s6_lz_tmp = 46;
				53'b000000000000000000000000000000000000000000000001?????: s6_lz_tmp = 47;
				53'b0000000000000000000000000000000000000000000000001????: s6_lz_tmp = 48;
				53'b00000000000000000000000000000000000000000000000001???: s6_lz_tmp = 49;
				53'b000000000000000000000000000000000000000000000000001??: s6_lz_tmp = 50;
				53'b0000000000000000000000000000000000000000000000000001?: s6_lz_tmp = 51;
				53'b00000000000000000000000000000000000000000000000000001: s6_lz_tmp = 52;
				default: s6_lz_tmp                                                   = 0;
			endcase
		end
	end
	always_comb begin
		if( s5_valid )begin
			if( s5_state==prepare_normalise )begin
				s6_exp_sum_tmp =$signed( s5_z_e )+$signed( 13'd1022 );
				s6_exp_sum2_tmp=$signed( -1022 )-$signed( s5_z_e );

				s6_state_tmp   =normalise;
			end else
				s6_state_tmp   =final_stage;
		end
	end

	always_ff @( posedge clk, posedge rst ) begin
		if( rst ) begin
			s6_valid    <=0;

		end else if( s5_valid )begin
			s6_valid    <=1'b1;
			s6_state    <=s6_state_tmp;

			s6_z_s      <=s5_z_s;
			s6_z_e      <=s5_z_e;
			s6_z_m      <=s5_z_m;

			s6_guard    <=s5_guard;

			s6_round_bit<=s5_round_bit;
			s6_sticky   <=s5_sticky;
			s6_exp_sum2 <=s6_exp_sum2_tmp;
			s6_exp_sum  <=s6_exp_sum_tmp;
			s6_lz       <=s6_lz_tmp;
			s6_z        <=s5_z;
		end else begin
			s6_valid    <=0;
		end
	end


//
// Stage 7 - normalise
//
	logic       [3:0]   s7_state, s7_state_tmp;
	logic       [52:0]  s7_z_m_tmp,s7_z_m;
	logic       [12:0]  s7_z_e,s7_z_e_tmp;
	logic        s7_z_s, s7_valid, s7_guard_tmp,s7_round_bit_tmp,s7_sticky_tmp,
	s7_sticky,s7_round_bit, s7_guard;
	logic       [63:0]  s7_z;

	always_comb begin
		if( s6_valid )begin
			if( s6_state ==normalise ) begin
				if ( $signed( s6_z_e ) > -1022 ) begin
					s7_sticky_tmp    =s6_sticky;
					s7_round_bit_tmp = s6_round_bit;
					s7_guard_tmp     = s6_guard;
					if( s6_exp_sum>s6_lz ) begin
						s7_z_e_tmp = s6_z_e - s6_lz;
						s7_z_m_tmp = s6_z_m << s6_lz;
						if( s6_lz>1 ) begin
							s7_z_m_tmp[s6_lz-1]      = s6_guard;
							s7_z_m_tmp[s6_lz-2]      = s6_round_bit;
						end if( s6_lz==1 )begin
							s7_z_m_tmp[0]            = s6_guard;
						end
					end else begin
						s7_z_e_tmp = s6_z_e - s6_exp_sum;
						s7_z_m_tmp = s6_z_m << s6_exp_sum;
						if( s6_exp_sum>1 ) begin
							s7_z_m_tmp[s6_exp_sum-1] = s6_guard;
							s7_z_m_tmp[s6_exp_sum-2] = s6_round_bit;
						end if( s6_exp_sum==1 )begin
							s7_z_m_tmp[0]            = s6_guard;
						end
					end
				end else if ( $signed( s6_z_e ) < -1022 ) begin
					s7_z_e_tmp       = s6_z_e + s6_exp_sum2;
					s7_guard_tmp     = 0;//|s6_z_m[s6_exp_sum2:1]; todo
					s7_z_m_tmp       =s6_z_m>>s6_exp_sum2; //{{s6_exp_sum2{1'b0}},s6_z_m[52:s6_exp_sum2]};
					s7_round_bit_tmp = s7_guard_tmp;
					s7_sticky_tmp    = s6_sticky | s7_round_bit_tmp;
				end
				s7_state_tmp = round;
			end else
				s7_state_tmp = final_stage;

		end

	end


	always_ff @( posedge clk, posedge rst ) begin
		if( rst ) begin
			s7_valid    <=0;

		end else if( s6_valid )begin
			s7_valid    <=1'b1;
			s7_state    <=s7_state_tmp;

			s7_z_s      <=s6_z_s;
			s7_z_e      <=s7_z_e_tmp;
			s7_z_m      <=s7_z_m_tmp;
			s7_guard    <=s7_guard_tmp;
			s7_round_bit<=s7_round_bit_tmp;
			s7_sticky   <=s7_sticky_tmp;

			s7_z        <=s6_z;
		end else begin
			s7_valid    <=0;
		end
	end


//
//  Stage 8 - round
//
	logic       [3:0]   s8_state, s8_state_tmp;

	logic       [52:0]  s8_z_m_tmp,s8_z_m;
	logic       [12:0]  s8_z_e,s8_z_e_tmp;
	logic               s8_z_s, s8_valid;
	logic       [63:0]  s8_z;

	always_comb begin
		if( s7_valid ) begin
			if ( s7_state==round )begin
				s8_z_m_tmp   =s7_z_m;
				s8_z_e_tmp   =s7_z_e;
				if ( s7_guard && ( s7_round_bit | s7_sticky | s7_z_m[0] ) ) begin
					s8_z_m_tmp = s7_z_m + 1;
					if ( s7_z_m == 53'h1ffffffffffffe ) begin
						s8_z_e_tmp =s7_z_e + 1;
					end
				end
				s8_state_tmp = pack;
			end else begin
				s8_state_tmp = final_stage;
			end
		end
	end


	always_ff @( posedge clk, posedge rst ) begin
		if( rst ) begin
			s8_valid<=0;

		end else if( s7_valid )begin
			s8_valid<=1'b1;
			s8_state<=s8_state_tmp;

			s8_z_s  <=s7_z_s;
			s8_z_e  <=s8_z_e_tmp;
			s8_z_m  <=s8_z_m_tmp;

			s8_z    <=s7_z;
		end else begin
			s8_valid<=0;
		end
	end

//
// stage 9 - final state
//
	logic       [63:0]  z_tmp;
	always_comb begin
		if( s8_valid ) begin
			if( s8_state==pack )
			begin
				z_tmp[51 : 0]  = s8_z_m[51:0];
				z_tmp[62 : 52] = s8_z_e[10:0] + 1023;
				z_tmp[63]      = s8_z_s;
				if ( $signed( s8_z_e ) == -1022 && s8_z_m[52] == 0 ) begin
					z_tmp[62 : 52] = 0;
				end
				//if overflow occurs, return inf
				if ( $signed( s8_z_e ) > 1023 ) begin
					z_tmp[51 : 0]  = 0;
					z_tmp[62 : 52] = 2047;
					z_tmp[63]      = s8_z_s;
				end
			end else begin
				z_tmp          =s8_z;
			end

		end
	end
	always_ff @( posedge clk, posedge rst ) begin
		if( rst ) begin
			out_valid<=0;

		end else if( s8_valid )begin
			out_valid<=1;
			z        <=z_tmp;
		end else begin
			out_valid<=0;
		end
	end

endmodule
