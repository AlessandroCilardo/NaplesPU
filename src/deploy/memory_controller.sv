//            Copyright 2019 NaplesPU
//   
//   Redistribution and use in source and binary forms, with or without modification,
//   are permitted provided that the following conditions are met:
//   
//   1. Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//   
//   2. Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//   
//   3. Neither the name of the copyright holder nor the names of its contributors
//   may be used to endorse or promote products derived from this software
//   without specific prior written permission.
//   
//   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
//   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//   IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//   INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
//   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
//   HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
//   EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

`timescale 1ns / 1ps

module memory_controller #(
	C_AXI_DATA_WIDTH = 32
) (

		// Command, block and AXI clock and reset signals
		input                               clk,
		input                               reset,

		// Command interface
		input  [31:0]                       command_word_i,
		input                               command_valid_i,
		output logic                        command_ready_o,

		output logic [31:0]                 command_word_o,
		output logic                        command_valid_o,
		input                               command_ready_i,

		// Block interface
		input  logic [31 : 0]               blk_request_address,
		input  logic [63 : 0]               blk_request_dirty_mask,
		input  logic [511 : 0]              blk_request_data,
		input  logic                        blk_request_read,
		input  logic                        blk_request_write,
		output logic                        mc_available,

		output logic                        mc_response_valid,
		output logic [31 : 0]               mc_response_address,
		output logic [511 : 0]              mc_response_data,
		input  logic                        blk_available,

		// AXI write address channel signals
		input                               axi_awready, // Indicates slave is ready to accept
		output logic [3:0]                  axi_awid,    // Write ID
		output logic [31:0]                 axi_awaddr,  // Write address
		output logic [7:0]                  axi_awlen,   // Write Burst Length
		output logic [2:0]                  axi_awsize,  // Write Burst size
		output logic [1:0]                  axi_awburst, // Write Burst type
		output logic [1:0]                  axi_awlock,  // Write lock type
		output logic [3:0]                  axi_awcache, // Write Cache type
		output logic [3:0]                  axi_awqos,
		output logic [3:0]                  axi_awregion,
		output logic [2:0]                  axi_awprot,  // Write Protection type
		output logic                        axi_awvalid, // Write address valid

		// AXI write data channel signals
		input                                 axi_wready, // Write data ready
		output logic [3:0]                    axi_wid,    // Write ID tag
		output logic [C_AXI_DATA_WIDTH-1:0]   axi_wdata,  // Write data
		output logic [C_AXI_DATA_WIDTH/8-1:0] axi_wstrb,  // Write strobes
		output logic                          axi_wlast,  // Last write transaction
		output logic                          axi_wvalid, // Write valid

		// AXI write response channel signals
		input  [3:0]                        axi_bid,    // Response ID
		input  [1:0]                        axi_bresp,  // Write response
		input                               axi_bvalid, // Write reponse valid
		output logic                        axi_bready, // Response ready

		// AXI read address channel signals
		input                               axi_arready, // Read address ready
		output logic [3:0]                  axi_arid,    // Read ID
		output logic [31:0]                 axi_araddr,  // Read address
		output logic [7:0]                  axi_arlen,   // Read Burst Length
		output logic [2:0]                  axi_arsize,  // Read Burst size
		output logic [1:0]                  axi_arburst, // Read Burst type
		output logic [1:0]                  axi_arlock,  // Read lock type
		output logic [3:0]                  axi_arcache, // Read Cache type
		output logic [3:0]                  axi_arqos,
		output logic [3:0]                  axi_arregion,
		output logic [2:0]                  axi_arprot,  // Read Protection type
		output logic                        axi_arvalid, // Read address valid

		// AXI read data channel signals
		input  [3:0]                        axi_rid,    // Response ID
		input  [1:0]                        axi_rresp,  // Read response
		input                               axi_rvalid, // Read reponse valid
		input  [C_AXI_DATA_WIDTH-1:0]       axi_rdata,   // Read data
		input                               axi_rlast,   // Read last
		output logic                        axi_rready  // Read Response ready
	);

	typedef enum {
		IDLE,
		ADDRESS,
		WRITE_BURST,
		WRITE_BLOCK,
		WAIT_WRITE_ACK,
		READ_BURST,
		READ_BLOCK
	} state_t;

	typedef enum logic [1:0] {
		OKAY = 0,
		EXOKAY = 1,
		SLVERR = 2,
		DECERR = 3
	} axi_resp_t;

	localparam READ = 0;

	state_t current_state;

	logic is_read, is_burst;
	logic [7:0] burst_len, word_counter;
	logic [31:0] setup_buffer;

	logic [31 : 0]  fifo_blk_request_address;
	logic [63 : 0]  fifo_blk_request_dirty_mask;
	logic [511 : 0] fifo_blk_request_data;
	logic           fifo_blk_request_read;
	logic           fifo_blk_request_write;
	logic           fifo_blk_dequeue;

	assign axi_awid     = 4'd0;
	assign axi_awsize   = 3'd2;
	assign axi_awburst  = 2'd1;
	assign axi_awlock   = 2'd0;
	assign axi_awcache  = 4'd0;
	assign axi_awqos    = 4'd0;
	assign axi_awregion = 4'd0;
	assign axi_awprot   = 3'd0;

	assign axi_awlen    = setup_buffer[7:0];

	assign axi_wid      = 4'd0;

	assign axi_arid     = 4'd0;
	assign axi_arsize   = 3'd2;
	assign axi_arburst  = 2'd1;
	assign axi_arlock   = 2'd0;
	assign axi_arcache  = 4'd0;
	assign axi_arqos    = 4'd0;
	assign axi_arregion = 4'd0;
	assign axi_arprot   = 3'd0;

	assign axi_arlen    = setup_buffer[7:0];

	// Block input buffering
	logic input_fifo_almost_full, input_fifo_empty;

	sync_fifo #(
		.WIDTH                 ( 32 + 64 + 512 + 1 + 1 ),
		.SIZE                  ( 2 ),
		.ALMOST_FULL_THRESHOLD ( 1 )
	) input_fifo (
		.clk          ( clk ),
		.reset        ( reset ),
		.flush_en     ( 1'b0 ),
		.full         ( ),
		.almost_full  ( input_fifo_almost_full ),
		.enqueue_en   ( blk_request_read | blk_request_write ),
		.value_i      ( {blk_request_address, blk_request_dirty_mask, blk_request_data, blk_request_read, blk_request_write} ),
		.empty        ( input_fifo_empty ),
		.almost_empty ( ),
		.dequeue_en   ( fifo_blk_dequeue ),
		.value_o      ( {fifo_blk_request_address, fifo_blk_request_dirty_mask, fifo_blk_request_data, fifo_blk_request_read, fifo_blk_request_write} )
	);

	assign mc_available = ~input_fifo_almost_full;

	always_ff @(posedge clk) begin
		if (reset) begin
			current_state     <= IDLE;
			mc_response_valid <= 1'b0;
			is_read           <= 1'b0;
		end else begin
			mc_response_valid <= 1'b0;

			case (current_state)
				IDLE: begin
					if (command_valid_i) begin
						is_read       <= command_word_i[31] == READ;
						is_burst      <= 1'b1;
						setup_buffer  <= command_word_i;
						burst_len     <= command_word_i[7:0] + 8'd1;
						word_counter  <= 8'd0;
						current_state <= ADDRESS;
					end else if (~input_fifo_empty) begin
						is_read       <= fifo_blk_request_read;
						is_burst      <= 1'b0;
						setup_buffer  <= {24'd0, 8'd15};
						burst_len     <= 8'd16;
						word_counter  <= 8'd0;
						current_state <= ADDRESS;
					end
				end

				ADDRESS: begin
					if (is_burst) begin
						if (command_valid_i) begin
							if (is_read & axi_arready) begin
								current_state <= READ_BURST;
							end else if (~is_read & axi_awready) begin
								current_state <= WRITE_BURST;
							end
						end
					end else begin
						mc_response_address <= fifo_blk_request_address;

						if (is_read & axi_arready) begin
							current_state <= READ_BLOCK;
						end else if (~is_read & axi_awready) begin
							current_state <= WRITE_BLOCK;
						end
					end
				end

				WRITE_BURST: begin
					if (command_valid_i & command_ready_o) begin
						word_counter <= word_counter + 1;

						if (word_counter == burst_len - 1) begin
							current_state <= WAIT_WRITE_ACK;
						end
					end
				end

				WRITE_BLOCK: begin
					if (axi_wready) begin
						word_counter <= word_counter + 1;

						if (word_counter == burst_len - 1) begin
							current_state <= WAIT_WRITE_ACK;
						end
					end
				end

				WAIT_WRITE_ACK: begin
					if (axi_bvalid) begin
						current_state <= IDLE;
					end
				end

				READ_BURST: begin
					if (axi_rvalid & command_ready_i) begin
						word_counter <= word_counter + 1;

						if (word_counter == burst_len - 1) begin
							current_state <= IDLE;
						end
					end
				end

				READ_BLOCK: begin
					if (axi_rvalid) begin
						word_counter <= word_counter + 1;

						mc_response_data[word_counter * 32 +: 32] <= axi_rdata;

						if (((word_counter == burst_len - 1) | (word_counter == burst_len)) & blk_available) begin
							mc_response_valid <= 1'b1;
							current_state     <= IDLE;
						end
					end
				end
			endcase
		end
	end

	// combinatorial outputs
	always_comb begin
		command_ready_o                       <= 1'b0;
		fifo_blk_dequeue                      <= 1'b0;
		command_valid_o                       <= 1'b0;
		axi_awvalid                           <= 1'b0;
		axi_arvalid                           <= 1'b0;
		axi_wvalid                            <= 1'b0;
		axi_bready                            <= 1'b0;
		axi_wlast                             <= 1'b0;
		axi_rready                            <= 1'b0;

		axi_awaddr                            <= {32{1'bX}};
		axi_wdata                             <= {32{1'bX}};
		axi_wstrb                             <= {4{1'bX}};
		axi_araddr                            <= {32{1'bX}};

		case (current_state)
			IDLE: begin
				if (command_valid_i) begin
					command_ready_o <= 1'b1;
				end
			end

			ADDRESS: begin
				if (is_burst) begin
					if (command_valid_i) begin
						axi_arvalid                   <=  is_read;
						axi_awvalid                   <= ~is_read;
						axi_awaddr                    <= command_word_i;
						axi_araddr                    <= command_word_i;

						if (is_read & axi_arready) begin
							command_ready_o             <= 1'b1;
						end else if (~is_read & axi_awready) begin
							command_ready_o             <= 1'b1;
						end
					end
				end else begin
					axi_arvalid                     <=  is_read;
					axi_awvalid                     <= ~is_read;

					axi_awaddr                      <= {fifo_blk_request_address[31:6], {6'd0}};
					axi_araddr                      <= {fifo_blk_request_address[31:6], {6'd0}};
				end
			end

			WRITE_BURST: begin
				axi_wdata                         <= command_word_i;
				axi_wstrb                         <= 4'b1111;

				if (command_valid_i & axi_wready) begin
					axi_wvalid                      <= 1'b1;
					command_ready_o                 <= 1'b1;

					if (word_counter == burst_len - 1) begin
						axi_wlast                     <= 1'b1;
					end
				end
			end

			WRITE_BLOCK: begin
				axi_wdata                         <= fifo_blk_request_data[word_counter * 32 +: 32];
				axi_wstrb                         <= fifo_blk_request_dirty_mask[word_counter * 4 +: 4];

				if (axi_wready) begin
					axi_wvalid                      <= 1'b1;

					if (word_counter == burst_len - 1) begin
						axi_wlast                     <= 1'b1;
					end
				end
			end

			WAIT_WRITE_ACK: begin
				if (axi_bvalid) begin
					axi_bready                      <= 1'b1;
					fifo_blk_dequeue                <= ~is_burst;
				end
			end

			READ_BURST: begin
				if (axi_rvalid) begin
					axi_rready                      <= command_ready_i;
					command_valid_o                 <= 1'b1;
				end
			end

			READ_BLOCK: begin
				if (axi_rvalid) begin
					axi_rready                      <= 1'b1;

					if (word_counter == burst_len - 1) begin
						fifo_blk_dequeue              <= 1'b1;
					end
				end
			end
		endcase
	end

	assign command_word_o = axi_rdata;

endmodule
