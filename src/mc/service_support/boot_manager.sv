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

`ifdef DISPLAY_REQUESTS_MANAGER
`include "npu_debug_log.sv"
`endif

module boot_manager # (
		parameter TILE_ID = 0 )
	(
		input                                               clk,
		input                                               reset,

		// From Network
		input  logic                                        network_available,
		input  service_message_t                            message_in,
		input  logic                                        message_in_valid,
		output logic                                        n2c_mes_service_consumed,

		// To Network
		output service_message_t                            message_out,
		output logic                                        message_out_valid,
		output tile_mask_t                                  destination_valid,

		// Interface To NaplesPU
		output logic                 [`THREAD_NUMB - 1 : 0] hi_thread_en,
		output logic                                        hi_job_valid,
		output address_t                                    hi_job_pc,
		output thread_id_t                                  hi_job_thread_id
	);

	host_message_t message_from_net;

	assign message_from_net			= host_message_t'(message_in.data);
	assign message_out_valid        = 1'b0;
	assign n2c_mes_service_consumed = message_in_valid;

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			hi_thread_en <= 0;
		end else begin
			if ( message_in_valid && message_from_net.message == ENABLE_THREAD )
				hi_thread_en <= message_from_net.hi_thread_en;
		end
	end

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			hi_job_valid             <= 1'b0;
		end else begin
			hi_job_valid             <= 1'b0;

			if ( message_in_valid && message_from_net.message == BOOT_COMMAND ) begin
				hi_job_valid     <= message_from_net.hi_job_valid;
				hi_job_pc        <= message_from_net.hi_job_pc;
				hi_job_thread_id <= message_from_net.hi_job_thread_id;
			end
		end
	end

`ifdef DISPLAY_REQUESTS_MANAGER

	always_ff @ ( posedge clk ) begin
		if ( n2c_mes_service_consumed & ~reset ) begin
			$fdisplay ( `DISPLAY_REQ_MANAGER_VAR, "=======================" ) ;
			$fdisplay ( `DISPLAY_REQ_MANAGER_VAR, "Boot Manager - [Time %.16d] [TILE %.2h]", $time ( ), TILE_ID ) ;
			print_boot_manager_message_in ( message_in.data ) ;
		end

		if ( n2c_mes_service_consumed ) begin
			$fflush( `DISPLAY_REQ_MANAGER_VAR ) ;
	end
`endif

endmodule
