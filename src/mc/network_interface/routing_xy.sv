`timescale 1ns / 1ps
`include "npu_network_defines.sv"

module routing_xy #(
		parameter MY_X_ADDR = 0,
		parameter MY_Y_ADDR = 0 )
	(
		input  logic [`TOT_X_NODE_W-1 : 0 ] dest_x_node,
		input  logic [`TOT_Y_NODE_W-1 : 0 ] dest_y_node,
		output logic [`PORT_NUM_W-1 : 0 ]   next_port
	);

	logic        [`TOT_X_NODE_W-1 : 0] xc, yc; // current
	logic signed [`TOT_Y_NODE_W   : 0] xdiff, ydiff; // difference

	assign xc    = MY_X_ADDR [`TOT_X_NODE_W-1 : 0],
		yc       = MY_Y_ADDR [`TOT_Y_NODE_W-1 : 0];
	assign xdiff = dest_x_node - xc,
		ydiff    = dest_y_node - yc;

	always_comb begin
		next_port = LOCAL;
		if ( xdiff > 0 )
			next_port = EAST;
		else if ( xdiff < 0 )
			next_port = WEST;
		else begin
			if ( ydiff > 0 )
				next_port = SOUTH;
			else if ( ydiff < 0 )
				next_port = NORTH;
		end
	end

endmodule
