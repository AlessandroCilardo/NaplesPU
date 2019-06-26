`timescale 1ns / 1ps
`include "npu_network_defines.sv"

/*
 * This module stores incoming flit from the network and rebuilt the original packet. Also, it handles back-pressure
 * informations (credit on/off).
 *
 * A FLIT if formed by an header and a body, the header has two fields: |TYPE|VCID|. VCID is fixed by the virtual channel
 * ID where the flit is sent. The virtual channel depends on the type of message. The filed TYPE can be: HEAD, BODY, TAIL
 * or HT. It is used by the control units to handles different flits.
 *
 * When the control unit checks the TAIL or HT header, the packet is complete and stored in packed FIFO output directly
 * connected to the Cache Controller.
 *
 * E.g. : If those flit sequence occurs:
 *          1st Flit in => {FLIT_TYPE_HEAD, FLIT_BODY_SIZE'h20}
 *          2nd Flit in => {FLIT_TYPE_BODY, FLIT_BODY_SIZE'h40}
 *          3rd Flit in => {FLIT_TYPE_BODY, FLIT_BODY_SIZE'h60}
 *          4th Flit in => {FLIT_TYPE_TAIL, FLIT_BODY_SIZE'h10};
 *  The rebuilt packet passed to the Cache Controller is:
 *          Packet out => {FLIT_BODY_SIZE'h10, FLIT_BODY_SIZE'h60, FLIT_BODY_SIZE'h40, FLIT_BODY_SIZE'h20}
 */

module virtual_network_net_to_core #(
		parameter TYPE             = "NONE",
		parameter VCID             = VC0,
		parameter PACKET_BODY_SIZE = 554,
		parameter PACKET_FIFO_SIZE = 4 )
	(
		input                                    clk,
		input                                    reset,
		input                                    enable,

		// Cache Controller interface
		output logic  [PACKET_BODY_SIZE - 1 : 0] vn_ntc_packet_out,
		output logic                             vn_ntc_packet_valid,
		input                                    core_packet_consumed,

		// Router interface
		output logic                             vn_ntc_credit,
		input                                    router_flit_valid,
		input  flit_t                            router_flit_in
	);

	localparam FLIT_NUMB = (PACKET_BODY_SIZE+`PAYLOAD_W-1) / `PAYLOAD_W;

//	logic                           credit_out;
	logic                           flit_valid;
	logic                           cu_packet_rebuilt_compl, enqueue_en;
	logic [PACKET_BODY_SIZE - 1 : 0] cu_rebuilt_packet;
	logic                           rebuilt_packet_fifo_empty, packet_alm_fifo_full;
	logic                           cu_is_for_cc, cu_is_for_dc;

//  -----------------------------------------------------------------------
//  -- Virtual Network Network to Core - Rebuild Packet FIFO
//  -----------------------------------------------------------------------
	// This FIFO stores the reconstructed packet from the network to the Cache Controller.
	// When the CC can read, it asserts packet_consumed bit.
	
	// The threshold is reduced of 2 due to controller: if a sequence of consecutive 1-flit packet arrives,
	// the on-off backpressure almost_full signal will raise up the clock edge after the threshold crossing as usual,
	// so it is important to reduce of 2 the threshold to avoid packet lost.
	// If the packet arriving near the threshold are bigger than 1 flit, the enqueue will be stopped with 1 free buffer space.
	sync_fifo #(
		.WIDTH                 ( PACKET_BODY_SIZE     ),
		.SIZE                  ( PACKET_FIFO_SIZE     ),
		.ALMOST_FULL_THRESHOLD ( PACKET_FIFO_SIZE - 2 ) 
	)
	rebuilt_packet_fifo (
		.clk         ( clk                       ),
		.reset       ( reset                     ),
		.flush_en    ( 1'b0                      ), //flush is synchronous, unlike reset
		.full        (                           ),
		.almost_full ( packet_alm_fifo_full      ),
		.enqueue_en  ( enqueue_en                ),
		.value_i     ( cu_rebuilt_packet         ),
		.empty       ( rebuilt_packet_fifo_empty ),
		.almost_empty(                           ),
		.dequeue_en  ( core_packet_consumed      ),
		.value_o     ( vn_ntc_packet_out         )
	);

	// When the packet FIFO is not empty there is a pending packet.
	assign vn_ntc_packet_valid = ~rebuilt_packet_fifo_empty;

	// If there are no more rooms in packet FIFO, the NI cannot dequeue FLITs from Router.
	assign vn_ntc_credit       = packet_alm_fifo_full;

	generate
		if ( TYPE == "CC" )
			assign
				enqueue_en    = cu_packet_rebuilt_compl & cu_is_for_cc;
		else if ( TYPE == "DC" )
			assign enqueue_en = cu_packet_rebuilt_compl & cu_is_for_dc;
		else
			assign enqueue_en = cu_packet_rebuilt_compl;
	endgenerate

//  -----------------------------------------------------------------------
//  -- Virtual Network Network to Core - Rebuild Packet Control Unit
//  -----------------------------------------------------------------------
	// Flits from the network are not stored in any FIFOs. The router_valid signal is directly
	// connected to the rebuilt packet control unit.
	// In Control Unit all incoming flit are mounted in a packet. It checks the Flit header, if
	// it is a TAIL or a HT type, the control unit stores the composed packet in the output FIFO
	// to the Cache Controller.
	control_unit_flit_to_packet #(
		.PACKET_BODY_SIZE( PACKET_BODY_SIZE )
	)
	control_unit_flit_to_packet (
		.clk                    ( clk                     ),
		.reset                  ( reset                   ),
		.enable                 ( enable                  ),
		//.credit_out             ( credit_out              ),
		//.packet_alm_fifo_full   ( packet_alm_fifo_full    ),
		//.core_packet_consumed   ( core_packet_consumed    ),
		//From Router
		.router_flit_valid      ( flit_valid              ),
		.router_flit_in         ( router_flit_in          ),
		//To Router
		//To rebuilt packet logic
		.cu_packet_rebuilt_compl( cu_packet_rebuilt_compl ),
		.cu_rebuilt_packet      ( cu_rebuilt_packet       ),
		.cu_is_for_cc           ( cu_is_for_cc            ),
		.cu_is_for_dc           ( cu_is_for_dc            )
	);

	// The flit is computed if it is for this virtual network.
	assign flit_valid          = router_flit_valid & router_flit_in.header.vc_id == VCID;

endmodule
