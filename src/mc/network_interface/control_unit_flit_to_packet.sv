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
`include "npu_network_defines.sv"

/* This module is composed of two parts: a control unit which handles 
 * incoming flits, rebuilding them as a packet; and a queue of rebuilt 
 * packets. 
 * Rebuilt packets are stored in a FIFO, so we can enqueue multiple requests.
 * When the receiver component is ready to handle the request, it will assert 
 * the core_packet_consumed signal, freeing one buffer slot.  
 */ 

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
