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
`include "npu_coherence_defines.sv"
`include "npu_debug_log.sv"

/*
 * This is the first stage of the Load/Store Unit.
 *
 * This stage is equipped with one queue per thread, which stores the threads-relative instructions coming from the
 * Operand Fetch. All pending requests are forwarded in parallel to the second stage.
 *
 * If the second stage is able to execute the instruction provided of i-th thread, asserts combinatorially
 * the i-th bit of the ldst2_dequeue_instruction mask in order to notify to this stage that the request
 * has been consumed. In this way, the second stage stalls instructions in this stage when it is busy.
 *
 * Before enqueuing a request, the data are aligned and compressed into a proper vector and replicated when necessary.
 *
 * The flush operation forces the data to be enqueued, even if the instruction_valid signal is not asserted.
 *
 * This stage also provides a recycle buffer: if a cache miss occurs in the 3th stage, the data is stored in this buffer,
 * and will be processed later. The output of this this buffer is forwarded to the 2nd stage along with the other requests.
 *
 * In case of a request on an IO Mapped address, the current request is forwarded to the Cache Controller and is not propagated
 * to the next stage.
 *
 */

module load_store_unit_stage1 #(
	parameter TILE_ID = 0
) (
		input  logic                                        clk,
		input  logic                                        reset,

		//  Operand Fetch
		input  logic                                        opf_valid,
		input  instruction_decoded_t                        opf_inst_scheduled,
		input  hw_lane_t                                    opf_fecthed_op0,
		input  hw_lane_t                                    opf_fecthed_op1,
		input  hw_lane_mask_t                               opf_hw_lane_mask,

		// Load Store Unit Stage 2
		input  thread_mask_t                                ldst2_dequeue_instruction,
		input  thread_mask_t                                ldst2_recycled,

		output thread_mask_t                                ldst1_valid,
		output instruction_decoded_t [`THREAD_NUMB - 1 : 0] ldst1_instruction,
		output dcache_address_t      [`THREAD_NUMB - 1 : 0] ldst1_address,
		output dcache_line_t         [`THREAD_NUMB - 1 : 0] ldst1_store_value,
		output dcache_store_mask_t   [`THREAD_NUMB - 1 : 0] ldst1_store_mask,
		output hw_lane_mask_t        [`THREAD_NUMB - 1 : 0] ldst1_hw_lane_mask,

		output thread_mask_t                                ldst1_recycle_valid,
		output instruction_decoded_t [`THREAD_NUMB - 1 : 0] ldst1_recycle_instruction,
		output dcache_address_t      [`THREAD_NUMB - 1 : 0] ldst1_recycle_address,
		output dcache_line_t         [`THREAD_NUMB - 1 : 0] ldst1_recycle_store_value,
		output dcache_store_mask_t   [`THREAD_NUMB - 1 : 0] ldst1_recycle_store_mask,
		output hw_lane_mask_t        [`THREAD_NUMB - 1 : 0] ldst1_recycle_hw_lane_mask,

		// Load Store Unit Stage 3
		input  logic                                        ldst3_miss,
		input  instruction_decoded_t                        ldst3_instruction,
		input  dcache_line_t                                ldst3_cache_line,
		input  hw_lane_mask_t                               ldst3_hw_lane_mask,
		input  dcache_store_mask_t                          ldst3_store_mask,
		input  dcache_address_t                             ldst3_address,

		input  logic                                        ldst3_io_valid,
		input  [$bits(io_operation_t)-1 : 0]                ldst3_io_operation,
		input  thread_id_t                                  ldst3_io_thread,

		// Instruction Scheduler
		output thread_mask_t                                ldst1_almost_full,

		//To Synch Core
		output logic                 [`THREAD_NUMB - 1 : 0] s1_no_ls_pending,
		output logic                 [`THREAD_NUMB - 1 : 0] miss_no_ls_pending,

		// Rollback Handler
		input  thread_mask_t                                rollback_valid,

		output logic                                        ldst1_rollback_en,
		output register_t                                   ldst1_rollback_pc,
		output thread_id_t                                  ldst1_rollback_thread_id
	);

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - FIFO Parameters
//  -----------------------------------------------------------------------

    localparam FIFO_ALMOST_FULL_THRESHOLD   = 1; // the thread is immediately stopped
    localparam FIFO_WIDTH                   = $bits( dcache_request_t );
    localparam FIFO_SIZE                    = 4; // the number of maximum load/store/flush between starting from a cache miss

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - Signals
//  -----------------------------------------------------------------------

	logic                                          instruction_valid;
	logic                                          is_flush;
	dcache_address_t                               effective_address;

	logic                                          is_vectorial_op;
	logic                                          is_word_op;
	logic                                          is_halfword_op;
	logic                                          is_byte_op;

	logic                                          is_1_byte_aligned;                //scalar byte operation
	logic                                          is_2_byte_aligned;                //scalar halfword operation
	logic                                          is_4_byte_aligned;                //scalar word operation

	logic                                          is_16_byte_aligned;               //byte vectorial operation
	logic                                          is_32_byte_aligned;               //halfword vectorial operation
	logic                                          is_64_byte_aligned;               //word  vector operation

	logic                                          is_misaligned;
	logic                                          is_out_of_memory;


	logic               [`HW_LANE - 1 : 0][7 : 0]  byte_vector;
	logic               [`HW_LANE - 1 : 0][15 : 0] halfword_vector;
	logic               [`HW_LANE - 1 : 0][31 : 0] word_vector;
	dcache_line_t                                  byte_aligned_vector_data;
	dcache_store_mask_t                            byte_aligned_vector_mask;
	dcache_line_t                                  halfword_aligned_vector_data;
	dcache_store_mask_t                            halfword_aligned_vector_mask;
	dcache_line_t                                  word_aligned_vector_data;
	dcache_store_mask_t                            word_aligned_vector_mask;
	dcache_line_t                                  byte_aligned_scalar_data;
	dcache_store_mask_t                            byte_aligned_scalar_mask;
	dcache_line_t                                  halfword_aligned_scalar_data;
	dcache_store_mask_t                            halfword_aligned_scalar_mask;
	dcache_line_t                                  word_aligned_scalar_data;
	dcache_store_mask_t                            word_aligned_scalar_mask;

	dcache_request_t                               fifo_input;

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - Instruction Decode
//  -----------------------------------------------------------------------

	assign instruction_valid  = opf_valid & opf_inst_scheduled.pipe_sel == PIPE_MEM & ~rollback_valid[opf_inst_scheduled.thread_id];
	assign is_flush           = instruction_valid & opf_inst_scheduled.op_code.contr_opcode == FLUSH;
	assign is_out_of_memory   = 1'b0; //XXX: To be implemented

	assign is_vectorial_op    = opf_inst_scheduled.is_destination_vectorial & opf_inst_scheduled.is_source1_vectorial;

	assign is_word_op         =
		opf_inst_scheduled.op_code.mem_opcode == LOAD_32 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_32_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_32 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_32_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_32 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_32_U ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_32 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_V_32 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_S_32;

	assign is_halfword_op     =
		opf_inst_scheduled.op_code.mem_opcode == LOAD_16 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_16_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_16 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_16_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_16 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_16_U ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_16 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_V_16 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_S_16;

	assign is_byte_op         =
		opf_inst_scheduled.op_code.mem_opcode == LOAD_8 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_8_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_8 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_8_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_8 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_8_U ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_8 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_V_8 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_S_8;

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - Address Alignment Check
//  -----------------------------------------------------------------------

	assign effective_address  = opf_fecthed_op0[0];

	assign is_1_byte_aligned  = 1'b1;
	assign is_2_byte_aligned  = ~( effective_address[0] );
	assign is_4_byte_aligned  = ~( |effective_address[1 : 0] );
	assign is_16_byte_aligned = ~( |effective_address[3 : 0] );
	assign is_32_byte_aligned = ~( |effective_address[4 : 0] );
	assign is_64_byte_aligned = ~( |effective_address[5 : 0] );

	assign is_misaligned      =
		( is_vectorial_op &&
			( ( is_byte_op && !is_16_byte_aligned ) ||
				( is_halfword_op && !is_32_byte_aligned ) ||
				( is_word_op && !is_64_byte_aligned ) ) ) ||
		( !is_vectorial_op &&
			( ( is_byte_op && !is_1_byte_aligned ) ||
				( is_halfword_op && !is_2_byte_aligned ) ||
				( is_word_op && !is_4_byte_aligned ) ) );

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			ldst1_rollback_en <= 1'b0;
		else
			ldst1_rollback_en <= ( is_misaligned | is_out_of_memory ) & instruction_valid;

	always_ff @ ( posedge clk ) begin
		ldst1_rollback_pc        <= `LDST_ADDR_MISALIGN_ISR;
		ldst1_rollback_thread_id <= opf_inst_scheduled.thread_id;
	end

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - Vector Operation Alignment
//  -----------------------------------------------------------------------
	genvar                                         lane_idx;
	generate
		for ( lane_idx = 0; lane_idx < `HW_LANE; lane_idx++ ) begin : vector_preparation
			assign byte_vector[lane_idx]     = opf_fecthed_op1[lane_idx][0 +: 8 ];
			assign halfword_vector[lane_idx] = opf_fecthed_op1[lane_idx][0 +: 16];
			assign word_vector[lane_idx]     = opf_fecthed_op1[lane_idx][0 +: 32];
		end
	endgenerate

	always_comb begin : byte_vector_aligner
		byte_aligned_vector_mask                                                         = {dcache_store_mask_t'( 1'b0 )};
		byte_aligned_vector_data                                                         = {( ( `DCACHE_WIDTH/$bits( byte_vector ) ) ){byte_vector}};
		byte_aligned_vector_mask[effective_address.offset +: ( $bits( byte_vector )/8 )] = {( $bits( byte_vector )/8 ){1'b1}};
	end

	always_comb begin : halfword_vector_aligner
		halfword_aligned_vector_mask                                                             = {dcache_store_mask_t'( 1'b0 )};
		halfword_aligned_vector_data                                                             = {( ( `DCACHE_WIDTH/$bits( halfword_vector ) ) ){halfword_vector}};
		halfword_aligned_vector_mask[effective_address.offset +: ( $bits( halfword_vector )/8 )] = {( $bits( halfword_vector )/8 ){1'b1}};
	end

	always_comb begin : word_vector_aligner
		word_aligned_vector_mask                                                         = {dcache_store_mask_t'( 1'b0 )};
		word_aligned_vector_data                                                         = {( ( `DCACHE_WIDTH/$bits( word_vector ) ) ){word_vector}};
		word_aligned_vector_mask[effective_address.offset +: ( $bits( word_vector )/8 )] = {( $bits( word_vector )/8 ){1'b1}};
	end

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - Scalar Operation Alignment
//  -----------------------------------------------------------------------
	always_comb begin : byte_scalar_aligner
		byte_aligned_scalar_mask                           = dcache_store_mask_t'( 1'b0 );
		byte_aligned_scalar_data                           = {( `DCACHE_WIDTH/8 ){opf_fecthed_op1[0][7 : 0]}}; // data replicated for all the line
		byte_aligned_scalar_mask[effective_address.offset] = 1'b1;
	end

	always_comb begin : half_word_scalar_aligner
		halfword_aligned_scalar_mask                                = dcache_store_mask_t'( 1'b0 );
		halfword_aligned_scalar_data                                = {( `DCACHE_WIDTH/16 ){opf_fecthed_op1[0][15 : 0]}}; // data replicated for all the line
		halfword_aligned_scalar_mask[effective_address.offset +: 2] = 2'b11;
	end

	always_comb begin : word_scalar_aligner
		word_aligned_scalar_mask                                = dcache_store_mask_t'( 1'b0 );
		word_aligned_scalar_data                                = {( `DCACHE_WIDTH/32 ){opf_fecthed_op1[0][31 : 0]}}; // data replicated for all the line
		word_aligned_scalar_mask[effective_address.offset +: 4] = 4'b1111;
	end

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - Thread Request Queues
//  -----------------------------------------------------------------------

	always_comb begin : FIFO_INPUT_SELECTOR

		fifo_input.instruction  = opf_inst_scheduled;
		fifo_input.address      = effective_address;
		fifo_input.hw_lane_mask = opf_hw_lane_mask;
`ifdef SIMULATION
		fifo_input.store_value = dcache_line_t'( 1'bX );
		fifo_input.store_mask  = dcache_store_mask_t'( 1'bX );
`else
		fifo_input.store_value = dcache_line_t'( 1'b0 );
		fifo_input.store_mask  = dcache_store_mask_t'( 1'b0 );
`endif

		if ( is_vectorial_op ) begin
			if ( is_byte_op ) begin
				fifo_input.store_value = byte_aligned_vector_data;
				fifo_input.store_mask  = byte_aligned_vector_mask;
			end else if ( is_halfword_op ) begin
				fifo_input.store_value = halfword_aligned_vector_data;
				fifo_input.store_mask  = halfword_aligned_vector_mask;
			end else if ( is_word_op ) begin
				fifo_input.store_value = word_aligned_vector_data;
				fifo_input.store_mask  = word_aligned_vector_mask;
			end
		end else begin
			if ( is_byte_op ) begin
				fifo_input.store_value = byte_aligned_scalar_data;
				fifo_input.store_mask  = byte_aligned_scalar_mask;
			end else if ( is_halfword_op ) begin
				fifo_input.store_value = halfword_aligned_scalar_data;
				fifo_input.store_mask  = halfword_aligned_scalar_mask;
			end else if ( is_word_op ) begin
				fifo_input.store_value = word_aligned_scalar_data;
				fifo_input.store_mask  = word_aligned_scalar_mask;
			end
		end

	end

	genvar                                         thread_idx;
	generate
		for ( thread_idx = 0; thread_idx < `THREAD_NUMB; thread_idx++ ) begin : LDST1_THREAD_FIFOS
			dcache_request_t fifo_output;
			logic            fifo_enqueue_en;
			logic            fifo_empty;

			assign fifo_enqueue_en                 = ( instruction_valid | is_flush ) &&
				opf_inst_scheduled.thread_id == thread_id_t'( thread_idx ) &&
				!ldst1_rollback_en;

			assign ldst1_valid[thread_idx]         = !fifo_empty;

			sync_fifo #(
				.WIDTH                ( FIFO_WIDTH                 ),
				.SIZE                 ( FIFO_SIZE                  ),
				.ALMOST_FULL_THRESHOLD( FIFO_ALMOST_FULL_THRESHOLD )
			)
			requests_fifo (
				.clk         ( clk                                   ),
				.reset       ( reset                                 ),
				.flush_en    ( 1'b0                                  ),
				.full        (                                       ),
				.almost_full ( ldst1_almost_full[thread_idx]         ),
				.enqueue_en  ( fifo_enqueue_en                       ),
				.value_i     ( fifo_input                            ),
				.empty       ( fifo_empty                            ),
				.almost_empty(                                       ),
				.dequeue_en  ( ldst2_dequeue_instruction[thread_idx] ),
				.value_o     ( fifo_output                           )
			);

			assign ldst1_instruction[thread_idx]   = fifo_output.instruction;
			assign ldst1_address[thread_idx]       = fifo_output.address;
			assign ldst1_store_value[thread_idx]   = fifo_output.store_value;
			assign ldst1_store_mask[thread_idx]    = fifo_output.store_mask;
			assign ldst1_hw_lane_mask [thread_idx] = fifo_output.hw_lane_mask;
			// check if there are no load/store pending in the queue
			assign s1_no_ls_pending [thread_idx]   = fifo_empty;
		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- Load Store Unit 1 - Instruction Recycle Buffers
//  -----------------------------------------------------------------------

	generate
		for ( thread_idx = 0; thread_idx < `THREAD_NUMB; thread_idx++ ) begin : instructions_recycle_buffer
			logic recycle_this_thread;
			assign recycle_this_thread = ( ldst3_miss && ldst3_instruction.thread_id == thread_id_t'( thread_idx ) ) |
			                             ( ldst3_io_valid && ldst3_io_operation == IO_READ && ldst3_io_thread == thread_id_t'( thread_idx ) );

			always_ff @( posedge clk, posedge reset ) begin
				if ( reset )
					ldst1_recycle_valid[thread_idx] <= 1'b0;
				else if ( recycle_this_thread )
					ldst1_recycle_valid[thread_idx] <= 1'b1;
				else if ( ldst2_recycled[thread_idx] )
					ldst1_recycle_valid[thread_idx] <= 1'b0;

				// It is not possible to assert recycle_this_thread and ldst2_recycled[thread_idx] at the same time.
				if ( ~reset )
					assert( !( ( recycle_this_thread == 1'b1 ) && ( ldst2_recycled[thread_idx] == 1'b1 ) ) );
			end

			always_ff @( posedge clk ) begin
				if ( recycle_this_thread ) begin
					ldst1_recycle_instruction[thread_idx]  <= ldst3_instruction;
					ldst1_recycle_address[thread_idx]      <= ldst3_address;
					ldst1_recycle_store_value[thread_idx]  <= ldst3_cache_line;
					ldst1_recycle_store_mask[thread_idx]   <= ldst3_store_mask;
					ldst1_recycle_hw_lane_mask[thread_idx] <= ldst3_hw_lane_mask;
				end
			end

		end
	endgenerate

	// Checks if there are no recycled load/store pending
	assign miss_no_ls_pending = ~ldst1_recycle_valid;

`ifdef SIMULATION

`ifdef DISPLAY_LDST
	generate
		for ( thread_idx = 0; thread_idx < `THREAD_NUMB; thread_idx++ ) begin : debug_log
			always_ff @( posedge clk ) begin
				print_ldst1_result(TILE_ID, ldst2_dequeue_instruction[thread_idx], ldst1_instruction[thread_idx], ldst1_address[thread_idx], ldst1_store_value[thread_idx], ldst1_store_mask[thread_idx]);
			end
		end
	endgenerate
`endif

	always_comb
		if ( ~reset )
			assert( ~ldst1_rollback_en )
			else
				$error( "[LDST]: Address is misaligned! Time: %t\tPC: %h\tAddress: %x", $time( ), opf_inst_scheduled.pc, effective_address );
`endif

endmodule
