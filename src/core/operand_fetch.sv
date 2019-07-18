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
`include "npu_user_defines.sv"
`include "npu_defines.sv"

/*
 * Operand_fetch module instantiates two register files: a scalar register file (SRF) and a vector register file (VRF).
 * The SRF contains `REGISTER_NUMBER registers (default 64) of `REGISTER_SIZE bits (default 32) each. Dually, the VRF
 * contains `REGISTER_NUMBER vectorial registers (default 64), each of them is composed by `HW_LANE scalar registers.
 *
 * Each thread has its own register file, this is achieved allocating a bigger SRAM (REGISTER_NUMBER x `THREAD_NUMB).
 *
 * The register `MASK_REG (default scalar register $60) stores the current mask used in vectorial operations, it is
 * forwarded in output through opf_fecthed_mask signal.
 *
 * When source 1 is immediate, its value is replied on each vector element.
 * Memory accesses and branches operations require a base address. In both cases Decode module maps base address in source0.
 *
 */

module operand_fetch(
		input                                               clk,
		input                                               reset,
		input                                               enable,

		// Interface with Instruction Scheduler Module (Issue)
		input                                               issue_valid,
		input  thread_id_t                                  issue_thread_id,
		input  instruction_decoded_t                        issue_inst_scheduled,
		input  scoreboard_t                                 issue_destination_bitmap,

		// Interface with Rollback Handler
		input                        [`THREAD_NUMB - 1 : 0] rollback_valid,

		// Interface with Writeback Module
		input                                               wb_valid,
		input  thread_id_t                                  wb_thread_id,
		input  wb_result_t                                  wb_result,

		// To Execution Pipes
		output logic                                        opf_valid,
		output instruction_decoded_t                        opf_inst_scheduled,
		output hw_lane_t                                    opf_fetched_op0,
		output hw_lane_t                                    opf_fetched_op1,
		output hw_lane_mask_t                               opf_hw_lane_mask,
		output scoreboard_t                                 opf_destination_bitmap,

		// Coherency lookup for memory accesses
		output register_t                                   effective_address,
		input  logic                                        uncoherent_area_hit
	);

	typedef logic [`BYTE_PER_REGISTER - 1 : 0] byte_width_t;
	typedef byte_width_t [`HW_LANE - 1 : 0] lane_byte_width_t;

	logic                                    next_valid;
	thread_id_t                              next_issue_thread_id;
	instruction_decoded_t                    next_issue_inst_scheduled;
	reg_addr_t                               next_source0;
	reg_addr_t                               next_source1;
	address_t                                next_pc;

	// Scalar RF signals
	logic                                    rd_en0_scalar, rd_en1_scalar, wr_en_scalar;
	register_t                               rd_out0_scalar, rd_out1_scalar;
	reg_addr_t                               rd_src1_eff_addr;
	hw_lane_mask_t                           mask_register [`THREAD_NUMB];

	// Vector RF signals
	logic                                    rd_en0_vector, rd_en1_vector, wr_en_vector;
	hw_lane_t                                rd_out0_vector, rd_out1_vector;

	scoreboard_t                             next_opf_destination_bitmap;
	hw_lane_mask_t                           opf_hw_lane_mask_buff;
	hw_lane_t                                opf_fetched_op0_buff;
	hw_lane_t                                opf_fetched_op1_buff;

	lane_byte_width_t                        write_en_byte;

//  -----------------------------------------------------------------------
//  -- Register Files read - 1 Stage
//  -----------------------------------------------------------------------
	genvar                                   lane_id;
	generate
		for ( lane_id = 0; lane_id < `HW_LANE; lane_id ++ ) begin : LANE_WRITE_EN
			// This for-generate calculates the write enable for each HW lane. The HW lane mask signal
			// handles which lane is affected by the current operation. Each vector register has a
			// byte wise write enable. In case of moveh and movel just half word has to be written,
			// the other half word has no changes.
			assign write_en_byte[lane_id] = wb_result.wb_result_write_byte_enable &
				{( `BYTE_PER_REGISTER ){wb_result.wb_result_hw_lane_mask[lane_id] & wr_en_vector}};
		end
	endgenerate

	// Vector RF
	memory_bank_2r1w #(
		.SIZE   ( `REGISTER_NUMBER * `THREAD_NUMB ),
		.NB_COL ( `BYTE_PER_REGISTER * `HW_LANE   )
	)
	vector_reg_file (
		.clock        ( clk                                             ),

		.read1_enable ( rd_en0_vector                                   ),
		.read1_address( {issue_thread_id, issue_inst_scheduled.source0} ),
		.read1_data   ( rd_out0_vector                                  ),

		.read2_enable ( rd_en1_vector                                   ),
		.read2_address( {issue_thread_id, issue_inst_scheduled.source1} ),
		.read2_data   ( rd_out1_vector                                  ),

		.write_enable ( write_en_byte                                   ),
		.write_address( {wb_thread_id, wb_result.wb_result_register}    ),
		.write_data   ( wb_result.wb_result_data                        )
	);

	assign rd_en0_vector         = issue_valid && issue_inst_scheduled.is_source0_vectorial;
	assign rd_en1_vector         = issue_valid && issue_inst_scheduled.is_source1_vectorial;
	assign wr_en_vector          = wb_valid && !wb_result.wb_result_is_scalar;

	// Scalar RF
	memory_bank_2r1w #(
		.SIZE   ( `REGISTER_NUMBER * `THREAD_NUMB ),
		.NB_COL ( `BYTE_PER_REGISTER              )
	)
	scalar_reg_file (
		.clock        ( clk                                                                            ),

		.read1_enable ( rd_en0_scalar                                                                  ),
		.read1_address( {issue_thread_id, issue_inst_scheduled.source0}                                ),
		.read1_data   ( rd_out0_scalar                                                                 ),

		.read2_enable ( rd_en1_scalar                                                                  ),
		.read2_address( {issue_thread_id, issue_inst_scheduled.source1}                                ),
		.read2_data   ( rd_out1_scalar                                                                 ),

		.write_enable ( wb_result.wb_result_write_byte_enable & {( `BYTE_PER_REGISTER ){wr_en_scalar}} ),
		.write_address( {wb_thread_id, wb_result.wb_result_register}                                   ),
		.write_data   ( wb_result.wb_result_data[0]                                                    )
	);

	assign rd_en0_scalar         = issue_valid && !issue_inst_scheduled.is_source0_vectorial;
	assign rd_en1_scalar         = issue_valid && ( !issue_inst_scheduled.is_source1_vectorial | issue_inst_scheduled.mask_enable );
	assign wr_en_scalar          = wb_valid && wb_result.wb_result_is_scalar;

	// We support a fixed lane mask register. All vectorial operation are masked, we statically load the mask register.
	genvar                                   thread_id;
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id ++ ) begin : REG_MASK
			always_ff @ ( posedge clk, posedge reset ) begin
				if ( reset )
					mask_register[thread_id] <= hw_lane_mask_t'(0);
				else if ( wb_thread_id == thread_id_t'(thread_id) & wb_result.wb_result_register == reg_addr_t'(`MASK_REG) )
					mask_register[thread_id] <= hw_lane_mask_t'(wb_result.wb_result_data[0]);
			end
		end
	endgenerate

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			next_valid                  <= 1'b0;
		else
			if ( enable )
				next_valid                  <= issue_valid & ~rollback_valid[issue_thread_id];

	always_ff @ ( posedge clk )
		if ( enable ) begin
			next_issue_thread_id        <= issue_thread_id;
			next_issue_inst_scheduled   <= issue_inst_scheduled;
			next_opf_destination_bitmap <= issue_destination_bitmap;
			next_source0                <= issue_inst_scheduled.source0;
			next_source1                <= issue_inst_scheduled.source1;
			next_pc                     <= issue_inst_scheduled.pc;
		end

//  -----------------------------------------------------------------------
//  -- Operand Fetch - 2 Stage
//  -----------------------------------------------------------------------

// Load mask register. If the current instruction is not masked the mask is set to all 1
	assign opf_hw_lane_mask_buff = ( next_issue_inst_scheduled.mask_enable ) ? mask_register[next_issue_thread_id] : {`HW_LANE{1'b1}};

	always_comb begin : OPERAND0_COMPOSER
		// Operand 0 - Memory access and branch operation require a base address.
		// In both cases Decode module maps base address in source0. Otherwise
		// operand 0 holds the value from the required register file.
		opf_fetched_op0_buff <= rd_out0_vector;

		if ( ~next_issue_inst_scheduled.is_source0_vectorial )
			if ( next_source0 == reg_addr_t'(`PC_REG) )
				if ( next_issue_inst_scheduled.is_memory_access )
					opf_fetched_op0_buff[0] <= next_pc + register_t'( next_issue_inst_scheduled.immediate );
				else
					opf_fetched_op0_buff    <= {`HW_LANE{next_pc}};
			else
				if ( next_issue_inst_scheduled.is_memory_access )
					// In case of memory access, opf_fetched_op0 holds the effective memory address
					opf_fetched_op0_buff[0] <= rd_out0_scalar + register_t'( next_issue_inst_scheduled.immediate );
				else
					opf_fetched_op0_buff    <= {`HW_LANE{rd_out0_scalar}};
	end

	assign effective_address = opf_fetched_op0_buff[0];

	always_comb begin : OPERAND1_COMPOSER
		// Operand 1 - If the current instruction has in immediate, this is replicated
		// on each vector element of operand 1. Otherwise operand 1 holds the value from
		// the required register file.
		if ( next_issue_inst_scheduled.is_source1_immediate )
			opf_fetched_op1_buff <= {`HW_LANE{next_issue_inst_scheduled.immediate}};
		else
			if( next_issue_inst_scheduled.is_source1_vectorial )
				opf_fetched_op1_buff <= rd_out1_vector;
			else
				if ( next_source1 == reg_addr_t'(`PC_REG) )
					opf_fetched_op1_buff <= {`HW_LANE{next_pc}};
				else
					opf_fetched_op1_buff <= {`HW_LANE{rd_out1_scalar}};
	end

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			opf_valid <= 1'b0;
		else
			if ( enable )
				opf_valid <= next_valid & ~rollback_valid[next_issue_thread_id];

	always_ff @ ( posedge clk )
		if ( enable ) begin
			opf_inst_scheduled     <= next_issue_inst_scheduled;
			opf_inst_scheduled.is_memory_access_coherent <= ~uncoherent_area_hit;

			opf_destination_bitmap <= next_opf_destination_bitmap;
			opf_hw_lane_mask       <= opf_hw_lane_mask_buff;
			opf_fetched_op0        <= opf_fetched_op0_buff;
			opf_fetched_op1        <= opf_fetched_op1_buff;
		end

endmodule
