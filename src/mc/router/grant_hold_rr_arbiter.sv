`timescale 1ns / 1ps

module grant_hold_rr_arbiter
    #(parameter NUM_REQUESTERS = 4)

    (input                              clk,
    input                               reset,
    input[NUM_REQUESTERS - 1:0]         request,
    input[NUM_REQUESTERS - 1:0]         hold_in,
    output logic[NUM_REQUESTERS - 1:0]  grant_oh);

	logic anyhold;
	logic [NUM_REQUESTERS - 1:0] grant_arb,last,hold;

	rr_arbiter #(
		.NUM_REQUESTERS(NUM_REQUESTERS)
	)
	u_rr_arbiter (
		.clk       (clk       ),
		.reset     (reset     ),
		.request   (request   ),
		.update_lru( 1'b0	  ), 
		//.update_lru('{default:'0}),
		.grant_oh  (grant_arb  )
	);
	
	assign grant_oh = anyhold ? hold : grant_arb ;
	assign hold = last & hold_in;
	assign anyhold = | hold;
	
	always_ff @(posedge clk, posedge reset) begin
	    if (reset) 
	    	last <= 0;
	    else
	    	last <= grant_oh;   
	end

endmodule

