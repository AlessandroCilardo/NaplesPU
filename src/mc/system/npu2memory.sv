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
`include "npu_debug_log.sv"
`include "npu_network_defines.sv"
`include "npu_coherence_defines.sv"

/*
 * This module manages the communication between memory and the tile_mc
 */

module npu2memory #(
		parameter TILE_ID             = 0,
		parameter SWAPEND             = 0,
		parameter MEM_ADDRESS_WIDTH = 32,
		parameter MEM_DATA_WIDTH    = 512 )
	(
		input                                                              clk,
		input                                                              reset,
		input                                                              enable,

		// Requests from NPU NI
		input  coherence_forwarded_message_t                               ni_forwarded_request,
		input  logic                                                       ni_forwarded_request_valid,
		output logic                                                       n2m_forwarded_request_available,
		output logic                                                       n2m_forwarded_request_consumed,

		input  coherence_response_message_t                                ni_response,
		input  logic                                                       ni_response_valid,
		output logic                                                       n2m_response_consumed,
		output logic 													   n2m_response_available,

		// Read responses to NPU NI
		output coherence_response_message_t                                n2m_response,
		output logic                                                       n2m_response_valid,
		output logic                                                       n2m_response_has_data,
		output logic                                                       n2m_response_to_cc_valid,
		output tile_address_t                                              n2m_response_to_cc,
		output logic                                                       n2m_response_to_dc_valid,
		output tile_address_t                                              n2m_response_to_dc,
		input  logic                                                       ni_response_network_available,

		// RW requests to MEM NI
		output logic                         [MEM_ADDRESS_WIDTH - 1 : 0]   n2m_request_address,
		output logic                         [MEM_DATA_WIDTH - 1 : 0]      n2m_request_data,
		output logic                                           [63 : 0]    n2m_request_dirty_mask,
		output logic                                                       n2m_request_read,
		output logic                                                       n2m_request_write,
		output logic                                                       n2m_request_is_instr,
		input  logic                                                       m2n_request_read_available,
		input  logic                                                       m2n_request_write_available,

		// Read responses from MEM NI
		input  logic                                                       m2n_response_valid,
		input  logic                         [MEM_ADDRESS_WIDTH - 1 : 0]   m2n_response_address,
		input  logic                         [MEM_DATA_WIDTH - 1 : 0]      m2n_response_data,
		output logic                                                       n2m_avail
	);

	localparam NUM_REQ = 2;
	localparam FIFO_LENGTH = 16;

    logic                                                    accept_fwd_req;
    logic                                                    accept_resp;
	logic                                                    request_is_valid, can_issue_response, pending_resp_fifo;
	logic                                                    request_is_read, request_is_write;
	logic                         [NUM_REQ - 1 : 0]          request_oh;
	logic                         [NUM_REQ - 1 : 0]          grant_oh;
	logic                                                    n2m_response_enqueued;
	logic                                                    n2m_forwarded_request_enqueued;

	coherence_response_message_t                             pending_response_out;
	coherence_forwarded_message_t                            pending_fwd_request_out;
	logic                                                    pending_read;
	logic                                                    response_fifo_full, fwd_request_fifo_full;
	logic                                                    response_fifo_empty, fwd_request_fifo_empty;
	logic                                                    response_fifo_dequeue_en, fwd_request_fifo_dequeue_en;
	logic                                                    mc_response_fifo_full;
	logic                         [MEM_DATA_WIDTH - 1 : 0] mc_response_fifo_out;
	logic                                                    mc_response_fifo_empty;

	logic                         [MEM_DATA_WIDTH - 1 : 0] m2n_response_data_swap;
	logic                         [MEM_DATA_WIDTH - 1 : 0] out_data_swap;

//  -----------------------------------------------------------------------
//  -- MEM to NaplesPU
//  -----------------------------------------------------------------------

	// Endian swap vector data
	genvar                                                   swap_word;
	generate
		if (SWAPEND) begin

			for ( swap_word = 0; swap_word < 16; swap_word++ ) begin : swap_word_gen
				assign m2n_response_data_swap[swap_word * 32 +: 8]      = m2n_response_data[swap_word * 32 + 24 +: 8];
				assign m2n_response_data_swap[swap_word * 32 + 8 +: 8]  = m2n_response_data[swap_word * 32 + 16 +: 8];
				assign m2n_response_data_swap[swap_word * 32 + 16 +: 8] = m2n_response_data[swap_word * 32 + 8 +: 8];
				assign m2n_response_data_swap[swap_word * 32 + 24 +: 8] = m2n_response_data[swap_word * 32 +: 8];

				assign out_data_swap[swap_word * 32 +: 8]               = pending_response_out.data[swap_word * 32 + 24 +: 8];
				assign out_data_swap[swap_word * 32 + 8 +: 8]           = pending_response_out.data[swap_word * 32 + 16 +: 8];
				assign out_data_swap[swap_word * 32 + 16 +: 8]          = pending_response_out.data[swap_word * 32 + 8 +: 8];
				assign out_data_swap[swap_word * 32 + 24 +: 8]          = pending_response_out.data[swap_word * 32 +: 8];
			end

		end else begin

			assign m2n_response_data_swap = m2n_response_data;
			assign out_data_swap          = pending_response_out.data;

		end
	endgenerate

	sync_fifo #(
		.WIDTH                 ( MEM_DATA_WIDTH ),
		.SIZE                  ( 2                ),
		.ALMOST_FULL_THRESHOLD ( 1                )
	)
	fifo_from_memory (
		.clk         ( clk                         ),
		.reset       ( reset                       ),
		.flush_en    ( 1'b0                        ),
		.full        (                             ),
		.almost_full ( mc_response_fifo_full       ),
		.enqueue_en  ( m2n_response_valid          ),
		.value_i     ( m2n_response_data_swap      ),
		.empty       ( mc_response_fifo_empty      ),
		.almost_empty(                             ),
		.dequeue_en  ( fwd_request_fifo_dequeue_en ),
		.value_o     ( mc_response_fifo_out        )
	);

	assign n2m_avail                       = ~mc_response_fifo_full;
	assign can_issue_response              = ~mc_response_fifo_empty & ni_response_network_available;
	assign pending_resp_fifo 			   = ~mc_response_fifo_empty;

	always_ff @( posedge clk ) begin
		if ( ~reset )
		begin
`ifdef DISPLAY_MEMORY_CONTROLLER
			if ( m2n_response_valid & ~mc_response_fifo_full ) begin
				$display( "[Time %t] [MC] Response from memory enqueued", $time() );
			end
`endif
		end
	end 

	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			n2m_response_valid       <= 1'b0;
			n2m_response_to_dc_valid <= 1'b0;
			n2m_response_to_cc_valid <= 1'b0;
		end else begin
			n2m_response_to_dc_valid <= ( request_is_write ) ? 1'b1 : (pending_fwd_request_out.packet_type == FWD_GETS & ~pending_fwd_request_out.req_is_uncoherent);
			n2m_response_to_cc_valid <= ( request_is_write ) ? 1'b0 : 1'b1;
			if ( can_issue_response | request_is_write)
				n2m_response_valid <= 1'b1;
			else
				n2m_response_valid <= 1'b0;
		end

	always_ff @ ( posedge clk ) begin
		if ( request_is_write ) begin
			n2m_response_has_data          <= 1'b0;
			n2m_response_to_cc             <= pending_response_out.source;
			n2m_response_to_dc             <= pending_response_out.memory_address[`ADDRESS_SIZE - 1 -: $clog2( `TILE_COUNT )];

			n2m_response.data              <= 0;
			n2m_response.from_directory    <= 1'b0;
			n2m_response.memory_address    <= pending_response_out.memory_address;
			n2m_response.source            <= tile_address_t'(TILE_ID);
			n2m_response.sharers_count     <= 0;
			n2m_response.packet_type       <= MC_ACK;
			n2m_response.requestor         <= pending_response_out.requestor;
			n2m_response.req_is_uncoherent <= pending_fwd_request_out.req_is_uncoherent;
		end 
		else begin
			n2m_response_has_data          <= 1'b1;
			n2m_response_to_cc             <= pending_fwd_request_out.source;
			n2m_response_to_dc             <= pending_fwd_request_out.memory_address[`ADDRESS_SIZE - 1 -: $clog2( `TILE_COUNT )];

			n2m_response.data              <= mc_response_fifo_out;
			n2m_response.from_directory    <= 1'b0;
			n2m_response.memory_address    <= pending_fwd_request_out.memory_address;
			n2m_response.source            <= tile_address_t'(TILE_ID);
			n2m_response.sharers_count     <= 0;
			n2m_response.packet_type       <= DATA;
			n2m_response.requestor         <= pending_fwd_request_out.requestor;
			n2m_response.req_is_uncoherent <= pending_fwd_request_out.req_is_uncoherent;
		end 
	end

	always_ff @ ( posedge clk ) begin
		if( n2m_response_valid )
		begin
			assert( (n2m_response.packet_type == MC_ACK) || (n2m_response.packet_type == DATA) ) else
				$error("[Time %t] [MC] Trying to send a message of type %s. Only MC_ACK or DATA admitted.", $time(), n2m_response.packet_type.name );

`ifdef DISPLAY_MEMORY_CONTROLLER
			if ( n2m_response.packet_type == MC_ACK)
			begin
				$display("[Time %t] [MC] Forwarding MC_ACK for address 0x%8h, ", $time(), n2m_response.memory_address);
			end

			else
			begin
				$display("[Time %t] [MC] Forwarding DATA from Memory Fifo for address 0x%8h, ", $time(), n2m_response.memory_address);
			end
`endif
		end
	end
	
//  -----------------------------------------------------------------------
//  -- NaplesPU to Memory - FIFOs
//  -----------------------------------------------------------------------

	sync_fifo #(
		.WIDTH                ( $bits( coherence_response_message_t ) ),
		.SIZE                 ( FIFO_LENGTH                           ),
		.ALMOST_FULL_THRESHOLD( FIFO_LENGTH - 1                       )
	)
	response_fifo (
		.clk         ( clk                      ),
		.reset       ( reset                    ),
		.flush_en    ( 1'b0                     ),
		.full        (                          ),
		.almost_full ( response_fifo_full       ),
		.enqueue_en  ( accept_resp              ),
		.value_i     ( ni_response              ),
		.empty       ( response_fifo_empty      ),
		.almost_empty(                          ),
		.dequeue_en  ( response_fifo_dequeue_en ),
		.value_o     ( pending_response_out     )
	);

    assign accept_resp            = ni_response_valid & ~response_fifo_full;
	assign n2m_response_consumed  = ~response_fifo_full & ni_response_valid;
	assign n2m_response_available = ~response_fifo_full;
	
	always_ff @( posedge clk ) begin
		if ( ~reset )
		begin
`ifdef DISPLAY_MEMORY_CONTROLLER
			if ( n2m_response_consumed ) begin
				$display( "[Time %t] [MC] Response of type %s equeued - Address: %h", $time(), ni_response.packet_type.name, ni_response.memory_address );
			end
`endif
		end
	end 

	// When a read request is scheduled to the MEM network, its source is stored in this FIFO. When the MEM
	// network responses this information is used to forward this response to the right requestor tile.
	sync_fifo #(
		.WIDTH                ( $bits( coherence_forwarded_message_t ) ),
		.SIZE                 ( FIFO_LENGTH                            ),
		.ALMOST_FULL_THRESHOLD( FIFO_LENGTH - 1                        )
	)
	fwd_request_fifo (
		.clk         ( clk                            ),
		.reset       ( reset                          ),
		.flush_en    ( 1'b0                           ),
		.full        (                                ),
		.almost_full ( fwd_request_fifo_full          ),
		.enqueue_en  ( accept_fwd_req           	  ),
		.value_i     ( ni_forwarded_request           ), 
		.empty       ( fwd_request_fifo_empty         ),
		.almost_empty(                                ),
		.dequeue_en  ( fwd_request_fifo_dequeue_en    ),
		.value_o     ( pending_fwd_request_out        )
	);

    assign accept_fwd_req                  = ni_forwarded_request_valid & ~fwd_request_fifo_full;
	assign n2m_forwarded_request_available = ~fwd_request_fifo_full;
	assign n2m_forwarded_request_consumed  = ~fwd_request_fifo_full & ni_forwarded_request_valid;

	always_ff @( posedge clk ) begin
		if ( ~reset )
		begin
`ifdef DISPLAY_MEMORY_CONTROLLER
			if ( n2m_forwarded_request_consumed ) begin
				$display( "[Time %t] [MC] Fwd message of type %s equeued - Address: %h", $time(), ni_forwarded_request.packet_type.name, ni_forwarded_request.memory_address );
			end
`endif
		end
	end 

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			pending_read <= 1'b0;
		end else begin
			if ( fwd_request_fifo_dequeue_en ) begin
				pending_read <= 1'b0;
			end else if( grant_oh[1] & m2n_request_read_available ) begin
				pending_read <= 1'b1;
			end
		end
	end

//  -----------------------------------------------------------------------
//  -- NaplesPU to Memory
//  -----------------------------------------------------------------------
	assign request_oh                      = {~fwd_request_fifo_empty, ~response_fifo_empty};

	round_robin_arbiter #(
		.SIZE( NUM_REQ )
	)
	u_round_robin_arbiter (
		.clk         ( clk                                                    ),
		.reset       ( reset                                                  ),
		.en          ( fwd_request_fifo_dequeue_en | response_fifo_dequeue_en ),
		.requests    ( request_oh                                             ),
		.decision_oh ( grant_oh                                               )
	);

	// A request is valid if there is a pending request from NI and pending request FIFO is not full
	assign request_is_valid                = |request_oh & enable & ~pending_read;
	assign request_is_read                 = request_is_valid & ( pending_fwd_request_out.packet_type == FWD_GETS | pending_fwd_request_out.packet_type == FWD_GETM ) & grant_oh[1];
	assign request_is_write                = m2n_request_write_available & ni_response_network_available & ~pending_resp_fifo & request_is_valid & pending_response_out.packet_type == WB & grant_oh[0];

	assign fwd_request_fifo_dequeue_en     = can_issue_response & pending_read;
	assign response_fifo_dequeue_en        = request_is_write;

	always_ff @(posedge clk, posedge reset)  begin
		if (reset) begin
			n2m_request_address = {MEM_ADDRESS_WIDTH{1'b0}};
		end else begin
			if ( request_is_read ) begin
				n2m_request_address = pending_fwd_request_out.memory_address;
			end else if( request_is_write ) begin
				n2m_request_address = pending_response_out.memory_address;
			end
		end
	end

	always_ff @(posedge clk, posedge reset)  begin
		if (reset) begin
			n2m_request_dirty_mask = {64{1'b0}};
		end else begin
			if( request_is_write ) begin
				n2m_request_dirty_mask = pending_response_out.dirty_mask;
			end
		end
	end

	always_ff @(posedge clk) begin
		if (m2n_request_read_available)
			n2m_request_read             = request_is_read;
		else
			n2m_request_read             = 1'b0;

		if (m2n_request_write_available)
			n2m_request_write            = request_is_write;
		else
			n2m_request_write            = 1'b0;

		n2m_request_is_instr            = pending_fwd_request_out.req_is_uncoherent;
		n2m_request_data                = out_data_swap;
	end

`ifdef DISPLAY_COHERENCE

	always_ff @( posedge clk ) begin

		if ( ( grant_oh[0] & response_fifo_dequeue_en ) | ( grant_oh[1] & fwd_request_fifo_dequeue_en & pending_fwd_request_out.req_is_uncoherent ) ) begin
			$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
			$fdisplay( `DISPLAY_COHERENCE_VAR, "Memory Controller - [Time %.16d] [TILE %.2d] - Message Received", $time( ), TILE_ID );

			if ( grant_oh[0] )
				print_resp( pending_response_out );
			else if ( grant_oh[1] & ~pending_fwd_request_out.req_is_uncoherent )
				print_fwd_req( pending_fwd_request_out );

			$fflush( `DISPLAY_COHERENCE_VAR );
		end

		if ( ~reset & ( n2m_response_valid ) ) begin
			if ( n2m_response_valid & ~n2m_response.req_is_uncoherent ) begin
				$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
				$fdisplay( `DISPLAY_COHERENCE_VAR, "Memory Controller - [Time %.16d] [TILE %.2d] - Message Sent", $time( ), TILE_ID );
				$fdisplay( `DISPLAY_COHERENCE_VAR, "Destination: %h", n2m_response_to_cc );
				print_resp( n2m_response );

				$fflush( `DISPLAY_COHERENCE_VAR );
			end
		end
	end

`endif

coherence_forwarded_message_t                          last_fwd_injected;
coherence_response_message_t                           last_response_injected;
logic												   is_last_req_fwd;

always_ff @ ( posedge clk )
begin
	if (fwd_request_fifo_dequeue_en)
	begin
		last_fwd_injected <= pending_fwd_request_out;
		is_last_req_fwd <= 1'b1;
	end
end

always_ff @ ( posedge clk )
begin
	if (response_fifo_dequeue_en)
	begin
		last_response_injected <= pending_response_out;
		is_last_req_fwd <= 1'b0;
	end
end

always_ff @ ( posedge clk )
begin
	if (n2m_response_valid && is_last_req_fwd)
	begin
	 	assert(last_fwd_injected.memory_address == n2m_response.memory_address) else
		$error("[Time %t] [MC] Wrong response received for fwd request. Address is %8h. Expected was %8h", $time(), n2m_response.memory_address, last_fwd_injected.memory_address);
	end else if (n2m_response_valid && ~is_last_req_fwd)
	begin
		assert(last_response_injected.memory_address == n2m_response.memory_address) else
		$error("[Time %t] [MC] Wrong response received for response request. Address is %8h. Expected was %8h", $time(), n2m_response.memory_address, last_response_injected.memory_address);
	end
end
endmodule
