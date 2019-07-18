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
`include "npu_synchronization_defines.sv"

module performance_counter #(
	parameter TILE_ID_PAR = 0)

	(
		input                                   clk,
		input hw_lane_t                         opf_fetched_op0,
		input                                   reset,
		input logic          [1 : 0][`THREAD_NUMB-1:0] perf_events
	);

	localparam          NUM_COUNTERS                  = `THREAD_NUMB;
	localparam          NUM_EVENTS                    = 2;


	logic      [64 : 0]                event_counter[NUM_EVENTS][NUM_COUNTERS];
	logic      [NUM_EVENTS-1:0][NUM_COUNTERS-1:0] display_counter;
	barrier_t           barrier_id[NUM_COUNTERS];
	
    logic          [NUM_COUNTERS-1:0] perf_events_send,perf_events_detect;
	assign 
		perf_events_detect = perf_events[0],
		perf_events_send = perf_events[1];

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset )begin
			for ( int i = 0; i < NUM_COUNTERS; i++ ) begin
				barrier_id[i]    <= 0;
			end
		end else begin
			for ( int i = 0; i < NUM_COUNTERS; i++ ) begin
				if(event_counter[0][i] == 2)
					barrier_id[i] <= opf_fetched_op0[0][$bits( barrier_t )-1:0];
			end
		end
	end
	always_ff @( posedge clk, posedge reset ) begin
		if ( reset )begin
			for ( int j = 0; j < NUM_EVENTS; j++ ) begin
				for ( int i = 0; i < NUM_COUNTERS; i++ ) begin
					event_counter[j][i] <= 0;
					display_counter[j][i] <= 0;
				end
			end

		end else begin
			for ( int j = 0; j < NUM_EVENTS; j++ ) begin
				for ( int i = 0; i < NUM_COUNTERS; i++ ) begin
					if ( perf_events[j][i]) begin
						event_counter[j][i] <= event_counter[j][i] + 1;
					end else begin
						if(event_counter[j][i]!=0 && display_counter[j][i] ==0) begin
							display_counter[j][i] <=1;
						end else begin
							display_counter[j][i] <= 0;
							event_counter[j][i]   <= 64'b0;
						end
					end
				end
			end
		end
	end

`ifdef DISPLAY_SYNC
`ifdef PERFORMANCE_SYNC
	



	always_ff @(posedge clk) begin
			for ( int i = 0; i < NUM_COUNTERS; i++ ) begin
				if(display_counter[0][i])begin
					$fdisplay ( `DISPLAY_SYNC_PERF_VAR, "=======================" ) ;
					$fdisplay ( `DISPLAY_SYNC_PERF_VAR, "=========Event Detect=======" ) ;
					$fdisplay ( `DISPLAY_SYNC_PERF_VAR, "[Tile_id -  %.16d ]  [Thread_id -  %.16d] [Barrier_Id - %.16d] [ CycleClock -  %.16d]" ,TILE_ID_PAR, i,barrier_id[i], event_counter[0][i]) ;
					$fflush   ( `DISPLAY_SYNC_PERF_VAR );
				end
				
				if (display_counter[1][i]) begin
					$fdisplay ( `DISPLAY_SYNC_PERF_VAR, "=======================" ) ;
					$fdisplay ( `DISPLAY_SYNC_PERF_VAR, "=========Event Send=======" ) ;
					$fdisplay ( `DISPLAY_SYNC_PERF_VAR, "[Tile_id -  %.16d ]  [Thread_id -  %.16d] [Barrier_Id - %.16d] [ CycleClock -  %.16d]" ,TILE_ID_PAR, i,barrier_id[i], event_counter[1][i]) ;
					$fflush   ( `DISPLAY_SYNC_PERF_VAR );
				end
				
			end
		end

`endif
`endif

endmodule
