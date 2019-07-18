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
 * Rollback Handler restores PCs and scoreboards of the threads which issued a rollback.
 * In case of jump or trap, the Brach module in the Execution pipeline issues a rollback
 * request to this stage, and passes to the Rollback Handler the thread ID that issued
 * the rollback, the old scoreboard and the PC to restore. Furthermore, the Rollback Handler
 * flushes all issued requests from the thread still in the pipeline.
 */

module rollback_handler(
		input                                       clk,
		input                                       reset,
		input                                       enable,

		input                                       is_instruction_valid,
		input  thread_id_t                          is_thread_id,
		input  scoreboard_t                         is_destination_mask,

		// From Branch Control
		input  scoreboard_t                         bc_scoreboard,
		input  logic                                bc_rollback_enable,
		input  logic                                bc_rollback_valid,
		input  address_t                            bc_rollback_pc,
		input  thread_id_t                          bc_rollback_thread_id,

		// From SPM
		input  logic                                spm_rollback_en,
		input  register_t                           spm_rollback_pc,
		input  thread_id_t                          spm_rollback_thread_id,

		// From LDST
		input  logic                                l1d_rollback_en,
		input  register_t                           l1d_rollback_pc,
		input  thread_id_t                          l1d_rollback_thread_id,

		// To Control Register
		output logic                                rollback_trap_en,
		output thread_id_t                          rollback_thread_id,
		output register_t                           rollback_trap_reason,
		output address_t     [`THREAD_NUMB - 1 : 0] rollback_pc_value,
		output thread_mask_t                        rollback_valid,
		output scoreboard_t  [`THREAD_NUMB - 1 : 0] rollback_clear_bitmap
	);

	scoreboard_t [`THREAD_NUMB - 1 : 0] clear_bitmap;

	genvar                              thread_id;
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin : ROLLBACK_GEN_HANDLER
			scoreboard_t scoreboard_clear_int;
			scoreboard_t scoreboard_set_issue;
			scoreboard_t scoreboard_temp;
			scoreboard_t scoreboard_set_issue_t0, scoreboard_set_issue_t1, scoreboard_set_issue_t2, scoreboard_set_issue_t3;
			
			// The rollback clear bitmap tracks issued instructions and cleans the thread scoreboard
			// in the Instruction Scheduler module when rollback or jumps occur.  
			assign scoreboard_clear_int             = ( bc_rollback_valid && bc_rollback_thread_id == thread_id ) ? bc_scoreboard : {$bits( scoreboard_t ){1'b1}};
			assign scoreboard_set_issue             = ( is_instruction_valid && is_thread_id == thread_id ) ? is_destination_mask : scoreboard_t'( 0 );
			assign scoreboard_temp                  = clear_bitmap[thread_id] & ~(scoreboard_set_issue_t3) & ~( scoreboard_clear_int & {`SCOREBOARD_LENGTH{bc_rollback_valid}} )
				| ( scoreboard_set_issue & {`SCOREBOARD_LENGTH{is_instruction_valid}} );
			assign rollback_clear_bitmap[thread_id] = scoreboard_temp;
			
			// An issued instruction is considered not flushable after 4 clock cycles.
			// A conditional branch is detected after 3 cycles from its issue, if the jump
			// is taken, all instructions issued during this period have to be flushed and the
			// scoreboard bits cleared.
			// Consequently, an instruction after 4 clock cycles ought not be affected by the
			// flush of the pipeline. 
			// This structure tracks issued instruction and after 4 clock cycles cleans the 
			// clear bitmap accordingly. 
			always_ff @ ( posedge clk, posedge reset ) begin : ROLLBACK_INSTRUCTION_TRACKER
				if ( reset ) begin
					scoreboard_set_issue_t0 <= scoreboard_t'( 1'b0 );
					scoreboard_set_issue_t1 <= scoreboard_t'( 1'b0 );
					scoreboard_set_issue_t2 <= scoreboard_t'( 1'b0 );
				end
				else if ( enable ) begin
					if ( rollback_valid[thread_id] ) begin
						scoreboard_set_issue_t0 <= scoreboard_t'( 1'b0 );
						scoreboard_set_issue_t1 <= scoreboard_t'( 1'b0 );
						scoreboard_set_issue_t2 <= scoreboard_t'( 1'b0 );
					end
					else begin
						scoreboard_set_issue_t0 <= scoreboard_set_issue;
						scoreboard_set_issue_t1 <= scoreboard_set_issue_t0;
						scoreboard_set_issue_t2 <= scoreboard_set_issue_t1;
						scoreboard_set_issue_t3 <= scoreboard_set_issue_t2;
					end
				end
			end

			always_comb begin : ROLLBACK_CHECKER
				if ( bc_rollback_thread_id == thread_id & bc_rollback_enable ) begin
					rollback_valid[thread_id]    = 1'b1;
					rollback_pc_value[thread_id] = bc_rollback_pc;
				end else if ( l1d_rollback_thread_id == thread_id & l1d_rollback_en ) begin
					rollback_valid[thread_id]    = 1'b1;
					rollback_pc_value[thread_id] = l1d_rollback_pc;
				end else if ( spm_rollback_thread_id == thread_id & spm_rollback_en ) begin
					rollback_valid[thread_id]    = 1'b1;
					rollback_pc_value[thread_id] = spm_rollback_pc;
				end else begin
					rollback_valid[thread_id]    = 1'b0;
					rollback_pc_value[thread_id] = 0;
				end
			end

			always_ff @ ( posedge clk, posedge reset )
				if ( reset )
					clear_bitmap[thread_id] <= scoreboard_t'( 1'b0 );
				else if ( enable ) begin
					if ( rollback_valid[thread_id] )
						clear_bitmap[thread_id] <= scoreboard_t'( 1'b0 );
					else
						clear_bitmap[thread_id] <= scoreboard_temp;
				end
		end
	endgenerate

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			rollback_trap_en <= 1'b0;
		else if ( enable )
			rollback_trap_en <= l1d_rollback_en | spm_rollback_en;

	always_ff @ ( posedge clk ) begin

		if ( l1d_rollback_en ) begin
			rollback_thread_id   <= l1d_rollback_thread_id;
			rollback_trap_reason <= `LDST_ADDR_MISALIGN;
		end else if ( spm_rollback_en ) begin
			rollback_thread_id   <= spm_rollback_thread_id;
			rollback_trap_reason <= `SPM_ADDR_MISALIGN;
		end else begin
			rollback_thread_id   <= thread_id_t'(0);
			rollback_trap_reason <= {`REGISTER_SIZE{1'b0}};
		end

	end

endmodule
