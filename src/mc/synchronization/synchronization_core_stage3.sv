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
`include "npu_synchronization_defines.sv"

module synchronization_core_stage3 
	(
		input clk,
		input reset,

		// All previous stages
		output sync_account_message_t ss3_account_pending,
		output logic                  ss3_account_pending_valid,

		//SYNC_STAGE2
		input  logic                  ss2_account_valid,
		input  sync_account_message_t ss2_account_mess,
		input  logic                  ss2_mem_valid,
		input  barrier_data_t         ss2_barrier_mem_read,
		output barrier_data_t         ss3_barrier_mem_write,
		output logic                  ss3_release_barrier,

		//VIRTUAL NETWORK
		output sync_release_message_t ss3_release_mess,
		output tile_mask_t            ss3_release_dest_valid,
		output logic                  ss3_release_mess_valid
	);

	barrier_data_t output_data_barrier;
	logic          output_release_valid;
	logic          can_issue_account;

	assign can_issue_account = ss2_account_valid;

	assign ss3_account_pending       = ss2_account_mess;
	assign ss3_account_pending_valid = ss2_account_valid;
	assign ss3_barrier_mem_write     = output_data_barrier;
	assign ss3_release_barrier       = output_release_valid;

	always_comb begin
		output_data_barrier = 0;

		if ( can_issue_account ) begin
			if ( ss2_mem_valid )begin
				output_data_barrier.cnt        = ss2_barrier_mem_read.cnt - 1;
				output_data_barrier.mask_slave = ss2_barrier_mem_read.mask_slave;
			end else begin
				output_data_barrier.cnt        = ss2_account_mess.cnt_setup;
				output_data_barrier.mask_slave = 0;
			end

			output_data_barrier.mask_slave[ss2_account_mess.tile_id_source] = 1;
		end
	end

	always_comb begin
		if ( ss2_account_valid && output_data_barrier.cnt == 0 )
			output_release_valid <= 1'b1;
		else
			output_release_valid <= 1'b0;
	end

	always_ff @ (posedge clk, posedge reset)
		if (reset)
			ss3_release_mess_valid <= 1'b0;
		else
			ss3_release_mess_valid <= output_release_valid;

	always_ff @( posedge clk )begin
		ss3_release_mess       <= ss2_account_mess;
		ss3_release_dest_valid <= output_data_barrier.mask_slave;
	end

endmodule
