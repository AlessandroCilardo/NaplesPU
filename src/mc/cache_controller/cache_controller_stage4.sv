`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"
`include "npu_network_defines.sv"

`ifdef DISPLAY_COHERENCE
`include "npu_debug_log.sv"
`endif

module cache_controller_stage4 # (
		parameter TILE_ID          = 0,
		parameter CORE_ID          = 0 )
	(
		input                                       clk,
		input                                       reset,

		// From Cache Controller Stage 3
		input  logic                                cc3_request_is_flush,
		input  logic                                cc3_message_valid,
		input  logic                                cc3_message_is_response,
		input  logic                                cc3_message_is_forward,
		input  message_request_t                    cc3_message_request_type,
		input  message_response_t                   cc3_message_response_type,
		input  message_forwarded_request_t          cc3_message_forwarded_request_type,
		input  dcache_address_t                     cc3_message_address,
		input  dcache_line_t                        cc3_message_data,
		input  dcache_store_mask_t                  cc3_message_dirty_mask,
		input  logic                                cc3_message_has_data,
		input  logic                                cc3_message_send_data_from_cache,
		input  logic                                cc3_message_is_receiver_dir,
		input  logic                                cc3_message_is_receiver_req,
		input  logic                                cc3_message_is_receiver_mc,
		input  tile_address_t                       cc3_message_requestor,

		// From Load Store Unit
		input  dcache_line_t                        ldst_snoop_data,

		// To Network Interface
		output logic                                cc4_request_valid,
		output coherence_request_message_t          cc4_request,
		output logic                                cc4_request_has_data,
		output tile_address_t               [1 : 0] cc4_request_destinations,
		output logic                        [1 : 0] cc4_request_destinations_valid,

		output logic                                cc4_response_valid,
		output coherence_response_message_t         cc4_response,
		output logic                                cc4_response_has_data,
		output tile_address_t               [1 : 0] cc4_response_destinations,
		output logic                        [1 : 0] cc4_response_destinations_valid,

		output logic                                cc4_forwarded_request_valid,
		output coherence_forwarded_message_t        cc4_forwarded_request,
		output tile_address_t                       cc4_forwarded_request_destination

	);

	// TODO The following logic calculates the home directory ID, such a logic
    // works only with square NoCs
	logic         [$clog2( `TILE_COUNT ) - 1 : 0] directory_id;
	dcache_line_t                       outgoing_data;

	assign outgoing_data                       = cc3_message_send_data_from_cache ? ldst_snoop_data : cc3_message_data;

	assign directory_id = cc3_message_address[`ADDRESS_SIZE - 1 -: $clog2( `TILE_COUNT )];

	assign cc4_request_valid                   = cc3_message_valid && !cc3_message_is_response && !cc3_message_is_forward,
		cc4_request.source                     = tile_address_t'(TILE_ID),
		cc4_request.packet_type                = message_requests_enum_t'( cc3_message_request_type ),
		cc4_request.memory_address             = cc3_message_address,
		cc4_request.data                       = outgoing_data,
		cc4_request_has_data                   = cc3_message_has_data,
		cc4_request_destinations [CC_ID]       = cc3_message_requestor,
		cc4_request_destinations [DC_ID]       = directory_id,
		cc4_request_destinations_valid [CC_ID] = cc3_message_is_receiver_req,
		cc4_request_destinations_valid [DC_ID] = cc3_message_is_receiver_dir;

	assign cc4_response_valid                  = cc3_message_valid && cc3_message_is_response,
		cc4_response.source                    = tile_address_t'(TILE_ID),
		cc4_response.packet_type               = message_responses_enum_t'( cc3_message_response_type ),
		cc4_response.memory_address            = cc3_message_address,
		cc4_response.sharers_count             = 0,
		cc4_response.from_directory            = 0,
		cc4_response.dirty_mask                = cc3_message_dirty_mask,
		cc4_response.data                      = outgoing_data,
		cc4_response.req_is_uncoherent         = 1'b0,
		cc4_response_has_data                  = cc3_message_has_data,
		cc4_response_destinations [CC_ID]      = ( cc3_request_is_flush | cc3_message_is_receiver_mc ) ? `TILE_MEMORY_ID : cc3_message_requestor,
		cc4_response_destinations [DC_ID]      = directory_id,
		cc4_response_destinations_valid[CC_ID] = cc3_message_is_receiver_req | cc3_request_is_flush | cc3_message_is_receiver_mc,
		cc4_response_destinations_valid[DC_ID] = cc3_message_is_receiver_dir;

	assign cc4_forwarded_request_valid         = cc3_message_valid && cc3_message_is_forward,
		cc4_forwarded_request.source            = tile_address_t'(TILE_ID),
		cc4_forwarded_request.packet_type       = message_forwarded_requests_enum_t'( cc3_message_forwarded_request_type ),
		cc4_forwarded_request.memory_address    = cc3_message_address,
		cc4_forwarded_request.req_is_uncoherent = 1'b1,
		cc4_forwarded_request.requestor         = DCACHE,
		cc4_forwarded_request_destination       = `TILE_MEMORY_ID;

`ifdef DISPLAY_COHERENCE

	always_ff @( posedge clk )
		if ( ( cc4_request_valid | cc4_response_valid ) & ~reset ) begin

			if ( cc4_request_valid ) begin
				$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
				$fdisplay( `DISPLAY_COHERENCE_VAR, "Cache Controller - [Time %.16d] [TILE %.2h] [Core %.2h] - Message Request Sent", $time( ), TILE_ID, CORE_ID );
				if ( cc4_request_destinations_valid[CC_ID] )
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Requestor Destinations: %h", cc4_request_destinations[CC_ID] );
				if ( cc4_request_destinations_valid[DC_ID] )
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Directory Destinations: %h", cc4_request_destinations[DC_ID] );
				print_req( cc4_request );
			end

			if ( cc4_response_valid ) begin
				$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
				$fdisplay( `DISPLAY_COHERENCE_VAR, "Cache Controller - [Time %.16d] [TILE %.2h] [Core %.2h] - Message Response Sent", $time( ), TILE_ID, CORE_ID );
				if ( cc4_response_destinations_valid[CC_ID] )
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Requestor Destinations: %h", cc4_response_destinations[CC_ID] );
				if ( cc4_response_destinations_valid[DC_ID] )
					$fdisplay( `DISPLAY_COHERENCE_VAR, "Directory Destinations: %h", cc4_response_destinations[DC_ID] );
				print_resp( cc4_response );
			end

			$fflush( `DISPLAY_COHERENCE_VAR );
		end

`endif

endmodule
