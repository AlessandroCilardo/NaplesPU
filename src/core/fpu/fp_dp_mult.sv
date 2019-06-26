`timescale 1ns / 1ps
//IEEE Floating Point Multiplier (Double Precision)
//Copyright (C) Jonathan P Dawson 2014
//2014-01-10

module fp_dp_mult(
		input    logic        clk,
		input    logic        rst,

		input    logic [63:0] a,
		input    logic [63:0] b,
		input    logic        in_valid,

		output   logic [63:0] z,
		output   logic        valid_out
	);
	reg                 s_output_z_stb;
	reg         [63:0]  s_output_z;
	reg                 s_input_a_ack;
	reg                 s_input_b_ack;

	reg         [3:0]   state;
  
  localparam idle         = 4'd0;
  localparam          special_cases = 4'd1;
  localparam          normalize   = 4'd2;
  localparam          multiply    = 4'd3;
  localparam          normalize_1   = 4'd4;
  localparam          normalize_2   = 4'd5;
  localparam          round         = 4'd6;
  localparam          pack          = 4'd7;
  localparam          final_stage         = 4'd8;

//
//   Stage 1 - prepare operand
//
	logic       [3:0]   s1_state;
	logic       [52:0]  s1_a_m, s1_b_m;
	logic       [12:0]  s1_a_e, s1_b_e;
	logic               s1_a_s, s1_b_s, s1_valid;
	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s1_valid<=0;
			s1_state<=idle;
		end else begin
			if( in_valid ) begin
				s1_a_m   <= {1'b0,a[51 : 0]};
				s1_b_m   <= {1'b0,b[51 : 0]};
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
	logic       [52:0]  s2_a_m, s2_b_m, s2_a_m_tmp, s2_b_m_tmp;
	logic       [12:0]  s2_a_e, s2_b_e, s2_a_e_tmp, s2_b_e_tmp;
	logic               s2_a_s, s2_b_s, s2_valid, s2_op_eq_tmp, s2_op_eq, s2_bshift_tmp, s2_bshift;
	logic       [63:0]  s2_z_tmp, s2_z;
	always_comb begin
		//if a is NaN or b is NaN return NaN
		s2_state_tmp=idle;
		if( s1_valid )begin
			//if a is NaN or b is NaN return NaN
			if ( ( s1_a_e == 1024 && s1_a_m != 0 ) || ( s1_b_e == 1024 && s1_b_m != 0 ) ) begin
				s2_z_tmp[63]    = 1;
				s2_z_tmp[62:52] = 2047;
				s2_z_tmp[51]    = 1;
				s2_z_tmp[50:0]  = 0;
				s2_state_tmp    = final_stage;
			//if a is inf return inf
			end else if ( s1_a_e == 1024 ) begin
				s2_z_tmp[63]    = s1_a_s ^ s1_b_s;
				s2_z_tmp[62:52] = 2047;
				s2_z_tmp[51:0]  = 0;
				s2_state_tmp    = final_stage;
				//if b is zero return NaN
				if ( ( $signed( s1_b_e ) == -1023 ) && ( s1_b_m == 0 ) ) begin
					s2_z_tmp[63]    = 1;
					s2_z_tmp[62:52] = 2047;
					s2_z_tmp[51]    = 1;
					s2_z_tmp[50:0]  = 0;
					s2_state_tmp    = final_stage;
				end
			//if b is inf return inf
			end else if ( s1_b_e == 1024 ) begin
				s2_z_tmp[63]    = s1_a_s ^ s1_b_s;
				s2_z_tmp[62:52] = 2047;
				s2_z_tmp[51:0]  = 0;
				//if b is zero return NaN
				if ( ( $signed( s1_a_e ) == -1023 ) && ( s1_a_m == 0 ) ) begin
					s2_z_tmp[63]    = 1;
					s2_z_tmp[62:52] = 2047;
					s2_z_tmp[51]    = 1;
					s2_z_tmp[50:0]  = 0;
					s2_state_tmp    = final_stage;
				end
				s2_state_tmp    = final_stage;
			//if a is zero return zero
			end else if ( ( $signed( s1_a_e ) == -1023 ) && ( s1_a_m == 0 ) ) begin
				s2_z_tmp[63]    = s1_a_s ^ s1_b_s;
				s2_z_tmp[62:52] = 0;
				s2_z_tmp[51:0]  = 0;
				s2_state_tmp    = final_stage;
			//if b is zero return zero
			end else if ( ( $signed( s1_b_e ) == -1023 ) && ( s1_b_m == 0 ) ) begin
				s2_z_tmp[63]    = s1_a_s ^ s1_b_s;
				s2_z_tmp[62:52] = 0;
				s2_z_tmp[51:0]  = 0;
				s2_state_tmp    = final_stage;
			end else begin
				//Denormalised Number
				if ( $signed( s1_a_e ) == -1023 ) begin
					s2_a_e_tmp      = -1022;
					s2_a_m_tmp      = s1_a_m;
				end else begin
					s2_a_m_tmp      = {1'b1, s1_a_m[51:0]};
					s2_a_e_tmp      = s1_a_e;
				end
				//Denormalised Number
				if ( $signed( s1_b_e ) == -1023 ) begin
					s2_b_e_tmp      = -1022;
					s2_b_m_tmp      = s1_b_m;
				end else begin
					s2_b_e_tmp      = s1_b_e;
					s2_b_m_tmp      = {1'b1, s1_b_m[51:0]};
				end
				s2_state_tmp    = normalize;
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
// Stage 3 - normalise
//
	logic       [3:0]   s3_state;
	logic       [5:0]   s3_la_tmp, s3_la, s3_lb_tmp, s3_lb;
	logic               s3_valid, s3_a_s, s3_b_s;
	logic       [12:0]  s3_a_e, s3_b_e;
	logic       [52:0]  s3_a_m, s3_b_m;
	logic       [63:0]  s3_z;
	always_comb
	begin
		if( s2_valid )begin
			unique casez ( s2_a_m )
				53'b1????????????????????????????????????????????????????: s3_la_tmp = 0;
				53'b01???????????????????????????????????????????????????: s3_la_tmp = 1;
				53'b001??????????????????????????????????????????????????: s3_la_tmp = 2;
				53'b0001?????????????????????????????????????????????????: s3_la_tmp = 3;
				53'b00001????????????????????????????????????????????????: s3_la_tmp = 4;
				53'b000001???????????????????????????????????????????????: s3_la_tmp = 5;
				53'b0000001??????????????????????????????????????????????: s3_la_tmp = 6;
				53'b00000001?????????????????????????????????????????????: s3_la_tmp = 7;
				53'b000000001????????????????????????????????????????????: s3_la_tmp = 8;
				53'b0000000001???????????????????????????????????????????: s3_la_tmp = 9;
				53'b00000000001??????????????????????????????????????????: s3_la_tmp = 10;
				53'b000000000001?????????????????????????????????????????: s3_la_tmp = 11;
				53'b0000000000001????????????????????????????????????????: s3_la_tmp = 12;
				53'b00000000000001???????????????????????????????????????: s3_la_tmp = 13;
				53'b000000000000001??????????????????????????????????????: s3_la_tmp = 14;
				53'b0000000000000001?????????????????????????????????????: s3_la_tmp = 15;
				53'b00000000000000001????????????????????????????????????: s3_la_tmp = 16;
				53'b000000000000000001???????????????????????????????????: s3_la_tmp = 19;
				53'b0000000000000000001??????????????????????????????????: s3_la_tmp = 17;
				53'b00000000000000000001?????????????????????????????????: s3_la_tmp = 18;
				53'b000000000000000000001????????????????????????????????: s3_la_tmp = 20;
				53'b0000000000000000000001???????????????????????????????: s3_la_tmp = 21;
				53'b00000000000000000000001??????????????????????????????: s3_la_tmp = 22;
				53'b000000000000000000000001?????????????????????????????: s3_la_tmp = 23;
				53'b0000000000000000000000001????????????????????????????: s3_la_tmp = 24;
				53'b00000000000000000000000001???????????????????????????: s3_la_tmp = 25;
				53'b000000000000000000000000001??????????????????????????: s3_la_tmp = 26;
				53'b0000000000000000000000000001?????????????????????????: s3_la_tmp = 27;
				53'b00000000000000000000000000001????????????????????????: s3_la_tmp = 28;
				53'b000000000000000000000000000001???????????????????????: s3_la_tmp = 29;
				53'b0000000000000000000000000000001??????????????????????: s3_la_tmp = 30;
				53'b00000000000000000000000000000001?????????????????????: s3_la_tmp = 31;
				53'b000000000000000000000000000000001????????????????????: s3_la_tmp = 32;
				53'b0000000000000000000000000000000001???????????????????: s3_la_tmp = 33;
				53'b00000000000000000000000000000000001??????????????????: s3_la_tmp = 34;
				53'b000000000000000000000000000000000001?????????????????: s3_la_tmp = 35;
				53'b0000000000000000000000000000000000001????????????????: s3_la_tmp = 36;
				53'b00000000000000000000000000000000000001???????????????: s3_la_tmp = 37;
				53'b000000000000000000000000000000000000001??????????????: s3_la_tmp = 38;
				53'b0000000000000000000000000000000000000001?????????????: s3_la_tmp = 39;
				53'b00000000000000000000000000000000000000001????????????: s3_la_tmp = 40;
				53'b000000000000000000000000000000000000000001???????????: s3_la_tmp = 41;
				53'b0000000000000000000000000000000000000000001??????????: s3_la_tmp = 42;
				53'b00000000000000000000000000000000000000000001?????????: s3_la_tmp = 43;
				53'b000000000000000000000000000000000000000000001????????: s3_la_tmp = 44;
				53'b0000000000000000000000000000000000000000000001???????: s3_la_tmp = 45;
				53'b00000000000000000000000000000000000000000000001??????: s3_la_tmp = 46;
				53'b000000000000000000000000000000000000000000000001?????: s3_la_tmp = 47;
				53'b0000000000000000000000000000000000000000000000001????: s3_la_tmp = 48;
				53'b00000000000000000000000000000000000000000000000001???: s3_la_tmp = 49;
				53'b000000000000000000000000000000000000000000000000001??: s3_la_tmp = 50;
				53'b0000000000000000000000000000000000000000000000000001?: s3_la_tmp = 51;
				53'b00000000000000000000000000000000000000000000000000001: s3_la_tmp = 52;
				default: s3_la_tmp                                                   = 0;
			endcase
		end
	end

	always_comb
	begin
		if( s2_valid )begin
			unique casez ( s2_b_m )
				53'b1????????????????????????????????????????????????????: s3_lb_tmp = 0;
				53'b01???????????????????????????????????????????????????: s3_lb_tmp = 1;
				53'b001??????????????????????????????????????????????????: s3_lb_tmp = 2;
				53'b0001?????????????????????????????????????????????????: s3_lb_tmp = 3;
				53'b00001????????????????????????????????????????????????: s3_lb_tmp = 4;
				53'b000001???????????????????????????????????????????????: s3_lb_tmp = 5;
				53'b0000001??????????????????????????????????????????????: s3_lb_tmp = 6;
				53'b00000001?????????????????????????????????????????????: s3_lb_tmp = 7;
				53'b000000001????????????????????????????????????????????: s3_lb_tmp = 8;
				53'b0000000001???????????????????????????????????????????: s3_lb_tmp = 9;
				53'b00000000001??????????????????????????????????????????: s3_lb_tmp = 10;
				53'b000000000001?????????????????????????????????????????: s3_lb_tmp = 11;
				53'b0000000000001????????????????????????????????????????: s3_lb_tmp = 12;
				53'b00000000000001???????????????????????????????????????: s3_lb_tmp = 13;
				53'b000000000000001??????????????????????????????????????: s3_lb_tmp = 14;
				53'b0000000000000001?????????????????????????????????????: s3_lb_tmp = 15;
				53'b00000000000000001????????????????????????????????????: s3_lb_tmp = 16;
				53'b000000000000000001???????????????????????????????????: s3_lb_tmp = 19;
				53'b0000000000000000001??????????????????????????????????: s3_lb_tmp = 17;
				53'b00000000000000000001?????????????????????????????????: s3_lb_tmp = 18;
				53'b000000000000000000001????????????????????????????????: s3_lb_tmp = 20;
				53'b0000000000000000000001???????????????????????????????: s3_lb_tmp = 21;
				53'b00000000000000000000001??????????????????????????????: s3_lb_tmp = 22;
				53'b000000000000000000000001?????????????????????????????: s3_lb_tmp = 23;
				53'b0000000000000000000000001????????????????????????????: s3_lb_tmp = 24;
				53'b00000000000000000000000001???????????????????????????: s3_lb_tmp = 25;
				53'b000000000000000000000000001??????????????????????????: s3_lb_tmp = 26;
				53'b0000000000000000000000000001?????????????????????????: s3_lb_tmp = 27;
				53'b00000000000000000000000000001????????????????????????: s3_lb_tmp = 28;
				53'b000000000000000000000000000001???????????????????????: s3_lb_tmp = 29;
				53'b0000000000000000000000000000001??????????????????????: s3_lb_tmp = 30;
				53'b00000000000000000000000000000001?????????????????????: s3_lb_tmp = 31;
				53'b000000000000000000000000000000001????????????????????: s3_lb_tmp = 32;
				53'b0000000000000000000000000000000001???????????????????: s3_lb_tmp = 33;
				53'b00000000000000000000000000000000001??????????????????: s3_lb_tmp = 34;
				53'b000000000000000000000000000000000001?????????????????: s3_lb_tmp = 35;
				53'b0000000000000000000000000000000000001????????????????: s3_lb_tmp = 36;
				53'b00000000000000000000000000000000000001???????????????: s3_lb_tmp = 37;
				53'b000000000000000000000000000000000000001??????????????: s3_lb_tmp = 38;
				53'b0000000000000000000000000000000000000001?????????????: s3_lb_tmp = 39;
				53'b00000000000000000000000000000000000000001????????????: s3_lb_tmp = 40;
				53'b000000000000000000000000000000000000000001???????????: s3_lb_tmp = 41;
				53'b0000000000000000000000000000000000000000001??????????: s3_lb_tmp = 42;
				53'b00000000000000000000000000000000000000000001?????????: s3_lb_tmp = 43;
				53'b000000000000000000000000000000000000000000001????????: s3_lb_tmp = 44;
				53'b0000000000000000000000000000000000000000000001???????: s3_lb_tmp = 45;
				53'b00000000000000000000000000000000000000000000001??????: s3_lb_tmp = 46;
				53'b000000000000000000000000000000000000000000000001?????: s3_lb_tmp = 47;
				53'b0000000000000000000000000000000000000000000000001????: s3_lb_tmp = 48;
				53'b00000000000000000000000000000000000000000000000001???: s3_lb_tmp = 49;
				53'b000000000000000000000000000000000000000000000000001??: s3_lb_tmp = 50;
				53'b0000000000000000000000000000000000000000000000000001?: s3_lb_tmp = 51;
				53'b00000000000000000000000000000000000000000000000000001: s3_lb_tmp = 52;
				default: s3_lb_tmp                                                   = 0;
			endcase
		end
	end


	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s3_valid<=0;

		end else if( s2_valid )begin
			s3_valid<=1'b1;
			s3_state<=s2_state;

			s3_a_s  <=s2_a_s;
			s3_a_e  <=s2_a_e;
			s3_a_m  <=s2_a_m;

			s3_b_s  <=s2_b_s;
			s3_b_e  <=s2_b_e;
			s3_b_m  <=s2_b_m;

			s3_la   <=s3_la_tmp;
			s3_lb   <=s3_lb_tmp;
			s3_z    <=s2_z;
		end else begin
			s3_valid<=0;
		end
	end

//
// Stage 4 -       normalize_a:
//
	logic       [63:0]  s4_z;
	logic       [3:0]   s4_state_tmp, s4_state;
	logic       [12:0]  s4_b_e_tmp, s4_a_e_tmp, s4_b_e, s4_a_e;
	logic       [52:0]  s4_a_m_tmp, s4_b_m_tmp, s4_a_m, s4_b_m;
	logic               s4_valid, s4_a_s, s4_b_s;
	always_comb
	begin
		if ( s3_valid ) begin
			if( s3_state==normalize )begin
				s4_a_m_tmp  = s3_a_m << s3_la;
				s4_a_e_tmp  = s3_a_e - s3_la;
				s4_b_m_tmp  = s3_b_m << s3_lb;
				s4_b_e_tmp  = s3_b_e - s3_lb;
				s4_state_tmp=multiply;
			end else begin
				s4_state_tmp=final_stage;

			end
		end
	end

	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s4_valid<=0;

		end else if( s3_valid )begin
			s4_valid<=1'b1;
			s4_state<=s4_state_tmp;

			s4_a_s  <=s3_a_s;
			s4_a_e  <=s4_a_e_tmp;
			s4_a_m  <=s4_a_m_tmp;

			s4_b_s  <=s3_b_s;
			s4_b_e  <=s4_b_e_tmp;
			s4_b_m  <=s4_b_m_tmp;

			s4_z    <=s3_z;
		end else begin
			s4_valid<=0;
		end
	end



//
// stage 5 - multiply
//
	logic       [3:0]   s5_state_tmp, s5_state;
	logic       [107:0] product;
	logic       [52:0]  s5_z_m;
	logic       [12:0]  s5_z_e_tmp,  s5_z_e;
	logic       [63:0]  s5_z;
	logic               s5_z_s_tmp, s5_z_s, s5_valid, s5_guard, s5_round_bit, s5_sticky;
	always_comb begin
		if( s4_valid )   begin
			if( s4_state==multiply )begin
				s5_z_s_tmp   = s4_a_s ^ s4_b_s;
				s5_z_e_tmp   = s4_a_e + s4_b_e + 1;
				product      = s4_a_m*s4_b_m*4;
				s5_state_tmp = normalize_1;
			end else begin
				s5_state_tmp = final_stage;
			end

		end
	end


	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s5_valid     <=0;

		end else if( s4_valid )begin
			s5_valid     <=1'b1;
			s5_state     <=s5_state_tmp;


			s5_z_m       <=product[107:55];
			s5_z_e       <=s5_z_e_tmp;
			s5_guard     <= product[54];
			s5_round_bit <= product[53];
			s5_sticky    <= ( product[52:0] != 0 );
			s5_z_s       <=s5_z_s_tmp;
			s5_z         <=s4_z;
		end else begin
			s5_valid     <=0;
		end
	end


//
// stage 6 - prepare normalize 1
//
	logic       [5:0]   s6_lz_tmp, s6_lz;
	logic       [3:0]   s6_state;
	logic       [52:0]  s6_z_m;
	logic       [12:0]  s6_z_e;
	logic       [63:0]  s6_z;
	logic               s6_valid, s6_sticky, s6_guard, s6_round_bit, s6_z_s ;
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

	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s6_valid     <=0;

		end else if( s5_valid )begin
			s6_valid     <=1'b1;
			s6_state     <=s5_state;

			s6_z_m       <=s5_z_m;
			s6_z_e       <=s5_z_e;
			s6_guard     <= s5_guard;
			s6_round_bit <= s5_round_bit;
			s6_sticky    <= s5_sticky;
			s6_z_s       <=s5_z_s;
			s6_z         <=s5_z;
			s6_lz        <=s6_lz_tmp;
		end else begin
			s6_valid     <=0;
		end
	end

//
// stage 7 - normalize
//
	logic       [3:0]   s7_state_tmp, s7_state;
	logic       [12:0]  s7_z_e_tmp, s7_z_e;
	logic       [52:0]  s7_z_m_tmp, s7_z_m;
	logic       [63:0]  s7_z;

	logic               s7_guard_tmp, s7_guard, s7_round_bit_tmp, s7_valid, s7_z_s, s7_sticky, s7_round_bit;
	always_comb begin
		if( s6_valid )begin
			if ( s6_state==normalize_1 ) begin
				s7_z_e_tmp          = s6_z_e - s6_lz;
				s7_z_m_tmp          = s6_z_m << s6_lz;
				s7_z_m_tmp[s6_lz-1] = s6_guard;
				s7_z_m_tmp[s6_lz-2] = s6_round_bit;
				s7_guard_tmp        = s6_round_bit;
				s7_round_bit_tmp    = 0;
				s7_state_tmp <= normalize_2;
			end else begin
				s7_state_tmp <= final_stage;
			end
		end
	end

	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s7_valid     <=0;

		end else if( s6_valid )begin
			s7_valid     <=1'b1;
			s7_state     <=s7_state_tmp;

			s7_z_m       <=s7_z_m_tmp;
			s7_z_e       <=s7_z_e_tmp;
			s7_guard     <= s7_guard_tmp;
			s7_round_bit <= s7_round_bit_tmp;
			s7_sticky    <= s6_sticky;
			s7_z_s       <=s6_z_s;
			s7_z         <=s6_z;
		end else begin
			s7_valid     <=0;
		end
	end

//
//
//
	logic       [3:0]   s8_state_tmp, s8_state;
	logic       [12:0]  s8_val_tmp, s8_z_e_tmp, s8_z_e;
	logic       [52:0]  s8_z_m_tmp, s8_z_m;
	logic       [63:0]  s8_z;
	logic s8_guard_tmp, s8_round_bit_tmp, s8_sticky_tmp,
	s8_guard, s8_round_bit, s8_sticky, s8_valid, s8_z_s;
	always_comb begin
		if ( s7_valid )begin
			if( s7_state==normalize_2 )begin
				if ( $signed( s7_z_e ) < -1022 ) begin
					s8_val_tmp       =( $signed( -1022 ) -$signed( s7_z_e ) );
					s8_z_e_tmp       = -1022;
					s8_z_m_tmp       = s7_z_m >> s8_val_tmp;
					s8_guard_tmp     = s7_z_m[s8_val_tmp];
					s8_round_bit_tmp = s7_z_m[s8_val_tmp-1];
					s8_sticky_tmp    = s7_sticky | s8_round_bit_tmp;
					s8_state_tmp     = round;
				end else begin
					s8_guard_tmp     = s7_guard;
					s8_sticky_tmp    = s7_sticky;
					s8_round_bit_tmp = s7_round_bit;
					s8_z_e_tmp       = s7_z_e;
					s8_z_m_tmp       = s7_z_m;
					s8_state_tmp     = round;
				end
			end else begin
				s8_state_tmp = final_stage;

			end

		end
	end

	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s8_valid     <=0;

		end else if( s7_valid )begin
			s8_valid     <=1'b1;
			s8_state     <=s8_state_tmp;

			s8_z_m       <=s8_z_m_tmp;
			s8_z_e       <=s8_z_e_tmp;
			s8_guard     <= s8_guard_tmp;
			s8_round_bit <= s8_round_bit_tmp;
			s8_sticky    <= s8_sticky_tmp;
			s8_z_s       <=s7_z_s;
			s8_z         <=s7_z;
		end else begin
			s8_valid     <=0;
		end
	end

//
// stage 9 - round
//
	logic       [12:0]  s9_z_e_tmp, s9_z_e;
	logic       [52:0]  s9_z_m_tmp, s9_z_m;
	logic       [3:0]   s9_state, s9_state_tmp;
	logic       [63:0]  s9_z;
	logic               s9_valid, s9_z_s;
	always_comb begin
		if( s8_valid ) begin
			if( s8_state==round )begin
				if ( s8_guard && ( s8_round_bit | s8_sticky | s8_z_m[0] ) ) begin
					s9_z_m_tmp = s8_z_m + 1;
					if ( s8_z_m == 53'hfffffe ) begin
						s9_z_e_tmp =s8_z_e + 1;
					end else begin
						s9_z_e_tmp <=s8_z_e;
					end
				end else begin
					s9_z_e_tmp <=s8_z_e;
					s9_z_m_tmp = s8_z_m;
				end

				s9_state_tmp <= pack;
			end else begin
				s9_state_tmp=final_stage;
			end

		end

	end
	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			s9_valid<=0;

		end else if( s8_valid )begin
			s9_valid<=1'b1;
			s9_state<=s9_state_tmp;

			s9_z_m  <=s9_z_m_tmp;
			s9_z_e  <=s9_z_e_tmp;
			s9_z_s  <=s8_z_s;
			s9_z    <=s8_z;
		end else begin
			s9_valid<=0;
		end
	end


//
// stage 10 -

	logic       [63:0]  z_tmp;
	always_comb begin
		if( s9_valid )begin
			if( s9_state==pack )begin
				z_tmp[51 : 0]  = s9_z_m[51:0];
				z_tmp[62 : 52] = s9_z_e[11:0] + 1023;
				z_tmp[63]      = s9_z_s;
				if ( $signed( s9_z_e ) == -1022 && s9_z_m[52] == 0 ) begin
					z_tmp[62 : 52] = 0;
				end
				//if overflow occurs, return inf
				if ( $signed( s9_z_e ) > 1023 ) begin
					z_tmp[51 : 0]  = 0;
					z_tmp[62 : 52] = 2047;
					z_tmp[63]      = s9_z_s;
				end
			end else begin
				z_tmp          = s9_z;
			end
		end
	end

	always_ff@( posedge clk, posedge rst ) begin
		if( rst ) begin
			valid_out<=0;

		end else if( s9_valid )begin
			valid_out<=1'b1;
			z        <=z_tmp;
		end else begin
			valid_out<=0;
		end
	end

endmodule