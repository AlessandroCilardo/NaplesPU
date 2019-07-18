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
//
//  Single-Port RAM with Byte-wide Write Enable
//

module memory_bank_1r1w
	#(
		parameter SIZE          = 1024,
		parameter ADDR_WIDTH    = $clog2( SIZE ),
		parameter COL_WIDTH     = 8,
		parameter NB_COL        = 4,                // Byte number per row
		parameter WRITE_FIRST   = "TRUE"
	)(
		input                                       clock,
		input   logic                               read_enable,
		input   logic   [ADDR_WIDTH         - 1:0]  read_address,
		input   logic   [NB_COL             - 1:0]  write_enable,
		input   logic   [ADDR_WIDTH         - 1:0]  write_address,
		input   logic   [NB_COL*COL_WIDTH   - 1:0]  write_data,

		output  logic   [NB_COL*COL_WIDTH   - 1:0]  read_data
	);

	reg    [NB_COL*COL_WIDTH-1 : 0] RAM [SIZE];
	logic  [NB_COL*COL_WIDTH-1 : 0] pass_thru_data, data_out;
	logic                           pass_thru_en;

	genvar                          i;

	generate
		if ( WRITE_FIRST == "TRUE" )
			assign read_data = pass_thru_en ? pass_thru_data : data_out;
		else
			assign read_data = data_out;
	endgenerate

	always_ff @( posedge clock ) begin
		pass_thru_en   <= |write_enable && read_enable && read_address == write_address;
	end

	generate
		if ( WRITE_FIRST == "TRUE" )
			for ( i = 0; i < NB_COL; i++ ) begin : PASSTHR_LOGIC
				always_ff @( posedge clock ) begin
					if ( write_enable[i] )
						pass_thru_data[( i+1 )*COL_WIDTH-1:i*COL_WIDTH] <= write_data[( i+1 )*COL_WIDTH-1:i*COL_WIDTH];
					else
						pass_thru_data[( i+1 )*COL_WIDTH-1:i*COL_WIDTH] <= RAM[write_address][( i+1 )*COL_WIDTH-1:i*COL_WIDTH];
				end
			end
		else
			always_ff @( posedge clock )
				pass_thru_data <= write_data;
	endgenerate

	always_ff @( posedge clock ) begin
		if ( read_enable )
			data_out <= RAM[read_address];
	end

	generate
		for ( i = 0; i < NB_COL; i++ ) begin : BYTE_WIDE_WRITE_LOGIC
			always_ff @( posedge clock ) begin
				if ( write_enable[i] )
					RAM[write_address][( i+1 )*COL_WIDTH-1:i*COL_WIDTH] <= write_data[( i+1 )*COL_WIDTH-1:i*COL_WIDTH];
			end
		end
	endgenerate

endmodule
