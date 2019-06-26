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
