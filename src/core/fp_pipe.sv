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
`include "npu_user_defines.sv"

/*
 * Floating Point Unit (FPU). The FPU supports single-precision FP operations according to 
 * the IEEE-754-2008 standard, auto-generated using FloPoCo open-source library.
 *
 */

module fp_pipe #(
		parameter ADDER_FP_INST  = 1,
		parameter MUL_FP_INST    = 1,
		parameter DIV_FP_INST    = 1,
		parameter FIX2FP_FP_INST = 1,
		parameter FP2FIX_FP_INST = 1,
		parameter ADDER_DP_INST  = 0,
		parameter MUL_DP_INST    = 0,
		parameter DIV_DP_INST    = 0,
		parameter FIX2FP_DP_INST = 0,
		parameter FP2FIX_DP_INST = 0
	)
	(
		input                        clk,
		input                        reset,
		input                        enable,

		// From Operand Fetch
		input                        opf_valid,
		input  instruction_decoded_t opf_inst_scheduled,
		input  hw_lane_t             opf_fetched_op0,
		input  hw_lane_t             opf_fetched_op1,
		input  hw_lane_mask_t        opf_fecthed_mask,
       
		// To Writeback
		output logic                 fpu_valid,
		output instruction_decoded_t fpu_inst_scheduled,
		output hw_lane_mask_t        fpu_fecthed_mask,
		output hw_lane_t             fpu_result_sp
	);

	localparam FP_DATA_WIDTH = 32;
	localparam DP_DATA_WIDTH = 64;

	typedef struct packed {
		instruction_decoded_t instruction_decoded;
		hw_lane_mask_t fetched_mask;
	} queue_t;

	logic                                          is_fpu, is_dp;
	logic is_cmp, is_add, is_sub, is_mul, is_div, is_itof, is_ftoi,
	is_cmp_dp, is_add_dp, is_sub_dp, is_mul_dp, is_div_dp, is_itof_dp, is_ftoi_dp;

	logic             [`HW_LANE - 1 : 0]           sign_is_eq, sign_is_gt, sign_is_lt;
	logic             [`HW_LANE - 1 : 0]           exp_is_eq, exp_is_gt, exp_is_lt;
	logic             [`HW_LANE - 1 : 0]           frac_is_eq, frac_is_gt, frac_is_lt;
	logic             [`HW_LANE - 1 : 0]           cmp_is_greater, cmp_is_lesser, cmp_is_eq;
	logic             [`HW_LANE - 1 : 0]           cmp_is_greater_reg, cmp_is_lesser_reg, cmp_is_eq_reg;

	logic             [`HW_LANE/2 - 1 : 0]         sign_is_eq_dp, sign_is_gt_dp, sign_is_lt_dp;
	logic             [`HW_LANE/2 - 1 : 0]         exp_is_eq_dp, exp_is_gt_dp, exp_is_lt_dp;
	logic             [`HW_LANE/2 - 1 : 0]         frac_is_eq_dp, frac_is_gt_dp, frac_is_lt_dp;
	logic             [`HW_LANE/2 - 1 : 0]         cmp_is_greater_dp, cmp_is_lesser_dp, cmp_is_eq_dp;
	logic             [`HW_LANE/2 - 1 : 0]         cmp_is_greater_reg_dp, cmp_is_lesser_reg_dp, cmp_is_eq_reg_dp;

	hw_lane_t                                      op0_add, op1_add, op0_mult, op1_mult, op0_div, op1_div, op0_itof, op0_ftoi;
	hw_lane_t                                      res_add, res_mult, res_div, res_itof, res_ftoi, fp_result;
	hw_lane_double_t                               op0_add_dp, op1_add_dp, op0_mult_dp, op1_mult_dp, op0_div_dp, op1_div_dp, op0_itof_dp, op0_ftoi_dp;
	hw_lane_t                                      res_add_dp, res_mult_dp, res_div_dp, res_itof_dp, res_ftoi_dp;
	hw_lane_double_t                               opf_fecthed_64_op0;
	hw_lane_double_t                               opf_fecthed_64_op1;
	ieee754_sp_t      [`HW_LANE - 1 : 0]           fpsp_op0, fpsp_op1;
	ieee754_dp_t      [`HW_LANE/2 - 1 : 0]         fpdp_op0, fpdp_op1;
	logic                                          something_pending;
	queue_t           [`FP_DIV_DP_LATENCY - 1 : 0] pending_queue;

//  -----------------------------------------------------------------------
//  -- FP Lane - Generate double operand
//  -----------------------------------------------------------------------

	genvar                                         hw_lane_64_id;
	generate
		for ( hw_lane_64_id = 0; hw_lane_64_id < `HW_LANE/2; hw_lane_64_id++ ) begin : DOUBLE_LANE_AGGREGATOR
			assign opf_fecthed_64_op0[hw_lane_64_id]= {opf_fetched_op0[( hw_lane_64_id*2 )+1], opf_fetched_op0[( hw_lane_64_id*2 )]};
			assign opf_fecthed_64_op1[hw_lane_64_id]= {opf_fetched_op1[( hw_lane_64_id*2 )+1], opf_fetched_op1[( hw_lane_64_id*2 )]};
		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- FP Lane - Control Unit
//  -----------------------------------------------------------------------

	// Enabled when a FP operation is dispatched
	assign is_fpu = opf_valid & opf_inst_scheduled.is_fp;
	assign is_dp  = opf_valid & opf_inst_scheduled.is_fp & opf_inst_scheduled.is_long;

	// Input demultiplexer, it dispatches inputs to the selected FP module
	always_comb begin : INPUT_DEMUX
		is_add      = 1'b0;
		is_sub      = 1'b0;
		is_mul      = 1'b0;
		is_div      = 1'b0;
		is_cmp      = 1'b0;
		is_itof     = 1'b0;
		is_ftoi     = 1'b0;
		is_add_dp   = 1'b0;
		is_sub_dp   = 1'b0;
		is_mul_dp   = 1'b0;
		is_div_dp   = 1'b0;
		is_cmp_dp   = 1'b0;
		is_itof_dp  = 1'b0;
		is_ftoi_dp  = 1'b0;

		op0_add     = op0_add;
		op1_add     = op1_add;
		op0_mult    = op0_mult;
		op1_mult    = op1_mult;
		op0_div     = op0_div;
		op1_div     = op1_div;
		op0_itof    = op0_itof;
		op0_ftoi    = op0_ftoi;
		op0_add_dp  = op0_add_dp;
		op1_add_dp  = op1_add_dp;
		op0_mult_dp = op0_mult_dp;
		op1_mult_dp = op1_mult_dp;
		op0_div_dp  = op0_div_dp;
		op1_div_dp  = op1_div_dp;
		op0_itof_dp = op0_itof_dp;
		op0_ftoi_dp = op0_ftoi_dp;

		if ( is_fpu )
			case ( opf_inst_scheduled.op_code )
				ADD_FP   : begin
					if ( is_dp ) begin
						op0_add_dp  =opf_fecthed_64_op0;
						op1_add_dp  =opf_fecthed_64_op1;
						is_add_dp   = 1'b1;
					end else begin
						op0_add     = opf_fetched_op0;
						op1_add     = opf_fetched_op1;
						is_add      = 1'b1;
					end

				end

				SUB_FP   : begin
					if ( is_dp ) begin
						op0_add_dp  =opf_fecthed_64_op0;
						op1_add_dp  =opf_fecthed_64_op1;
						is_sub_dp   = 1'b1;
					end else begin
						op0_add     = opf_fetched_op0;
						op1_add     = opf_fetched_op1;
						is_sub      = 1'b1;
					end
				end

				MUL_FP   : begin
					if ( is_dp ) begin
						op0_mult_dp =opf_fecthed_64_op0;
						op1_mult_dp =opf_fecthed_64_op1;
						is_mul_dp   = 1'b1;
					end else begin
						op0_mult    = opf_fetched_op0;
						op1_mult    = opf_fetched_op1;
						is_mul      = 1'b1;

					end
				end

				DIV_FP   : begin
					if ( is_dp ) begin
						op0_div_dp  =opf_fecthed_64_op0;
						op1_div_dp  =opf_fecthed_64_op1;
						is_div_dp   = 1'b1;
					end else begin
						op0_div     = opf_fetched_op0;
						op1_div     = opf_fetched_op1;
						is_div      = 1'b1;
					end
				end

				CMPGT_FP,
				CMPLT_FP,
				CMPGE_FP,
				CMPLE_FP,
				CMPEQ_FP,
				CMPNE_FP : begin
					if ( is_dp ) begin
						is_cmp_dp   = 1'b1;
					end else begin
						is_cmp      = 1'b1;
					end
				end

				ITOF     : begin
					if ( is_dp ) begin
						op0_itof_dp = opf_fetched_op0;
						is_itof_dp  = 1'b1;
					end else begin
						op0_itof    = opf_fetched_op0;
						is_itof     = 1'b1;
					end
				end

				FTOI     : begin
					op0_ftoi   = opf_fetched_op0;
					is_ftoi    = 1'b1;
				end

				default : begin
					is_add     = 1'b0;
					is_sub     = 1'b0;
					is_mul     = 1'b0;
					is_div     = 1'b0;
					is_cmp     = 1'b0;
					is_itof    = 1'b0;
					is_ftoi    = 1'b0;
					is_add_dp  = 1'b0;
					is_sub_dp  = 1'b0;
					is_mul_dp  = 1'b0;
					is_div_dp  = 1'b0;
					is_cmp_dp  = 1'b0;
					is_itof_dp = 1'b0;
					is_ftoi_dp = 1'b0;
				end
			endcase
	end

	// Pending queue is a shifting queue which holds the pending requests. All floating point operators have a latency > 1,
	// the results are ready after a latency dependent on the selected operator (see local parameters for latency values).
	// The decoded instruction and the fetched mask from OPF are delayed in order to be forwarded in output along with
	// final results.
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			pending_queue <= 0;
		else
			if ( is_add | is_sub )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : `FP_ADD_LATENCY+1], {opf_inst_scheduled, opf_fecthed_mask} , pending_queue[`FP_ADD_LATENCY-1 : 1]};
			else if ( is_mul )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : `FP_MULT_LATENCY+1], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[`FP_MULT_LATENCY-1 : 1]};
			else if ( is_div )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : 18], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[16 : 1]};
			else if ( is_cmp )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : 2], {opf_inst_scheduled, opf_fecthed_mask}};
			else if ( is_itof )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : `FP_ITOF_LATENCY+1], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[`FP_ITOF_LATENCY-1 : 1]};
			else if ( is_ftoi )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : `FP_FTOI_LATENCY+1], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[`FP_FTOI_LATENCY-1 : 1]}; //pending_queue <= {queue_t'( 0 ), pending_queue[31 : 6], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[4 : 1]};
			else if ( is_add_dp | is_sub_dp )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : `FP_ADD_DP_LATENCY+1], {opf_inst_scheduled, opf_fecthed_mask} , pending_queue[`FP_ADD_DP_LATENCY-1 : 1]};
			else if ( is_mul_dp )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : `FP_MULT_DP_LATENCY+1], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[`FP_MULT_DP_LATENCY-1 : 1]};
			else if ( is_div_dp )
				pending_queue <= {{opf_inst_scheduled, opf_fecthed_mask}, pending_queue[31 : 1]};
			else if ( is_cmp_dp )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : 2], {opf_inst_scheduled, opf_fecthed_mask}};
			else if ( is_itof_dp )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : 9], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[7 : 1]};
			else if ( is_ftoi_dp )
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : 6], {opf_inst_scheduled, opf_fecthed_mask}, pending_queue[4 : 1]};
			else
				pending_queue <= {queue_t'( 0 ), pending_queue[31 : 1]};

// ASSERT: an error raise if more then an operation is recognized
`ifdef SIMULATION
	always_ff @ ( posedge clk )
		if ( ~reset & is_fpu )
			assert ( $onehot( {is_add, is_sub, is_mul, is_div, is_cmp, is_itof, is_ftoi, is_add_dp, is_sub_dp, is_mul_dp,
							is_div_dp, is_cmp_dp, is_itof_dp, is_ftoi_dp} ) ) else $fatal( 0, "[FP Pipe] Wrong Opcode, not OH!" );
`endif

//  -----------------------------------------------------------------------
//  -- FP Lane - Compare 32 bit
//  -----------------------------------------------------------------------
	genvar                                         hw_lane_id;
	generate
		for ( hw_lane_id = 0; hw_lane_id < `HW_LANE; hw_lane_id++ ) begin : SP_COMPARATOR_LANE
			assign fpsp_op0[hw_lane_id      ] = opf_fetched_op0[hw_lane_id];
			assign fpsp_op1[hw_lane_id      ] = opf_fetched_op1[hw_lane_id];

			assign sign_is_eq[hw_lane_id    ] = fpsp_op0[hw_lane_id].sign == fpsp_op1[hw_lane_id].sign;
			assign sign_is_gt[hw_lane_id    ] = fpsp_op0[hw_lane_id].sign < fpsp_op1[hw_lane_id].sign; // 0 is positive and 1 is negative
			assign sign_is_lt[hw_lane_id    ] = fpsp_op0[hw_lane_id].sign > fpsp_op1[hw_lane_id].sign;

			assign exp_is_eq[hw_lane_id     ] = fpsp_op0[hw_lane_id].exp == fpsp_op1[hw_lane_id].exp;
			assign exp_is_gt[hw_lane_id     ] = fpsp_op0[hw_lane_id].exp > fpsp_op1[hw_lane_id].exp;
			assign exp_is_lt[hw_lane_id     ] = fpsp_op0[hw_lane_id].exp < fpsp_op1[hw_lane_id].exp;

			assign frac_is_eq[hw_lane_id    ] = fpsp_op0[hw_lane_id].frac == fpsp_op1[hw_lane_id].frac;
			assign frac_is_gt[hw_lane_id    ] = fpsp_op0[hw_lane_id].frac > fpsp_op1[hw_lane_id].frac;
			assign frac_is_lt[hw_lane_id    ] = fpsp_op0[hw_lane_id].frac < fpsp_op1[hw_lane_id].frac;

			assign cmp_is_eq[hw_lane_id     ] = sign_is_eq[hw_lane_id     ] & exp_is_eq[hw_lane_id] & frac_is_eq[hw_lane_id];
			assign cmp_is_greater[hw_lane_id] = sign_is_gt[hw_lane_id     ] | ( sign_is_eq[hw_lane_id] & exp_is_gt[hw_lane_id] | ( sign_is_eq[hw_lane_id] & exp_is_eq[hw_lane_id] & frac_is_gt[hw_lane_id] ) );
			assign cmp_is_lesser[hw_lane_id ] = sign_is_lt[hw_lane_id     ] | ( sign_is_eq[hw_lane_id] & exp_is_lt[hw_lane_id] | ( sign_is_eq[hw_lane_id] & exp_is_eq[hw_lane_id] & frac_is_lt[hw_lane_id] ) );
		end
	endgenerate

	always_ff @ ( posedge clk ) begin
		cmp_is_eq_reg      <= cmp_is_eq;
		cmp_is_greater_reg <= cmp_is_greater;
		cmp_is_lesser_reg  <= cmp_is_lesser;
	end

`ifdef SIMULATION
	always_ff @( posedge clk )
		if ( ~reset & is_cmp )
			assert ( ( cmp_is_eq | cmp_is_greater | cmp_is_lesser ) != 0 ) else $fatal( 0, "[FP Pipe] The comparison result is not eq, lt or gt!" );
 `endif
//  -----------------------------------------------------------------------
//  -- FP Lane - Add, Mult, Div 32 BIT
//  -----------------------------------------------------------------------
	// Floating point operator, generated with FloPoCo, single precision. There is not a real
	// subtractor, when a subtraction is dispatched we revert the sign of the second operand
	// in the adder
	generate
		for ( hw_lane_id = 0; hw_lane_id < `HW_LANE; hw_lane_id++ ) begin : SP_UNIT_ALLOCATOR
			register_t op1_add_sub;

			// In case of subtraction, is_sub changes the sign of the second operand
			assign op1_add_sub = is_sub ? {~op1_add[hw_lane_id][31], op1_add[hw_lane_id][30 : 0]} : op1_add[hw_lane_id];

			if( ADDER_FP_INST == 1 ) begin
				fp_addsub u_fp_addsub (
					.clk    ( clk                                   ),
					.rst    ( reset                                 ),

					.do_fadd( is_add & opf_fecthed_mask[hw_lane_id] ),
					.do_fsub( is_sub & opf_fecthed_mask[hw_lane_id] ),
					.a      ( op0_add[hw_lane_id]                   ),
					.b      ( op1_add[hw_lane_id]                   ),

					.q      ( res_add[hw_lane_id]                   ),
					.valid  (                                       )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_add ) else $fatal( 0, "[FP Pipe] FP Add scheduled but no floating point adder is instantiated!" );
			end

			if( MUL_FP_INST == 1 ) begin
				fp_mult u_fp_mult (
					.clk    ( clk                                   ),
					.rst    ( reset                                 ),

					.do_fmul( is_mul & opf_fecthed_mask[hw_lane_id] ),
					.a      ( op0_mult[hw_lane_id]                  ),
					.b      ( op1_mult[hw_lane_id]                  ),

					.q      ( res_mult[hw_lane_id]                  ),
					.valid  (                                       )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_mul ) else $fatal( 0, "[FP Pipe] FP Mult scheduled but no floating point multiplier is instantiated!" );
			end

			if ( DIV_FP_INST == 1 ) begin
				fp_div #(
					.DATA_WIDTH( FP_DATA_WIDTH )
				)
				u_fp_div (
					.clk   ( clk                 ),
					.rst   ( reset               ),
					.enable( enable              ),
					.op0   ( op0_div[hw_lane_id] ),
					.op1   ( op1_div[hw_lane_id] ),
					.res   ( res_div[hw_lane_id] )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_div ) else $fatal( 0, "[FP Pipe] FP Div scheduled but no floating point divider is instantiated!" );
			end

			if( FIX2FP_FP_INST==1 ) begin
				fp_itof u_fp_itof (
					.clk           ( clk                                    ),
					.input_a       ( op0_itof[hw_lane_id]                   ),
					.input_valid   ( is_itof & opf_fecthed_mask[hw_lane_id] ),
					.output_valid_z(                                        ),
					.output_z      ( res_itof[hw_lane_id]                   ),
					.rst           ( reset                                  )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_itof ) else $fatal( 0, "[FP Pipe] FP IntToFP scheduled but no floating point converter is instantiated!" );
			end

			if( FP2FIX_FP_INST==1 ) begin
				fp_ftoi u_fp_ftoi (
					.clk     ( clk                                    ),
					.rst     ( reset                                  ),

					.do_f2int( is_ftoi & opf_fecthed_mask[hw_lane_id] ),
					.b       ( op0_ftoi[hw_lane_id]                   ),
					.q       ( res_ftoi[hw_lane_id]                   ),
					.valid   (                                        )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_ftoi ) else $fatal( 0, "[FP Pipe] FP FPToInt scheduled but no floating point converter is instantiated!" );
			end
		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- FP Lane - Compare 64 bit
//  -----------------------------------------------------------------------

	generate
		for ( hw_lane_id = 0; hw_lane_id < `HW_LANE/2; hw_lane_id++ ) begin : DP_COMPARATOR_LANE
			assign fpdp_op0[hw_lane_id         ] = opf_fecthed_64_op0[hw_lane_id];
			assign fpdp_op1[hw_lane_id         ] = opf_fecthed_64_op1[hw_lane_id];

			assign sign_is_eq_dp[hw_lane_id    ] = fpdp_op0[hw_lane_id].sign == fpdp_op1[hw_lane_id].sign;
			assign sign_is_gt_dp[hw_lane_id    ] = fpdp_op0[hw_lane_id].sign < fpdp_op1[hw_lane_id].sign; // 0 is positive and 1 is negative
			assign sign_is_lt_dp[hw_lane_id    ] = fpdp_op0[hw_lane_id].sign > fpdp_op1[hw_lane_id].sign;

			assign exp_is_eq_dp[hw_lane_id     ] = fpdp_op0[hw_lane_id].exp == fpdp_op1[hw_lane_id].exp;
			assign exp_is_gt_dp[hw_lane_id     ] = fpdp_op0[hw_lane_id].exp > fpdp_op1[hw_lane_id].exp;
			assign exp_is_lt_dp[hw_lane_id     ] = fpdp_op0[hw_lane_id].exp < fpdp_op1[hw_lane_id].exp;

			assign frac_is_eq_dp[hw_lane_id    ] = fpdp_op0[hw_lane_id].frac == fpdp_op1[hw_lane_id].frac;
			assign frac_is_gt_dp[hw_lane_id    ] = fpdp_op0[hw_lane_id].frac > fpdp_op1[hw_lane_id].frac;
			assign frac_is_lt_dp[hw_lane_id    ] = fpdp_op0[hw_lane_id].frac < fpdp_op1[hw_lane_id].frac;

			assign cmp_is_eq_dp[hw_lane_id     ] = sign_is_eq_dp[hw_lane_id     ] & exp_is_eq_dp[hw_lane_id] & frac_is_eq_dp[hw_lane_id];
			assign cmp_is_greater_dp[hw_lane_id] = sign_is_gt_dp[hw_lane_id     ] | ( sign_is_eq_dp[hw_lane_id] & exp_is_gt_dp[hw_lane_id] | ( sign_is_eq_dp[hw_lane_id] & exp_is_eq_dp[hw_lane_id] & frac_is_gt_dp[hw_lane_id] ) );
			assign cmp_is_lesser_dp[hw_lane_id ] = sign_is_lt_dp[hw_lane_id     ] | ( sign_is_eq_dp[hw_lane_id] & exp_is_lt_dp[hw_lane_id] | ( sign_is_eq_dp[hw_lane_id] & exp_is_eq_dp[hw_lane_id] & frac_is_lt_dp[hw_lane_id] ) );
		end
	endgenerate

	always_ff @ ( posedge clk ) begin
		cmp_is_eq_reg_dp      <= cmp_is_eq_dp;
		cmp_is_greater_reg_dp <= cmp_is_greater_dp;
		cmp_is_lesser_reg_dp  <= cmp_is_lesser_dp;
	end

`ifdef SIMULATION
	always_ff @( posedge clk )
		if ( ~reset & is_cmp_dp )
			assert ( ( cmp_is_eq_dp | cmp_is_greater_dp | cmp_is_lesser_dp ) != 0 ) else $fatal( 0, "[FP Pipe] The double precision comparison result is not eq, lt or gt!" );
 `endif

//  -----------------------------------------------------------------------
//  -- FP Lane - Add, Mult, Div 64 BIT
//  -----------------------------------------------------------------------

	// Floating point operator, generated with FloPoCo, single precision. There is not a real
	// subtractor, when a subtraction is dispatched we revert the sign of the second operand
	// in the adder
	generate
		for ( hw_lane_id = 0; hw_lane_id < `HW_LANE/2; hw_lane_id++ ) begin : DP_UNIT_ALLOCATOR
			register_64_t op1_add_sub_dp;

			// In case of subtraction, is_sub changes the sign of the second operand
			assign op1_add_sub_dp = is_sub_dp ? {~op1_add_dp[hw_lane_id][63], op1_add_dp[hw_lane_id][62 : 0]} : op1_add_dp[hw_lane_id];

			if( ADDER_DP_INST == 1 ) begin
				fp_dp_addsub u_fp_dp_addsub (
					.a        ( op0_add_dp[hw_lane_id]                                 ),
					.b        ( op1_add_sub_dp                                         ),
					.clk      ( clk                                                    ),
					.in_valid ( ( is_add_dp|is_sub_dp ) & opf_fecthed_mask[hw_lane_id] ),
					.out_valid(                                                        ),
					.rst      ( reset                                                  ),
					.z        ( {res_add_dp[hw_lane_id*2+1],res_add_dp[hw_lane_id*2]}  )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_add_dp ) else $fatal( 0, "[FP Pipe] FP DP Add scheduled but no floating point DP adder is instantiated!" );
			end

			if( MUL_DP_INST == 1 ) begin
				fp_dp_mult u_fp_dp_mult (
					.a        ( op0_mult_dp[hw_lane_id]                                 ),
					.b        ( op1_div_dp[hw_lane_id]                                  ),
					.clk      ( clk                                                     ),
					.in_valid ( is_mul_dp & opf_fecthed_mask[hw_lane_id]                ),
					.rst      ( reset                                                   ),
					.valid_out(                                                         ),
					.z        ( {res_mult_dp[hw_lane_id*2+1],res_mult_dp[hw_lane_id*2]} )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_mul_dp ) else $fatal( 0, "[FP Pipe] FP DP Mult scheduled but no floating point DP multiplier is instantiated!" );
			end

			if( DIV_DP_INST == 1 ) begin
				fp_dp_div #(
					.DATA_WIDTH( DP_DATA_WIDTH )
				)
				u_fp_dp_div (
					.clk ( clk                                                   ),
					.rst ( reset                                                 ),
					.op0 ( op0_div_dp[hw_lane_id]                                ),
					.op1 ( op1_div_dp[hw_lane_id]                                ),
					.res ( {res_div_dp[hw_lane_id*2+1],res_div_dp[hw_lane_id*2]} )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_div_dp ) else $fatal( 0, "[FP Pipe] FP DP Div scheduled but no floating point DP divider is instantiated!" );
			end

			if( FIX2FP_DP_INST == 1 ) begin
				fp_dp_fix2fp #(
					.DATA_WIDTH( DP_DATA_WIDTH )
				)
				u_fp_dp_fix2fp (
					.clk ( clk                                                     ),
					.rst ( reset                                                   ),
					.op0 ( op0_itof_dp[hw_lane_id]                                 ),
					.res ( {res_itof_dp[hw_lane_id*2+1],res_itof_dp[hw_lane_id*2]} )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_itof_dp ) else $fatal( 0, "[FP Pipe] FP DP IntToFP scheduled but no floating point DP converter is instantiated!" );
			end

			if( FP2FIX_DP_INST == 1 ) begin
				fp_dp_fp2fix #(
					.DATA_WIDTH( DP_DATA_WIDTH )
				)
				u_fp_dp_fp2fix (
					.clk ( clk                                                     ),
					.rst ( reset                                                   ),
					.op0 ( op0_ftoi_dp[hw_lane_id]                                 ),
					.res ( {res_ftoi_dp[hw_lane_id*2+1],res_ftoi_dp[hw_lane_id*2]} )
				);
			end else begin
				always_ff @( posedge clk )
					if ( ~reset & is_fpu )
						assert ( ~is_ftoi_dp ) else $fatal( 0, "[FP Pipe] FP DP FPToInt scheduled but no floating point DP converter is instantiated!" );
			end

		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- FP - Result
//  -----------------------------------------------------------------------

	// The output demultiplexer collects FP results from the selected operator based on the pending request.
	// The pending request contains the decoded instruction and the fetched mask of the current operation,
	// it is stripped and forwarded to the Writeback.
	always_comb begin
		something_pending = 1'b1;
		fp_result         = 0;

		case ( pending_queue[0].instruction_decoded.op_code )
			ADD_FP,
			SUB_FP   : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result    = res_add_dp;
				end else begin
					fp_result    = res_add;
				end
			end

			MUL_FP   : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result    = res_mult_dp;
				end else begin
					fp_result    = res_mult;
				end
			end

			DIV_FP   : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result    = res_div_dp;
				end else begin
					fp_result    = res_div;
				end
			end

			CMPGT_FP : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}},{`HW_LANE/2{1'b0}}, cmp_is_greater_reg_dp}
					: {{`HW_LANE{1'b0}}, {`HW_LANE{cmp_is_greater_reg_dp[0]}}};
				end else begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}}, cmp_is_greater_reg}
					: {{`HW_LANE{1'b0}}, {`HW_LANE{cmp_is_greater_reg[0]}}};
				end
			end

			CMPLT_FP : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}},{`HW_LANE/2{1'b0}}, cmp_is_lesser_reg_dp}
					: {{ `HW_LANE{1'b0}}, {`HW_LANE{cmp_is_lesser_reg_dp[0]}}};
				end else begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}}, cmp_is_lesser_reg}
					: {{`HW_LANE{1'b0}}, {`HW_LANE{cmp_is_lesser_reg[0]}}};
				end
			end

			CMPGE_FP : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}},{`HW_LANE/2{1'b0}}, cmp_is_greater_reg_dp | cmp_is_eq_reg_dp}
					: {{`HW_LANE{1'b0}}, {`HW_LANE{cmp_is_greater_reg_dp[0] | cmp_is_eq_reg_dp[0]}}};
				end else begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}}, cmp_is_greater_reg | cmp_is_eq_reg}
					: {{`HW_LANE {1'b0}}, {`HW_LANE{cmp_is_greater_reg[0] | cmp_is_eq_reg[0]}}};
				end
			end

			CMPLE_FP : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}},{`HW_LANE/2{1'b0}}, cmp_is_lesser_reg_dp | cmp_is_eq_reg_dp}
					: {{`HW_LANE{1'b0}}, {`HW_LANE{cmp_is_lesser_reg_dp[0] | cmp_is_eq_reg_dp[0]}}};
				end else begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}}, cmp_is_lesser_reg | cmp_is_eq_reg}
					: {{ `HW_LANE{1'b0}}, {`HW_LANE{cmp_is_lesser_reg[0] | cmp_is_eq_reg[0]}}};
				end
			end

			CMPEQ_FP : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}},{`HW_LANE/2{1'b0}}, cmp_is_eq_reg_dp}
					: {{`HW_LANE{1'b0}}, {`HW_LANE{cmp_is_eq_reg_dp[0]}}};
				end else begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}}, cmp_is_eq_reg}
					: {{ `HW_LANE{1'b0}}, {`HW_LANE{cmp_is_eq_reg[0]}}};
				end
			end

			CMPNE_FP : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}},{`HW_LANE/2{1'b0}}, ~cmp_is_eq_reg_dp}
					: {{`HW_LANE{1'b0}}, {`HW_LANE{~cmp_is_eq_reg_dp[0]}}};
				end else begin
					fp_result[0] = ( pending_queue[0].instruction_decoded.is_source0_vectorial ) ? {{`HW_LANE{1'b0}}, ~cmp_is_eq_reg}
					: {{ `HW_LANE{1'b0}}, {`HW_LANE{~cmp_is_eq_reg[0]}}};
				end
			end

			ITOF     : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result    = res_itof_dp;
				end else begin
					fp_result    = res_itof;
				end
			end
			FTOI     : begin
				if( pending_queue[0].instruction_decoded.is_long ) begin
					fp_result    = res_ftoi_dp;
				end else begin
					fp_result    = res_ftoi;
				end
			end
			default : begin
				fp_result         = {`HW_LANE{{32{1'bX}}}};
				something_pending = 1'b0;
			end
		endcase
	end

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			fpu_valid <= 1'b0;
		else
			fpu_valid <= something_pending;

	always_ff @ ( posedge clk ) begin
		fpu_result_sp      <= fp_result;
		fpu_inst_scheduled <= pending_queue[0].instruction_decoded;
		fpu_fecthed_mask   <= pending_queue[0].fetched_mask;
	end

endmodule
