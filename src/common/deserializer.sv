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
module deserializer# (
		parameter REG_SIZE = 32)
	(
		input                       clk,
		input                       reset,
		input						enable,
		input        				data_in,
		input                       start_shift,
		output logic [REG_SIZE-1:0] data_out
		//output logic				stop_shift
	);

	logic            [$clog2 (REG_SIZE) : 0]    cnt;
	logic            [REG_SIZE-1:0]             reg_temp;
	
	

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			reg_temp   <= {REG_SIZE{1'b0}};
			cnt        <= {$clog2(REG_SIZE){1'b0}};
			//stop_shift <= 1'b0;
			data_out   <= {REG_SIZE{1'b0}};
		end else if (enable) begin
			if (cnt != REG_SIZE) begin
				if (start_shift) begin
					reg_temp   <= {reg_temp[REG_SIZE-2:0],data_in};
					cnt        <= cnt + 1'b1;
				end
			end else begin
				cnt        <= {$clog2(REG_SIZE){1'b0}};
				data_out   <= reg_temp;
				//stop_shift <= 1'b1;
			end
		end
	end
endmodule

