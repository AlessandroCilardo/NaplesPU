`timescale 1ns / 1ps
`include "npu_network_defines.sv"
/*
 * The look-ahead routing calculates the destination port of the next node instead of the actual one 
 * because the actual destination port is yet ready in the header flit. The algorithm is a version of 
 * the X-Y deterministic routing. It is deadlock-free because it removes four on eight possible turns: 
 * when a packet turns towards Y directions, it cannot turn more. 
 */

module look_ahead_routing #(
	parameter MY_X_ADDR	= 0,
	parameter MY_Y_ADDR	= 0)
(
	input  logic [`TOT_X_NODE_W-1 : 0 ]	dest_x_node,
	input  logic [`TOT_Y_NODE_W-1 : 0 ]	dest_y_node,
	output logic [`PORT_NUM_W-1   : 0 ] next_port 
);

	logic        [`TOT_X_NODE_W-1 : 0] xc, yc; // current
	logic signed [`TOT_Y_NODE_W   : 0] xdiff, ydiff; // difference
	
	assign 	xc = MY_X_ADDR [`TOT_X_NODE_W-1 : 0],
			yc = MY_Y_ADDR [`TOT_Y_NODE_W-1 : 0];
	assign 	xdiff = dest_x_node - xc,
			ydiff = dest_y_node - yc;
	
	always_comb begin
			next_port = LOCAL;
			if (xdiff > 1) next_port = EAST;
			else if	(xdiff < -1) next_port = WEST;
				 else if (xdiff == 1 || xdiff == -1 ) begin
						if (ydiff >= 1) next_port = SOUTH;
						else if (ydiff == 0) next_port = LOCAL;
							 else next_port = NORTH;
					  end// xdiff	==	1 || xdiff	==	-1 	
					else begin //xdiff ==0
						if (ydiff > 1) next_port = SOUTH;
						else if	(ydiff	==	1) next_port = LOCAL;
							 else if (ydiff	==-1) next_port	= LOCAL; 
								  else if (ydiff	< -1) next_port	= NORTH; 
									   else next_port = {`PORT_NUM_W{1'b0}}; //{`PORT_NUM_W{1'bx}}; //xdiff ==0
					end //else
	end
	

endmodule
