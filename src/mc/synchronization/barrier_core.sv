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
`include "npu_message_service_defines.sv"
`include "npu_synchronization_defines.sv"
`include "npu_debug_log.sv"

/*
 * Three staged module:
 *  1 - Wait for sync ACCOUNT messages from the core, then waits for a RELEASE message form 
 *      the synchronization master
 *      1.a - each thread can inssue an ACCOUNT request if no memory operations are pendings
 *  2 - if multiple threads have a pending ACCOUNT request, a RR arbiter schedules one of 
 *      them at time
 *      2.a - when a thread ACCOUNT request is issued, this module sends to
 *      the synchronization master all the involved thread/core info through the NoC
 *  3 - When it receives a RELEASE message from the synchronization master,
 *      all stalled thread on that synch ID are released
 */

module barrier_core # (
		parameter TILE_ID        = 0,
        parameter THREAD_NUMB    = `THREAD_NUMB,
		parameter MANYCORE       = 0,
		parameter DIS_SYNCMASTER = 0 )
	(
		input                              clk,
		input                              reset,
		//Operand Fetch
		input                              opf_valid,
		input  instruction_decoded_t       opf_inst_scheduled,
		// To Core
		output logic [THREAD_NUMB - 1 : 0] bc_release_val,
		//Id_Barrier
		input  hw_lane_t                   opf_fetched_op0,
		//Destination Barrier
		input  hw_lane_t                   opf_fetched_op1,
		//Load Store Unit
		input  logic [THREAD_NUMB - 1 : 0] no_load_store_pending,
		input  logic [THREAD_NUMB - 1 : 0] scoreboard_empty,
		//to Network Interface
		output                             c2n_account_valid,
		output sync_account_message_t      c2n_account_message,
		output tile_mask_t                 c2n_account_destination_valid,

		input  logic                       network_available,
		//From Network Interface
		input  sync_release_message_t      n2c_release_message,
		input                              n2c_release_valid,
		output logic                       n2c_mes_service_consumed
	);

	//
	//Stage 1 Barrier Core
	//

    //localparam EFFECTIVE_TILE_COUNT = MANYCORE ? `TILE_COUNT : 2;
	localparam EFFECTIVE_TILE_COUNT = `TILE_COUNT;


	// Account Generate
	barrier_t                   barrier_release;
	thread_id_t                 account_scheduled_id;
	logic [THREAD_NUMB - 1 : 0] is_valid, mask_release, release_bit_attend;
	sync_account_message_t      c2n_account_message_tmp [THREAD_NUMB];
	logic [THREAD_NUMB - 1 : 0] can_account, valid_tmp, release_val_tmp;
	logic [THREAD_NUMB - 1 : 0] is_thread_account_mask;
	tile_address_t              destination [THREAD_NUMB];
	tile_mask_t                 one_hot_destination_valid [THREAD_NUMB];

	generate
		genvar thread_id;
		for ( thread_id = 0; thread_id < THREAD_NUMB; thread_id++ ) begin : barrier_entries

			assign is_valid[thread_id]     = opf_valid & opf_inst_scheduled.is_control & opf_inst_scheduled.thread_id==thread_id & opf_inst_scheduled.pipe_sel==PIPE_SYNC & opf_inst_scheduled.op_code==BARRIER_CORE;
			assign can_account[thread_id]  = valid_tmp[thread_id] & no_load_store_pending[thread_id] & ~scoreboard_empty[thread_id] & network_available;

			always_ff @( posedge clk, posedge reset )begin
				if ( reset ) begin
					valid_tmp[thread_id]               <= 1'b0;
					release_bit_attend[thread_id]      <= 0;
					bc_release_val[thread_id]          <= 1'b1;
					c2n_account_message_tmp[thread_id] <= 0;
				end
				else begin
					bc_release_val[thread_id]          <= release_val_tmp[thread_id];
					if ( is_valid[thread_id] ) begin

						if ( DIS_SYNCMASTER )
							destination[thread_id] <= opf_fetched_op0[0][$bits( barrier_t )-1:$clog2( `BARRIER_NUMB_FOR_TILE )];
						else
							if( MANYCORE )
								destination[thread_id] <= `CENTRAL_SYNCH_ID;
							else
								destination[thread_id] <= 0;

						c2n_account_message_tmp[thread_id].tile_id_source <= tile_address_t'( TILE_ID );
						c2n_account_message_tmp[thread_id].id_barrier     <= opf_fetched_op0[0][$bits( barrier_t )-1:0];
						c2n_account_message_tmp[thread_id].cnt_setup      <= opf_fetched_op1[0][$bits( cnt_barrier_t )-1:0];

						valid_tmp[thread_id]                              <= 1'b1;
						release_bit_attend[thread_id]                     <= 1'b1;

					end else if ( is_thread_account_mask[thread_id] )begin

						valid_tmp[thread_id]                              <= 0;
						c2n_account_message_tmp[thread_id]                <= c2n_account_message_tmp[thread_id];
						release_bit_attend[thread_id]                     <= 1'b1;

					end else if ( release_val_tmp[thread_id] ) begin

						c2n_account_message_tmp[thread_id]                <= c2n_account_message_tmp[thread_id];
						release_bit_attend[thread_id]                     <= 1'b0;

					end else begin

						c2n_account_message_tmp[thread_id]                <= c2n_account_message_tmp[thread_id];
						valid_tmp[thread_id]                              <= valid_tmp[thread_id];
						release_bit_attend[thread_id]                     <= release_bit_attend[thread_id];

					end

				end

			end

			assign mask_release[thread_id] = ( barrier_release == c2n_account_message_tmp[thread_id].id_barrier )
				& n2c_release_valid & release_bit_attend[thread_id];

			always_comb begin
				release_val_tmp[thread_id] = 1;

				if ( release_bit_attend[thread_id] && ~mask_release[thread_id] )
					release_val_tmp[thread_id] = 0;
			end

			if( MANYCORE )
				idx_to_oh #(
					.NUM_SIGNALS( $bits( tile_mask_t  )          ),
					.DIRECTION  ( "LSB0"                         ),
					.INDEX_WIDTH( $clog2( EFFECTIVE_TILE_COUNT ) )
				)
				u_idx_to_oh (
					.index  ( destination[thread_id]               ),
					.one_hot( one_hot_destination_valid[thread_id] )
				);
			else
				assign one_hot_destination_valid[thread_id] = tile_mask_t'( 0 );

		end

	endgenerate


	//Release Receive
	assign n2c_mes_service_consumed = n2c_release_valid;
	assign barrier_release          = (n2c_release_valid) ? n2c_release_message.id_barrier : 0;

	//
	// Stage 2 Barrier Core
	//
	//Schedule Account message between Thread. Round Robin Scheduler

	round_robin_arbiter #(
		.SIZE( THREAD_NUMB )
	)
	u_round_robin_arbiter (
		.clk         ( clk                    ),
		.reset       ( reset                  ),
		.en          ( |can_account           ),
		.requests    ( can_account            ),
		.decision_oh ( is_thread_account_mask )
	);

	oh_to_idx #(
		.NUM_SIGNALS( THREAD_NUMB         ),
		.DIRECTION  ( "LSB0"               ),
		.INDEX_WIDTH( $bits( thread_id_t ) )
	)
	oh_to_idx (
		.one_hot( is_thread_account_mask ),
		.index  ( account_scheduled_id   )
	);

	//
	// Stage 3 Barrier Core
	//
	//Send Account Message
	assign c2n_account_valid   = can_account[account_scheduled_id];
	assign c2n_account_message = c2n_account_message_tmp[account_scheduled_id];
	if ( MANYCORE )
		assign c2n_account_destination_valid = one_hot_destination_valid[account_scheduled_id];
	else
		assign c2n_account_destination_valid = tile_mask_t'( 0 );

`ifdef DISPLAY_SYNC

	always_ff @( posedge clk ) begin
		//  for ( int thread_idx = 0; thread_idx < THREAD_NUMB; thread_idx++ ) begin
		if( is_valid[0] )begin
			$fdisplay ( `DISPLAY_BARRIER_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier_Core [Tile_id %.16d ] - [Time %.16d]", TILE_ID,$time ( ) ) ;
			`ifdef DIRECTORY_BARRIER
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier Arrive [Thread: 0]  [id_barrier %.16d]  [dest %.16d]", opf_fetched_op0[0][$bits( barrier_t )-1:0] , opf_fetched_op0[0][$bits( barrier_t )-1:$clog2( `BARRIER_NUMB_FOR_TILE )] );
			`else
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier Arrive [Thread: 0]  [id_barrier %.16d]  [dest %.16d]", opf_fetched_op0[0][$bits( barrier_t )-1:0] , opf_fetched_op1[0][$clog2( EFFECTIVE_TILE_COUNT )-1:0] );
			`endif
			$fdisplay ( `DISPLAY_BARRIER_VAR, " [Can_Account: %.16d ]", can_account[0] );
			$fflush ( `DISPLAY_BARRIER_VAR );
		end
		if( is_valid[1] )begin
			$fdisplay ( `DISPLAY_BARRIER_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier_Core [Tile_id %.16d ] - [Time %.16d]", TILE_ID,$time ( ) ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier Arrive [Thread: 1]  [id_barrier %.16d]  [dest %.16d]", opf_fetched_op0[0][$bits( barrier_t )-1:0] , opf_fetched_op0[0][$bits( barrier_t )-1:$clog2( `BARRIER_NUMB_FOR_TILE )] );
			$fdisplay ( `DISPLAY_BARRIER_VAR, " [Can_Account: %.16d ]", can_account[1] );
			$fflush ( `DISPLAY_BARRIER_VAR );
		end
		if( is_valid[2] )begin
			$fdisplay ( `DISPLAY_BARRIER_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier_Core [Tile_id %.16d ] - [Time %.16d]", TILE_ID,$time ( ) ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier Arrive [Thread: 2]  [id_barrier %.16d]  [dest %.16d]", opf_fetched_op0[0][$bits( barrier_t )-1:0] , opf_fetched_op0[0][$bits( barrier_t )-1:$clog2( `BARRIER_NUMB_FOR_TILE )] );
			$fdisplay ( `DISPLAY_BARRIER_VAR, " [Can_Account: %.16d ]", can_account[2] );
			$fflush ( `DISPLAY_BARRIER_VAR );
		end
		if( is_valid[3] )begin
			$fdisplay ( `DISPLAY_BARRIER_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier_Core [Tile_id %.16d ] - [Time %.16d]", TILE_ID,$time ( ) ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier Arrive [Thread: 3]  [id_barrier %.16d]  [dest %.16d]", opf_fetched_op0[0][$bits( barrier_t )-1:0] , opf_fetched_op0[0][$bits( barrier_t )-1:$clog2( `BARRIER_NUMB_FOR_TILE )] );
			$fdisplay ( `DISPLAY_BARRIER_VAR, " [Can_Account: %.16d ]", can_account[3] );
			$fflush ( `DISPLAY_BARRIER_VAR );
		end
		if( can_account[account_scheduled_id] ) begin
			$fdisplay ( `DISPLAY_BARRIER_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier_Core [Tile_id %.16d ] - [Time %.16d]", TILE_ID,$time ( ) ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Account Send [Thread: %.16d ]  [id_barrier %.16d]  [dest %.16d]",account_scheduled_id, c2n_account_message.id_barrier ,destination[account_scheduled_id] );
			$fflush ( `DISPLAY_BARRIER_VAR );
		end
		if( n2c_release_valid ) begin
			$fdisplay ( `DISPLAY_BARRIER_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Barrier_Core [Tile_id %.16d ] - [Time %.16d]", TILE_ID,$time ( ) ) ;
			$fdisplay ( `DISPLAY_BARRIER_VAR, "Release Arrive [Thread: %.16d ]  [id_barrier %.16d]  ",account_scheduled_id, n2c_release_message.id_barrier );
			$fflush ( `DISPLAY_BARRIER_VAR );
		end


	end
`endif

`ifdef DISPLAY_BARRIER_CORE
	always_ff @ ( posedge clk )
		if ( ~reset ) begin
			if ( c2n_account_valid )
				$display( "[Time %t] [TILE %2d] [THREAD %2d] Barrier Core - Account sent, Barrier ID: %d", $time( ), TILE_ID, account_scheduled_id, c2n_account_message.id_barrier );
		end
`endif

endmodule
