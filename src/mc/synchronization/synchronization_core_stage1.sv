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
`include "npu_synchronization_defines.sv"
`include "npu_debug_log.sv"

module synchronization_core_stage1 # (
		parameter TILE_ID = 0 )
	(
		input                 clk,
		input                 reset,
		// NETWORK INTERFACE

		//Account
		input  sync_account_message_t ni_account_mess,
		input  logic                  ni_account_mess_valid,
		output logic                  ss1_account_consumed,
		//Release
		input  logic                  ni_release_almost_full,

		//SYNC_STAGE2
		output sync_account_message_t ss1_account_mess,
		output logic                  ss1_account_valid,
		input  sync_account_message_t ss2_account_pending,
		input  logic                  ss2_account_pending_valid,

		//SYNC_STAGE3
		input  sync_account_message_t ss3_account_pending,
		input  logic                  ss3_account_pending_valid
	);

	barrier_t                                 output_id_barrier;
	logic                                     output_barrier_valid;
	logic                                     can_issue_account;
	logic                                     release_fifo_full;
	cnt_barrier_t                             output_cnt_max;
	logic         [$clog2( `TILE_COUNT )-1:0] output_id_tile_source;
	logic                                     update_consumed_account;

	assign can_issue_account = ni_account_mess_valid & !( ss2_account_pending_valid && ss2_account_pending.id_barrier == ni_account_mess.id_barrier ) & !( ss3_account_pending_valid && ss3_account_pending.id_barrier == ni_account_mess.id_barrier ) & !ni_release_almost_full;

	always_comb begin: arbiter
		output_id_barrier       = 0;
		update_consumed_account = 1'b0;
		output_barrier_valid    = 1'b0;
		output_cnt_max          = 0;
		output_id_tile_source   = 0;

		if ( can_issue_account ) begin
			output_barrier_valid    = 1'b1;
			output_id_barrier       = ni_account_mess.id_barrier;
			output_id_tile_source   = ni_account_mess.tile_id_source;
			output_cnt_max          = ni_account_mess.cnt_setup;

			update_consumed_account = 1'b1;
		end
	end

	always_ff @( posedge clk ) begin
		ss1_account_mess <= ni_account_mess;
	end

	always_ff @( posedge clk, posedge reset )
		if ( reset ) begin
			ss1_account_valid <= 1'b0;
		end else begin
			ss1_account_valid <= output_barrier_valid;
		end

	assign ss1_account_consumed = update_consumed_account;

`ifdef DISPLAY_SYNC
	always_ff @( posedge clk ) begin
		if( ni_account_mess_valid )begin
			$fdisplay ( `DISPLAY_SYNC_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_SYNC_VAR, "Sync_Core-Stage1 - [Tile - %.16d]  [Time %.16d]",TILE_ID, $time ( ) ) ;
//          if(ni_setup_mess_valid)
//              $fdisplay ( `DISPLAY_SYNC_VAR, "Setup Request - [Id %.16d]  [cnt %.16d]  [is_master %.16d]", ni_setup_mess.id_barrier, ni_setup_mess.cnt_setup, ni_setup_mess.is_master ) ;
			if( ni_account_mess_valid )
				$fdisplay ( `DISPLAY_SYNC_VAR, "Account Request - [Id %.16d]  [tile_src %.16d], [cnt %.16d]", ni_account_mess.id_barrier, ni_account_mess.tile_id_source, ni_account_mess.cnt_setup ) ;
//          if(can_issue_setup)
//              $fdisplay ( `DISPLAY_SYNC_VAR, "Setup Schedule - [Id %.16d]  [cnt %.16d]  [is_master: TODO]", output_id_barrier,output_cnt_max ) ;
			//else
			if( can_issue_account )
				$fdisplay ( `DISPLAY_SYNC_VAR, "Account Schedule - [Id %.16d]  [tile_src %.16d]", output_id_barrier, output_id_tile_source ) ;

			$fflush ( `DISPLAY_SYNC_VAR ) ;

		end
	end
`endif

endmodule
