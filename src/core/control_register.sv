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
 * The Control Register unit holds status and performance information. Some status information are
 * shared among all threads (such as Core ID or the global performance counter), others are thread-
 * specific (such as Thread ID and Thread PC).
 *
 * The Control Register unit has a direct interface with the Host Interface, in this way the user
 * can access these information on the host-side.
 *
 */

module control_register #(
		parameter TILE_ID_PAR = 0,
		parameter CORE_ID_PAR = 4 )
	(
		input                                               clk,
		input                                               reset,
		input                                               enable,

		// From Host Controller
		input  logic                                        hi_read_cr_valid,
		input  logic                                        hi_write_cr_valid,
		input  register_t                                   hi_read_cr_request,
		input  register_t                                   hi_write_cr_data,

		// To Host Controller
		output register_t                                   cr_response,

		// From Instruction Fetch
		input  address_t             [`THREAD_NUMB - 1 : 0] if_current_pc,

		// From Barrier Core
		input  logic                 [`THREAD_NUMB - 1 : 0] bc_release_thread,

		// From Operand Fetch
		input  logic                                        opf_valid,
		input  instruction_decoded_t                        opf_inst_scheduled,
		input  hw_lane_t                                    opf_fetched_op0,
		input  hw_lane_t                                    opf_fetched_op1,
		// This is used for memory access coherency lookup
		input  register_t                                   effective_address,

		// To Operand Fetch
		output logic                                        uncoherent_area_hit,

		// From Thread Controller
		input  thread_mask_t                                tc_thread_en,
		input  logic                                        tc_inst_miss,

		// From LDST
		input  logic                                        ldst_miss,
		input  thread_mask_t                                ldst_almost_full,

		// From Rollback Handler
		input  logic                                        rollback_trap_en,
		input  thread_id_t                                  rollback_thread_id,
		input  register_t                                   rollback_trap_reason,

		// To Writeback
		output register_t                                   cr_result,

		// Configuration signals
		output logic                                        cr_ctrl_cache_wt

	);

	localparam COUNTER_WIDTH = 64;
	localparam DEBUG_REG_NUM = 16;

	typedef struct packed {
		logic cache_wt;
		logic interrupt_enable;
		logic supervisor;
		logic interrupt_pending;
		logic interrupt_trigger_mode;
		logic [26 : 0] unused;
	} ctrl_register_t;

//  -----------------------------------------------------------------------
//  -- Control Registers - Signals
//  -----------------------------------------------------------------------
	control_register_index_t                         command_core, command_from_host;
	thread_id_t                                      thread_from_host;
	logic                    [COUNTER_WIDTH - 1 : 0] global_counter;
	logic                                            is_cr_write, write_thread_status, write_argc, write_argv, write_mmap;
	logic                                            write_argc_host, write_argv_host, write_ctrl_reg;
	thread_status_t                                  thread_status_reg [`THREAD_NUMB];
	thread_status_t                                  thread_status [`THREAD_NUMB];
	core_trap_t                                      trap_reason [`THREAD_NUMB];
	register_t                                       data_miss_counter, instr_miss_counter;
	register_t                                       argc_register, argv_register;
	register_t                                       thread_blocked_cycle_count [`THREAD_NUMB];
	thread_mask_t                                    thread_under_work;
	register_t                                       thread_work_cycles[`THREAD_NUMB];
	register_t                                       kernel_cycles;
	ctrl_register_t                                  cpu_ctrl_reg;
	logic                    [31 : 0]                pwr_res;
	uncoherent_mmap                                  uncoherent_memory_areas[`UNCOHERENCE_MAP_SIZE];
	register_t               [DEBUG_REG_NUM - 1 : 0] debug_register;
	logic                    [DEBUG_REG_NUM - 1 : 0] debug_write_cpu, debug_write_host;

	assign pwr_res          = 0;

//  -----------------------------------------------------------------------
//  -- Control Registers - Read Requests from the Core
//  -----------------------------------------------------------------------
	assign command_core        = control_register_index_t'( opf_fetched_op1 );
	assign is_cr_write         = opf_inst_scheduled.pipe_sel == PIPE_CR & opf_inst_scheduled.op_code.contr_opcode == WRITE_CR & opf_valid;
	assign write_thread_status = opf_fetched_op1[0][$clog2( `CTR_NUMB ) - 1 : 0] == THREAD_STATUS_ID;
	assign write_argc          = opf_fetched_op1[0][$clog2( `CTR_NUMB ) - 1 : 0] == ARGC_ID;
	assign write_argv          = opf_fetched_op1[0][$clog2( `CTR_NUMB ) - 1 : 0] == ARGV_ID;
	assign write_mmap          = opf_fetched_op1[0][$clog2( `CTR_NUMB ) - 1 : 0] == UNCOHERENCE_MAP_ID;
	assign write_argc_host     = hi_write_cr_valid & hi_read_cr_request[15 : 0] == 16'(ARGC_ID);
	assign write_argv_host     = hi_write_cr_valid & hi_read_cr_request[15 : 0] == 16'(ARGV_ID);
	assign write_ctrl_reg      = hi_write_cr_valid & hi_read_cr_request[15 : 0] == 16'(CPU_CTRL_REG_ID);

	// Read requests from the core.
	always_comb begin : READ_DEMUX_TO_CORE
		case ( command_core )
			TILE_ID           : cr_result = TILE_ID_PAR;
			CORE_ID           : cr_result = CORE_ID_PAR;
			THREAD_ID         : cr_result = register_t'(opf_inst_scheduled.thread_id);
			GLOBAL_ID         : cr_result = {TILE_ID_PAR, CORE_ID_PAR, opf_inst_scheduled.thread_id};
			GCOUNTER_LOW_ID   : cr_result = global_counter[31 : 0];
			GCOUNTER_HIGH_ID  : cr_result = global_counter[63 : 32];
			THREAD_EN_ID      : cr_result = {{( `REGISTER_SIZE - `THREAD_NUMB ){1'b0}}, tc_thread_en};
			MISS_DATA_ID      : cr_result = data_miss_counter;
			MISS_INSTR_ID     : cr_result = instr_miss_counter;
			PC_ID             : cr_result = if_current_pc[opf_inst_scheduled.thread_id];
			TRAP_REASON_ID    : cr_result = trap_reason[opf_inst_scheduled.thread_id];
			THREAD_STATUS_ID  : cr_result = register_t'(thread_status[opf_inst_scheduled.thread_id]);
			ARGC_ID           : cr_result = argc_register;
			ARGV_ID           : cr_result = argv_register;
			THREAD_NUMB_ID    : cr_result = `THREAD_NUMB;
			THREAD_MISS_CC_ID : cr_result = thread_blocked_cycle_count[opf_inst_scheduled.thread_id];
			KERNEL_WORK       : cr_result = kernel_cycles;
			CPU_CTRL_REG_ID   : cr_result = cpu_ctrl_reg;
			PWR_MDL_REG_ID    : cr_result = pwr_res;
            UNCOHERENCE_MAP_ID: cr_result = 0;
			DEBUG_BASE_ADDR   : cr_result = debug_register[0];
			DEBUG_BASE_ADDR+1 : cr_result = debug_register[1];
			DEBUG_BASE_ADDR+2 : cr_result = debug_register[2];
			DEBUG_BASE_ADDR+3 : cr_result = debug_register[3];
			DEBUG_BASE_ADDR+4 : cr_result = debug_register[4];
			DEBUG_BASE_ADDR+5 : cr_result = debug_register[5];
			DEBUG_BASE_ADDR+6 : cr_result = debug_register[6];
			DEBUG_BASE_ADDR+7 : cr_result = debug_register[7];
			DEBUG_BASE_ADDR+8 : cr_result = debug_register[8];
			DEBUG_BASE_ADDR+9 : cr_result = debug_register[9];
			DEBUG_BASE_ADDR+10: cr_result = debug_register[10];
			DEBUG_BASE_ADDR+11: cr_result = debug_register[11];
			DEBUG_BASE_ADDR+12: cr_result = debug_register[12];
			DEBUG_BASE_ADDR+13: cr_result = debug_register[13];
			DEBUG_BASE_ADDR+14: cr_result = debug_register[14];
			DEBUG_BASE_ADDR+15: cr_result = debug_register[15];

			default :
`ifdef SIMULATION
				cr_result = {`REGISTER_SIZE{1'bx}};
`else
			cr_result     = {`REGISTER_SIZE{1'b0}};
`endif

		endcase
	end

//  -----------------------------------------------------------------------
//  -- Debug Registers
//  -----------------------------------------------------------------------
	genvar reg_id;
	generate
		for (reg_id = 0; reg_id < DEBUG_REG_NUM; reg_id++) begin : DEBUG_REG_GEN
			assign debug_write_cpu[reg_id] = opf_fetched_op1[0][$clog2( `CTR_NUMB ) - 1 : 0] == (DEBUG_BASE_ADDR+reg_id);
			assign debug_write_host[reg_id] = hi_write_cr_valid & hi_read_cr_request[15 : 0] == (DEBUG_BASE_ADDR+reg_id);

			always_ff @ (posedge clk, posedge reset) begin
				if ( reset )
					debug_register[reg_id] <= 0;
				else begin
					if (debug_write_host[reg_id])
						debug_register[reg_id] <= hi_write_cr_data;
                    else if (is_cr_write & debug_write_cpu[reg_id]) begin
						debug_register[reg_id] <= opf_fetched_op0[0];
`ifdef DISPLAY_DEBUG_REG
                        $display("[Time %t][CORE %2d] Debug Reg %2d: %h", $time(), TILE_ID_PAR, opf_fetched_op1[0][$clog2( `CTR_NUMB ) - 1 : 0], opf_fetched_op0[0]);
`endif
                    end
				end
			end
		end
	endgenerate

//  -----------------------------------------------------------------------
//  -- CPU Control/Configuration Register
//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			cpu_ctrl_reg.cache_wt               <= 1'b0;
			cpu_ctrl_reg.interrupt_enable       <= 1'b0;
			cpu_ctrl_reg.supervisor             <= 1'b0;
			cpu_ctrl_reg.interrupt_pending      <= 1'b0;
			cpu_ctrl_reg.interrupt_trigger_mode <= 1'b0;
			cpu_ctrl_reg.unused                 <= 0;
		end
		else
			if ( hi_write_cr_valid )
				cpu_ctrl_reg <= hi_write_cr_data;
	end

	assign cr_ctrl_cache_wt    = cpu_ctrl_reg.cache_wt;

//  -----------------------------------------------------------------------
//  -- Control Registers - Registers
//  -----------------------------------------------------------------------
	// Global Counter counts clock cycles since the last reset
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			kernel_cycles <= 0;
		else
			if ( |thread_under_work )
				kernel_cycles <= kernel_cycles + 1;

	// Global Counter counts clock cycles since the last reset
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			global_counter <= {COUNTER_WIDTH{1'b0}};
		else
			if ( enable )
				global_counter <= global_counter + {{( COUNTER_WIDTH - 1 ){1'b0}}, 1'b1};

	// Cache L1 Data misses counter
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			data_miss_counter <= {`REGISTER_SIZE{1'b0}};
		else
			if ( ldst_miss )
				data_miss_counter <= data_miss_counter + {{( `REGISTER_SIZE - 1 ){1'b0}}, 1'b1};

	// Cache L1 Instruction misses counter
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			instr_miss_counter <= {`REGISTER_SIZE{1'b0}};
		else
			if ( tc_inst_miss )
				instr_miss_counter <= instr_miss_counter + {{( `REGISTER_SIZE - 1 ){1'b0}}, 1'b1};

	// Trap reason and Thread status registers, one per thread
	genvar                                           thread_id;
	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id = thread_id + 1 ) begin
			always_ff @ ( posedge clk, posedge reset )
				if ( reset )
					thread_under_work[thread_id] <= 1'b0;
				else
					if ( thread_status[thread_id] == RUNNING | thread_status[thread_id] == WAITING_BARRIER )
						thread_under_work[thread_id] <= 1'b1;
					else
						thread_under_work[thread_id] <= 1'b0;

			always_ff @ ( posedge clk, posedge reset )
				if ( reset )
					thread_work_cycles[thread_id] <= 0;
				else
					if ( thread_under_work[thread_id] )
						thread_work_cycles[thread_id] <= thread_work_cycles[thread_id] + 1;

			always_ff @ ( posedge clk, posedge reset )
				if ( reset )
					trap_reason[thread_id] <= core_trap_t'( {`REGISTER_SIZE{1'b0}} );
				else
					if ( rollback_trap_en & thread_id == rollback_thread_id )
						trap_reason[thread_id] <= core_trap_t'( rollback_trap_reason );

			always_ff @ ( posedge clk, posedge reset )
				if ( reset )
					thread_status_reg[thread_id] <= THREAD_IDLE;
				else
					if ( is_cr_write & thread_id == opf_inst_scheduled.thread_id & write_thread_status )
						thread_status_reg[thread_id] <= thread_status_t'( opf_fetched_op0[0][`THREAD_STATUS_BIT - 1 : 0] );

			always_ff @ ( posedge clk, posedge reset )
				if ( reset )
					thread_blocked_cycle_count[thread_id] <= register_t'( 0 );
				else
					if ( ldst_almost_full[thread_id] )
						thread_blocked_cycle_count[thread_id] <= thread_blocked_cycle_count[thread_id] + 1;

			assign thread_status[thread_id] = ( ~bc_release_thread[thread_id] ) ? WAITING_BARRIER : thread_status_reg[thread_id];

		end
	endgenerate

	// Argument passing registers. These registers are used to pass arguments to a main function. Either
	// the host and the boot flow can fill them.
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			argc_register <= 0;
		else
			if ( write_argc_host )
				argc_register <= hi_write_cr_data;
			else
				if ( is_cr_write & write_argc )
					argc_register <= opf_fetched_op0[0];

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			argv_register <= 0;
		else
			if ( write_argv_host )
				argv_register <= hi_write_cr_data;
			else
				if ( is_cr_write & write_argv )
					argv_register <= opf_fetched_op0[0];

	// Uncoherent memory regions
	// Format of the control register write:
	//  3         2         1
	// 10987654321098765432109876543210
	//         [I][START---][END-----]V
	//         [N]
	//         [D]
	//         [E]
	//         [X]

	logic [`UNCOHERENCE_MAP_SIZE-1 : 0] uncoherent_area_hits;

	logic [`UNCOHERENCE_MAP_BITS-1 : 0] address_lookup;

	assign address_lookup = effective_address[`ADDRESS_SIZE-1 -: `UNCOHERENCE_MAP_BITS];

	genvar region_id;
	generate
		for (region_id = 0; region_id < `UNCOHERENCE_MAP_SIZE; region_id++) begin : UNCOHERENT_AREA_LOOKUP
			always_ff @ ( posedge clk, posedge reset )
				if ( reset ) begin
					uncoherent_memory_areas[region_id].valid <= 1'b0;
				end else begin
					if ( is_cr_write & write_mmap & opf_fetched_op0[0][$bits(uncoherent_mmap) +: $clog2(`UNCOHERENCE_MAP_SIZE)] == region_id ) begin
						uncoherent_memory_areas[region_id] <= opf_fetched_op0[0][$bits(uncoherent_mmap)-1 : 0];
					end
				end

			assign uncoherent_area_hits[region_id] = address_lookup >= uncoherent_memory_areas[region_id].start_addr && address_lookup <= uncoherent_memory_areas[region_id].end_addr && uncoherent_memory_areas[region_id].valid;
		end
	endgenerate

	assign uncoherent_area_hit = |uncoherent_area_hits;

//  -----------------------------------------------------------------------
//  -- Control Registers - Read Requests from the Host
//  -----------------------------------------------------------------------
	// Read requests from the host controller. These are fulfilled through a separate bus.
	assign command_from_host   = control_register_index_t'( hi_read_cr_request[15 : 0] );
	assign thread_from_host    = thread_id_t'(hi_read_cr_request[31 : 16]);

	always_ff @(posedge clk) begin : READ_DEMUX_TO_HOST
		if (reset) begin
`ifdef SIMULATION
		cr_response = {`REGISTER_SIZE{1'bx}};
`else
		cr_response = 32'hAABBCCDD;
`endif
		end else begin
			if ( hi_read_cr_valid ) begin
				case ( command_from_host )
					TILE_ID           : cr_response = TILE_ID_PAR;
					CORE_ID           : cr_response = CORE_ID_PAR;
					THREAD_ID         : cr_response = thread_from_host;
					GLOBAL_ID         : cr_response = {TILE_ID_PAR, CORE_ID_PAR, opf_inst_scheduled.thread_id};
					GCOUNTER_LOW_ID   : cr_response = global_counter[31 : 0];
					GCOUNTER_HIGH_ID  : cr_response = global_counter[63 : 32];
					THREAD_EN_ID      : cr_response = {{( `REGISTER_SIZE - `THREAD_NUMB ){1'b0}}, tc_thread_en};
					MISS_DATA_ID      : cr_response = data_miss_counter;
					MISS_INSTR_ID     : cr_response = instr_miss_counter;
					PC_ID             : cr_response = if_current_pc[thread_from_host];
					TRAP_REASON_ID    : cr_response = register_t'(trap_reason[thread_from_host]);
					THREAD_STATUS_ID  : cr_response = register_t'(thread_status[thread_from_host]);
					ARGC_ID           : cr_response = argc_register;
					ARGV_ID           : cr_response = argv_register;
					THREAD_NUMB_ID    : cr_response = `THREAD_NUMB;
					THREAD_MISS_CC_ID : cr_response = register_t'(thread_blocked_cycle_count[thread_from_host]);
					KERNEL_WORK       : cr_response = kernel_cycles;
					CPU_CTRL_REG_ID   : cr_response = cpu_ctrl_reg;
					PWR_MDL_REG_ID    : cr_response = pwr_res;
                    UNCOHERENCE_MAP_ID: cr_response = 0;
					DEBUG_BASE_ADDR   : cr_response = debug_register[0];
					DEBUG_BASE_ADDR+1 : cr_response = debug_register[1];
					DEBUG_BASE_ADDR+2 : cr_response = debug_register[2];
					DEBUG_BASE_ADDR+3 : cr_response = debug_register[3];
					DEBUG_BASE_ADDR+4 : cr_response = debug_register[4];
					DEBUG_BASE_ADDR+5 : cr_response = debug_register[5];
					DEBUG_BASE_ADDR+6 : cr_response = debug_register[6];
					DEBUG_BASE_ADDR+7 : cr_response = debug_register[7];
					DEBUG_BASE_ADDR+8 : cr_response = debug_register[8];
					DEBUG_BASE_ADDR+9 : cr_response = debug_register[9];
					DEBUG_BASE_ADDR+10: cr_response = debug_register[10];
					DEBUG_BASE_ADDR+11: cr_response = debug_register[11];
					DEBUG_BASE_ADDR+12: cr_response = debug_register[12];
					DEBUG_BASE_ADDR+13: cr_response = debug_register[13];
					DEBUG_BASE_ADDR+14: cr_response = debug_register[14];
					DEBUG_BASE_ADDR+15: cr_response = debug_register[15];
				endcase
			end
		end
	end

`ifdef DISPLAY_THREAD_STATUS

	generate
		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id = thread_id + 1 ) begin
			initial begin
				$monitor( "[Time %t] [TILE %2d] [THREAD %2d] Status: %s", $time( ), TILE_ID_PAR, thread_id, thread_status[thread_id].name( ) );
				$fmonitor( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %2d] [THREAD %2d] Status: %s", $time( ), TILE_ID_PAR, thread_id, thread_status[thread_id].name( ) );
			end
		end

		for ( thread_id = 0; thread_id < `THREAD_NUMB; thread_id = thread_id + 1 ) begin
			initial begin
				$monitor( "[Time %t] [TILE %2d] [THREAD %2d] Trap  : %s", $time( ), TILE_ID_PAR, thread_id, trap_reason[thread_id].name( ) );
				$fmonitor( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TILE %2d] [THREAD %2d] Trap  : %s", $time( ), TILE_ID_PAR, thread_id, trap_reason[thread_id].name( ) );
			end
		end
	endgenerate

`endif

    final begin
		$display( "[Time %t] [TESTBENCH] [CORE %1d] Kernel Cycles: %d ", $time( ), TILE_ID_PAR, kernel_cycles );
		$display( "[Time %t] [TESTBENCH] [CORE %1d] DCache misses: %d ", $time( ), TILE_ID_PAR, data_miss_counter );
		$display( "[Time %t] [TESTBENCH] [CORE %1d] ICache misses: %d ", $time( ), TILE_ID_PAR, instr_miss_counter );

	`ifdef SIMULATION
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE %1d] Kernel Cycles: %d ", $time( ), TILE_ID_PAR, kernel_cycles );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE %1d] DCache misses: %d ", $time( ), TILE_ID_PAR, data_miss_counter );
		$fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE %1d] ICache misses: %d ", $time( ), TILE_ID_PAR, instr_miss_counter );
	`endif

		for ( int thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin
            if (thread_status_reg[thread_id] != THREAD_IDLE) begin
			    $display( "[Time %t] [TESTBENCH] [CORE %1d] Thread %2d active cycles: %d ", $time( ), TILE_ID_PAR, thread_id, thread_work_cycles[thread_id] );
	`ifdef SIMULATION
			    $fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE %1d] Thread %2d active cycles: %d ", $time( ), TILE_ID_PAR, thread_id, thread_work_cycles[thread_id] );
	`endif
            end
		end

		for ( int thread_id = 0; thread_id < `THREAD_NUMB; thread_id++ ) begin
            if (thread_status_reg[thread_id] != THREAD_IDLE) begin
			    $display( "[Time %t] [TESTBENCH] [CORE %1d] Thread %2d misses cycles: %d ", $time( ), TILE_ID_PAR, thread_id, thread_blocked_cycle_count[thread_id] );
	`ifdef SIMULATION
			    $fdisplay( `DISPLAY_SIMULATION_LOG_VAR, "[Time %t] [TESTBENCH] [CORE %1d] Thread %2d misses cycles: %d ", $time( ), TILE_ID_PAR, thread_id, thread_blocked_cycle_count[thread_id] );
	`endif
            end
        end 
        
    end 



endmodule
