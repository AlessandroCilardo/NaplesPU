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
 * Writeback stage detects on-the-fly structural hazard on register file writeback operation and performs sign extension in load operations.
 * Some operators, such as Scratchpad Memory, have non predictable latency at issue time, hence the Writeback unit have to
 * check eventually structural hazard on register files. Furthermore, this module handles 8-bit/16-bit and 32-bit load sign extentions.
 */

module writeback #(
	parameter TILE_ID = 0 ) 
	(
		input                                               clk,
		input                                               reset,
		input                                               enable,

		// From FP Ex Pipe
		input                                               fp_valid,
		input  instruction_decoded_t                        fp_inst_scheduled,
		input  hw_lane_t                                    fp_result,
		input  hw_lane_mask_t                               fp_mask_reg,

		// From INT Ex Pipe
		input                                               int_valid,
		input  instruction_decoded_t                        int_inst_scheduled,
		input  hw_lane_t                                    int_result,
		input  hw_lane_mask_t                               int_hw_lane_mask,

		// From Scrathpad Memory Pipe
		input                                               spm_valid,
		input  instruction_decoded_t                        spm_inst_scheduled,
		input  hw_lane_t                                    spm_result,
		input  hw_lane_mask_t                               spm_hw_lane_mask,

		// From Cache L1 Pipe
		input                                               ldst_valid,
		input  instruction_decoded_t                        ldst_inst_scheduled,
		input  hw_lane_t                                    ldst_result,
		input  hw_lane_mask_t                               ldst_hw_lane_mask,
		input  dcache_address_t                             ldst_address,

		// To Operand Fetch
		output logic                                        wb_valid,
		output thread_id_t                                  wb_thread_id,
		output wb_result_t                                  wb_result,

		// TO Dynamic Scheduler
		output                       [`NUM_EX_PIPE - 1 : 0] wb_fifo_full
	);

//  -----------------------------------------------------------------------
//  -- Writeback Parameter and Signals
//  -----------------------------------------------------------------------
	typedef struct packed {
		register_t pc;
		logic writeback_valid;
		thread_id_t thread_id;

		hw_lane_t writeback_result;
		hw_lane_mask_t writeback_hw_lane_mask;
		dcache_address_t result_address;

		reg_addr_t destination;
		logic has_destination;
		logic is_destination_vectorial;


		opcode_t op_code;
		pipeline_disp_t pipe_sel;
		logic is_memory_access;
		logic is_branch;
		logic is_control;
		logic is_movei;
	} writeback_request_t;

    localparam  PIPE_FP_ID   = 0; // FP pipe FIFO index
    localparam  PIPE_INT_ID  = 1; // INT pipe FIFO index
    localparam  PIPE_SPM_ID  = 2; // SPM memory FIFO index
    localparam  PIPE_MEM_ID  = 3; // LDST unit FIFO index

	//localparam [4:0]WB_FIFO_SIZE = '{8, 8, 8, 8, 2*`THREAD_NUMB };
	//localparam [4:0]WB_FIFO_FT   = '{4, 4, 4, 4, `THREAD_NUMB};
    localparam WB_FIFO_SIZE = 2 * `THREAD_NUMB;
    localparam WB_FIFO_FT   = `THREAD_NUMB;


	logic               [`NUM_EX_PIPE - 1 : 0]               writeback_fifo_empty;                 // FIFO empty mask, one per FIFO. If the i-th is low the i-th FIFO has a pending request to be processed
	logic               [`NUM_EX_PIPE - 1 : 0]               writeback_fifo_full;                  // FIFO full mask, one per FIFO. If the i-th bit is high the i-th FIFO is full and the Dynamic Scheduler cannot issue further instructions
	logic               [`NUM_EX_PIPE - 1 : 0]               pending_requests;                     // Pending requests mask, one per FIFO
	logic               [`NUM_EX_PIPE - 1 : 0]               selected_request_oh;                  // One-hot mask, stores the FIFO which will be served
	logic               [$clog2( `NUM_EX_PIPE ) - 1 : 0]     selected_pipe;

	// FIFO structs
	writeback_request_t                                      input_wb_request [`NUM_EX_PIPE];
	writeback_request_t                                      output_wb_request [`NUM_EX_PIPE];

//  -----------------------------------------------------------------------
//  -- Writeback Request FIFOs
//  -----------------------------------------------------------------------
	assign input_wb_request[PIPE_FP_ID].pc                        = fp_inst_scheduled.pc;
	assign input_wb_request[PIPE_FP_ID].writeback_valid           = fp_valid;
	assign input_wb_request[PIPE_FP_ID].thread_id                 = fp_inst_scheduled.thread_id;
	assign input_wb_request[PIPE_FP_ID].writeback_result          = fp_result;
	assign input_wb_request[PIPE_FP_ID].writeback_hw_lane_mask    = fp_mask_reg;
	assign input_wb_request[PIPE_FP_ID].destination               = fp_inst_scheduled.destination;
	assign input_wb_request[PIPE_FP_ID].is_destination_vectorial  = fp_inst_scheduled.is_destination_vectorial;
	assign input_wb_request[PIPE_FP_ID].op_code                   = fp_inst_scheduled.op_code;
	assign input_wb_request[PIPE_FP_ID].pipe_sel                  = fp_inst_scheduled.pipe_sel;
	assign input_wb_request[PIPE_FP_ID].is_memory_access          = fp_inst_scheduled.is_memory_access;
	assign input_wb_request[PIPE_FP_ID].has_destination           = fp_inst_scheduled.has_destination;
	assign input_wb_request[PIPE_FP_ID].is_branch                 = fp_inst_scheduled.is_branch;
	assign input_wb_request[PIPE_FP_ID].is_control                = fp_inst_scheduled.is_control;
	assign input_wb_request[PIPE_FP_ID].is_movei                  = fp_inst_scheduled.is_movei;
	assign input_wb_request[PIPE_FP_ID].result_address            = 0;

	assign input_wb_request[PIPE_INT_ID].pc                       = int_inst_scheduled.pc;
	assign input_wb_request[PIPE_INT_ID].writeback_valid          = int_valid;
	assign input_wb_request[PIPE_INT_ID].thread_id                = int_inst_scheduled.thread_id;
	assign input_wb_request[PIPE_INT_ID].writeback_result         = int_result;
	assign input_wb_request[PIPE_INT_ID].writeback_hw_lane_mask   = int_hw_lane_mask;
	assign input_wb_request[PIPE_INT_ID].destination              = int_inst_scheduled.destination;
	assign input_wb_request[PIPE_INT_ID].is_destination_vectorial = int_inst_scheduled.is_destination_vectorial;
	assign input_wb_request[PIPE_INT_ID].op_code                  = int_inst_scheduled.op_code;
	assign input_wb_request[PIPE_INT_ID].pipe_sel                 = ( int_inst_scheduled.pipe_sel == PIPE_BRANCH & int_inst_scheduled.is_int ) ? PIPE_INT : int_inst_scheduled.pipe_sel;
	assign input_wb_request[PIPE_INT_ID].is_memory_access         = int_inst_scheduled.is_memory_access;
	assign input_wb_request[PIPE_INT_ID].has_destination          = int_inst_scheduled.has_destination;
	assign input_wb_request[PIPE_INT_ID].is_branch                = int_inst_scheduled.is_branch;
	assign input_wb_request[PIPE_INT_ID].is_control               = int_inst_scheduled.is_control;
	assign input_wb_request[PIPE_INT_ID].is_movei                 = int_inst_scheduled.is_movei;
	assign input_wb_request[PIPE_INT_ID].result_address           = 0;

	assign input_wb_request[PIPE_SPM_ID].pc                       = spm_inst_scheduled.pc;
	assign input_wb_request[PIPE_SPM_ID].writeback_valid          = spm_valid;
	assign input_wb_request[PIPE_SPM_ID].thread_id                = spm_inst_scheduled.thread_id;
	assign input_wb_request[PIPE_SPM_ID].writeback_result         = spm_result;
	assign input_wb_request[PIPE_SPM_ID].writeback_hw_lane_mask   = spm_hw_lane_mask;
	assign input_wb_request[PIPE_SPM_ID].destination              = spm_inst_scheduled.destination;
	assign input_wb_request[PIPE_SPM_ID].is_destination_vectorial = spm_inst_scheduled.is_destination_vectorial;
	assign input_wb_request[PIPE_SPM_ID].op_code                  = spm_inst_scheduled.op_code;
	assign input_wb_request[PIPE_SPM_ID].pipe_sel                 = spm_inst_scheduled.pipe_sel;
	assign input_wb_request[PIPE_SPM_ID].is_memory_access         = spm_inst_scheduled.is_memory_access;
	assign input_wb_request[PIPE_SPM_ID].has_destination          = spm_inst_scheduled.has_destination;
	assign input_wb_request[PIPE_SPM_ID].is_branch                = spm_inst_scheduled.is_branch;
	assign input_wb_request[PIPE_SPM_ID].is_control               = spm_inst_scheduled.is_control;
	assign input_wb_request[PIPE_SPM_ID].is_movei                 = spm_inst_scheduled.is_movei;
	assign input_wb_request[PIPE_SPM_ID].result_address           = 0;

	assign input_wb_request[PIPE_MEM_ID].pc                       = ldst_inst_scheduled.pc;
	assign input_wb_request[PIPE_MEM_ID].writeback_valid          = ldst_valid;
	assign input_wb_request[PIPE_MEM_ID].thread_id                = ldst_inst_scheduled.thread_id;
	assign input_wb_request[PIPE_MEM_ID].writeback_result         = ldst_result;
	assign input_wb_request[PIPE_MEM_ID].writeback_hw_lane_mask   = ldst_hw_lane_mask;
	assign input_wb_request[PIPE_MEM_ID].destination              = ldst_inst_scheduled.destination;
	assign input_wb_request[PIPE_MEM_ID].is_destination_vectorial = ldst_inst_scheduled.is_destination_vectorial;
	assign input_wb_request[PIPE_MEM_ID].op_code                  = ldst_inst_scheduled.op_code;
	assign input_wb_request[PIPE_MEM_ID].pipe_sel                 = ldst_inst_scheduled.pipe_sel;
	assign input_wb_request[PIPE_MEM_ID].is_memory_access         = ldst_inst_scheduled.is_memory_access;
	assign input_wb_request[PIPE_MEM_ID].has_destination          = ldst_inst_scheduled.has_destination;
	assign input_wb_request[PIPE_MEM_ID].is_branch                = ldst_inst_scheduled.is_branch;
	assign input_wb_request[PIPE_MEM_ID].is_control               = ldst_inst_scheduled.is_control;
	assign input_wb_request[PIPE_MEM_ID].is_movei                 = ldst_inst_scheduled.is_movei;
	assign input_wb_request[PIPE_MEM_ID].result_address           = ldst_address;

	genvar                                                   i;
	generate
		for ( i = 0; i < `NUM_EX_PIPE; i++ ) begin : WB_FIFOS
			sync_fifo #(
				.WIDTH                ( $bits( writeback_request_t ) ),
				.SIZE                 ( WB_FIFO_SIZE                 ),
				// 4 equals to the distance from the first stage of the operand fetch stage
				.ALMOST_FULL_THRESHOLD( WB_FIFO_SIZE - WB_FIFO_FT    )
			) writeback_request_fifo (
				.clk          ( clk                                 ),
				.reset        ( reset                               ),
				.flush_en     ( 1'b0                                ),
				.full         (                                     ),
				.almost_full  ( writeback_fifo_full[i]              ),
				.enqueue_en   ( input_wb_request[i].writeback_valid ),
				.value_i      ( input_wb_request[i]                 ),
				.empty        ( writeback_fifo_empty[i]             ),
				.almost_empty (                                     ),
				.dequeue_en   ( selected_request_oh[i]              ),
				.value_o      ( output_wb_request[i]                )
			);
		end
	endgenerate

	// This signal states to the Dynamic Scheduler which FIFO is full in a one-hot configuration.
	// When one of those bits is high, the Dynamic Scheduler stops the instruction issue.
	assign wb_fifo_full                                           = writeback_fifo_full;

//  -----------------------------------------------------------------------
//  -- Request Dispatcher and Result Composer
//  -----------------------------------------------------------------------
	hw_lane_t                                                byte_data_mem;
	hw_lane_t                                                half_data_mem;
	hw_lane_t                                                word_data_mem;
	hw_lane_t                                                byte_data_mem_s;
	hw_lane_t                                                half_data_mem_s;

	hw_lane_t                                                byte_data_spm;
	hw_lane_t                                                half_data_spm;
	hw_lane_t                                                word_data_spm;
	hw_lane_t                                                byte_data_spm_s;
	hw_lane_t                                                half_data_spm_s;

	hw_lane_t                                                result_data_mem;
	hw_lane_t                                                result_data_spm;
	wb_result_t                                              wb_next;
	thread_id_t                                              wb_thread_id_next;

	reg_byte_enable_t                                        reg_byte_en;
	logic                                                    write_on_reg;

	dcache_offset_t                                          dcache_offset;
	dcache_offset_t                                          spm_offset;

	assign pending_requests                                       = ~writeback_fifo_empty;

	round_robin_arbiter #(
		.SIZE( `NUM_EX_PIPE )
	) u_round_robin_arbiter (
		.clk         ( clk                 ),
		.reset       ( reset               ),
		.en          ( 1'b0                ),
		.requests    ( pending_requests    ),
		.decision_oh ( selected_request_oh )
	);

	oh_to_idx #(
		.NUM_SIGNALS( `NUM_EX_PIPE ),
		.DIRECTION  ( "LSB0"           )
	) oh_to_idx (
		.one_hot( selected_request_oh ),
		.index  ( selected_pipe       )
	);

	always_comb begin
		write_on_reg  = output_wb_request[selected_pipe].has_destination;
		dcache_offset = {2'd0, output_wb_request[PIPE_MEM_ID].result_address.offset[`DCACHE_OFFSET_LENGTH - 1 : 2]};
		spm_offset    = {2'd0, output_wb_request[PIPE_SPM_ID].result_address.offset[`DCACHE_OFFSET_LENGTH - 1 : 2]};
	end

	// The following logic performs sign extension in both SPM and LDST load operations
	genvar                                                   j;
	generate
		for ( j = 0; j < `HW_LANE; j++ ) begin : LANE_DATA_COMPOSER

			// LDST unit load operation sign extension
			assign word_data_mem[j] = output_wb_request[PIPE_MEM_ID].writeback_result[j][31 : 0];

			always_comb
				case ( output_wb_request[PIPE_MEM_ID].result_address.offset[1 : 0] )
					2'b00 : byte_data_mem[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_mem[j][7 : 0]};
					2'b01 : byte_data_mem[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_mem[j][15 : 8]};
					2'b10 : byte_data_mem[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_mem[j][23 : 16]};
					2'b11 : byte_data_mem[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_mem[j][31 : 24]};
				endcase

			always_comb
				case ( output_wb_request[PIPE_MEM_ID].result_address.offset[1] )
					1'b0 : half_data_mem[j] = {{( `REGISTER_SIZE - 16 ){1'b0}}, word_data_mem[j][15 : 0]};
					1'b1 : half_data_mem[j] = {{( `REGISTER_SIZE - 16 ){1'b0}}, word_data_mem[j][31 : 16]};
				endcase

			always_comb
				case ( output_wb_request[PIPE_MEM_ID].result_address.offset[1 : 0] )
					2'b00 : byte_data_mem_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_mem[j][7]} }, word_data_mem[j][7 : 0]};
					2'b01 : byte_data_mem_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_mem[j][15]} }, word_data_mem[j][15 : 8]};
					2'b10 : byte_data_mem_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_mem[j][23]} }, word_data_mem[j][23 : 16]};
					2'b11 : byte_data_mem_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_mem[j][31]} }, word_data_mem[j][31 : 24]};
				endcase

			always_comb
				case ( output_wb_request[PIPE_MEM_ID].result_address.offset[1] )
					1'b0 : half_data_mem_s[j] = {{( `REGISTER_SIZE - 16 ){word_data_mem[j][15]}}, word_data_mem[j][15 : 0]};
					1'b1 : half_data_mem_s[j] = {{( `REGISTER_SIZE - 16 ){word_data_mem[j][31]}}, word_data_mem[j][31 : 16]};
				endcase

			// SPM unit load operation sign extension
			assign word_data_spm[j] = output_wb_request[PIPE_SPM_ID].writeback_result[j][31 : 0];

			always_comb
				case ( output_wb_request[PIPE_SPM_ID].result_address.offset[1 : 0] )
					2'b00 : byte_data_spm[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_spm[j][7 : 0]};
					2'b01 : byte_data_spm[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_spm[j][15 : 8]};
					2'b10 : byte_data_spm[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_spm[j][23 : 16]};
					2'b11 : byte_data_spm[j] = {{( `REGISTER_SIZE - 8 ){1'b0}}, word_data_spm[j][31 : 24]};
				endcase

			always_comb
				case ( output_wb_request[PIPE_SPM_ID].result_address.offset[1] )
					1'b0 : half_data_spm[j] = {{( `REGISTER_SIZE - 16 ){1'b0}}, word_data_spm[j][15 : 0]};
					1'b1 : half_data_spm[j] = {{( `REGISTER_SIZE - 16 ){1'b0}}, word_data_spm[j][31 : 16]};
				endcase

			always_comb
				case ( output_wb_request[PIPE_SPM_ID].result_address.offset[1 : 0] )
					2'b00 : byte_data_spm_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_spm[j][7]} }, word_data_spm[j][7 : 0]};
					2'b01 : byte_data_spm_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_spm[j][15]} }, word_data_spm[j][15 : 8]};
					2'b10 : byte_data_spm_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_spm[j][23]} }, word_data_spm[j][23 : 16]};
					2'b11 : byte_data_spm_s[j] = {{( `REGISTER_SIZE - 8 ){word_data_spm[j][31]} }, word_data_spm[j][31 : 24]};
				endcase

			always_comb
				case ( output_wb_request[PIPE_SPM_ID].result_address.offset[1] )
					1'b0 : half_data_spm_s[j] = {{( `REGISTER_SIZE - 16 ){word_data_spm[j][15]}}, word_data_spm[j][15 : 0]};
					1'b1 : half_data_spm_s[j] = {{( `REGISTER_SIZE - 16 ){word_data_spm[j][31]}}, word_data_spm[j][31 : 16]};
				endcase
		end
	endgenerate

	always_comb begin : RESULT_COMPOSER_MEM
		case ( output_wb_request[PIPE_MEM_ID].op_code )

			// Scalar
			LOAD_8      : result_data_mem = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, byte_data_mem_s[dcache_offset] };
			LOAD_16     : result_data_mem = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, half_data_mem_s[dcache_offset] };
			LOAD_32,
			LOAD_64     : result_data_mem = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, word_data_mem[dcache_offset] };

			LOAD_8_U    : result_data_mem = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, byte_data_mem[dcache_offset] };
			LOAD_16_U   : result_data_mem = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, half_data_mem[dcache_offset] };
			LOAD_32_U   : result_data_mem = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, word_data_mem[dcache_offset] };

			// Vector
			LOAD_V_8    : result_data_mem = byte_data_mem_s;
			LOAD_V_16   : result_data_mem = half_data_mem_s;
			LOAD_V_32,
			LOAD_V_64   : result_data_mem = word_data_mem;

			LOAD_V_8_U  : result_data_mem = byte_data_mem;
			LOAD_V_16_U : result_data_mem = half_data_mem;
			LOAD_V_32_U : result_data_mem = word_data_mem;

			default : result_data_mem     = 0;
		endcase
	end

	always_comb begin : RESULT_COMPOSER_SPM
		case ( output_wb_request[PIPE_SPM_ID].op_code )

			// Scalar
			LOAD_8      : result_data_spm = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, byte_data_spm_s[spm_offset] };
			LOAD_16     : result_data_spm = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, half_data_spm_s[spm_offset] };
			LOAD_32,
			LOAD_64     : result_data_spm = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, word_data_spm[spm_offset] };

			LOAD_8_U    : result_data_spm = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, byte_data_spm[spm_offset] };
			LOAD_16_U   : result_data_spm = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, half_data_spm[spm_offset] };
			LOAD_32_U   : result_data_spm = { {( `REGISTER_SIZE * ( `HW_LANE - 1 ) ){1'b0}}, word_data_spm[spm_offset] };

			// Vector
			LOAD_V_8    : result_data_spm = byte_data_spm_s;
			LOAD_V_16   : result_data_spm = half_data_spm_s;
			LOAD_V_32,
			LOAD_V_64   : result_data_spm = word_data_spm;

			LOAD_V_8_U  : result_data_spm = byte_data_spm;
			LOAD_V_16_U : result_data_spm = half_data_spm;
			LOAD_V_32_U : result_data_spm = word_data_spm;

			default : result_data_spm     = 0;
		endcase
	end

	// Byte write enable generator for move operations
	always_comb begin : RESULT_COMPOSER_MOVE
		case ( output_wb_request[PIPE_INT_ID].op_code )
			// Move Immediate writes the whole register.
			MOVEI   : reg_byte_en = 4'b1111;
			MOVEI_L : reg_byte_en = 4'b0011;
			MOVEI_H : reg_byte_en = 4'b1100;
			default : reg_byte_en = 4'b0000;
		endcase
	end

	// Output data composer. The wb_result_data are directly forwarded to the register files
	always_comb begin : WB_OUTPUT_DATA_SELECTION
		case ( output_wb_request[selected_pipe].pipe_sel )
			PIPE_MEM : wb_next.wb_result_data = result_data_mem;
			PIPE_SPM : wb_next.wb_result_data = result_data_spm;
			PIPE_INT,
			PIPE_CR,
			PIPE_CRP,
			PIPE_FP  : wb_next.wb_result_data = output_wb_request[selected_pipe].writeback_result;
			default : wb_next.wb_result_data  = 0;
		endcase
	end

	// Output info composer
	always_comb begin : WB_OUTPUT_INFO_COMPOSER
		wb_thread_id_next              = output_wb_request[selected_pipe].thread_id;
		wb_next.wb_result_pc           = output_wb_request[selected_pipe].pc;
		wb_next.wb_result_register     = output_wb_request[selected_pipe].destination;
		wb_next.wb_result_is_scalar    = !output_wb_request[selected_pipe].is_destination_vectorial;
		wb_next.wb_result_hw_lane_mask = output_wb_request[selected_pipe].writeback_hw_lane_mask;

		if( output_wb_request[selected_pipe].is_movei )
			wb_next.wb_result_write_byte_enable = reg_byte_en;
		else
			wb_next.wb_result_write_byte_enable = {`BYTE_PER_REGISTER{1'b1}};
	end

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset )
			wb_valid <= 1'b0;
		else if ( enable ) begin
			// The output valid bit is asserted when at least one request was pending
			if ( selected_request_oh != 0 & write_on_reg )
				wb_valid <= output_wb_request[selected_pipe].writeback_valid;
			else
				wb_valid <= 1'b0;
		end
	end

	always_ff @ ( posedge clk ) begin
		if ( enable ) begin
			if ( selected_request_oh != 0 & write_on_reg ) begin
				wb_result    <= wb_next;
				wb_thread_id <= wb_thread_id_next;
			end
		end
	end

`ifdef DISPLAY_WB
	always_ff @ ( posedge clk )
		if ( wb_valid )
			print_wb_result( TILE_ID, wb_thread_id, wb_result );
`endif

endmodule
