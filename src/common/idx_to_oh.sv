`timescale 1ns / 1ps
module idx_to_oh #(
	parameter NUM_SIGNALS = 4,
	parameter DIRECTION = "LSB0",
	parameter INDEX_WIDTH = $clog2(NUM_SIGNALS)
) (
	input        [INDEX_WIDTH - 1:0] index,
	output logic [NUM_SIGNALS - 1:0] one_hot
);

	genvar i;
	generate
		for (i = 0; i < NUM_SIGNALS; i++) begin
			if (DIRECTION == "LSB0") begin
				assign one_hot[i] = index == i;
			end else begin
				assign one_hot[i] = index == (NUM_SIGNALS-1-i);
			end
		end
	endgenerate

endmodule
