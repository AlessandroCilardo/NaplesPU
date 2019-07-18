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
 * Decoder module decodes fetched instruction from instruction_fetch_stage and fills all
 * instruction_decoded_t fields. This module produces control signals used by all units in
 * the datapath. The output dec_instr helps execution and control module to manage the
 * issued instruction.
 * 
 */

module decode (
		input                                               clk,
		input                                               reset,
		input                                               enable,

		input                                               if_valid,
		input  thread_id_t                                  if_thread_selected_id,
		input  register_t                                   if_pc_scheduled,
		input  instruction_t                                if_inst_scheduled,

		input                        [`THREAD_NUMB - 1 : 0] rollback_valid,
		output logic                                        dec_valid,
		output instruction_decoded_t                        dec_instr
	);

	instruction_decoded_t  instruction_decoded_next;

	logic                  is_rollback;

	// Checks if a rollback is occurring for the scheduled thread.
	assign is_rollback = rollback_valid[if_thread_selected_id];

	RR_instruction_body_t  RR_instruction_body ;
	RI_instruction_body_t  RI_instruction_body ;
	MVI_instruction_body_t MVI_instruction_body;
	MEM_instruction_body_t MEM_instruction_body;
	JBA_instruction_body_t JBA_instruction_body;
	JRA_instruction_body_t JRA_instruction_body;
	CTR_instruction_body_t CTR_instruction_body;

	always_comb begin : DECODE_LOGIC
		RR_instruction_body                = if_inst_scheduled.body.RR_body;
		RI_instruction_body                = if_inst_scheduled.body.RI_body;
		MVI_instruction_body               = if_inst_scheduled.body.MVI_body;
		MEM_instruction_body               = if_inst_scheduled.body.MEM_body;
		JBA_instruction_body               = if_inst_scheduled.body.JBA_body;
		JRA_instruction_body               = if_inst_scheduled.body.JRA_body;
		CTR_instruction_body               = if_inst_scheduled.body.CTR_body;

		instruction_decoded_next           = instruction_decoded_t' ( 1'b0 ) ;
		instruction_decoded_next.pc        = if_pc_scheduled;
		instruction_decoded_next.thread_id = if_thread_selected_id;
		instruction_decoded_next.is_valid  = 1'b0;

		casez ( if_inst_scheduled.opcode )
			// RR
			8'b00_?????? : begin
				instruction_decoded_next.mask_enable              = |RR_instruction_body.register_selection;
				instruction_decoded_next.is_valid                 = 1'b1;
				instruction_decoded_next.op_code                  = alu_op_t' ( if_inst_scheduled.opcode[5 : 0] ) ;
				instruction_decoded_next.is_long					  = RR_instruction_body.long;
				
				instruction_decoded_next.source0                  = RR_instruction_body.source0;
				instruction_decoded_next.source1                  = RR_instruction_body.source1;
				instruction_decoded_next.destination              = RR_instruction_body.destination;

				// An RR instruction always has two sources and a destination register
				instruction_decoded_next.has_source0              = 1'b1;
				instruction_decoded_next.has_source1              = 1'b1;
				instruction_decoded_next.has_destination          = 1'b1;

				instruction_decoded_next.is_source0_vectorial     = RR_instruction_body.register_selection[1];
				instruction_decoded_next.is_source1_vectorial     = RR_instruction_body.register_selection[0];
				instruction_decoded_next.is_destination_vectorial = RR_instruction_body.register_selection[2];

				instruction_decoded_next.immediate                = 0;
				instruction_decoded_next.is_source1_immediate     = 1'b0;

				instruction_decoded_next.is_memory_access         = 1'b0;

				// Selects which pipe will handle this instruction, the choice is done based on the OPCODE
				if ( if_inst_scheduled.opcode.alu_opcode <= MOVE || ( if_inst_scheduled.opcode.alu_opcode >= SEXT8 & if_inst_scheduled.opcode.alu_opcode <= SEXT32 )
						|| if_inst_scheduled.opcode.alu_opcode == CRT_MASK ) begin
					instruction_decoded_next.pipe_sel             = PIPE_INT;
					instruction_decoded_next.is_int               = 1'b1;
					instruction_decoded_next.is_fp                = 1'b0;
				end else if ( if_inst_scheduled.opcode.alu_opcode == CRP_V_32 ) begin
					instruction_decoded_next.pipe_sel             = PIPE_CRP;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_fp                = 1'b0;
				end else begin
					instruction_decoded_next.pipe_sel             = PIPE_FP;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_fp                = 1'b1;
				end

				instruction_decoded_next.is_load                  = 1'b0;
				instruction_decoded_next.is_movei                 = 1'b0;
				if ( if_inst_scheduled.body.RR_body.destination == reg_addr_t'(`PC_REG) )
					instruction_decoded_next.is_branch            = 1'b1;
				else
					instruction_decoded_next.is_branch            = 1'b0;
				instruction_decoded_next.is_conditional           = 1'b0;
				instruction_decoded_next.is_control               = 1'b0;

			end

			// RI
			8'b010_????? : begin
				instruction_decoded_next.mask_enable              = |RI_instruction_body.register_selection;
				instruction_decoded_next.is_valid                 = 1'b1;
				instruction_decoded_next.op_code                  = alu_op_t' ( if_inst_scheduled.opcode[4 : 0] ) ;

				instruction_decoded_next.source0                  = RI_instruction_body.source0;
				instruction_decoded_next.source1                  = 0;
				instruction_decoded_next.destination              = RI_instruction_body.destination;

				instruction_decoded_next.has_source0              = 1'b1;
				instruction_decoded_next.has_source1              = 1'b0;
				instruction_decoded_next.has_destination          = 1'b1;

				instruction_decoded_next.is_destination_vectorial = RI_instruction_body.register_selection[1];
				instruction_decoded_next.is_source0_vectorial     = RI_instruction_body.register_selection[0];
				instruction_decoded_next.is_source1_vectorial     = 1'b0;

				instruction_decoded_next.immediate                = {{23{RI_instruction_body.immediate[8]}}, RI_instruction_body.immediate};
				instruction_decoded_next.is_source1_immediate     = 1'b1;

				instruction_decoded_next.pipe_sel                 = PIPE_INT;

				instruction_decoded_next.is_memory_access         = 1'b0;
				instruction_decoded_next.is_int                   = 1'b1;
				instruction_decoded_next.is_fp                    = 1'b0;
				instruction_decoded_next.is_load                  = 1'b0;
				instruction_decoded_next.is_movei                 = 1'b0;
				instruction_decoded_next.is_branch                = 1'b0;
				instruction_decoded_next.is_conditional           = 1'b0;
				instruction_decoded_next.is_control               = 1'b0;

			end

			//MVI
			8'b01100_??? : begin
				// If the destination register is vectorial, the instruction is masked
				instruction_decoded_next.mask_enable              = MVI_instruction_body.register_selection;
				instruction_decoded_next.is_valid                 = 1'b1;
				instruction_decoded_next.op_code                  = alu_op_t' ( if_inst_scheduled.opcode[2 : 0] ) ;

				instruction_decoded_next.source0                  = 0;
				instruction_decoded_next.source1                  = 0;
				instruction_decoded_next.destination              = MVI_instruction_body.destination;

				instruction_decoded_next.has_source0              = 1'b0;
				instruction_decoded_next.has_source1              = 1'b0;
				instruction_decoded_next.has_destination          = 1'b1;

				instruction_decoded_next.is_destination_vectorial = MVI_instruction_body.register_selection;
				instruction_decoded_next.is_source0_vectorial     = 1'b0;
				instruction_decoded_next.is_source1_vectorial     = 1'b0;

				instruction_decoded_next.immediate                = {{16{MVI_instruction_body.immediate[15]}}, MVI_instruction_body.immediate};
				instruction_decoded_next.is_source1_immediate     = 1'b1;

				instruction_decoded_next.pipe_sel                 = PIPE_INT;

				instruction_decoded_next.is_memory_access         = 1'b0;
				instruction_decoded_next.is_int                   = 1'b0;
				instruction_decoded_next.is_fp                    = 1'b0;
				instruction_decoded_next.is_load                  = 1'b0;
				instruction_decoded_next.is_movei                 = 1'b1;
				instruction_decoded_next.is_branch                = 1'b0;
				instruction_decoded_next.is_conditional           = 1'b0;
				instruction_decoded_next.is_control               = 1'b0;

			end

			//MEM
			8'b10_?????? : begin
				// The instruction is masked if the OPCODE is a vectorial operation
				instruction_decoded_next.mask_enable              = ( ( if_inst_scheduled.opcode[5 : 0] >= LOAD_V_8 & if_inst_scheduled.opcode[5 : 0] <= LOAD_V_32_U )
					| ( if_inst_scheduled.opcode[5 : 0] >= STORE_V_8 & if_inst_scheduled.opcode[5 : 0] <= STORE_V_64 ) );

				instruction_decoded_next.is_valid                 = 1'b1;
				instruction_decoded_next.op_code                  = memory_op_t' ( if_inst_scheduled.opcode[5 : 0] ) ;
				instruction_decoded_next.is_long					  = MEM_instruction_body.long;
				
				instruction_decoded_next.source0                  = MEM_instruction_body.base_register;
				instruction_decoded_next.source1                  = MEM_instruction_body.src_dest_register;
				instruction_decoded_next.destination              = MEM_instruction_body.src_dest_register;

				instruction_decoded_next.has_source0              = 1'b1;
				instruction_decoded_next.has_source1              = 1'b1;
				instruction_decoded_next.has_destination          = !if_inst_scheduled.opcode[5];

				instruction_decoded_next.is_source0_vectorial     = 1'b0;
				instruction_decoded_next.is_source1_vectorial     = ( ( if_inst_scheduled.opcode[5 : 0] >= LOAD_V_8 & if_inst_scheduled.opcode[5 : 0] <= LOAD_V_32_U )
					| ( if_inst_scheduled.opcode[5 : 0] >= STORE_V_8 & if_inst_scheduled.opcode[5 : 0] <= STORE_V_64 ) );

				instruction_decoded_next.is_destination_vectorial = ( ( if_inst_scheduled.opcode[5 : 0] >= LOAD_V_8 & if_inst_scheduled.opcode[5 : 0] <= LOAD_V_32_U )
					| ( if_inst_scheduled.opcode[5 : 0] >= STORE_V_8 & if_inst_scheduled.opcode[5 : 0] <= STORE_V_64 ) );

				instruction_decoded_next.immediate                = {{23{MEM_instruction_body.offset[8]}}, MEM_instruction_body.offset};

				// If a store occurs is_source1_immediate is not set, otherwise opf_fecthed_op1 holds the immediate value
				// and not the store value has should be.
				if ( MEM_instruction_body.shared ) begin
					instruction_decoded_next.pipe_sel             = PIPE_SPM;
					instruction_decoded_next.is_memory_access     = 1'b1;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_source1_immediate = 1'b0;
				end else begin
					instruction_decoded_next.pipe_sel             = PIPE_MEM;
					instruction_decoded_next.is_memory_access     = 1'b1;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_source1_immediate = 1'b0;
				end

				instruction_decoded_next.is_fp                    = 1'b0;
				instruction_decoded_next.is_load                  = !if_inst_scheduled.opcode[5];
				instruction_decoded_next.is_movei                 = 1'b0;
				instruction_decoded_next.is_branch                = 1'b0;
				instruction_decoded_next.is_conditional           = 1'b0;
				instruction_decoded_next.is_control               = 1'b0;

			end

			//JBA
			8'b01110_??? : begin
				instruction_decoded_next.mask_enable              = 1'b0;
				instruction_decoded_next.is_valid                 = 1'b1;
				instruction_decoded_next.op_code                  = `OP_CODE_WIDTH' ( if_inst_scheduled.opcode[2 : 0] ) ;

				// In case of conditional branches, source0 stores the conditional value to satisfies.
				// In case of unconditional branches, it contains the jump base address.
				instruction_decoded_next.source0                  = JBA_instruction_body.dest;

				instruction_decoded_next.has_source0              = 1'b1;
				instruction_decoded_next.has_source1              = 1'b1;


				if ( if_inst_scheduled.opcode[2 : 0] == JMPSR ) begin
					instruction_decoded_next.has_destination      = 1'b1;
					instruction_decoded_next.is_int               = 1'b1;
					instruction_decoded_next.is_source1_immediate = 1'b0;
					instruction_decoded_next.destination          = `RA_REG;
					instruction_decoded_next.source1              = `PC_REG;
				end else if ( if_inst_scheduled.opcode[2 : 0] == JRET ) begin
					instruction_decoded_next.has_destination      = 1'b0;
					instruction_decoded_next.has_source0          = 1'b1;
					instruction_decoded_next.has_source1          = 1'b0;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_source1_immediate = 1'b0;
					instruction_decoded_next.destination          = 0;
					instruction_decoded_next.source0              = `RA_REG;
				end else begin
					instruction_decoded_next.has_destination      = 1'b0;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_source1_immediate = 1'b1;
					instruction_decoded_next.destination          = 0;
					instruction_decoded_next.source1              = JBA_instruction_body.dest;

				end

				instruction_decoded_next.is_source0_vectorial     = 1'b0;
				instruction_decoded_next.is_source1_vectorial     = 1'b0;
				instruction_decoded_next.is_destination_vectorial = 1'b0;

				instruction_decoded_next.immediate                = {{14{JBA_instruction_body.immediate[17]}}, JBA_instruction_body.immediate};

				instruction_decoded_next.pipe_sel                 = PIPE_BRANCH;

				instruction_decoded_next.is_memory_access         = 1'b0;
				instruction_decoded_next.is_fp                    = 1'b0;
				instruction_decoded_next.is_load                  = 1'b0;
				instruction_decoded_next.is_movei                 = 1'b0;
				instruction_decoded_next.is_branch                = 1'b1;
				instruction_decoded_next.is_conditional           = if_inst_scheduled.opcode[2];
				instruction_decoded_next.is_control               = 1'b0;
				instruction_decoded_next.branch_type              = JBA;

			end

			//JRA
			8'b01111_??? : begin
				instruction_decoded_next.mask_enable              = 1'b0;
				instruction_decoded_next.is_valid                 = 1'b1;
				instruction_decoded_next.op_code                  = `OP_CODE_WIDTH' ( if_inst_scheduled.opcode[2 : 0] ) ;

				instruction_decoded_next.source1                  = 0;
				instruction_decoded_next.destination              = 0;

				if ( if_inst_scheduled.opcode[2 : 0] == JMPSR ) begin
					instruction_decoded_next.has_destination      = 1'b1;
					instruction_decoded_next.has_source0          = 1'b1;
					instruction_decoded_next.has_source1          = 1'b0;
					instruction_decoded_next.is_int               = 1'b1;
					instruction_decoded_next.is_source1_immediate = 1'b1;
					instruction_decoded_next.destination          = `RA_REG;
					instruction_decoded_next.source0              = `PC_REG;
				end else if ( if_inst_scheduled.opcode[2 : 0] == JRET ) begin
					instruction_decoded_next.has_destination      = 1'b0;
					instruction_decoded_next.has_source0          = 1'b1;
					instruction_decoded_next.has_source1          = 1'b0;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_source1_immediate = 1'b0;
					instruction_decoded_next.destination          = 0;
					instruction_decoded_next.source0              = `RA_REG;
				end else begin
					instruction_decoded_next.has_destination      = 1'b0;
					instruction_decoded_next.has_source0          = 1'b0;
					instruction_decoded_next.has_source1          = 1'b0;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.is_source1_immediate = 1'b1;
					instruction_decoded_next.destination          = 0;
					instruction_decoded_next.source0              = JBA_instruction_body.dest;

				end



				instruction_decoded_next.is_source0_vectorial     = 1'b0;
				instruction_decoded_next.is_source1_vectorial     = 1'b0;
				instruction_decoded_next.is_destination_vectorial = 1'b0;


				instruction_decoded_next.immediate                = {{14{JRA_instruction_body.immediate[17]}}, JRA_instruction_body.immediate[17 : 0]};
				instruction_decoded_next.is_source1_immediate     = 1'b1;

				instruction_decoded_next.pipe_sel                 = PIPE_BRANCH;

				instruction_decoded_next.is_memory_access         = 1'b0;
				instruction_decoded_next.is_movei                 = 1'b0;
				instruction_decoded_next.is_fp                    = 1'b0;
				instruction_decoded_next.is_load                  = 1'b0;
				instruction_decoded_next.is_branch                = 1'b1;
				instruction_decoded_next.is_conditional           = 1'b0;
				instruction_decoded_next.is_control               = 1'b0;
				instruction_decoded_next.branch_type              = JRA;

			end

			//Control
			8'b01101_??? : begin
				instruction_decoded_next.mask_enable              = 1'b0;
				instruction_decoded_next.is_valid                 = 1'b1;
				instruction_decoded_next.op_code                  = `OP_CODE_WIDTH' ( if_inst_scheduled.opcode[2 : 0] ) ;

				instruction_decoded_next.source0                  = CTR_instruction_body.source0;
				instruction_decoded_next.source1                  = CTR_instruction_body.source1;
				instruction_decoded_next.destination              = CTR_instruction_body.source0;

				instruction_decoded_next.has_source0              = 1'b1;

				instruction_decoded_next.is_source0_vectorial     = 1'b0;
				instruction_decoded_next.is_source1_vectorial     = 1'b0;
				instruction_decoded_next.is_destination_vectorial = 1'b0;

				instruction_decoded_next.immediate                = 0;
				instruction_decoded_next.is_source1_immediate     = 1'b0;
				instruction_decoded_next.is_memory_access         = 1'b0;

				if ( if_inst_scheduled.opcode.contr_opcode[2 : 0] == READ_CR | if_inst_scheduled.opcode.contr_opcode[2 : 0] == WRITE_CR ) begin
					instruction_decoded_next.pipe_sel             = PIPE_CR;
					instruction_decoded_next.is_int               = 1'b1;
					instruction_decoded_next.has_source1          = 1'b1;
					instruction_decoded_next.is_control           = 1'b0;
					instruction_decoded_next.has_destination      = if_inst_scheduled.opcode.contr_opcode[2 : 0] == READ_CR;
				end else if ( if_inst_scheduled.opcode.contr_opcode[2 : 0] == FLUSH || if_inst_scheduled.opcode.contr_opcode[2 : 0] == DCACHE_INV ) begin
					instruction_decoded_next.pipe_sel             = PIPE_MEM;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.has_source1          = 1'b0;
					instruction_decoded_next.is_control           = 1'b1;
					instruction_decoded_next.has_destination      = 1'b0;
				end else begin
					instruction_decoded_next.pipe_sel             = PIPE_SYNC;
					instruction_decoded_next.is_int               = 1'b0;
					instruction_decoded_next.has_source1          = 1'b1;
					instruction_decoded_next.is_control           = 1'b1;
					instruction_decoded_next.has_destination      = 1'b0;
				end

				instruction_decoded_next.is_fp                    = 1'b0;
				instruction_decoded_next.is_load                  = 1'b0;
				instruction_decoded_next.is_movei                 = 1'b0;
				instruction_decoded_next.is_branch                = 1'b0;
				instruction_decoded_next.is_branch                = 1'b0;
				instruction_decoded_next.is_conditional           = 1'b0;

			end


			default : begin

			end

		endcase
	end

	always_ff @ ( posedge clk, posedge reset ) begin : DEC_OUTPUT_VALID
		if ( reset ) begin
			dec_valid <= 1'b0;
		end else if ( enable ) begin
			dec_valid <= if_valid & ~is_rollback & instruction_decoded_next.is_valid;// & ~dsu_pipe_flush[if_thread_selected_id];
		end
	end

	always_ff @ ( posedge clk ) 
		dec_instr <= instruction_decoded_next;

endmodule
