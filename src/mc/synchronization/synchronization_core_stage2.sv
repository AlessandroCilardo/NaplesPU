`timescale 1ns / 1ps
`include "npu_synchronization_defines.sv"
`include "npu_debug_log.sv"

module synchronization_core_stage2 # (
		parameter TILE_ID = 0
	)
	(
		input                 clk,
		input                 reset,

		//SYNC_STAGE1
		input  sync_account_message_t ss1_account_mess,
		input  logic                  ss1_account_valid,

		output logic                  ss2_account_pending_valid,
		output sync_account_message_t ss2_account_pending,

		//SYNC_STAGE3
		output logic                  ss2_account_valid,
		output sync_account_message_t ss2_account_mess,
		output logic                  ss2_mem_valid,
		output barrier_data_t         ss2_barrier_mem_read,

		input  logic                  ss3_account_pending_valid,
		input  sync_account_message_t ss3_account_pending,
		input  barrier_data_t         ss3_barrier_mem_write,
		input  logic                  ss3_release_barrier
	);

	logic                                    ss2_barrier_valid_tmp;
	logic       [`BARRIER_NUMB_FOR_TILE-1:0] valid_mem;

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset )
			valid_mem                                                               <= 'd0;
		else if ( ss3_account_pending_valid )
			valid_mem[ss3_account_pending.id_barrier[$clog2( `BARRIER_NUMB_FOR_TILE )-1:0]] <= ~ss3_release_barrier;
	end

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			ss2_account_valid <= 0;
		end else begin
			ss2_account_mess  <= ss1_account_mess;
			ss2_account_valid <= ss1_account_valid;
			ss2_mem_valid     <= valid_mem[ss1_account_mess.id_barrier[$clog2( `BARRIER_NUMB_FOR_TILE )-1:0]];
		end
	end

	assign ss2_account_pending       = ss1_account_mess;
	assign ss2_account_pending_valid = ss1_account_valid;

	//BRAM
	memory_bank_1r1w #
	(
		.COL_WIDTH   ( $bits( barrier_data_t ) ),
		.NB_COL      ( 1                       ),
		.SIZE        ( `BARRIER_NUMB_FOR_TILE  ),
		.WRITE_FIRST ( "TRUE"                  )
	)
	tag_sram
	(
		.clock        ( clk                                                          ),
		.read_address ( ss1_account_mess.id_barrier[$clog2( `BARRIER_NUMB_FOR_TILE )-1:0] ),
		.read_data    ( ss2_barrier_mem_read                                        ),
		.read_enable  ( ss1_account_valid                                               ),
		.write_address( ss3_account_pending.id_barrier[$clog2( `BARRIER_NUMB_FOR_TILE )-1:0] ),
		.write_data   ( ss3_barrier_mem_write                                       ),
		.write_enable ( ss3_account_pending_valid                                            )
	);

`ifdef DISPLAY_SYNC
	always_ff @( posedge clk ) begin
		if( ss1_account_valid || ss3_account_pending_valid || ss2_account_valid )begin
			$fdisplay ( `DISPLAY_SYNC_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_SYNC_VAR, "Sync_Core-Stage2 - [Tile - %.16d ] [Time %.16d]",TILE_ID, $time ( ) ) ;
			if( ss1_account_valid ) begin
				$fdisplay ( `DISPLAY_SYNC_VAR, "=========" ) ;
				$fdisplay ( `DISPLAY_SYNC_VAR, "From Stage 1 Before Read" ) ;
				$fdisplay ( `DISPLAY_SYNC_VAR, "Account - [Id %.16d]  [Tile_src %.16d]", ss1_account_mess.id_barrier, ss1_account_mess.tile_id_source ) ;
			end
			if( ss3_account_pending_valid ) begin
				$fdisplay ( `DISPLAY_SYNC_VAR, "=========" ) ;
				$fdisplay ( `DISPLAY_SYNC_VAR, "From Stage 3" ) ;
				$fdisplay ( `DISPLAY_SYNC_VAR, "Account - [Id %.16d]  [Tile_src %.16d]", ss3_account_pending.id_barrier, ss3_account_pending.tile_id_source ) ;
				$fdisplay ( `DISPLAY_SYNC_VAR, "DataWrite - [cnt: %.16d] [mask_slave: %.16d]", ss3_barrier_mem_write.cnt,ss3_barrier_mem_write.mask_slave ) ;

			end
			if( ss2_account_valid ) begin
				$fdisplay ( `DISPLAY_SYNC_VAR, "=========" ) ;
				$fdisplay ( `DISPLAY_SYNC_VAR, "To Stage 3 After Read" ) ;
				$fdisplay ( `DISPLAY_SYNC_VAR, "Account - [Id %.16d]  [Tile_src %.16d]", ss2_account_mess.id_barrier, ss2_account_mess.tile_id_source ) ;
				if( ss2_mem_valid )
					$fdisplay ( `DISPLAY_SYNC_VAR, "DataRead - [cnt: %.16d] [mask_slave: %.16d]", ss2_barrier_mem_read.cnt,ss2_barrier_mem_read.mask_slave ) ;
				else
					$fdisplay ( `DISPLAY_SYNC_VAR, "DataRead - NOT VALID(first_read)" );

			end

			$fflush ( `DISPLAY_SYNC_VAR ) ;
		end

	end
`endif
endmodule
