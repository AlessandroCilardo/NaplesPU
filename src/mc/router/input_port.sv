`timescale 1ns / 1ps
`include "npu_network_defines.sv"

/*
 * There are two queues: one to house flits (FQ) and another to house only head flits (HQ).
 *  The queue lengths are equals to contemplate the worst case - packets with only one flit.
 * Every time a valid flit enters in this unit, the HQ enqueues its only if the flit type is
 * `head' or `head-tail'. The FQ has the task of housing all the flits, while the 
 * HQ has to "register" all the entrance packets. To assert the dequeue signal for HQ, 
 * either allocator grant assertion and the output of a tail flit have to happen, 
 * so the number of elements in the HQ determines the number of packet entered in this virtual channel.
 * 
 * This organization works only if a condition is respected: the flits of each packets 
 * are stored consecutively and ordered in the FQ. To obtain this condition, a deterministic
 * routing has to be used and all the network interfaces have to send all the flits of a packet
 * without interleaving with other packet flits.
 */

module input_port
	(
		// Interface to other router
		input  logic                                             wr_en_in,
		input  flit_t                                            flit_in,
		output        [`VC_PER_PORT - 1 : 0]                     on_off_out,

		output flit_t [`VC_PER_PORT - 1 : 0]                     ip_flit_in_mux,
		output        [`VC_PER_PORT - 1 : 0] [`PORT_NUM - 1 : 0] ip_dest_port,
		input         [`VC_PER_PORT - 1 : 0]                     sa_grant,

		output        [`VC_PER_PORT - 1 : 0]                     ip_empty,

		input                                                    clk,
		input                                                    reset
	);

	port_t [`VC_PER_PORT - 1 : 0]                     dest_port;
	logic  [`VC_PER_PORT - 1 : 0]                     request_not_valid;
	logic  [`VC_PER_PORT - 1 : 0] [`PORT_NUM - 1 : 0] dest_port_oh;

	genvar                                            i;
	generate
		for( i=0; i < `VC_PER_PORT; i=i + 1 ) begin : vc_loop
			logic [`PORT_NUM_W - 1 : 0] dest_port_app;

			sync_fifo #(
				.WIDTH ( $bits( flit_t )   ),
				.SIZE  ( `QUEUE_LEN_PER_VC ),
				.ALMOST_FULL_THRESHOLD ( `QUEUE_LEN_PER_VC - 1 ) )
			flit_fifo (
				.clk         ( clk                                  ),
				.reset       ( reset                                ),
				.flush_en    (                                      ),
				.full        (                                      ),
				.almost_full ( on_off_out[i]                        ),
				.enqueue_en  ( wr_en_in & flit_in.header.vc_id == i ),
				.value_i     ( flit_in                              ),
				.empty       ( ip_empty[i]                          ),
				.almost_empty(                                      ),
				.dequeue_en  ( sa_grant[i]                          ),
				.value_o     ( ip_flit_in_mux[i]                    )
			);

			sync_fifo #(
				.WIDTH ( $bits( port_t ) ),
				.SIZE ( `QUEUE_LEN_PER_VC ) )
			header_fifo (
				.clk         ( clk                                                                                                            ),
				.reset       ( reset                                                                                                          ),
				.flush_en    (                                                                                                                ),
				.full        (                                                                                                                ),
				.almost_full (                                                                                                                ),
				.enqueue_en  ( wr_en_in & flit_in.header.vc_id == i & ( flit_in.header.flit_type == HEADER | flit_in.header.flit_type == HT ) ),
				.value_i     ( flit_in.header.next_hop_port                                                                                   ),
				.empty       ( request_not_valid[i]                                                                                           ),
				.almost_empty(                                                                                                                ),
				.dequeue_en  ( ( ip_flit_in_mux[i].header.flit_type == TAIL | ip_flit_in_mux[i].header.flit_type == HT ) & sa_grant[i]        ),
				.value_o     ( dest_port_app                                                                                                  )
			);
			assign dest_port[i]    = port_t'( dest_port_app ); // segnale di appoggio per problemi con i tipi

			idx_to_oh #(
				.NUM_SIGNALS( `PORT_NUM )
			)
			u_idx_to_oh (
				.one_hot( dest_port_oh[i] ),
				.index  ( dest_port[i]    )
			);
			assign ip_dest_port[i] = dest_port_oh[i] & {`PORT_NUM{~request_not_valid[i]}};

		end
	endgenerate

endmodule
