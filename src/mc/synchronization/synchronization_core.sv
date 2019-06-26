`timescale 1ns / 1ps
`include "npu_synchronization_defines.sv"

module synchronization_core # (
		parameter TILE_ID = 0 )
	(
		input                         clk,
		input                         reset,
		// NETWORK INTERFACE
		output logic                  account_available,
		//Account
		input  sync_account_message_t ni_account_mess,
		input  logic                  ni_account_mess_valid,
		output logic                  sc_account_consumed,
		//Release
		output sync_release_message_t sc_release_mess,
		output tile_mask_t            sc_release_dest_valid,
		output logic                  sc_release_valid,
		input  logic                  ni_available
	);

	// Release info to store in FIFO
	typedef struct packed {
		sync_release_message_t message;
		tile_mask_t destinations;
	} sync_release_info_t;

	// signals stage1
	sync_account_message_t ss1_account_mess;
	logic                  ss1_account_valid;

	// signals stage2
	sync_account_message_t ss2_account_pending;
	logic                  ss2_account_pending_valid;
	sync_account_message_t ss2_account_mess;
	logic                  ss2_account_valid;
	logic                  ss2_mem_valid;
	barrier_data_t         ss2_barrier_mem_read;

	// signals stage3
	sync_account_message_t ss3_account_pending;
	logic                  ss3_account_pending_valid;
	barrier_data_t         ss3_barrier_mem_write;
	logic                  ss3_release_barrier;
	sync_release_message_t ss3_release_mess;
	tile_mask_t            ss3_release_dest_valid;
	logic                  ss3_release_mess_valid;

//  -----------------------------------------------------------------------
//  -- Synchronization Core- FIFO Account/Release
//  -----------------------------------------------------------------------

	logic                  ni_account_mess_valid_fifo, empty_account, almost_full_account, ss1_account_consumed_fifo, account_consumed_fifo;
	sync_account_message_t ni_account_mess_fifo;

	sync_fifo #(
		.WIDTH                 ( $bits( sync_account_message_t ) ),
		.SIZE                  ( 8                               ),
		.ALMOST_FULL_THRESHOLD ( 7                               ),
		.ALMOST_EMPTY_THRESHOLD( 1                               )
	)
	account_sync_fifo (
		.almost_empty(                                                 ),
		.almost_full ( almost_full_account                             ),
		.clk         ( clk                                             ),
		.dequeue_en  ( account_consumed_fifo                           ), 
		.empty       ( empty_account                                   ),
		.enqueue_en  ( ni_account_mess_valid &( ~almost_full_account ) ),
		.flush_en    ( 1'b0                                            ), 
		.full        (                                                 ),
		.reset       ( reset                                           ),
		.value_i     ( ni_account_mess                                 ),
		.value_o     ( ni_account_mess_fifo                            )
	);
	assign ni_account_mess_valid_fifo = !empty_account;
	assign sc_account_consumed        = ( ~almost_full_account ) & ni_account_mess_valid;
	assign account_consumed_fifo      = ss1_account_consumed_fifo;
	assign account_available          = ~almost_full_account;

	logic               ni_release_info_valid_fifo, empty_release, almost_full_release,deq_rel;
	sync_release_info_t sc_release_info_fifo_in, sc_release_info_fifo_out;

	assign sc_release_info_fifo_in.message      = ss3_release_mess;
	assign sc_release_info_fifo_in.destinations = ss3_release_dest_valid;

	sync_fifo #(
		.WIDTH                 ( $bits( sync_release_info_t ) ),
		.SIZE                  ( 8                            ),
		.ALMOST_FULL_THRESHOLD ( 4                            ),
		.ALMOST_EMPTY_THRESHOLD( 1                            )
	)
	release_sync_fifo (
		.almost_empty(                          ),
		.almost_full ( almost_full_release      ),
		.clk         ( clk                      ),
		.dequeue_en  ( deq_rel                  ),
		.empty       ( empty_release            ),
		.enqueue_en  ( ss3_release_mess_valid   ),
		.flush_en    ( 1'b0                     ),
		.full        (                          ),
		.reset       ( reset                    ),
		.value_i     ( sc_release_info_fifo_in  ),
		.value_o     ( sc_release_info_fifo_out )
	);

	assign sc_release_valid      = !empty_release;
	assign sc_release_mess       = sc_release_info_fifo_out.message;
	assign sc_release_dest_valid = sc_release_info_fifo_out.destinations;

	assign deq_rel               = !empty_release & ni_available;

//  -----------------------------------------------------------------------
//  -- Synchronization Core - Stage1
//  -----------------------------------------------------------------------

	synchronization_core_stage1 # (
		.TILE_ID( TILE_ID )
	)
	Stage1(
		.clk                       ( clk                        ),
		.reset                     ( reset                      ),
		//Network Interface
		.ni_account_mess           ( ni_account_mess_fifo       ),
		.ni_account_mess_valid     ( ni_account_mess_valid_fifo ),
		.ss1_account_consumed      ( ss1_account_consumed_fifo  ),
		.ni_release_almost_full    ( almost_full_release        ),
		//Sync_Stage2
		.ss1_account_mess          ( ss1_account_mess           ),
		.ss1_account_valid         ( ss1_account_valid          ),
		.ss2_account_pending_valid ( ss2_account_pending_valid  ),
		.ss2_account_pending       ( ss2_account_pending        ),
		//Sync_Stage3
		.ss3_account_pending       ( ss3_account_pending        ),
		.ss3_account_pending_valid ( ss3_account_pending_valid  )
	);

//  -----------------------------------------------------------------------
//  -- Synchronization Core - Stage2
//  -----------------------------------------------------------------------

	synchronization_core_stage2 # (
		.TILE_ID( TILE_ID )
	)
	Stage2(
		.clk                       ( clk                    ),
		.reset                     ( reset                  ),
		//Sync_Stage1
		.ss1_account_mess          ( ss1_account_mess       ),
		.ss1_account_valid         ( ss1_account_valid      ),
		.ss2_account_pending       ( ss2_account_pending    ),
		.ss2_account_pending_valid ( ss2_account_pending_valid ),
		//Sync_Stage3
		.ss2_account_valid         ( ss2_account_valid      ),
		.ss2_account_mess          ( ss2_account_mess       ),
		.ss2_mem_valid             ( ss2_mem_valid          ),
		.ss2_barrier_mem_read      ( ss2_barrier_mem_read  ),

		.ss3_account_pending_valid ( ss3_account_pending_valid ),
		.ss3_account_pending       ( ss3_account_pending    ),
		.ss3_barrier_mem_write     ( ss3_barrier_mem_write ),
		.ss3_release_barrier       ( ss3_release_barrier    )
	);

//  -----------------------------------------------------------------------
//  -- Synchronization Core - Stage3
//  -----------------------------------------------------------------------

	synchronization_core_stage3 Stage3(
		.clk                       ( clk                       ),
		.reset                     ( reset                     ),
		//Sync_Stage1
		.ss3_account_pending       ( ss3_account_pending       ),
		.ss3_account_pending_valid ( ss3_account_pending_valid ),

		//Sync_Stage2
		.ss2_account_valid         ( ss2_account_valid         ),
		.ss2_account_mess          ( ss2_account_mess          ),
		.ss2_mem_valid             ( ss2_mem_valid             ),
		.ss2_barrier_mem_read      ( ss2_barrier_mem_read      ),
		.ss3_barrier_mem_write     ( ss3_barrier_mem_write     ),
		.ss3_release_barrier       ( ss3_release_barrier       ),

		.ss3_release_mess_valid    ( ss3_release_mess_valid    ),
		.ss3_release_mess          ( ss3_release_mess          ),
		.ss3_release_dest_valid    ( ss3_release_dest_valid    )
	);

`ifdef DISPLAY_SYNCH_CORE
	always_ff @ ( posedge clk )
		if ( ~reset ) begin
			if ( ni_account_mess_valid )
				$display( "[Time %t] [Synch C %1d] Account received. \tBarrier ID: %d", $time( ), TILE_ID, ni_account_mess.id_barrier );
			if ( ss3_release_mess_valid )
				$display( "[Time %t] [Synch C %1d] Release sent. \tBarrier ID: %d", $time( ), TILE_ID, ss3_release_mess.id_barrier );
		end
`endif

endmodule
