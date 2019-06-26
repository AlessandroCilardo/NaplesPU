`timescale 1ns / 1ps
module mux_npu #(
		parameter N          = 4,
		parameter WIDTH      = 32,
		parameter HOLD_VALUE = "TRUE" )
	(
		input        [N-1:0]            onehot,
		input        [N-1:0][WIDTH-1:0] i_data ,
		output logic [WIDTH-1:0]        o_data
	);

	logic [$clog2( N ) - 1 : 0] index;
	logic                       valid;

	priority_encoder_npu #(
		.INPUT_WIDTH ( N     ),
		.MAX_PRIORITY( "MSB" )
	)
	u_priority_encoder (
		.decode( onehot ),
		.encode( index  ),
		.valid ( valid  )
	);

	generate
		if ( HOLD_VALUE == "TRUE" )
			assign o_data = i_data[index];
		else
			assign o_data = valid ? i_data[index]: {WIDTH{1'b0}};
	endgenerate

endmodule
