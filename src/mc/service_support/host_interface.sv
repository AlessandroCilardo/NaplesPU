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
`include "npu_message_service_defines.sv"
`include "npu_network_defines.sv"

module host_interface #(
		parameter TILE_ID = 0,
		parameter ITEM_w  = 32 	)
	(
		input						  clk,
		// Interface to Host
		input        [ITEM_w - 1 : 0] item_data_i,  // Input: items from outside
		input                         item_valid_i, // Input: valid signal associated with item_data_i port
		output logic                  item_avail_o, // Output: avail signal to input port item_data_i
		output logic [ITEM_w - 1 : 0] item_data_o,  // Output: items to outside
		output logic                  item_valid_o, // Output: valid signal associated with item_data_o port
		input                         item_avail_i, // Input: avail signal to ouput port item_data_o

		// Interface Host Request Manager
		input  logic                  hm_item_valid_o,
		input  logic                  hm_item_avail_o,
		output logic [ITEM_w - 1 : 0] hm_item_data_i,
		output logic                  hm_item_valid_i,
		output logic                  hm_item_avail_i,
		input  logic [ITEM_w - 1 : 0] hm_item_data_o,

		// Interface Debug request manager
		input  logic                  dsu_item_valid_o,
		input  logic                  dsu_item_avail_o,
		output logic [ITEM_w - 1 : 0] dsu_item_data_i,
		output logic                  dsu_item_valid_i,
		output logic                  dsu_item_avail_i,
		input  logic [ITEM_w - 1 : 0] dsu_item_data_o,

		input logic wait_boot,
		input logic wait_dsu
	);

	host_message_type_t                  command_host_in;

	assign command_host_in = host_message_type_t'( item_data_i );
	assign item_avail_o     = hm_item_avail_o; //& dsu_item_avail_o;

	always_comb begin
		item_data_o		 = {ITEM_w{1'b0}};
		item_valid_o 	 = 0;
		
		hm_item_data_i   = {ITEM_w{1'b0}};
		hm_item_valid_i  = 0;
		hm_item_avail_i  = 0;
		
		dsu_item_data_i  = {ITEM_w{1'b0}};
		dsu_item_valid_i = 0;
		dsu_item_avail_i = 0;
		
		if ( wait_boot == 0 && wait_dsu == 0) begin
			if ( ( BOOT_COMMAND  <= command_host_in && command_host_in <= GET_CORE_STATUS ) && hm_item_avail_o && item_valid_i ) begin
				hm_item_avail_i  = item_avail_i;
				hm_item_valid_i  = item_valid_i;
				item_valid_o 	 = hm_item_valid_o;
				hm_item_data_i   = item_data_i;
				item_data_o 	 = hm_item_data_o;
			end
		end else if ( wait_boot == 1 && wait_dsu == 0) begin
			hm_item_avail_i  = item_avail_i;
			hm_item_valid_i  = item_valid_i;
			item_valid_o 	 = hm_item_valid_o;
			hm_item_data_i   = item_data_i;
			item_data_o 	 = hm_item_data_o;
		end else if ( wait_boot == 0 && wait_dsu == 1) begin
			dsu_item_avail_i = item_avail_i;
			dsu_item_valid_i = item_valid_i;
			item_valid_o  	 = dsu_item_valid_o;
			dsu_item_data_i  = item_data_i;
			item_data_o	  	 = dsu_item_data_o;
		end 
	end

`ifdef SIMULATION
	always_ff @( posedge clk ) begin
		assert ( !(wait_boot == 1 & wait_dsu == 1) )else $fatal( "Concurrent host interface driver!" ); 
	end
`endif	
	
endmodule
