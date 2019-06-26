`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/04/2018 12:33:58 PM
// Design Name: 
// Module Name: dummy_acc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


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
