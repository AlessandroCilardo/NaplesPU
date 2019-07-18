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

module io_device_test #(
		parameter ADDRESS_WIDTH = 32,
		parameter DATA_WIDTH    = 32,
		parameter BUS_WIDTH     = 512 )
	(
		input                                clk,
		input                                reset,

		// From System Bus
		input  logic [ADDRESS_WIDTH - 1 : 0] n2m_request_address,
		input  logic [BUS_WIDTH - 1 : 0]     n2m_request_data,
		input  logic                         n2m_request_read,
		input  logic                         n2m_request_write,
		input  logic                         mc_avail_o,

		// To System Bus
		output logic                         m2n_request_available,
		output logic                         m2n_response_valid,
		output logic [ADDRESS_WIDTH - 1 : 0] m2n_response_address,
		output logic [BUS_WIDTH - 1 : 0]     m2n_response_data

	);

    localparam BASE_ADDRESS  = 0;
    localparam REG_A_ADDRESS = BASE_ADDRESS + 1;
    localparam REG_B_ADDRESS = REG_A_ADDRESS + 1;
    localparam COUNTER_REG   = REG_B_ADDRESS + 1;

	logic [4 : 0]                 counter;
	logic [31 : 0]                real_counter;
	logic                         pending_request;
	logic                         write_base_reg, write_reg_a, write_reg_b;
	logic [DATA_WIDTH - 1 : 0]    base_reg;
	logic [DATA_WIDTH - 1 : 0]    reg_a;
	logic [DATA_WIDTH - 1 : 0]    reg_b;
	logic [ADDRESS_WIDTH - 1 : 0] pending_address;

	assign write_base_reg        = n2m_request_write & ( n2m_request_address[6 : 2] == BASE_ADDRESS );
	assign write_reg_a           = n2m_request_write & ( n2m_request_address[6 : 2] == REG_A_ADDRESS );
	assign write_reg_b           = n2m_request_write & ( n2m_request_address[6 : 2] == REG_B_ADDRESS );

	assign m2n_request_available = ( counter == 0 ) ? 1'b1 : 1'b0;

// --------------------------------------------------------------------------
// Read Mux
// --------------------------------------------------------------------------

	always_ff @ ( posedge clk )
		if ( n2m_request_read )
			pending_address <= n2m_request_address;

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			pending_request <= 1'b0;
		else
			if ( n2m_request_read )
				pending_request <= 1'b1;
			else
				if ( mc_avail_o & pending_request )
					pending_request <= 1'b0;

	assign m2n_response_address  = n2m_request_address;

	// Read multiplexer
	always_comb begin
		if ( n2m_request_read )
			case( n2m_request_address[6 : 2] )
				BASE_ADDRESS  : m2n_response_data = {( BUS_WIDTH/DATA_WIDTH ){base_reg}};
				REG_A_ADDRESS : m2n_response_data = {( BUS_WIDTH/DATA_WIDTH ){reg_a}};
				REG_B_ADDRESS : m2n_response_data = {( BUS_WIDTH/DATA_WIDTH ){reg_b}};
				COUNTER_REG   : m2n_response_data = {( BUS_WIDTH/DATA_WIDTH ){real_counter}};

				default :
					m2n_response_data = {BUS_WIDTH{1'b0}};
			endcase
	end

	always_ff @ ( posedge clk, negedge reset )
		if ( reset )
			m2n_response_valid <= 1'b0;
		else
			if ( mc_avail_o & pending_request )
				m2n_response_valid <= 1'b1;
			else
				m2n_response_valid <= 1'b0;


// --------------------------------------------------------------------------
// Write Mux
// --------------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			counter <= 0;
		else
			if ( ( write_base_reg | write_reg_a | write_reg_b ) & ( counter == 0 ) )
				counter <= 'd31;
			else
				if ( counter != 0 )
					counter <= counter - 1;
				
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			real_counter <= 0;
		else
			real_counter <= real_counter + 1;

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			base_reg <= 0;
		else
			if ( write_base_reg )
				base_reg <= n2m_request_data[31 : 0];

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			reg_a <= 0;
		else
			if ( write_reg_a )
				reg_a <= n2m_request_data[63 : 32];

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			reg_b <= 0;
		else
			if ( write_reg_b )
				reg_b <= n2m_request_data[95 : 64];

endmodule
