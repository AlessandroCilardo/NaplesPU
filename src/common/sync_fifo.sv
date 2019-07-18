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
module sync_fifo #(
	parameter WIDTH                  = 64,
	parameter SIZE                   = 4,
	parameter ALMOST_FULL_THRESHOLD  = SIZE,
	parameter ALMOST_EMPTY_THRESHOLD = 1
) (
	input                      clk,
	input                      reset,
	input                      flush_en,
	output logic               full,
	output logic               almost_full,
	input                      enqueue_en,
	input        [WIDTH - 1:0] value_i,
	output logic               empty,
	output logic               almost_empty,
	input                      dequeue_en,
	output       [WIDTH - 1:0] value_o
);

	localparam PTR_WIDTH = $clog2( SIZE     );
	localparam CNT_WIDTH = $clog2( SIZE + 1 );

	// Pointers management
	logic [PTR_WIDTH - 1:0] head;
	logic [PTR_WIDTH - 1:0] tail;

	// Internal storage
	logic [CNT_WIDTH - 1:0] cnt;
	logic [WIDTH - 1 : 0]   mem  [SIZE];

	assign almost_full  = cnt >= ( PTR_WIDTH + 1 )'( ALMOST_FULL_THRESHOLD );
	assign almost_empty = cnt <= ( PTR_WIDTH + 1 )'( ALMOST_EMPTY_THRESHOLD );
	assign full         = cnt == CNT_WIDTH'( SIZE );
	assign empty        = cnt == 0;

	assign value_o      = mem[head];

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			head <= 0;
			tail <= 0;
			cnt  <= 0;
		end
		else begin
			if ( flush_en ) begin
				head <= 0;
				tail <= 0;
				cnt  <= 0;
			end
			else begin
				if ( enqueue_en ) begin
					assert ( !full ) else $fatal( 0, "Cannot enqueue on full FIFO!" );
					tail      <= tail + 1;
					mem[tail] <= value_i;
				end

				if ( dequeue_en ) begin
					assert ( !empty ) else $fatal( 0, "Cannot dequeue from empty FIFO!" );
					head <= head + 1;
				end

				if ( enqueue_en && !dequeue_en )
					cnt <= cnt + 1;
				else if ( dequeue_en && !enqueue_en )
					cnt <= cnt - 1;
			end
		end
	end

endmodule
