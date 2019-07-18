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

module io_device_mem #(
		parameter ADDRESS_WIDTH = 32,
		parameter BUS_WIDTH     = 512,
		parameter DATA_WIDTH     = 512 )
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

    logic   [DATA_WIDTH - 1 : 0]    mem_dummy [3];
	logic                         pending_request;
	logic [DATA_WIDTH - 1 : 0]    base_reg;
	logic [ADDRESS_WIDTH - 1 : 0] pending_address;

	assign m2n_request_available = 1'b1;

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
			case( n2m_request_address[6] )
				0  : m2n_response_data = mem_dummy[0];
				1  : m2n_response_data = mem_dummy[1];

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
	initial begin
		mem_dummy[0] = {32'h1200_0000, 32'h0200_0000, 32'h2200_0000, 32'h3200_0000, 
					    32'h1100_0000, 32'h0300_0000, 32'h2300_0000, 32'h3300_0000, 
						32'h1000_0000, 32'h0400_0000, 32'h2400_0000, 32'h3400_0000, 
						32'h0900_0000, 32'h0500_0000, 32'h2500_0000, 32'h3500_0000};

		mem_dummy[1] = {32'h4200_0000, 32'h5200_0000, 32'h6200_0000, 32'h7200_0000, 
					    32'h4100_0000, 32'h5300_0000, 32'h6300_0000, 32'h7300_0000, 
						32'h4000_0000, 32'h5400_0000, 32'h6400_0000, 32'h7400_0000, 
						32'h4900_0000, 32'h5500_0000, 32'h6500_0000, 32'h7500_0000};
	end

endmodule
