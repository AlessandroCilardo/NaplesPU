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
 * This module is the L1 cache controller allocated in the single-cored version of NPU system and directly connected to the LDST unit.
 * The main task is to handle requests from the core (load/store miss, instruction miss, flush, evict) and
 * to serialize them. The request are scheduled with a fixed priority.
 *
 * An FSM manages the response from the main memory:
 *  - Instruction misses are on the read only memory segment (hence no need for coherence), hence the controller does not handle such requests
 *  - for a load/store miss, a read was performed, so the response data has to be stored in the proper cache set/way;
 *      if all the way are occupied for the given set, a replace command to the LDST unit is issued
 *  - for a flush/evict, a store is performed, but the flush operation has to write the data back to the main memory, this operation does not
 *      alter the coherence state.
 *
 * Note that the hit check has to be done for a load/store miss because the read request are not merged, so a response
 * could arrive after a cache miss for the same address.
 *
 */

module sc_cache_controller #(
		parameter ENDSWAP = 0
	)(
		input                                              clk,
		input                                              reset,

		// Core Interface
		output logic                                       cc_dequeue_store_request,
		output logic                                       cc_dequeue_load_request,
		output logic                                       cc_dequeue_replacement_request,
		output logic                                       cc_dequeue_flush_request,
		output logic                                       cc_dequeue_dinv_request,
		input  logic                                       ci_store_request_valid,
		input  thread_id_t                                 ci_store_request_thread_id,
		input  dcache_address_t                            ci_store_request_address,
		input  logic                                       ci_store_request_coherent,
		input  logic                                       ci_load_request_valid,
		input  thread_id_t                                 ci_load_request_thread_id,
		input  dcache_address_t                            ci_load_request_address,
		input  logic                                       ci_load_request_coherent,
		input  logic                                       ci_replacement_request_valid,
		input  thread_id_t                                 ci_replacement_request_thread_id,
		input  dcache_address_t                            ci_replacement_request_address,
		input  dcache_line_t                               ci_replacement_request_cache_line,
		input  dcache_store_mask_t                         ci_replacement_request_dirty_mask,
		input  logic                                       ci_flush_request_valid,
		input  dcache_address_t                            ci_flush_request_address,
		input  dcache_line_t                               ci_flush_request_cache_line,
		input  dcache_store_mask_t                         ci_flush_request_dirty_mask,
		input  logic                                       ci_flush_request_coherent,
		input  logic                                       ci_dinv_request_valid,
		input  dcache_address_t                            ci_dinv_request_address,
		input  thread_id_t                                 ci_dinv_request_thread_id,
		input  dcache_line_t                               ci_dinv_request_cache_line,
		input  dcache_store_mask_t                         ci_dinv_request_dirty_mask,
		input  logic                                       ci_dinv_request_coherent,

		// LDST
		output logic                                       cc_update_ldst_valid,
		output dcache_way_idx_t                            cc_update_ldst_way,
		output dcache_address_t                            cc_update_ldst_address,
		output dcache_privileges_t                         cc_update_ldst_privileges,
		output dcache_line_t                               cc_update_ldst_store_value,
		output cc_command_t                                cc_update_ldst_command,

		output logic                                       cc_wakeup,
		output thread_id_t                                 cc_wakeup_thread_id,

		output logic                                       cc_snoop_tag_valid,
		output dcache_set_t                                cc_snoop_tag_set,
		output logic                                       cc_snoop_data_valid,
		output dcache_set_t                                cc_snoop_data_set,
		output dcache_way_idx_t                            cc_snoop_data_way,

		input  dcache_line_t                               ldst_snoop_data,
		input  dcache_privileges_t   [`DCACHE_WAY - 1 : 0] ldst_snoop_privileges,
		input  dcache_tag_t          [`DCACHE_WAY - 1 : 0] ldst_snoop_tag,

		// From LDST Unit - IO Map interface
		input  logic                                       ldst_io_valid,
		input  thread_id_t                                 ldst_io_thread,
		input  logic [$bits(io_operation_t)-1 : 0]         ldst_io_operation,
		input  address_t                                   ldst_io_address,
		input  register_t                                  ldst_io_data,

		output logic                                       io_intf_resp_valid,
		output thread_id_t                                 io_intf_wakeup_thread,
		output register_t                                  io_intf_resp_data,
		input  logic                                       ldst_io_resp_consumed,

		// To LDST Unit - IO Map interface
		output logic                                       io_intf_available,

		// Memory controller
		output address_t                                   n2m_request_address,
		output dcache_line_t                               n2m_request_data,
		output dcache_store_mask_t                         n2m_request_dirty_mask,
		output logic                                       n2m_request_read,
		output logic                                       n2m_request_write,
		output logic                                       mc_avail_o,

		input  logic                                       m2n_request_available,
		input  logic                                       m2n_response_valid,
		input  address_t                                   m2n_response_address,
		input  dcache_line_t                               m2n_response_data,

		// Thread Controller - Instruction cache interface
		output logic                                       mem_instr_request_available,
		output icache_lane_t                               mem_instr_request_data_in,
		output logic                                       mem_instr_request_valid,

		input  logic                                       tc_instr_request_valid,
		input  address_t                                   tc_instr_request_address
	);

	localparam IOM_FIFO_SIZE   = 8;
	localparam INSTR_FIFO_SIZE = 2;

//  -----------------------------------------------------------------------
//  -- Typedefs and Signals
//  -----------------------------------------------------------------------

	typedef struct packed {
		thread_id_t thread;
		io_operation_t operation;
		dcache_address_t address;
		register_t data;
	} io_fifo_t;

	typedef enum {IDLE, SEND_REQ, WAIT_RESP} state_t;

	state_t                                           state;

	io_fifo_t                                         iom_request_in, iom_request_out, iom_resp_in, iom_resp_out;
	logic                                             pending_iom, dequeue_iom, empty_iom, iom_almost_full;
	logic                                             iom_resp_enqueue, iom_resp_empty;

	address_t                                         instr_req_addr;
	logic                                             pending_instr, empty_instr, dequeue_instr;

	logic                                             req_completed, execute_req;

	logic                                             granted_read;
	logic                                             granted_write;
	logic                                             granted_need_snoop;
	logic                                             granted_need_hit_miss; // 1 = need hit, 0 = need miss
	logic                                             granted_wakeup;
	thread_id_t                                       granted_thread_id;
	dcache_address_t                                  granted_address;
	dcache_line_t                                     granted_cache_line;
	dcache_store_mask_t                               granted_dirty_mask;

	dcache_line_t                                     m2n_response_data_swap;
	dcache_line_t                                     out_data_swap;

	dcache_way_mask_t                                 way_matched_oh, way_busy_oh;
	dcache_way_idx_t                                  way_matched_idx, way_matched_reg;
	logic                                             snoop_hit, ways_full, update_counter_way;
	logic             [$clog2( `DCACHE_WAY ) - 1 : 0] counter_way [`DCACHE_SET];

//  -----------------------------------------------------------------------
//  -- Memory swap Interface
//  -----------------------------------------------------------------------
	// Endian swap vector data
	genvar                                            swap_word;
	generate
		if ( ENDSWAP )
			for ( swap_word = 0; swap_word < 16; swap_word++ ) begin : swap_word_gen
				assign m2n_response_data_swap[swap_word * 32 +: 8 ]     = m2n_response_data[swap_word * 32 + 24 +: 8];
				assign m2n_response_data_swap[swap_word * 32 + 8 +: 8 ] = m2n_response_data[swap_word * 32 + 16 +: 8];
				assign m2n_response_data_swap[swap_word * 32 + 16 +: 8] = m2n_response_data[swap_word * 32 + 8 +: 8 ];
				assign m2n_response_data_swap[swap_word * 32 + 24 +: 8] = m2n_response_data[swap_word * 32 +: 8 ];

				assign n2m_request_data[swap_word * 32 +: 8 ]           = out_data_swap[swap_word * 32 + 24 +: 8 ];
				assign n2m_request_data[swap_word * 32 + 8 +: 8 ]       = out_data_swap[swap_word * 32 + 16 +: 8 ];
				assign n2m_request_data[swap_word * 32 + 16 +: 8 ]      = out_data_swap[swap_word * 32 + 8 +: 8 ];
				assign n2m_request_data[swap_word * 32 + 24 +: 8 ]      = out_data_swap[swap_word * 32 +: 8 ];
			end
		else begin
			assign m2n_response_data_swap = m2n_response_data;
			assign n2m_request_data       = out_data_swap;
		end
	endgenerate

	assign out_data_swap          = granted_cache_line;
	assign n2m_request_dirty_mask = granted_dirty_mask;

//  -----------------------------------------------------------------------
//  -- Core Interface - IO and Instruction requests buffering
//  -----------------------------------------------------------------------
	assign iom_request_in.thread       = ldst_io_thread;
	assign iom_request_in.operation    = io_operation_t'(ldst_io_operation);
	assign iom_request_in.address      = ldst_io_address;
	assign iom_request_in.data         = ldst_io_data;

	// IO Mapped requests FIFO.
	sync_fifo #(
		.WIDTH                 ( $bits( io_fifo_t ) ),
		.SIZE                  ( IOM_FIFO_SIZE      ),
		.ALMOST_FULL_THRESHOLD ( IOM_FIFO_SIZE - 4  )
	)
	iom_fifo (
		.clk         ( clk             ),
		.reset       ( reset           ),
		.flush_en    ( 1'b0            ),
		.full        (                 ),
		.almost_full ( iom_almost_full ),
		.enqueue_en  ( ldst_io_valid   ),
		.value_i     ( iom_request_in  ),
		.empty       ( empty_iom       ),
		.almost_empty(                 ),
		.dequeue_en  ( dequeue_iom     ),
		.value_o     ( iom_request_out )
	);

	// When the IO Map FIFO is full, the Cache Controller refuses further IO Map
	// requests.
	assign io_intf_available     = ~iom_almost_full;

	assign iom_resp_in.thread    = iom_request_out.thread;
	assign iom_resp_in.operation = iom_request_out.operation;
	assign iom_resp_in.address   = iom_request_out.address;
	assign iom_resp_in.data      = m2n_response_data[$bits(register_t)-1 : 0];

	sync_fifo #(
		.WIDTH                 ( $bits( io_fifo_t ) ),
		.SIZE                  ( IOM_FIFO_SIZE      )
	)
	iom_response_fifo (
		.clk         ( clk                   ),
		.reset       ( reset                 ),
		.flush_en    ( 1'b0                  ),
		.full        (                       ),
		.almost_full (                       ),
		.enqueue_en  ( iom_resp_enqueue      ),
		.value_i     ( iom_resp_in           ),
		.empty       ( iom_resp_empty        ),
		.almost_empty(                       ),
		.dequeue_en  ( ldst_io_resp_consumed ),
		.value_o     ( iom_resp_out          )
	);

	assign io_intf_resp_valid    = ~iom_resp_empty;
	assign io_intf_wakeup_thread = iom_resp_out.thread;
	assign io_intf_resp_data     = iom_resp_out.data;

	sync_fifo #(
		.WIDTH ( $bits( tc_instr_request_address ) ),
		.SIZE  ( INSTR_FIFO_SIZE                   )
	)
	instr_fifo (
		.clk         ( clk                      ),
		.reset       ( reset                    ),
		.flush_en    ( 1'b0                     ),
		.full        (                          ),
		.almost_full (                          ),
		.enqueue_en  ( tc_instr_request_valid   ),
		.value_i     ( tc_instr_request_address ),
		.empty       ( empty_instr              ),
		.almost_empty(                          ),
		.dequeue_en  ( dequeue_instr            ),
		.value_o     ( instr_req_addr           )
	);

	assign pending_iom                        = ~empty_iom;

	assign pending_instr                      = ~empty_instr,
	       mem_instr_request_available        =  empty_instr;

	localparam CC_REQUESTORS = 7;

	typedef enum logic [$clog2(CC_REQUESTORS)-1 : 0] {
		REPLACEMENT,
		FLUSH,
		DINV,
		STORE,
		LOAD,
		IOM,
		INSTR
	} request_type;

	logic [CC_REQUESTORS-1 : 0] requestors;
	logic [CC_REQUESTORS-1 : 0] grants;
	logic [CC_REQUESTORS-1 : 0] grants_reg; // this is a grant and hold like arbitration

	assign requestors[STORE]       = ci_store_request_valid;
	assign requestors[LOAD]        = ci_load_request_valid;
	assign requestors[REPLACEMENT] = ci_replacement_request_valid;
	assign requestors[FLUSH]       = ci_flush_request_valid;
	assign requestors[DINV]        = ci_dinv_request_valid;
	assign requestors[IOM]         = pending_iom;
	assign requestors[INSTR]       = pending_instr;

	assign req_completed = dequeue_instr | dequeue_iom | cc_dequeue_store_request |
	                       cc_dequeue_load_request | cc_dequeue_replacement_request |
	                       cc_dequeue_flush_request | cc_dequeue_dinv_request;

	assign execute_req = ~granted_need_snoop |
	                     (granted_need_snoop & ((snoop_hit & granted_need_hit_miss) | (~snoop_hit & ~granted_need_hit_miss)));

	round_robin_arbiter #(
		.SIZE ( /*CC_REQUESTORS*/8 )
	) arb (
		.clk         ( clk                ),
		.reset       ( reset              ),
		.en          ( 1'b0               ), // Fixed priority scheduling
		.requests    ( {1'b0, requestors} ),
		.decision_oh ( grants             )
	);

//  -----------------------------------------------------------------------
//  -- Snoop Data cache
//  -----------------------------------------------------------------------
	assign cc_snoop_data_valid = 1'b0,
	       cc_snoop_data_set   = 0,
	       cc_snoop_data_way   = 0;

	assign cc_wakeup_thread_id = granted_thread_id;

//  -----------------------------------------------------------------------
//  -- Snooping match hit
//  -----------------------------------------------------------------------
	// This logic checks whether a cache hit occurs or not after a snoop request. If the retrieved
	// cache line is not valid, both privileges are equal 0.
	genvar                                            dcache_way;
	generate
		for ( dcache_way = 0; dcache_way < `DCACHE_WAY; dcache_way++ ) begin
			assign way_busy_oh[dcache_way]    = ( ldst_snoop_privileges[dcache_way].can_read | ldst_snoop_privileges[dcache_way].can_write );
			assign way_matched_oh[dcache_way] = ( ldst_snoop_tag[dcache_way] == granted_address.tag ) & way_busy_oh[dcache_way];
		end
	endgenerate

	assign snoop_hit = |way_matched_oh;
	assign ways_full = &way_busy_oh;

	oh_to_idx #(
		.NUM_SIGNALS( `DCACHE_WAY ),
		.DIRECTION  ( "LSB0"      )
	)
	u_oh_to_idx_way (
		.index  ( way_matched_idx ),
		.one_hot( way_matched_oh  )
	);

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			way_matched_reg <= dcache_way_idx_t'(0);
		end else if (snoop_hit) begin
			way_matched_reg <= way_matched_idx;
		end
	end

	assign mc_avail_o = 1'b1;

//  -----------------------------------------------------------------------
//  -- FSM controller
//  -----------------------------------------------------------------------
	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			state                     <= IDLE;
			cc_update_ldst_valid      <= 1'b0;
			cc_wakeup                 <= 1'b0;
			n2m_request_read          <= 1'b0;
			n2m_request_write         <= 1'b0;
			granted_read              <= 1'b0;
			granted_write             <= 1'b0;
			mem_instr_request_valid   <= 1'b0;
		end else begin
			cc_update_ldst_valid      <= 1'b0;
			cc_wakeup                 <= 1'b0;
			n2m_request_read          <= 1'b0;
			n2m_request_write         <= 1'b0;
			mem_instr_request_valid   <= 1'b0;

			case ( state )
				IDLE: begin
					if (grants[LOAD]) begin
						granted_read          <= 1'b1;
						granted_write         <= 1'b0;
						granted_need_snoop    <= 1'b1;
						granted_need_hit_miss <= 1'b0;
						granted_wakeup        <= 1'b1;
						granted_thread_id     <= ci_load_request_thread_id;
						granted_address       <= ci_load_request_address;
					end else if (grants[STORE]) begin
						granted_read          <= 1'b1;
						granted_write         <= 1'b0;
						granted_need_snoop    <= 1'b1;
						granted_need_hit_miss <= 1'b0;
						granted_wakeup        <= 1'b1;
						granted_thread_id     <= ci_store_request_thread_id;
						granted_address       <= ci_store_request_address;
					end else if (grants[REPLACEMENT]) begin
						granted_read          <= 1'b0;
						granted_write         <= 1'b1;
						granted_need_snoop    <= 1'b0;
						granted_wakeup        <= 1'b0;
						granted_address       <= ci_replacement_request_address;
						granted_cache_line    <= ci_replacement_request_cache_line;
						granted_dirty_mask    <= ci_replacement_request_dirty_mask;
					end else if (grants[FLUSH]) begin
						granted_read          <= 1'b0;
						granted_write         <= 1'b1;
						granted_need_snoop    <= 1'b1;
						granted_need_hit_miss <= 1'b1;
						granted_wakeup        <= 1'b0;
						granted_address       <= ci_flush_request_address;
						granted_cache_line    <= ci_flush_request_cache_line;
						granted_dirty_mask    <= ci_flush_request_dirty_mask;
					end else if (grants[DINV]) begin
						granted_read          <= 1'b0;
						granted_write         <= 1'b1;
						granted_need_snoop    <= 1'b1;
						granted_need_hit_miss <= 1'b1;
						granted_wakeup        <= 1'b1;
						granted_thread_id     <= ci_dinv_request_thread_id;
						granted_address       <= ci_dinv_request_address;
						granted_cache_line    <= ci_dinv_request_cache_line;
						granted_dirty_mask    <= ci_dinv_request_dirty_mask;
					end else if (grants[INSTR]) begin
						granted_read          <= 1'b1;
						granted_write         <= 1'b0;
						granted_need_snoop    <= 1'b0;
						granted_wakeup        <= 1'b0;
						granted_address       <= instr_req_addr;
					end else if (grants[IOM]) begin
						granted_read          <= iom_request_out.operation == IO_READ;
						granted_write         <= iom_request_out.operation == IO_WRITE;
						granted_need_snoop    <= 1'b0;
						granted_wakeup        <= iom_request_out.operation == IO_READ;
						granted_thread_id     <= iom_request_out.thread;
						granted_address       <= iom_request_out.address;
						granted_cache_line    <= {{{$bits(dcache_line_t) - $bits(register_t)}{1'b0}}, iom_request_out.data};
						granted_dirty_mask    <= {{{$bits(dcache_store_mask_t) - 4}{1'b0}}, 4'b1111};
					end

					if (|grants) begin
						state                 <= SEND_REQ;
					end

					grants_reg              <= grants;
				end

				SEND_REQ: begin
					if (execute_req) begin
						if (m2n_request_available) begin
							n2m_request_address <= granted_address;
							n2m_request_read    <= granted_read;
							n2m_request_write   <= granted_write;

							if (granted_read) begin
								state <= WAIT_RESP;
							end else begin
								state <= IDLE;

								if (grants_reg[DINV]) begin
									cc_update_ldst_valid       <= 1'b1;
									cc_update_ldst_way         <= way_matched_reg;
									cc_update_ldst_address     <= granted_address;
									cc_update_ldst_privileges  <= dcache_privileges_t'(0);
									cc_update_ldst_command     <= CC_UPDATE_INFO_DATA;
								end

								if (granted_wakeup) begin
									cc_wakeup           <= 1'b1;
								end
							end
						end else begin
							// snoop is successful, next cycle we don't need to check it
							granted_need_snoop <= 1'b0;
							state              <= SEND_REQ;
						end
					end else begin
						state <= IDLE;

						if (granted_wakeup) begin
							cc_wakeup           <= 1'b1;
						end
					end
				end

				WAIT_RESP: begin
					if (m2n_response_valid) begin
						state <= IDLE;

						// handle req
						if (grants_reg[INSTR]) begin
							mem_instr_request_data_in <= m2n_response_data_swap;
							mem_instr_request_valid   <= 1'b1;
						end else if (grants_reg[LOAD] | grants_reg[STORE]) begin
							cc_update_ldst_valid       <= 1'b1;
							cc_update_ldst_way         <= counter_way[granted_address.index];
							cc_update_ldst_address     <= granted_address;
							cc_update_ldst_privileges  <= dcache_privileges_t'(2'b11);
							cc_update_ldst_store_value <= m2n_response_data_swap;
							cc_update_ldst_command     <= ways_full ? CC_REPLACEMENT : CC_UPDATE_INFO_DATA;
						end

						if (granted_wakeup) begin
							cc_wakeup                  <= 1'b1;
						end
					end
				end
			endcase
		end
	end

	// Combinatorial outputs
	always_comb begin
		cc_snoop_tag_valid <= 1'b0;
		cc_snoop_tag_set   <= dcache_set_t'( 1'bX );

		dequeue_instr                  <= 1'b0;
		dequeue_iom                    <= 1'b0;
		iom_resp_enqueue               <= 1'b0;
		cc_dequeue_store_request       <= 1'b0;
		cc_dequeue_load_request        <= 1'b0;
		cc_dequeue_replacement_request <= 1'b0;
		cc_dequeue_flush_request       <= 1'b0;
		cc_dequeue_dinv_request        <= 1'b0;
		update_counter_way             <= 1'b0;

		case ( state )
			IDLE: begin
				if (grants[LOAD]) begin
					cc_snoop_tag_valid <= 1'b1;
					cc_snoop_tag_set   <= ci_load_request_address.index;
				end else if (grants[STORE]) begin
					cc_snoop_tag_valid <= 1'b1;
					cc_snoop_tag_set   <= ci_store_request_address.index;
				end else if (grants[FLUSH]) begin
					cc_snoop_tag_valid <= 1'b1;
					cc_snoop_tag_set   <= ci_flush_request_address.index;
				end else if (grants[DINV]) begin
					cc_snoop_tag_valid <= 1'b1;
					cc_snoop_tag_set   <= ci_dinv_request_address.index;
				end 
			end

			SEND_REQ: begin
				if (execute_req) begin
					if (m2n_request_available) begin
						if (grants_reg[REPLACEMENT]) begin
							cc_dequeue_replacement_request <= 1'b1;
						end else if (grants_reg[FLUSH]) begin
							cc_dequeue_flush_request       <= 1'b1;
						end else if (grants_reg[DINV]) begin
							cc_dequeue_dinv_request        <= 1'b1;
						end else if (grants_reg[IOM] & iom_request_out.operation == IO_WRITE) begin
							dequeue_iom                    <= 1'b1;
						end
					end
				end else begin
					if (grants_reg[LOAD]) begin
						cc_dequeue_load_request        <= 1'b1;
					end else if (grants_reg[STORE]) begin
						cc_dequeue_store_request       <= 1'b1;
					end else if (grants_reg[FLUSH]) begin
						cc_dequeue_flush_request       <= 1'b1;
					end else if (grants_reg[DINV]) begin
						cc_dequeue_dinv_request        <= 1'b1;
					end
				end
			end

			WAIT_RESP: begin
				if (m2n_response_valid) begin
					if (grants_reg[INSTR]) begin
						dequeue_instr <= 1'b1;
					end else if (grants_reg[STORE]) begin
						cc_dequeue_store_request <= 1'b1;
						update_counter_way       <= 1'b1;
					end else if (grants_reg[LOAD]) begin
						cc_dequeue_load_request  <= 1'b1;
						update_counter_way       <= 1'b1;
					end else if (grants_reg[IOM]) begin
						dequeue_iom              <= 1'b1;
						iom_resp_enqueue         <= 1'b1;
					end
				end
			end
		endcase
	end

//  -----------------------------------------------------------------------
//  -- Way Counter
//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			counter_way <= '{default : '0};
		else
			if ( update_counter_way )
				counter_way[granted_address.index] <= counter_way[granted_address.index] + 1;

`ifdef DISPLAY_COHERENCE

	always_comb begin
		if ( (|grants) & ~reset ) begin
			$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
			$fdisplay( `DISPLAY_COHERENCE_VAR, "Cache Controller - [Time %.16d]", $time( ) );

			if ( grants[FLUSH] ) begin
				print_flush( ci_flush_request_address );
			end else if ( grants[DINV] ) begin
				print_dinv ( ci_dinv_request_address, ci_dinv_request_thread_id );
			end else if ( grants[REPLACEMENT] ) begin
				print_replacement( ci_replacement_request_address, ci_replacement_request_thread_id );
			end else if ( grants[STORE] ) begin
				print_store( ci_store_request_address, ci_store_request_thread_id );
			end else if ( grants[LOAD] ) begin
				print_load( ci_load_request_address, ci_load_request_thread_id );
			end

			$fflush( `DISPLAY_COHERENCE_VAR );
		end
	end

`endif

endmodule
