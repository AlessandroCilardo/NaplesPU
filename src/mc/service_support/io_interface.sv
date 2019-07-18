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
`include "npu_message_service_defines.sv"
`include "npu_debug_log.sv"

module io_interface # (
		parameter TILE_ID = 0
	) (
		input                                      clk,
		input                                      reset,

		// Core IO interface - Master port
		output logic                               io_intf_available_to_core,
		input  logic                               ldst_io_valid,
		input  thread_id_t                         ldst_io_thread,
		input  logic [$bits(io_operation_t)-1 : 0] ldst_io_operation,
		input  address_t                           ldst_io_address,
		input  register_t                          ldst_io_data,
		output logic                               io_intf_resp_valid,
		output thread_id_t                         io_intf_wakeup_thread,
		output register_t                          io_intf_resp_data,
		input  logic                               ldst_io_resp_consumed,

		// Slave port
		input  logic                               slave_available_to_io_intf,
		output logic                               io_intf_valid,
		output thread_id_t                         io_intf_thread,
		output logic [$bits(io_operation_t)-1 : 0] io_intf_operation,
		output address_t                           io_intf_address,
		output register_t                          io_intf_data,
		input  logic                               slave_resp_valid,
		input  thread_id_t                         slave_wakeup_thread,
		input  register_t                          slave_resp_data,
		output logic                               io_intf_resp_consumed,

		// Network interface
		input  logic                               ni_io_network_available,
		output io_message_t                        io_intf_message_out,
		output logic                               io_intf_message_out_valid,
		output tile_mask_t                         io_intf_destination_valid,

		output logic                               io_intf_message_consumed,
		input io_message_t                         ni_io_message,
		input logic                                ni_io_message_valid
	);

	// Request handling signals
	logic                      can_issue_req;
	io_message_t               pending_req[`THREAD_NUMB];
	logic [`THREAD_NUMB-1 : 0] pending_req_valid;

	logic                      can_issue_resp;
	logic                      resp_pending;
	io_message_t               saved_mess;

	logic                      can_issue_msg;
	logic                      msg_is_reply;
	logic                      issue_req, issue_msg;

	tile_id_t                  dest_tile_idx;
	tile_mask_t                dest_tile_oh;

	// FIFO from Core
	logic req_almost_full, req_empty;
	io_message_t req_value_i, req_value_o;

	assign io_intf_available_to_core = ~req_almost_full,
	       req_value_i.io_source     = tile_id_t'(TILE_ID),
	       req_value_i.io_thread     = ldst_io_thread,
	       req_value_i.io_operation  = io_operation_t'(ldst_io_operation),
		   req_value_i.io_address    = ldst_io_address,
		   req_value_i.io_data       = ldst_io_data;

	sync_fifo #(
		.WIDTH                 ( $bits( io_message_t ) ),
		.SIZE                  ( `THREAD_NUMB          ),
		.ALMOST_FULL_THRESHOLD ( `THREAD_NUMB - 2      )
	)
	req_fifo (
		.almost_empty(                 ),
		.almost_full ( req_almost_full ),
		.clk         ( clk             ),
		.dequeue_en  ( issue_req       ),
		.empty       ( req_empty       ),
		.enqueue_en  ( ldst_io_valid   ),
		.flush_en    ( 1'd0            ),
		.full        (                 ),
		.reset       ( reset           ),
		.value_i     ( req_value_i     ),
		.value_o     ( req_value_o     )
	);

	// FIFO to Core
	logic resp_almost_full, resp_enq, resp_full, resp_empty;
	io_message_t resp_value_o;

	assign io_intf_resp_valid    = ~resp_empty,
	       io_intf_wakeup_thread = resp_value_o.io_thread,
	       io_intf_resp_data     = resp_value_o.io_data;

	assign resp_enq              = issue_msg & msg_is_reply;

	sync_fifo #(
		.WIDTH                 ( $bits( io_message_t ) ),
		.SIZE                  ( `THREAD_NUMB          )
	)
	resp_fifo (
		.almost_empty(                       ),
		.almost_full (                       ),
		.clk         ( clk                   ),
		.dequeue_en  ( ldst_io_resp_consumed ),
		.empty       ( resp_empty            ),
		.enqueue_en  ( resp_enq              ),
		.flush_en    ( 1'd0                  ),
		.full        ( resp_full             ),
		.reset       ( reset                 ),
		.value_i     ( ni_io_message         ),
		.value_o     ( resp_value_o          )
	);

	// Request handling logic
	assign can_issue_req  = ~req_empty & ~pending_req_valid[req_value_o.io_thread] & ni_io_network_available;
	assign can_issue_resp = slave_resp_valid & ni_io_network_available;

	// Message handling logic
	assign can_issue_msg = ni_io_message_valid & (~msg_is_reply | ~resp_full);
	assign msg_is_reply  = ni_io_message_valid & ni_io_message.io_source == tile_id_t'(TILE_ID);
	assign issue_req = can_issue_req & ~can_issue_msg;
	assign issue_msg = can_issue_msg;

	always_comb begin
		io_intf_message_consumed <= 1'b0;
		io_intf_resp_consumed    <= 1'b0;

		if (issue_msg) begin
			if (msg_is_reply) begin
				io_intf_message_consumed <= ~resp_full;
			end else if (ni_io_message.io_operation == IO_WRITE) begin
				io_intf_message_consumed <= 1'b1;
			end else if (can_issue_resp) begin
				io_intf_message_consumed <= 1'b1;
				io_intf_resp_consumed    <= 1'b1;
			end
		end
	end

	// Request bookkeeping logic
	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			pending_req_valid <= {`THREAD_NUMB{1'b0}};
		end else begin
			if (issue_req & req_value_o.io_operation == IO_READ) begin
				pending_req_valid[req_value_o.io_thread] <= 1'b1;
			end else if (resp_enq) begin
				pending_req_valid[ni_io_message.io_thread]  <= 1'b0;
			end
		end
	end

	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			resp_pending <= 1'b0;
		end else begin
			if (~resp_pending) begin
				if (issue_msg & ~msg_is_reply & ni_io_message.io_operation != IO_WRITE) begin
					resp_pending <= 1'b1;
					saved_mess   <= ni_io_message;
				end
			end else if (slave_resp_valid) begin
				resp_pending <= 1'b0;
			end
		end
	end

	always_ff @(posedge clk or posedge reset) begin
		if (reset) begin
			io_intf_message_out_valid     <= 1'b0;
		end else begin
			io_intf_message_out_valid   <= 1'b0;

			if (~resp_pending & issue_req) begin
				io_intf_message_out_valid   <= 1'b1;
				io_intf_destination_valid   <= dest_tile_oh;

				io_intf_message_out         <= req_value_o;
			end else if (can_issue_resp) begin
				io_intf_message_out_valid   <= 1'b1;
				io_intf_destination_valid   <= dest_tile_oh;

				io_intf_message_out         <= saved_mess;
				io_intf_message_out.io_data <= slave_resp_data;
			end
		end
	end

	assign io_intf_valid     = issue_msg & ~msg_is_reply & ~resp_pending;
	assign io_intf_thread    = ni_io_message.io_thread;
	assign io_intf_operation = ni_io_message.io_operation;
	assign io_intf_address   = ni_io_message.io_address;
	assign io_intf_data      = ni_io_message.io_data;

	assign dest_tile_idx = issue_req ? `TILE_H2C_ID : saved_mess.io_source;

	idx_to_oh
	#(
		.NUM_SIGNALS( `NoC_X_WIDTH*`NoC_Y_WIDTH ),
		.DIRECTION  ( "LSB0"                    )
	)
	u_idx_to_oh
	(
		.one_hot( dest_tile_oh  ),
		.index  ( dest_tile_idx )
	);

`ifdef DISPLAY_IO

	always_ff @(posedge clk) begin
		if (issue_msg) begin
			print_io_msg(TILE_ID, ni_io_message, 0);
		end

		if (io_intf_message_out_valid) begin
			print_io_msg(TILE_ID, io_intf_message_out, 1);
		end
	end

`endif

endmodule
