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

`ifndef __NPU_DEBUG_LOG
`define __NPU_DEBUG_LOG

`include "npu_user_defines.sv"
`include "npu_coherence_defines.sv"
`include "npu_message_service_defines.sv"

//  -----------------------------------------------------------------------
//  -- Log file defines
//  -----------------------------------------------------------------------
`ifdef SIMULATION	

//	`define TOP tb_npu
	
	`ifdef COHERENCE_INJECTION
		`define TOP tb_coherence_injection
	`else 
		`ifdef SINGLE_CORE
			`define TOP tb_singlecore
		`else
			`define TOP tb_npu
		`endif
	`endif

	`ifdef DISPLAY_COHERENCE
		`define DISPLAY_COHERENCE_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_coherence.txt"}
		`define DISPLAY_COHERENCE_VAR  `TOP.coherence_file
	`endif

	`ifdef DISPLAY_SPM
		`define DISPLAY_SPM_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_spm.txt"}
		`define DISPLAY_SPM_VAR  `TOP.spm_file
	`endif

	`ifdef DISPLAY_CORE
		`define DISPLAY_CORE_VAR  `TOP.core_file
		`define DISPLAY_CORE_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_core.txt"}
	`endif

	`ifdef DISPLAY_LDST
		`define DISPLAY_LDST_VAR  `TOP.ldst_file
		`define DISPLAY_LDST_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_ldst.txt"}
	`endif

	`ifdef DISPLAY_MEMORY
		`define DISPLAY_MEMORY_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_memory.txt"}
	`endif

	`ifdef DISPLAY_MEMORY_TRANS
		`define DISPLAY_MEMORY_TRANS_FILE {`PROJECT_PATH, "simulation_log/", `KERNEL_NAME, "/display_memory_trans.txt"}
	`endif

	`ifdef DISPLAY_REQUESTS_MANAGER
		`define DISPLAY_REQ_MANAGER_VAR  `TOP.requests_file
		`define DISPLAY_REQ_MANAGER_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_requests_manager.txt"}
	`endif

	`ifdef DISPLAY_SIMULATION_LOG
		`define DISPLAY_SIMULATION_LOG_VAR  `TOP.sim_log_file
		`define DISPLAY_SIMULATION_LOG_FILE {`PROJECT_PATH, "simulation_log/", `KERNEL_NAME, "/display_simulation.txt"}
	`endif

	`ifdef DISPLAY_SYNC
		`define DISPLAY_SYNC_VAR     `TOP.sync_file
		`define DISPLAY_BARRIER_VAR  `TOP.barrier_file
		`define DISPLAY_SYNC_FILE    {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_sync.txt"}
		`define DISPLAY_BARRIER_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_barrier_core.txt"}
		`ifdef PERFORMANCE_SYNC
			`define DISPLAY_SYNC_PERF_VAR  `TOP.perf_sync_perf
			`define DISPLAY_SYNC_PERF_FILE {`PROJECT_PATH, "simulation_log/",`KERNEL_NAME,"/display_sync_perf.txt"}
		`endif
	`endif
	
	`ifdef DISPLAY_IO
		`define DISPLAY_IO_VAR  `TOP.io_file
		`define DISPLAY_IO_FILE {`PROJECT_PATH, "simulation_log/", `KERNEL_NAME, "/display_io.txt"}
	`endif

	`ifdef DISPLAY_FPU
	        `define DISPLAY_FPU_VAR `TOP.fpu_file
		`define DISPLAY_FPU_FILE {`PROJECT_PATH, "simulation_log/", `KERNEL_NAME, "/display_fpu.txt"}
	`endif

`endif

`ifdef DISPLAY_COHERENCE
task print_req;
	input coherence_request_message_t mess_in;

	automatic dcache_address_t block_addr = mess_in.memory_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Source:       %h", mess_in.source );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Address:      %h (block %h)", mess_in.memory_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Packet Type:  %s", mess_in.packet_type.name( ) );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Data:         %h", mess_in.data );
	end
endtask

task print_rep;
	input replacement_request_t mess_in;

	automatic dcache_address_t block_addr = mess_in.memory_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Source:       %h", mess_in.source );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Address:      %h (block %h)", mess_in.memory_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Packet Type:  REPLACEMENT" );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Data:					%h", mess_in.data );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "State:        %h", mess_in.state );
	end
endtask

task print_resp;
	input coherence_response_message_t mess_in;

	automatic dcache_address_t block_addr = mess_in.memory_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Source:       %h", mess_in.source );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "From DC:      %b", mess_in.from_directory );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Address:      %h (block %h)", mess_in.memory_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Requestor:    %s", mess_in.requestor.name( ) );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Packet Type:  %s", mess_in.packet_type.name( ) );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Data:         %h", mess_in.data );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Mask:         %h", mess_in.dirty_mask );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Uncoherent:   %b", mess_in.req_is_uncoherent );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Sharer Count: %d", mess_in.sharers_count );
	end
endtask

task print_fwd_req;
	input coherence_forwarded_message_t mess_in;

	automatic dcache_address_t block_addr = mess_in.memory_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Source:       %h", mess_in.source );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Address:      %h (block %h)", mess_in.memory_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Requestor:    %s", mess_in.requestor.name( ) );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Packet Type:  %s", mess_in.packet_type.name( ) );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Uncoherent:   %b", mess_in.req_is_uncoherent );
	end
endtask

task print_flush;
	input dcache_address_t ci_flush_request_address;

	automatic dcache_address_t block_addr = ci_flush_request_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Flush Address: %h (block %h)", ci_flush_request_address, block_addr );
	end
endtask

task print_dinv;
	input dcache_address_t ci_dinv_request_address;
	input thread_id_t ci_dinv_request_thread_id;

	automatic dcache_address_t block_addr = ci_dinv_request_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "DInv Address: %h (block %h)", ci_dinv_request_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Thread ID:    %h", ci_dinv_request_thread_id );
	end
endtask


task print_replacement;
	input dcache_address_t ci_replacement_request_address;
	input thread_id_t ci_replacement_request_thread_id;

	automatic dcache_address_t block_addr = ci_replacement_request_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Replacement Address: %h (block %h)", ci_replacement_request_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Thread ID:         %h", ci_replacement_request_thread_id );
	end
endtask

task print_store;
	input dcache_address_t ci_store_request_address;
	input thread_id_t ci_store_request_thread_id;

	automatic dcache_address_t block_addr = ci_store_request_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Store Address: %h (block %h)", ci_store_request_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Thread ID:     %h", ci_store_request_thread_id );
	end
endtask

task print_load;
	input dcache_address_t ci_load_request_address;
	input thread_id_t ci_load_request_thread_id;

	automatic dcache_address_t block_addr = ci_load_request_address;
	block_addr.offset = 0;

	begin
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Load Address: %h (block %h)", ci_load_request_address, block_addr );
		$fdisplay( `DISPLAY_COHERENCE_VAR, "Thread ID:    %h", ci_load_request_thread_id );
	end
endtask
`endif

`ifdef DISPLAY_HOST
// Host Interface display
task print_host_interface_message_in;
	input host_message_type_t message_in;
	input logic [31 : 0] item_data_i;
	input interface_state_t state;
	input interface_state_t next_state;
	begin
		$fdisplay( `DISPLAY_HOST_VAR, "=======================" );
		$fdisplay( `DISPLAY_HOST_VAR, "Host Interface - [Time %t] - Message Received", $time( ) );
		if ( state == IDLE )
			$fdisplay( `DISPLAY_HOST_VAR, "Message: %s", message_in.name( ) );
		else
			$fdisplay( `DISPLAY_HOST_VAR, "Hex: %h", item_data_i );
		$fdisplay( `DISPLAY_HOST_VAR, "State: %s", next_state.name( ) );
	end
endtask

task print_host_interface_message_out;
	input host_message_type_t message_out;
	input interface_state_t state;
	input interface_state_t next_state;
	begin
		$fdisplay( `DISPLAY_HOST_VAR, "=======================" );
		$fdisplay( `DISPLAY_HOST_VAR, "Host Interface - [Time %t] - Message Sent", $time( ) );
		$fdisplay( `DISPLAY_HOST_VAR, "Message: %s", message_out.name( ) );
		$fdisplay( `DISPLAY_HOST_VAR, "State: %s", next_state.name( ) );
	end
endtask
`endif

`ifdef DISPLAY_REQUESTS_MANAGER
//H2C CONTROLLER AND HOST REQUESTS MANAGER PRINTER TASK
//h2c controller
task print_host_interface_message_in;
	input logic [31 : 0] item_data_i;
	input interface_state_t state;
	input interface_state_t next_state;
	begin
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "=======================" );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "H2C Interface - [Time %t] - Message Received from host", $time( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Hex: %h", item_data_i );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "State: %s", state.name( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Next State: %s", next_state.name( ) );
	end
endtask

task print_host_interface_command;
	input host_message_type_t message_in;
	input interface_state_t state;
	input interface_state_t next_state;
	begin
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "=======================" );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "H2C Interface - [Time %t] - Command Received from host", $time( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Message: ******%s", message_in.name( ),"******" );
	end
endtask

task print_h2c_interface_message_to_net;
	input host_message_t c2n_mes_service;
	input tile_address_t destination;
	input interface_state_t state;

	begin
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "=======================" );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "H2C Interface - [Time %t] - Message Sent over NOC", $time( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Message: %s", c2n_mes_service.message.name( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Y  = %d", destination.y );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "X  = %d", destination.x );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Thread  = %d", c2n_mes_service.hi_job_thread_id );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Enable Thread Mask   = %b", c2n_mes_service.hi_thread_en );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "PC = %h", c2n_mes_service.hi_job_pc );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "State: %s", state.name( ) );
	end
endtask

task print_h2c_interface_message_from_net;
	input host_message_t c2n_mes_service;
	input interface_state_t next_state;

	begin
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "=======================" );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "H2C Interface - [Time %t] - Message From NOC", $time( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Message: %s", c2n_mes_service.message.name( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Next State: %s", next_state.name( ) );
	end
endtask

task print_h2c_interface_status_from_net;
	input host_message_t n2c_mes_service;
	input logic [3 : 0] hi_thread_en;

	begin
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "=======================" );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "H2C Interface - [Time %t] - Message From NOC", $time( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Message: %s", n2c_mes_service.message.name( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Enabled Thread Mask   = %b", hi_thread_en );
	end
endtask

//boot manager
task print_boot_manager_message_in;
	input host_message_t message_in;
	begin
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "=======================" );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "BM Interface - [Time %t] - Message Received from host request manager", $time( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Message: %s", message_in.message.name( ) );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Thread  = %d", message_in.hi_job_thread_id );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "Enable Thread Mask = %b", message_in.hi_thread_en );
		$fdisplay( `DISPLAY_REQ_MANAGER_VAR, "PC = %h", message_in.hi_job_pc );
	end
endtask

`endif

`ifdef DISPLAY_CORE

`ifdef DISPLAY_ISSUE
task print_core_issue;
	input int tile_id;
	input instruction_decoded_t is_instruction;
	//$fdisplay( `DISPLAY_CORE_VAR, "=======================" );
	$fwrite( `DISPLAY_CORE_VAR, "[Time %t] [TILE %.2h] [THREAD %.2h] - Instruction Issue - [PC %h] ", $time( ), tile_id, is_instruction.thread_id, is_instruction.pc );
	//$fdisplay( file, "PC: %h", is_instruction.pc );
	if ( is_instruction.is_memory_access ) begin
		$fwrite( `DISPLAY_CORE_VAR, "op_code: %.10s \t\t\tDest: %d,  Src0: %d,  Src1: %d\n", is_instruction.op_code.mem_opcode.name( ), is_instruction.destination, is_instruction.source0, is_instruction.source1 );
	end else if ( is_instruction.is_branch )
		$fwrite( `DISPLAY_CORE_VAR, "op_code: %.10s\n", is_instruction.op_code.j_opcode.name( ) );
	else if ( is_instruction.is_int | is_instruction.is_fp )
		$fwrite( `DISPLAY_CORE_VAR, "op_code: %.10s\n", is_instruction.op_code.alu_opcode.name( ) );
	else if ( is_instruction.is_movei )
		$fwrite( `DISPLAY_CORE_VAR, "op_code: %.10s\n", is_instruction.op_code.movei_opcode.name( ) );
	else if ( is_instruction.is_control )
		$fwrite( `DISPLAY_CORE_VAR, "op_code: %.10s\n", is_instruction.op_code.contr_opcode.name( ) );
	$fflush(`DISPLAY_CORE_VAR);
endtask
`endif

`ifdef DISPLAY_INT
task print_int_result;
	input int tile_id;
	input instruction_decoded_t int_instr_scheduled;
	input hw_lane_t int_result;
	$fdisplay( `DISPLAY_CORE_VAR, "[Time %t] [TILE %.2h] [THREAD %.2h] - Integer pipe      - [PC %h] op_code: %.10s \t\t\tResult: %h", $time( ), tile_id,int_instr_scheduled.thread_id, int_instr_scheduled.pc,
		int_instr_scheduled.op_code.alu_opcode.name( ), int_result );
	$fflush(`DISPLAY_CORE_VAR);
endtask

`endif

`ifdef DISPLAY_WB
task print_wb_result;
	input int tile_id;
	input thread_id_t thread_id;
	input wb_result_t wb_result;
	$fdisplay( `DISPLAY_CORE_VAR, "[Time %t] [TILE %.2h] [THREAD %.2h] - Writeback         - [PC %h] Register: %s%.2d\tData: %h", $time( ), tile_id, thread_id, wb_result.wb_result_pc,
	wb_result.wb_result_is_scalar ? "s" : "v", wb_result.wb_result_register, wb_result.wb_result_data );
	$fflush(`DISPLAY_CORE_VAR);
endtask

`endif

`endif // DISPLAY_CORE


`ifdef DISPLAY_LDST
task print_ldst1_result;
	input int tile_id;
	input instr_valid;
	input instruction_decoded_t ldst1_instruction;
	input address_t ldst1_address;
	input dcache_line_t ldst1_store_value;
	input dcache_store_mask_t ldst1_store_mask;

	if ( instr_valid ) begin
		string instr_op;
		dcache_address_t block_addr;

		if (ldst1_instruction.is_load) begin
			instr_op = "LOAD";
		end else begin
			if (ldst1_instruction.is_control) begin
				instr_op = ldst1_instruction.op_code.contr_opcode.name();
			end else begin
				instr_op = "STORE";
			end
		end

		if (~ldst1_instruction.is_memory_access_coherent) begin
			instr_op = {instr_op, " (uncoherent)"};
		end

		block_addr = ldst1_address;
		block_addr.offset = 0;

		if (instr_op == "STORE") begin
			$fdisplay( `DISPLAY_LDST_VAR, "[Time %t] [TILE %.2h] [THREAD %2d] - LDST Stage 1 - %s request - PC: %h\tAddress: %h (block %h)\tMask: %h\tData: %h", $time(), TILE_ID, ldst1_instruction.thread_id, instr_op, ldst1_instruction.pc, ldst1_address, block_addr, ldst1_store_mask, ldst1_store_value );
		end else begin
			$fdisplay( `DISPLAY_LDST_VAR, "[Time %t] [TILE %.2h] [THREAD %2d] - LDST Stage 1 - %s request - PC: %h\tAddress: %h (block %h)", $time(), TILE_ID, ldst1_instruction.thread_id, instr_op, ldst1_instruction.pc, ldst1_address, block_addr );
		end
		$fflush( `DISPLAY_LDST_VAR );
	end
endtask

task print_ldst3_result;
	input int tile_id;
	input ldst3_flush;
	input ldst3_dinv;
	input ldst3_evict;
	input ldst3_miss;
	input instruction_decoded_t ldst3_instruction;
	input address_t ldst3_address;
	input dcache_line_t ldst3_cache_line;

	automatic dcache_address_t block_addr = ldst3_address;
	block_addr.offset = 0;

	if ( ldst3_evict )
		$fdisplay( `DISPLAY_LDST_VAR, "[Time %t] [TILE %.2h] [THREAD %2d] - LDST Stage 3 - Evict request - PC: %h\tAddress: %h (block %h)\tData: %h", $time(), tile_id, ldst3_instruction.thread_id, ldst3_instruction.pc,
			ldst3_address, block_addr, ldst3_cache_line );
		
	if ( ldst3_miss )
		$fdisplay( `DISPLAY_LDST_VAR, "[Time %t] [TILE %.2h] [THREAD %2d] - LDST Stage 3 - Miss request  - PC: %h\tAddress: %h (block %h)", $time(), tile_id, ldst3_instruction.thread_id, ldst3_instruction.pc, 
			ldst3_address, block_addr );
		
	if ( ldst3_flush )
		$fdisplay( `DISPLAY_LDST_VAR, "[Time %t] [TILE %.2h] [THREAD %2d] - LDST Stage 3 - Flush request - PC: %h\tAddress: %h (block %h)\tData: %h", $time(), tile_id, ldst3_instruction.thread_id, ldst3_instruction.pc,
			ldst3_address, block_addr, ldst3_cache_line );

	if ( ldst3_dinv )
		$fdisplay( `DISPLAY_LDST_VAR, "[Time %t] [TILE %.2h] [THREAD %2d] - LDST Stage 3 - DInv request - PC: %h\tAddress: %h (block %h)\tData: %h", $time(), tile_id, ldst3_instruction.thread_id, ldst3_instruction.pc,
			ldst3_address, block_addr, ldst3_cache_line );

	if ( ldst3_evict | ldst3_miss | ldst3_flush )
			$fflush( `DISPLAY_LDST_VAR );
endtask

`endif

`ifdef DISPLAY_IO
task print_io_msg;
	input int tile_id;
	input io_message_t msg;
	input bit is_out;

	if (is_out) begin
		if (msg.io_source == tile_id_t'(tile_id)) begin
			$fdisplay(`DISPLAY_IO_VAR, "[Time %t] [TILE %.2h] Sent IO Request     - Thread %2d\tOperation %s\tAddress %08x\tData %08x", $time(), tile_id, msg.io_thread, msg.io_operation.name(), msg.io_address, msg.io_data);
		end else begin
			$fdisplay(`DISPLAY_IO_VAR, "[Time %t] [TILE %.2h] Sent IO Reply       - Thread %2d\tOperation %s\tAddress %08x\tData %08x", $time(), tile_id, msg.io_thread, msg.io_operation.name(), msg.io_address, msg.io_data);
		end
	end else begin
		if (msg.io_source == tile_id_t'(tile_id)) begin
			$fdisplay(`DISPLAY_IO_VAR, "[Time %t] [TILE %.2h] Received IO Reply   - Thread %2d\tOperation %s\tAddress %08x\tData %08x", $time(), tile_id, msg.io_thread, msg.io_operation.name(), msg.io_address, msg.io_data);
		end else begin
			$fdisplay(`DISPLAY_IO_VAR, "[Time %t] [TILE %.2h] Received IO Request - Thread %2d\tOperation %s\tAddress %08x\tData %08x", $time(), tile_id, msg.io_thread, msg.io_operation.name(), msg.io_address, msg.io_data);
		end
	end
endtask
`endif

`endif
