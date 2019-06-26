`timescale 1ns / 1ps
`include "npu_network_defines.sv"

module crossbar
	(
		input         [`PORT_NUM-1:0][`PORT_NUM-1 : 0] port_sel,
		input  flit_t [`PORT_NUM-1:0]                  flit_in ,
		input  logic  [`PORT_NUM-1 : 0]                flit_valid_in,
		output logic  [`PORT_NUM-1 : 0]                wr_en_out,
		output flit_t [`PORT_NUM-1:0]                  flit_out
	);

	logic  [`PORT_NUM-1:0][`PORT_NUM-1 : 0]  mux_sel ;
	flit_t [`PORT_NUM-1:0][`PORT_NUM-1:0]    flit_in_mux_array;
	logic  [`PORT_NUM-1 : 0] [`PORT_NUM-1:0] flit_valid_mux_in;

	genvar                                   i,j;
	generate
		for( i=0; i<`PORT_NUM; i=i+1 ) begin : port_loop
			for( j=0; j<`PORT_NUM; j=j+1 ) begin : port_loop2
				assign flit_in_mux_array[i][j] = flit_in[j],
					mux_sel[i][j]              = port_sel[j][i],
					flit_valid_mux_in[i][j]    = flit_valid_in[j];
			end // for j

			mux_npu #(
				.N         ( `PORT_NUM       ),
				.WIDTH     ( $bits( flit_t ) ),
				.HOLD_VALUE( "TRUE"         )
			)
			mux_flit (
				.onehot( mux_sel[i]           ),
				.i_data( flit_in_mux_array[i] ),
				.o_data( flit_out[i]          )
			);

			mux_npu #(
				.N         ( `PORT_NUM ),
				.WIDTH     ( 1         ),
				.HOLD_VALUE( "FALSE"    )
			)
			mux_valid (
				.onehot( mux_sel[i]           ),
				.i_data( flit_valid_mux_in[i] ),
				.o_data( wr_en_out[i]         )
			);

		end//for i
	endgenerate

endmodule
