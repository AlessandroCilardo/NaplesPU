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

module io_device_simple #(
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

	logic                      pending_request;

	assign m2n_request_available = 1'b1 ;

// --------------------------------------------------------------------------
// Read Mux
// --------------------------------------------------------------------------

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
		m2n_response_data[31 : 0]    = 32'hF0;
		m2n_response_data[63 : 32]   = 32'hF1;
		m2n_response_data[95 : 64]   = 32'hF2;
		m2n_response_data[127 : 96]  = 32'hF3;
		m2n_response_data[159 : 128] = 32'hF4;
		m2n_response_data[191 : 160] = 32'hF5;
		m2n_response_data[223 : 192] = 32'hF6;
		m2n_response_data[255 : 224] = 32'hF7;
		m2n_response_data[287 : 256] = 32'hF8;
		m2n_response_data[319 : 288] = 32'hF9;
		m2n_response_data[351 : 320] = 32'hFA;
		m2n_response_data[383 : 352] = 32'hFB;
		m2n_response_data[415 : 384] = 32'hFC;
		m2n_response_data[447 : 416] = 32'hFD;
		m2n_response_data[479 : 448] = 32'h2;
		m2n_response_data[511 : 480] = 32'hFE;
	end

	always_ff @ ( posedge clk, negedge reset )
		if ( reset )
			m2n_response_valid <= 1'b0;
		else
			if ( mc_avail_o & pending_request )
				m2n_response_valid <= 1'b1;
			else
				m2n_response_valid <= 1'b0;

endmodule
