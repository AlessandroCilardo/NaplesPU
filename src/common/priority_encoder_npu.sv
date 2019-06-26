`timescale 1ns / 1ps
module priority_encoder_npu #(
        parameter INPUT_WIDTH   = 4,
        parameter MAX_PRIORITY  = "LSB"
    )(
        input   logic   [INPUT_WIDTH            - 1 : 0]    decode,
        output  logic   [$clog2(INPUT_WIDTH)    - 1 : 0]    encode,
        output  logic                                       valid
    );

    generate
        always_comb begin
            encode = 0;
            if (MAX_PRIORITY == "LSB") begin
                for (int i = INPUT_WIDTH - 1; i >= 0; i--)
                    if (decode[i] == 1)
                        encode = i[$clog2(INPUT_WIDTH)  - 1 : 0];
            end else begin
                for (int i = 0; i < INPUT_WIDTH; i++)
                    if (decode[i] == 1)
                        encode = i[$clog2(INPUT_WIDTH)  - 1 : 0];
            end
        end
    endgenerate

    assign valid = |decode;

endmodule
