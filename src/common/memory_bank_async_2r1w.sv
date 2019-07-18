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
//  Single-Port RAM with Byte-wide Write Enable and Asynchronous Read
//

module memory_bank_async_2r1w
    #(
        parameter SIZE         = 1024,
        parameter ADDR_WIDTH   = $clog2(SIZE),
        parameter COL_WIDTH    = 8,
        parameter NB_COL       = 4, // Byte number per row
        parameter WRITE_FIRST1 = "FALSE",
        parameter WRITE_FIRST2 = "FALSE"
    )(
        input                                 clock,
        input  logic                          read1_enable, //Word-wide asynchronous read enable
        input  logic [ADDR_WIDTH - 1:0]       read1_address,
        input  logic                          read2_enable, //Word-wide asynchronous read enable
        input  logic [ADDR_WIDTH - 1:0]       read2_address,
        input  logic [NB_COL - 1:0]           write_enable, //Byte-wide synchronous write enable
        input  logic [ADDR_WIDTH - 1:0]       write_address,
        input  logic [NB_COL*COL_WIDTH - 1:0] write_data,

        output logic [NB_COL*COL_WIDTH - 1:0] read1_data,
        output logic [NB_COL*COL_WIDTH - 1:0] read2_data
    );

    reg   [NB_COL*COL_WIDTH-1 : 0] RAM [SIZE];

    logic [NB_COL*COL_WIDTH-1 : 0] pass_thru_data1, data_out1;
    logic                          pass_thru_en1;

    logic [NB_COL*COL_WIDTH-1 : 0] pass_thru_data2, data_out2;
    logic                          pass_thru_en2;



    generate
        if (WRITE_FIRST1 == "TRUE")
            assign read1_data = pass_thru_en1 ? pass_thru_data1 : data_out1;
        else
            assign read1_data = data_out1;
    endgenerate

    generate
        if (WRITE_FIRST2 == "TRUE")
            assign read2_data = pass_thru_en2 ? pass_thru_data2 : data_out2;
        else
            assign read2_data = data_out2;
    endgenerate

    always_latch begin
        pass_thru_en1   <= |write_enable && read1_enable && read1_address == write_address;
        pass_thru_data1 <= write_data;
    end

    always_latch begin
        pass_thru_en2   <= |write_enable && read2_enable && read2_address == write_address;
        pass_thru_data2 <= write_data;
    end

    always_latch begin
        if (read1_enable)
            data_out1 <= RAM[read1_address];
    end

    always_latch begin
        if (read2_enable)
            data_out2 <= RAM[read2_address];
    end

    generate
        genvar i;
        for (i = 0; i < NB_COL; i++) begin
            always_ff @(posedge clock) begin
                if (write_enable[i])
                    RAM[write_address][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= write_data[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
            end
        end
    endgenerate

endmodule
