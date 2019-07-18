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

`include "npu_system_defines.sv"

/* This module logs transactions to the main memory, logging all 
 * the memory request issued by the core and all the memory responses 
 * from the main memory.
 */

module npu_core_logger #(
		parameter CORE_LOG_SIZE = 512,
		parameter MEM_LOG_SIZE  = 512,
		parameter DATA_WIDTH    = 512,
		parameter ADDR_WIDTH    = 32 )
	(
		input                                       clk,
		input                                       reset,
		input                                       enable,

		// From the Memory
		input                                       mc_valid_i,
		input                  [ADDR_WIDTH - 1 : 0] mc_address_i,
		input                  [DATA_WIDTH - 1 : 0] mc_block_i,

		// From the Core
		input                                       core_write_i,
		input                                       core_read_i,
		input                  [ADDR_WIDTH - 1 : 0] core_address_i,
		input                  [DATA_WIDTH - 1 : 0] core_block_i,

		// Snoop Request
		input                                       snoop_valid_i,
		input  log_snoop_req_t                      snoop_request_i,
		input                  [ADDR_WIDTH - 1 : 0] snoop_addr_i,

		// Log Output
		output logic                                cl_valid_o,
		output logic           [ADDR_WIDTH - 1 : 0] cl_req_addr_o,
		output logic           [DATA_WIDTH - 1 : 0] cl_req_data_o,
		output logic           [ADDR_WIDTH - 1 : 0] cl_req_id_o,
		output logic                                cl_req_is_write_o,
		output logic                                cl_req_is_read_o
	);

	typedef struct packed{
		logic [ADDR_WIDTH - 1 : 0] req_id;
		logic [ADDR_WIDTH - 1 : 0] req_addr;
		logic [DATA_WIDTH - 1 : 0] req_data;
		logic is_read;
		logic is_write;
	} log_request_t;

    localparam CORE_SRAM_SIZE = CORE_LOG_SIZE;
    localparam MEM_SRAM_SIZE  = MEM_LOG_SIZE;

	log_request_t                             req_from_core_in, req_from_mem_in;
	log_request_t                             req_from_core_out, req_from_mem_out;
	logic                                     req_from_core_valid, req_from_mem_valid;
	log_snoop_req_enum_t                      snoop_input_req, snoop_input_req_pending;

	logic                [ADDR_WIDTH - 1 : 0] core_current_elem;
	logic                [ADDR_WIDTH - 1 : 0] mem_current_elem;
	logic                [ADDR_WIDTH - 1 : 0] events_counter;

	logic                                     core_log_read_en, mem_log_read_en;

//  -----------------------------------------------------------------------
//  -- Request assignment
//  -----------------------------------------------------------------------

	assign snoop_input_req           = log_snoop_req_enum_t ' ( snoop_request_i );
	assign req_from_core_valid       = ( core_write_i | core_read_i ) & ( core_address_i >= `IO_MAP_BASE_ADDR );
	assign req_from_mem_valid        = mc_valid_i & ( mc_address_i >= `IO_MAP_BASE_ADDR );

	assign req_from_core_in.req_addr = core_address_i,
		req_from_core_in.req_data    = core_block_i,
		req_from_core_in.is_read     = core_read_i,
		req_from_core_in.is_write    = core_write_i,
		req_from_core_in.req_id      = events_counter;

	assign req_from_mem_in.req_addr  = mc_address_i,
		req_from_mem_in.req_data     = mc_block_i,
		req_from_mem_in.is_read      = 1'b0,
		req_from_mem_in.is_write     = 1'b1,
		req_from_mem_in.req_id       = events_counter;

//  -----------------------------------------------------------------------
//  -- SRAMs
//  -----------------------------------------------------------------------

	/*------ Core Log ------*/

	assign core_log_read_en          = snoop_valid_i & snoop_input_req == SNOOP_CORE;

	memory_bank_1r1w #(
		.COL_WIDTH   ( $bits( log_request_t ) ),
		.NB_COL      ( 1                      ),
		.WRITE_FIRST ( "TRUE"                 ),
		.SIZE        ( CORE_SRAM_SIZE         )
	) u_core_log(
		.read_enable   ( core_log_read_en    ),
		.read_address  ( snoop_addr_i        ),
		.read_data     ( req_from_core_out   ),
		.write_enable  ( req_from_core_valid ),
		.write_address ( core_current_elem   ),
		.write_data    ( req_from_core_in    ),
		.clock         ( clk                 )
	);

	/*------ Mem Log ------*/

	assign mem_log_read_en           = snoop_valid_i & snoop_input_req == SNOOP_MEM;

	memory_bank_1r1w #(
		.COL_WIDTH   ( $bits( log_request_t ) ),
		.NB_COL      ( 1                      ),
		.WRITE_FIRST ( "TRUE"                 ),
		.SIZE        ( MEM_SRAM_SIZE          )
	) u_mem_log(
		.read_enable   ( mem_log_read_en    ),
		.read_address  ( snoop_addr_i       ),
		.read_data     ( req_from_mem_out   ),
		.write_enable  ( req_from_mem_valid ),
		.write_address ( mem_current_elem   ),
		.write_data    ( req_from_mem_in    ),
		.clock         ( clk                )
	);

//  -----------------------------------------------------------------------
//  -- Request Output
//  -----------------------------------------------------------------------

	always_comb begin : OUT_DEMUX
		case( snoop_input_req_pending )
			GET_CORE_EVENTS   : begin
				cl_req_addr_o     = req_from_core_out.req_addr;
				cl_req_data_o     = req_from_core_out.req_data;
				cl_req_id_o       = core_current_elem;
				cl_req_is_write_o = req_from_core_out.is_write;
				cl_req_is_read_o  = req_from_core_out.is_read;
			end

			GET_MEM_EVENTS    : begin
				cl_req_addr_o     = req_from_core_out.req_addr;
				cl_req_data_o     = req_from_core_out.req_data;
				cl_req_id_o       = mem_current_elem;
				cl_req_is_write_o = req_from_core_out.is_write;
				cl_req_is_read_o  = req_from_core_out.is_read;
			end

			GET_EVENT_COUNTER : begin
				cl_req_addr_o     = req_from_core_out.req_addr;
				cl_req_data_o     = req_from_core_out.req_data;
				cl_req_id_o       = events_counter;
				cl_req_is_write_o = req_from_core_out.is_write;
				cl_req_is_read_o  = req_from_core_out.is_read;
			end

			SNOOP_CORE        : begin
				cl_req_addr_o     = req_from_core_out.req_addr;
				cl_req_data_o     = req_from_core_out.req_data;
				cl_req_id_o       = req_from_core_out.req_id;
				cl_req_is_write_o = req_from_core_out.is_write;
				cl_req_is_read_o  = req_from_core_out.is_read;
			end

			SNOOP_MEM         : begin
				cl_req_addr_o     = req_from_mem_out.req_addr;
				cl_req_data_o     = req_from_mem_out.req_data;
				cl_req_id_o       = req_from_mem_out.req_id;
				cl_req_is_write_o = req_from_mem_out.is_write;
				cl_req_is_read_o  = req_from_mem_out.is_read;
			end

			default : begin
				cl_req_addr_o     = req_from_mem_out.req_addr;
				cl_req_data_o     = req_from_mem_out.req_data;
				cl_req_id_o       = req_from_mem_out.req_id;
				cl_req_is_write_o = req_from_mem_out.is_write;
				cl_req_is_read_o  = req_from_mem_out.is_read;
			end

		endcase
	end

	always_ff @ ( posedge clk, posedge reset ) begin : VALID_OUT
		if ( reset )
			cl_valid_o <= 1'b0;
		else
			if ( enable )
				cl_valid_o <= snoop_valid_i;
	end

	always_ff @ ( posedge clk, posedge reset ) begin : SNOOP_REQ_PENDING
		if ( reset )
			snoop_input_req_pending <= SNOOP_CORE;
		else
			if ( enable )
				snoop_input_req_pending <= snoop_input_req;
	end

//  -----------------------------------------------------------------------
//  -- Event Counters
//  -----------------------------------------------------------------------

	always_ff @ ( posedge clk, posedge reset ) begin : CORE_EVENTS
		if ( reset )
			core_current_elem <= 0;
		else
			if ( enable )
				if ( req_from_core_valid )
					core_current_elem <= core_current_elem + 1;
	end

	always_ff @ ( posedge clk, posedge reset ) begin : MEM_EVENTS
		if ( reset )
			mem_current_elem <= 0;
		else
			if ( enable )
				if ( req_from_mem_valid )
					mem_current_elem <= mem_current_elem + 1;
	end

	always_ff @ ( posedge clk, posedge reset ) begin : ID_EVENTS
		if ( reset )
			events_counter <= 0;
		else
			if ( enable )
				if ( req_from_mem_valid | req_from_core_valid )
					events_counter <= events_counter + 1;
	end


endmodule
