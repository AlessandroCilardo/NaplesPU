`timescale 1ns / 1ps
module oh_to_idx #(
	parameter NUM_SIGNALS = 4,
	parameter DIRECTION = "LSB0",
	parameter INDEX_WIDTH = $clog2(NUM_SIGNALS)
) (
	input        [NUM_SIGNALS - 1:0] one_hot,
	output logic [INDEX_WIDTH - 1:0] index);

	always_comb begin
		index = 0;

		for ( int i = 0; i < NUM_SIGNALS; i++ )
		begin
			if ( one_hot[i] )
			begin
				if ( DIRECTION == "LSB0" )
					index |= i[INDEX_WIDTH - 1:0];
				else
					index |= ~i[INDEX_WIDTH - 1:0];
			end
		end
	end
endmodule
