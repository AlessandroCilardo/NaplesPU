`timescale 1ns / 1ps
//
//  Single-Port RAM with Byte-wide Write Enable
//

module memory_bank #(
        parameter SIZE          = 1024,
        parameter ADDR_WIDTH    = $clog2(SIZE),
        parameter COL_WIDTH     = 8,
        parameter NB_COL        = 4
    )(
        input                                       clock,
        input   logic                               enable,
        input   logic   [ADDR_WIDTH         - 1:0]  address,
        input   logic   [NB_COL             - 1:0]  write_enable,
        input   logic   [NB_COL*COL_WIDTH   - 1:0]  write_data,
        output  logic   [NB_COL*COL_WIDTH   - 1:0]  read_data
    );

    reg [NB_COL*COL_WIDTH - 1:0] RAM [SIZE - 1 : 0];

    always_ff @(posedge clock) begin
        if (enable)
            read_data <= RAM[address];
    end

    generate
        genvar i;
        for (i = 0; i < NB_COL; i++) begin
            always_ff @(posedge clock) begin
                if (write_enable[i] && enable)
                    RAM[address][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= write_data[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
            end
        end
    endgenerate

endmodule
