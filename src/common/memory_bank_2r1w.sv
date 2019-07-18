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

module memory_bank_2r1w #(
        parameter SIZE          = 1024,
        parameter ADDR_WIDTH    = $clog2(SIZE),
        parameter COL_WIDTH     = 8,
        parameter NB_COL        = 4,
        parameter WRITE_FIRST1  = "TRUE",
        parameter WRITE_FIRST2  = "TRUE"
    )(
        input                                       clock,
        input   logic                               read1_enable,
        input   logic   [ADDR_WIDTH-1		  : 0]  read1_address,
        output  logic   [NB_COL*COL_WIDTH-1   : 0]  read1_data,

        input   logic                               read2_enable,
        input   logic   [ADDR_WIDTH-1         : 0]  read2_address,
        output  logic   [NB_COL*COL_WIDTH-1   : 0]  read2_data,

        input   logic   [NB_COL-1             : 0]  write_enable,
        input   logic   [ADDR_WIDTH-1		  : 0]  write_address,
        input   logic   [NB_COL*COL_WIDTH-1   : 0]  write_data
    );

	memory_bank_1r1w #(
		.SIZE        (SIZE),
		.ADDR_WIDTH  (ADDR_WIDTH),
		.COL_WIDTH   (COL_WIDTH),
		.NB_COL      (NB_COL),
        .WRITE_FIRST (WRITE_FIRST1)
	)
	memory_bank_1r1w_1 (
		.clock        (clock),
		.read_enable  (read1_enable),
		.read_address (read1_address),
		.write_enable (write_enable),
		.write_address(write_address),
		.write_data   (write_data),
		.read_data    (read1_data)
	);

	memory_bank_1r1w #(
		.SIZE         (SIZE),
		.ADDR_WIDTH   (ADDR_WIDTH),
		.COL_WIDTH    (COL_WIDTH),
		.NB_COL       (NB_COL),
        .WRITE_FIRST  (WRITE_FIRST2)
	)
	memory_bank_1r1w_2 (
		.clock        (clock),
		.read_enable  (read2_enable),
		.read_address (read2_address),
		.write_enable (write_enable),
		.write_address(write_address),
		.write_data   (write_data),
		.read_data    (read2_data)
	);


endmodule
