`timescale 1ns / 1ps
`include "npu_network_defines.sv"

module control_unit_flit_to_packet #(
		parameter PACKET_BODY_SIZE = 256
	) (
		input                                    clk,
		input                                    reset,
		input                                    enable,

		// From Router
		input  logic                             router_flit_valid,
		input  flit_t                            router_flit_in,

		// To rebuilt packet logic
		output logic  [PACKET_BODY_SIZE - 1 : 0] cu_rebuilt_packet,
		output logic                             cu_packet_rebuilt_compl,
		output logic                             cu_is_for_cc,
		output logic                             cu_is_for_dc
	);

	localparam FLIT_NUMB = (PACKET_BODY_SIZE+`PAYLOAD_W-1) / `PAYLOAD_W;
	
	logic       [$clog2( FLIT_NUMB + 1 ) - 1 : 0] count;

	flit_body_t [FLIT_NUMB - 1 : 0]           rebuilt_packet;
	
	genvar i;
	generate
		for (i = 0; i < FLIT_NUMB; i++) begin : OUTPUT_COMPOSER
			if (i == FLIT_NUMB-1) begin
				localparam EFFECTIVE_BITS = PACKET_BODY_SIZE%`PAYLOAD_W;

				assign cu_rebuilt_packet[i * `PAYLOAD_W +: EFFECTIVE_BITS] = rebuilt_packet[i][EFFECTIVE_BITS-1 : 0];
			end else begin
				assign cu_rebuilt_packet[i * `PAYLOAD_W +: `PAYLOAD_W] = rebuilt_packet[i];
			end
		end
	endgenerate
	
	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			cu_packet_rebuilt_compl <= 1'b0;
			rebuilt_packet       <= '{default: '0};
			cu_is_for_cc            <= 1'b0;
			cu_is_for_dc            <= 1'b0;
			count <= '{default: '0};
		end else begin
			
			cu_packet_rebuilt_compl <= 1'b0;
			if (enable) begin
			
				if (router_flit_valid) begin
					rebuilt_packet[count] <= router_flit_in.payload;
					
					if (router_flit_in.header.flit_type == TAIL || router_flit_in.header.flit_type == HT) begin
						count <= '{default: '0};
						cu_packet_rebuilt_compl <= 1'b1;
					end else
						count <= count + 1;
						
					if (router_flit_in.header.flit_type == HEADER || router_flit_in.header.flit_type == HT) begin
						cu_is_for_cc <= router_flit_in.header.core_destination == TO_CC;
						cu_is_for_dc <= router_flit_in.header.core_destination == TO_DC;
					end 
					
				end

			end
		end
	end

endmodule
