`timescale 1ns / 1ps

module uart_router(
		input  clk,
		input  reset,

		input        [31:0] command_word_i,
		input               command_valid_i,
		output logic        command_ready_o,

		output logic [31:0] command_word_o,
		output logic        command_valid_o,
		input               command_ready_i,

		output logic [31:0] port_0_word_o,
		output logic        port_0_valid_o,
		input               port_0_ready_i,

		input        [31:0] port_0_word_i,
		input               port_0_valid_i,
		output logic        port_0_ready_o,

		output logic [31:0] port_1_word_o,
		output logic        port_1_valid_o,
		input               port_1_ready_i,

		input        [31:0] port_1_word_i,
		input               port_1_valid_i,
		output logic        port_1_ready_o
	);

	typedef enum {
		IDLE,
		RUNNING
	} state_t;

	state_t dn_state, up_state;
	logic [15:0] word_cnt;
	logic [15:0] output_port;

	// Downstream logic

	always_ff @(posedge clk) begin
		if (reset) begin
			dn_state      <= IDLE;
			word_cnt      <= 'd0;
			output_port   <= 'd0;
		end else begin
			case (dn_state)
				IDLE: begin
					if (command_valid_i) begin
						output_port <= command_word_i[15:0];
						word_cnt    <= command_word_i[31:16];
						dn_state    <= RUNNING;
					end
				end

				RUNNING: begin
					if (command_valid_i) begin
						if ((output_port == 0 && port_0_ready_i) | (output_port == 1 && port_1_ready_i)) begin
							word_cnt <= word_cnt - 16'd1;

							if (word_cnt == 16'd1) begin
								dn_state <= IDLE;
							end
						end
					end
				end
			endcase
		end
	end

	assign port_0_word_o = command_word_i;
	assign port_1_word_o = command_word_i;

	always_comb begin
		port_0_valid_o  <= 1'd0;
		port_1_valid_o  <= 1'd0;

		command_ready_o <= 1'd0;

		case (dn_state)
			IDLE: begin
				if (command_valid_i) begin
					command_ready_o <= 1'd1;
				end
			end

			RUNNING: begin
				if (command_valid_i) begin
					if (output_port == 0) begin
						port_0_valid_o  <= 1'd1;

						if (port_0_ready_i) begin
							command_ready_o <= 1'd1;
						end
					end else if (output_port == 1) begin
						port_1_valid_o  <= 1'd1;

						if (port_1_ready_i) begin
							command_ready_o <= 1'd1;
						end
					end
				end
			end
		endcase
	end

	// Upstream logic

	always_ff @(posedge clk) begin
		if (reset) begin
			up_state      <= IDLE;
		end else begin
			case (up_state)
				IDLE: begin
					if ((port_0_valid_i | port_1_valid_i) & command_ready_i) begin
						up_state    <= RUNNING;
					end
				end

				RUNNING: begin
					if (command_ready_i) begin
						up_state <= IDLE;
					end
				end
			endcase
		end
	end

	always_comb begin
		command_valid_o <= 1'b0;
		command_word_o  <= {32{1'bX}};
		port_0_ready_o  <= 1'b0;
		port_1_ready_o  <= 1'b0;

		case (up_state)
			IDLE: begin
				if (port_0_valid_i) begin
					command_valid_o <= 1'b1;
					command_word_o  <= 32'h00010000;
				end else if (port_1_valid_i) begin
					command_valid_o <= 1'b1;
					command_word_o  <= 32'h00010001;
				end
			end

			RUNNING: begin
				if (port_0_valid_i) begin
					command_valid_o <= 1'b1;
					command_word_o  <= port_0_word_i;

					if (command_ready_i) begin
						port_0_ready_o <= 1'b1;
					end
				end else if (port_1_valid_i) begin
					command_valid_o <= 1'b1;
					command_word_o  <= port_1_word_i;

					if (command_ready_i) begin
						port_1_ready_o <= 1'b1;
					end
				end
			end
		endcase
	end

endmodule
