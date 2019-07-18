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

module dummy_acc(
		// Command, block and AXI clock and reset signals
		input                  clk,
		input                  reset,

		// Command interface
		input  [31:0]          command_word_i,
		input                  command_valid_i,
		output logic           command_ready_o,

		output logic [31:0]    command_word_o,
		output logic           command_valid_o,
		input                  command_ready_i,

		input  logic           mem2acc_response_valid,
		input  logic [31 : 0]  mem2acc_response_address,
		input  logic [511 : 0] mem2acc_response_data,
		output logic           acc_available,

		// To Memory
		output logic [31 : 0]  acc2mem_request_address,
		output logic [63 : 0]  acc2mem_request_dirty_mask,
		output logic [511 : 0] acc2mem_request_data,
		output logic           acc2mem_request_read,
		output logic           acc2mem_request_write,
		input  logic           mem_request_available
	);

	typedef enum {
		IDLE,
		RUNNING
	} state_t;

	state_t current_state;
	logic [31:0] cnt;
	logic        can_run;

	assign can_run         = command_valid_i & mem_request_available;

	assign acc_available   = 1'b1;

	always_ff @(posedge clk) begin
		if (reset) begin
			acc2mem_request_read  <= 1'b0;
			acc2mem_request_write <= 1'b0;
			cnt                   <= 32'd1;
			current_state         <= IDLE;
		end else begin
			acc2mem_request_write <= 1'b0;

			case (current_state)
				IDLE: begin
					if (can_run) begin
						acc2mem_request_address    <= command_word_i;
						acc2mem_request_dirty_mask <= {64{1'b1}};
						acc2mem_request_data       <= {16{cnt}};
						acc2mem_request_write      <= 1'b1;
						cnt                        <= cnt + 32'd1;
						current_state              <= RUNNING;
					end
				end

				RUNNING: begin
					if (command_ready_i) begin
						current_state              <= IDLE;
					end
				end
			endcase
		end
	end

	always_comb begin
		command_valid_o <= 1'b0;
		command_word_o  <= {32{1'bX}};
		command_ready_o <= 1'b0;

		case (current_state)
			IDLE: begin
				if (can_run) begin
					command_ready_o <= 1'b1;
				end
			end

			RUNNING: begin
				command_valid_o <= 1'b1;
				command_word_o  <= 32'h00000ACC;
			end
		endcase
	end

endmodule
