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
`include "npu_system_defines.sv"
`include "npu_debug_log.sv"

module tb_npu #(
		parameter KERNEL_IMAGE = "",
		parameter THREAD_MASK  = 8'hFF,
		parameter CORE_MASK    = 32'h03 )
	( );

	logic                         clk                        = 1'b0;
	logic                         reset                      = 1'b1;

	int                           sim_start, sim_end;
	int                           sim_log_file;

//  -----------------------------------------------------------------------
//  -- TB parameters and signals
//  -----------------------------------------------------------------------

	localparam CLK_PERIOD_NS = `CLOCK_PERIOD_NS;
	localparam PC_DEFAULT    = 32'h0000_0400;
	localparam ADDRESS_WIDTH = 32;
	localparam DATA_WIDTH    = 512;
	localparam ITEM_w        = 32;
	localparam NoC_ROW       = `NoC_Y_WIDTH;
	localparam NoC_COL       = `NoC_X_WIDTH;

	// Memory signals
	logic                         mem2nup_request_available;
	logic                         mem2nup_response_valid;
	logic [ADDRESS_WIDTH - 1 : 0] mem2nup_response_address;
	logic [DATA_WIDTH - 1 : 0]    mem2nup_response_data;
	logic [ADDRESS_WIDTH - 1 : 0] nup2mem_request_address;
	logic [63 : 0]                nup2mem_request_dirty_mask;
	logic [DATA_WIDTH - 1 : 0]    nup2mem_request_data;
	logic                         nup2mem_request_read;
	logic                         nup2mem_request_write;
	logic                         nup_available;

	// Item interface signals
	logic [ITEM_w - 1 : 0]        item_data_i;         // Input: items from outside
	logic                         item_valid_i = 1'b0; // Input: valid signal associated with item_data_i port
	logic                         item_avail_o;        // Output: avail signal to input port item_data_i
	logic [ITEM_w - 1 : 0]        item_data_o;         // Output: items to outside
	logic                         item_valid_o;        // Output: valid signal associated with item_data_o port
	logic                         item_avail_i = 1'b1;

//  -----------------------------------------------------------------------
//  -- TB termination logic
//  -----------------------------------------------------------------------

	localparam ACTIVE_THREADS = $countones(THREAD_MASK);
	localparam COUNTER_WIDTH = $clog2(ACTIVE_THREADS+1);

	logic [COUNTER_WIDTH-1:0]     write_cnt;

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset )
			write_cnt <= {COUNTER_WIDTH{1'b0}};
		else if ( nup2mem_request_write && nup2mem_request_address == 32'hFFFFFFC0 )
			write_cnt <= write_cnt + 1;
	end

	logic console_enable  = 1'b0;
	logic console_drained = 1'b0;

//  -----------------------------------------------------------------------
//  -- TB Unit Under Test
//  -----------------------------------------------------------------------

`ifdef SINGLE_CORE
	npu_system # (
		.ADDRESS_WIDTH ( ADDRESS_WIDTH ),
		.DATA_WIDTH    ( DATA_WIDTH    ),
		.ITEM_w        ( ITEM_w        )
	)
	npu_system (
		.clk                       ( clk                        ),
		.reset                     ( reset                      ),
		.hi_thread_en              (                            ),
		.mem2nup_request_available ( mem2nup_request_available  ),
		.mem2nup_response_valid    ( mem2nup_response_valid     ),
		.mem2nup_response_address  ( mem2nup_response_address   ),
		.mem2nup_response_data     ( mem2nup_response_data      ),
		.nup2mem_request_address   ( nup2mem_request_address    ),
		.nup2mem_request_dirty_mask( nup2mem_request_dirty_mask ),
		.nup2mem_request_data      ( nup2mem_request_data       ),
		.nup2mem_request_read      ( nup2mem_request_read       ),
		.nup2mem_request_write     ( nup2mem_request_write      ),
		.nup_available             ( nup_available              ),
		.item_data_i               ( item_data_i                ),
		.item_valid_i              ( item_valid_i               ),
		.item_avail_o              ( item_avail_o               ),
		.item_data_o               ( item_data_o                ),
		.item_valid_o              ( item_valid_o               ),
		.item_avail_i              ( item_avail_i               )
	);
`else
	npu_noc #(
		.MEM_ADDR_w      ( ADDRESS_WIDTH ),
		.MEM_DATA_BLOCK_w( DATA_WIDTH    ),
		.ITEM_w          ( ITEM_w        )
	)
	u_npu_noc (
		.clk                 ( clk          ),
		.reset               ( reset        ),
		.enable              ( 1'b1         ),

		.item_data_i         ( item_data_i  ),
		.item_valid_i        ( item_valid_i ),
		.item_avail_o        ( item_avail_o ),
		.item_data_o         ( item_data_o  ),
		.item_valid_o        ( item_valid_o ),
		.item_avail_i        ( item_avail_i ),

		//interface MC
		.mc_address_o        ( nup2mem_request_address    ),
		.mc_dirty_mask_o     ( nup2mem_request_dirty_mask ),
		.mc_block_o          ( nup2mem_request_data       ),
		.mc_avail_o          ( nup_available              ),
		.mc_sender_o         (                            ),
		.mc_read_o           ( nup2mem_request_read       ),
		.mc_write_o          ( nup2mem_request_write      ),

		.mc_address_i        ( mem2nup_response_address   ),
		.mc_block_i          ( mem2nup_response_data      ),
		.mc_dst_i            ( 10'b0                      ),
		.mc_sender_i         ( 10'b0                      ),
		.mc_read_avail_i     ( mem2nup_request_available  ),
		.mc_write_avail_i    ( mem2nup_request_available  ),
		.mc_valid_i          ( mem2nup_response_valid     ),
		.mc_request_i        ( 1'b0                       ) 
	);
`endif

	memory_dummy # (
		.ADDRESS_WIDTH  ( ADDRESS_WIDTH         ),
		.DATA_WIDTH     ( DATA_WIDTH            ),
		.OFF_WIDTH      ( `ICACHE_OFFSET_LENGTH ),
		.FILENAME_INSTR ( KERNEL_IMAGE          )
	)
	u_memory_dummy (
		.clk                   ( clk                        ),
		.reset                 ( reset                      ),
		//From MC
		//To Memory NI
		.n2m_request_address   ( nup2mem_request_address    ),
		.n2m_request_data      ( nup2mem_request_data       ),
		.n2m_request_read      ( nup2mem_request_read       ),
		.n2m_request_write     ( nup2mem_request_write      ),
		.mc_avail_o            ( nup_available              ),
		//From Memory NI
		.m2n_request_available ( mem2nup_request_available  ),
		.m2n_response_valid    ( mem2nup_response_valid     ),
		.m2n_response_address  ( mem2nup_response_address   ),
		.m2n_response_data     ( mem2nup_response_data      ),
		.n2m_request_dirty_mask( nup2mem_request_dirty_mask )
	);

//  -----------------------------------------------------------------------
//  -- TB Tasks
//  -----------------------------------------------------------------------

	task ITEM_SEND;
		input [31 : 0] data_in;
		integer i;
		begin
			// Send Start Bit
			#( CLK_PERIOD_NS / 4 );
			item_valid_i = 1'b1;
			item_data_i  = data_in;

			do
				begin
					@(posedge clk);
				end
			while ( ~item_avail_o );

			#( CLK_PERIOD_NS / 4 );
			item_valid_i = 1'b0;
		end
	endtask // ITEM_SEND

	task set_core_pc;
		input [`TOT_Y_NODE_W-1:0] row;
		input [`TOT_X_NODE_W-1:0] col;
		input [7 : 0] thread_id;
		input [31 : 0] pc;

		automatic logic [31:0] item;

		$display( "[Time %t] [HOST INTERFACE] Booting Thread %2d of Core %1d - PC %08x ", $time( ), thread_id, ( row * NoC_COL + col ), pc );
`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [HOST INTERFACE] Booting Thread %2d of Core %1d - PC %08x ", $time( ), thread_id, ( row * NoC_COL + col ), pc );
`endif

		item = BOOT_COMMAND;
		ITEM_SEND(item);

		item[31:16] = row * NoC_COL + col;
		item[15:0]  = thread_id;
		ITEM_SEND(item);

		ITEM_SEND(pc);
	endtask

	task enable_core;
		input [`TOT_Y_NODE_W-1:0] row;
		input [`TOT_X_NODE_W-1:0] col;
		input [`THREAD_NUMB-1 : 0] thread_mask;

		automatic logic [31:0] item;

		$display( "[Time %t] [HOST INTERFACE] Enabling Core %1d - Thread mask: %02x", $time( ), ( row * NoC_COL + col ), thread_mask );
`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [HOST INTERFACE] Enabling Core %1d - Thread mask: %02x", $time( ), ( row * NoC_COL + col ), thread_mask );
`endif

		item = ENABLE_THREAD;
		ITEM_SEND(item);

		item[31:16] = row * NoC_COL + col;
		item[15:0]  = thread_mask;
		ITEM_SEND(item);
	endtask

	task logger_cmd;
		input [15 : 0] cmd;
		input [15 : 0] address;
		automatic host_message_type_t message_out = CORE_LOG;

		$display( "[Time %t] [HOST INTERFACE] Sending Log request %2d to Addr %4x ", $time( ), cmd, address );
`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [HOST INTERFACE] Sending Log request %2d to Addr %4x ", $time( ), cmd, address );
`endif
		ITEM_SEND( message_out );
		ITEM_SEND( {address, cmd} );
	endtask

	task npu_configuration;
`ifdef SINGLE_CORE
		$display( "[Time %t] [TESTBENCH] Thread Numb: %4d ", $time( ), `THREAD_NUMB );
		$display( "[Time %t] [TESTBENCH] DCache Sets: %4d ", $time( ), `USER_ICACHE_SET );
		$display( "[Time %t] [TESTBENCH] DCache Ways: %4d ", $time( ), `USER_ICACHE_WAY );
		$display( "[Time %t] [TESTBENCH] ICache Sets: %4d ", $time( ), `USER_DCACHE_SET );
		$display( "[Time %t] [TESTBENCH] ICache Ways: %4d ", $time( ), `USER_DCACHE_WAY );
		$display( "[Time %t] [TESTBENCH] Cache is WT: %4d ", $time( ), npu_system.npu_core.u_control_register.cpu_ctrl_reg.cache_wt );
	`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Thread Numb: %4d ", $time( ), `THREAD_NUMB );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] DCache Sets: %4d ", $time( ), `USER_ICACHE_SET );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] DCache Ways: %4d ", $time( ), `USER_ICACHE_WAY );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] ICache Sets: %4d ", $time( ), `USER_DCACHE_SET );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] ICache Ways: %4d ", $time( ), `USER_DCACHE_WAY );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Cache is WT: %4d ", $time( ), npu_system.npu_core.u_control_register.cpu_ctrl_reg.cache_wt );
	`endif
`else
		$display( "[Time %t] [TESTBENCH] Total Tiles: %4d ", $time( ), `TILE_COUNT );
		$display( "[Time %t] [TESTBENCH] Net X Width: %4d ", $time( ), `NoC_X_WIDTH );
		$display( "[Time %t] [TESTBENCH] Net Y Width: %4d ", $time( ), `NoC_Y_WIDTH );
		$display( "[Time %t] [TESTBENCH] Tile MC ID : %4d ", $time( ), `TILE_MEMORY_ID );
		$display( "[Time %t] [TESTBENCH] Tile H2C ID: %4d ", $time( ), `TILE_H2C_ID );
		$display( "[Time %t] [TESTBENCH] Total Cores: %4d ", $time( ), `TILE_NPU );
		$display( "[Time %t] [TESTBENCH] Thread Numb: %4d ", $time( ), `THREAD_NUMB );
		$display( "[Time %t] [TESTBENCH] DCache Sets: %4d ", $time( ), `USER_ICACHE_SET );
		$display( "[Time %t] [TESTBENCH] DCache Ways: %4d ", $time( ), `USER_ICACHE_WAY );
		$display( "[Time %t] [TESTBENCH] ICache Sets: %4d ", $time( ), `USER_DCACHE_SET );
		$display( "[Time %t] [TESTBENCH] ICache Ways: %4d ", $time( ), `USER_DCACHE_WAY );
	`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Total Tiles: %4d ", $time( ), `TILE_COUNT );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Net X Width: %4d ", $time( ), `NoC_X_WIDTH );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Net Y Width: %4d ", $time( ), `NoC_Y_WIDTH );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Tile MC ID : %4d ", $time( ), `TILE_MEMORY_ID );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Tile H2C ID: %4d ", $time( ), `TILE_H2C_ID );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Total Cores: %4d ", $time( ), `TILE_NPU );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] Thread Numb: %4d ", $time( ), `THREAD_NUMB );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] DCache Sets: %4d ", $time( ), `USER_ICACHE_SET );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] DCache Ways: %4d ", $time( ), `USER_ICACHE_WAY );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] ICache Sets: %4d ", $time( ), `USER_DCACHE_SET );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] ICache Ways: %4d ", $time( ), `USER_DCACHE_WAY );
	`endif
`endif
	endtask

	task npu_stats;
`ifdef SINGLE_CORE
		$display( "[Time %t] [TESTBENCH] [CORE 0] Output Memory: %h ", $time( ), npu_system.npu_core.u_control_register.argv_register );
		$display( "[Time %t] [TESTBENCH] [CORE 0] Output Blocks: %h ", $time( ), npu_system.npu_core.u_control_register.argc_register );
		$display( "[Time %t] [TESTBENCH] [CORE 0] Kernel Cycles: %d ", $time( ), npu_system.npu_core.u_control_register.kernel_cycles );
		$display( "[Time %t] [TESTBENCH] [CORE 0] DCache misses: %d ", $time( ), npu_system.npu_core.u_control_register.data_miss_counter );
		$display( "[Time %t] [TESTBENCH] [CORE 0] ICache misses: %d ", $time( ), npu_system.npu_core.u_control_register.instr_miss_counter );

	`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] Output Memory: %h ", $time( ), npu_system.npu_core.u_control_register.argv_register );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] Output Blocks: %h ", $time( ), npu_system.npu_core.u_control_register.argc_register );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] Kernel Cycles: %d ", $time( ), npu_system.npu_core.u_control_register.kernel_cycles );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] DCache misses: %d ", $time( ), npu_system.npu_core.u_control_register.data_miss_counter );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] ICache misses: %d ", $time( ), npu_system.npu_core.u_control_register.instr_miss_counter );
	`endif

		for ( int thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin
			$display( "[Time %t] [TESTBENCH] [CORE 0] Thread %2d active cycles: %d ", $time( ), thread_id, npu_system.npu_core.u_control_register.thread_work_cycles[thread_id] );
	`ifdef SIMULATION
			$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] Thread %2d active cycles: %d ", $time( ), thread_id, npu_system.npu_core.u_control_register.thread_work_cycles[thread_id] );
	`endif
		end

		for ( int thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin
			$display( "[Time %t] [TESTBENCH] [CORE 0] Thread %2d misses cycles: %d ", $time( ), thread_id, npu_system.npu_core.u_control_register.thread_blocked_cycle_count[thread_id] );
	`ifdef SIMULATION
			$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] Thread %2d misses cycles: %d ", $time( ), thread_id, npu_system.npu_core.u_control_register.thread_blocked_cycle_count[thread_id] );
	`endif
		end
`else
		$display( "[Time %t] [TESTBENCH] [CORE %1d] Output Memory: %h ", $time( ), 0, u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.u_npu_core.u_control_register.argv_register );
		$display( "[Time %t] [TESTBENCH] [CORE %1d] Output Blocks: %h ", $time( ), 0, u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.u_npu_core.u_control_register.argc_register );

	`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE %1d] Output Memory: %h ", $time( ), 0, u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.u_npu_core.u_control_register.argv_register );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE %1d] Output Blocks: %h ", $time( ), 0, u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.u_npu_core.u_control_register.argc_register );
	`endif

`endif
	endtask

	function int read_global_counter ( );
	`ifdef SINGLE_CORE
		automatic int data = npu_system.npu_core.u_control_register.global_counter;
	`else
		automatic int data = u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.u_npu_core.u_control_register.global_counter;
	`endif
		$display( "[Time %t] [TESTBENCH] [CORE 0] Global Counter: %x ", $time( ), data );
	`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] Global Counter: %x ", $time( ), data );
	`endif
		return data;
	endfunction : read_global_counter

//  -----------------------------------------------------------------------
//  -- TB Body
//  -----------------------------------------------------------------------

	always #( CLK_PERIOD_NS/2 ) clk = ~clk;

	initial begin

		npu_configuration( );

		#100
		reset     = 1'b0;
        
		// NaplesPU Cores
		for ( int row = 0; row < NoC_ROW; row++ ) begin
			for ( int col = 0; col < NoC_COL; col++ ) begin
				if ( ( ( row * NoC_COL + col ) < `TILE_NPU ) & CORE_MASK[row * NoC_COL + col] ) begin
					// Sets thread PCs
					for ( int i = 0; i < `THREAD_NUMB; i++ ) begin
						if ( THREAD_MASK[i] )
							set_core_pc( row, col, i, PC_DEFAULT );
					end
				end
			end
		end

		#100
		// NaplesPU Cores
		for ( int row = 0; row < NoC_ROW; row++ ) begin
			for ( int col = 0; col < NoC_COL; col++ ) begin
				if ( ( ( row * NoC_COL + col ) < `TILE_NPU ) & CORE_MASK[row * NoC_COL + col] ) begin
					enable_core( row, col, THREAD_MASK );
				end
			end
		end

		sim_start = read_global_counter( );

		ITEM_SEND( 32'h00000006 );
		ITEM_SEND( 32'h00000041 );
		#2000;
		ITEM_SEND( 32'h00000006 );
		ITEM_SEND( 32'h00000042 );
		ITEM_SEND( 32'h00000006 );
		ITEM_SEND( 32'h00000043 );
		ITEM_SEND( 32'h00000006 );
		ITEM_SEND( 32'h00000044 );
		ITEM_SEND( 32'h00000006 );
		ITEM_SEND( 32'h00000045 );
		ITEM_SEND( 32'h00000006 );
		ITEM_SEND( 32'h00000046 );
		ITEM_SEND( 32'h00000006 );
		ITEM_SEND( 32'h0000005A );

		console_enable = 1'd1;
		wait( write_cnt == ACTIVE_THREADS );
		sim_end   = read_global_counter( );

		console_enable = 1'd0;
		wait ( console_drained );
		#1000 $finish( );
	end

	initial begin
		wait ( console_enable );

		forever begin
			ITEM_SEND(32'd4);

			if (item_valid_o == 1'b1 & item_data_o == 32'd1) begin
				ITEM_SEND(32'd5);
				$display( "[Time %t] [TESTBENCH] [CONSOLE] Character received: %c (0x%02h)", $time( ), item_data_o[7:0], item_data_o[7:0] );
			end else if (~console_enable) begin
				console_drained = 1'b1;
				break;
			end
		end
	end

	final begin
		$display( "[Time %t] [TESTBENCH] [CORE 0] Total Simulation Time: %d ", $time( ), sim_end - sim_start );
`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE 0] Total Simulation Time: %d ", $time( ), sim_end - sim_start );
`endif
		npu_stats( );
	end

//  -----------------------------------------------------------------------
//  -- TB Simulation File log
//  -----------------------------------------------------------------------
`ifdef DISPLAY_SIMULATION_LOG
	initial sim_log_file = $fopen ( `DISPLAY_SIMULATION_LOG_FILE, "wb" ) ;

	final $fclose ( sim_log_file ) ;
`endif

`ifdef DISPLAY_CORE
	int core_file;

	initial core_file = $fopen ( `DISPLAY_CORE_FILE, "wb" ) ;

	final $fclose ( core_file ) ;
`endif

`ifdef DISPLAY_COHERENCE
	int coherence_file;

	initial coherence_file = $fopen ( `DISPLAY_COHERENCE_FILE, "wb" ) ;

	final $fclose ( coherence_file ) ;
`endif

`ifdef DISPLAY_SPM
	int spm_file;

	initial spm_file = $fopen ( `DISPLAY_SPM_FILE, "wb" ) ;

	final $fclose ( spm_file ) ;
`endif

`ifdef DISPLAY_LDST
	int ldst_file;

	initial ldst_file = $fopen ( `DISPLAY_LDST_FILE, "wb" ) ;

	final $fclose ( ldst_file ) ;
`endif

`ifdef DISPLAY_SYNC
	int barrier_file;
	initial barrier_file = $fopen( `DISPLAY_BARRIER_FILE, "w" );
	final $fclose( barrier_file );

	int sync_file;
	initial sync_file = $fopen( `DISPLAY_SYNC_FILE, "w" );
	final $fclose( sync_file );

`ifdef PERFORMANCE_SYNC
	int perf_sync_perf;
	initial perf_sync_perf = $fopen( `DISPLAY_SYNC_PERF_FILE, "w" );
	final $fclose( perf_sync_perf );
`endif
`endif

`ifdef DISPLAY_REQUESTS_MANAGER
	int requests_file;
	initial requests_file = $fopen( `DISPLAY_REQ_MANAGER_FILE, "w" );
	final $fclose( requests_file );
`endif

`ifdef DISPLAY_IO
	int io_file;
	initial io_file = $fopen( `DISPLAY_IO_FILE, "w" );
	final $fclose( io_file );
`endif

endmodule
