`timescale 1ns / 1ps
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"

`ifdef DISPLAY_COHERENCE
 `include "npu_debug_log.sv"
`endif

module directory_controller_stage1 #(
		parameter TILE_ID = 0 )
	(
		input                                                                                       clk,
		input                                                                                       reset,

		// From Network Interface
		input  logic                                                                                ni_response_network_available,
		input  logic                                                                                ni_forwarded_request_network_available,

		input  logic                                                                                ni_request_valid,
		input  coherence_request_message_t                                                          ni_request,

		input  logic                                                                                ni_response_valid,
		input  coherence_response_message_t                                                         ni_response,

		// From Sleep Queue
		input  logic                                                                                rp_empty,
		input  replacement_request_t                                                                rp_request,

		// From Directory Controller Stage 2
		input  logic                                                                                dc2_pending,
		input  l2_cache_address_t                                                                   dc2_pending_address,

		// From Directory Controller Stage 3
		input  logic                                                                                dc3_pending,
		input  l2_cache_address_t                                                                   dc3_pending_address,

		input  logic                                                                                dc3_update_cache_enable,
		input  logic                                                                                dc3_update_cache_validity_bit,
		input  l2_cache_set_t                                                                       dc3_update_cache_set,
		input  l2_cache_way_idx_t                                                                   dc3_update_cache_way,
		input  l2_cache_tag_t                                                                       dc3_update_cache_tag,
		input  logic                        [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc3_update_cache_state,

		// From TSHR
		input  logic                                                                                tshr_full,
		input  logic                        [`TSHR_LOOKUP_PORTS - 1 : 0]                            tshr_lookup_hit,
		input  tshr_idx_t                   [`TSHR_LOOKUP_PORTS - 1 : 0]                            tshr_lookup_index,
		input  tshr_entry_t                 [`TSHR_LOOKUP_PORTS - 1 : 0]                            tshr_lookup_entry_info,

		// From WB Gen Queue
		input  logic                                                                                wb_gen_pending,
		input  dcache_line_t                                                                        wb_gen_data,
		input  address_t                                                                            wb_gen_addr,

		// To WB Gen Queue
		output logic                                                                                dc1_wb_request_dequeue,

		// To TSHR
		output l2_cache_tag_t               [`TSHR_LOOKUP_PORTS - 1 : 0]                            dc1_tshr_lookup_tag,
		output l2_cache_set_t               [`TSHR_LOOKUP_PORTS - 1 : 0]                            dc1_tshr_lookup_set,

		// To Network Interface
		output logic                                                                                dc1_request_consumed,
		output logic                                                                                dc1_response_inject_consumed,

		// To Sleep Queue
		output logic                                                                                dc1_repl_queue_dequeue,

		// To Directory Controller Stage 2
		output logic                                                                                dc1_message_valid,
		output logic                        [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0]                 dc1_message_type,
		output logic                                                                                dc1_message_tshr_hit,
		output tshr_idx_t                                                                           dc1_message_tshr_index,
		output tshr_entry_t                                                                         dc1_message_tshr_entry_info,
		output l2_cache_address_t                                                                   dc1_message_address,
		output dcache_line_t                                                                        dc1_message_data,
		output tile_address_t                                                                       dc1_message_source,
		output logic                        [`L2_CACHE_WAY - 1 : 0]                                 dc1_message_cache_valid,
		output logic                        [`L2_CACHE_WAY - 1 : 0][`DIRECTORY_STATE_WIDTH - 1 : 0] dc1_message_cache_state,
		output l2_cache_tag_t               [`L2_CACHE_WAY - 1 : 0]                                 dc1_message_cache_tag,

		output logic                        [`DIRECTORY_STATE_WIDTH - 1 : 0]                        dc1_replacement_state,
		output logic                        [`TILE_COUNT - 1 : 0]                                   dc1_replacement_sharers_list,
		output tile_address_t                                                                       dc1_replacement_owner
	);

	localparam REQUEST_TSHR_LOOKUP_PORT             = 0;
	localparam RESPONSE_TSHR_LOOKUP_PORT            = 1;
	localparam REPLACEMENT_REQUEST_TSHR_LOOKUP_PORT = 2;

	typedef struct packed {
		l2_cache_tag_t tag;
		logic [`DIRECTORY_STATE_WIDTH - 1 : 0] state;
	} cache_tag_entry_t;

	l2_cache_address_t                                          ni_request_address;
	l2_cache_address_t                                          ni_response_address;
	l2_cache_address_t                                          rp_request_address;

	logic                                                       output_message_valid;
	coherence_request_t                                         output_message_type;
	logic                                                       output_message_tshr_hit;
	tshr_idx_t                                                  output_message_tshr_index;
	tshr_entry_t                                                output_message_tshr_entry_info;
	l2_cache_address_t                                          output_message_address;
	dcache_line_t                                               output_message_data;
	tile_address_t                                              output_message_source;
	logic               [`DIRECTORY_STATE_WIDTH - 1 : 0]        output_replacement_state;
	logic               [`TILE_COUNT - 1 : 0]                   output_replacement_sharers_list;
	tile_address_t                                              output_replacement_owner;

	logic                                                       request_tshr_hit;
	tshr_idx_t                                                  request_tshr_index;
	tshr_entry_t                                                request_tshr_entry_info;

	logic                                                       response_tshr_hit;
	tshr_idx_t                                                  response_tshr_index;
	tshr_entry_t                                                response_tshr_entry_info;

	logic                                                       replacement_request_tshr_hit;
	tshr_idx_t                                                  replacement_request_tshr_index;
	tshr_entry_t                                                replacement_request_tshr_entry_info;

	logic               [`DIRECTORY_STATE_WIDTH - 1 : 0]        dpr_state;
	logic               [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] dpr_message_type;
	logic                                                       dpr_from_owner;

	logic                                                       stall_request;

	logic                                                       can_issue_request;
	logic                                                       can_issue_response;
	logic                                                       can_issue_replacement_request;
	logic                                                       can_issue_wb_request;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 1 - TSHR Look-up signals
//  -----------------------------------------------------------------------

	assign ni_request_address                                        = ni_request.memory_address;
	assign ni_response_address                                       = ni_response.memory_address;
	assign rp_request_address                                        = rp_request.memory_address;

	assign dc1_tshr_lookup_tag[REQUEST_TSHR_LOOKUP_PORT]             = ni_request_address.tag;
	assign dc1_tshr_lookup_set[REQUEST_TSHR_LOOKUP_PORT]             = ni_request_address.index;
	assign dc1_tshr_lookup_tag[RESPONSE_TSHR_LOOKUP_PORT]            = ni_response_address.tag;
	assign dc1_tshr_lookup_set[RESPONSE_TSHR_LOOKUP_PORT]            = ni_response_address.index;
	assign dc1_tshr_lookup_tag[REPLACEMENT_REQUEST_TSHR_LOOKUP_PORT] = rp_request_address.tag;
	assign dc1_tshr_lookup_set[REPLACEMENT_REQUEST_TSHR_LOOKUP_PORT] = rp_request_address.index;

	assign request_tshr_hit                                          = tshr_lookup_hit[REQUEST_TSHR_LOOKUP_PORT];
	assign request_tshr_index                                        = tshr_lookup_index[REQUEST_TSHR_LOOKUP_PORT];
	assign request_tshr_entry_info                                   = tshr_lookup_entry_info[REQUEST_TSHR_LOOKUP_PORT];

	assign response_tshr_hit                                         = tshr_lookup_hit[RESPONSE_TSHR_LOOKUP_PORT];
	assign response_tshr_index                                       = tshr_lookup_index[RESPONSE_TSHR_LOOKUP_PORT];
	assign response_tshr_entry_info                                  = tshr_lookup_entry_info[RESPONSE_TSHR_LOOKUP_PORT];

	assign replacement_request_tshr_hit                              = tshr_lookup_hit[REPLACEMENT_REQUEST_TSHR_LOOKUP_PORT];
	assign replacement_request_tshr_index                            = tshr_lookup_index[REPLACEMENT_REQUEST_TSHR_LOOKUP_PORT];
	assign replacement_request_tshr_entry_info                       = tshr_lookup_entry_info[REPLACEMENT_REQUEST_TSHR_LOOKUP_PORT];

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 1 - Stall protocol ROM signals
//  -----------------------------------------------------------------------

	assign dpr_state                                                 = tshr_lookup_entry_info[REQUEST_TSHR_LOOKUP_PORT].state;
	assign dpr_message_type                                          = ni_request.packet_type;
	assign dpr_from_owner                                            = ni_request.source == request_tshr_entry_info.owner;

	dc_stall_protocol_rom stall_protocol_rom (
		.input_state         ( dpr_state        ),
		.input_request       ( dpr_message_type ),
		.input_is_from_owner ( dpr_from_owner   ),
		.dpr_output_stall    ( stall_request    )
	);

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 1 - Can issue signals
//  -----------------------------------------------------------------------

	assign can_issue_request = ni_request_valid && !tshr_full && ( !request_tshr_hit || ( request_tshr_hit && !request_tshr_entry_info.valid) ||( request_tshr_hit && request_tshr_entry_info.valid && !stall_request ) ) &&
		! (
			( dc2_pending ) ||
			( dc3_pending )
		) && ni_forwarded_request_network_available && ni_response_network_available;
	
	// WB Gen Queue has the highest priority since is a transation still
	// in progress. A WB is scheduled as soon as it is pending.
	assign can_issue_response             = ni_response_valid;
	assign can_issue_wb_request           = wb_gen_pending;                           
	always_comb
		can_issue_replacement_request = !rp_empty && !tshr_full && !replacement_request_tshr_hit &&
		! (
			( dc2_pending ) ||
			( dc3_pending )
		) && ni_forwarded_request_network_available && ni_response_network_available;

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 1 - Fixed-priority scheduler
//  -----------------------------------------------------------------------
	// Replacement requests have the highest priority over other requests. It is scheduled as
	// soon as it is pending.

	always_comb begin

		output_message_valid            = 1'b0;
		output_message_type             = 0;
		output_message_tshr_hit         = 0;
		output_message_tshr_index       = 0;
		output_message_tshr_entry_info  = 0;
		output_message_address          = 0;
		output_message_data             = 0;
		output_message_source           = 0;
		dc1_request_consumed            = 1'b0;
		dc1_response_inject_consumed    = 1'b0;
		dc1_wb_request_dequeue          = 1'b0;
		dc1_repl_queue_dequeue          = 1'b0;
		output_replacement_state        = 0;
		output_replacement_sharers_list = 0;
		output_replacement_owner        = 0;
		
		if ( can_issue_wb_request ) begin 
			output_message_valid            = 1'b1;
			output_message_type             = coherence_request_t'(MESSAGE_WB_GEN);
			output_message_address          = wb_gen_addr;
			output_message_data             = wb_gen_data;
			dc1_wb_request_dequeue          = 1'b1;
		end else if ( can_issue_replacement_request ) begin
			output_message_valid            = 1'b1;
			output_message_type             = coherence_request_t'(REPLACEMENT); 
			output_message_tshr_hit         = replacement_request_tshr_hit;
			output_message_tshr_index       = replacement_request_tshr_index;
			output_message_tshr_entry_info  = replacement_request_tshr_entry_info;
			output_message_address          = rp_request_address;
			output_message_data             = rp_request.data;
			output_message_source           = rp_request.source;
			dc1_repl_queue_dequeue          = 1'b1;
			output_replacement_state        = rp_request.state;
			output_replacement_sharers_list = rp_request.sharers_list;
			output_replacement_owner        = rp_request.owner;
		end else if ( can_issue_response ) begin
			output_message_valid            = 1'b1;
			output_message_type             = ni_response.packet_type;
			output_message_tshr_hit         = response_tshr_hit;
			output_message_tshr_index       = response_tshr_index;
			output_message_tshr_entry_info  = response_tshr_entry_info;
			output_message_address          = ni_response_address;
			output_message_data             = ni_response.data;
			output_message_source           = ni_response.source;
			dc1_response_inject_consumed    = 1'b1;
		end else if ( can_issue_request ) begin
			output_message_valid            = 1'b1;
			output_message_type             = ni_request.packet_type;
			output_message_tshr_hit         = request_tshr_hit;
			output_message_tshr_index       = request_tshr_index;
			output_message_tshr_entry_info  = request_tshr_entry_info;
			output_message_address          = ni_request_address;
			output_message_data             = ni_request.data;
			output_message_source           = ni_request.source;
			dc1_request_consumed            = 1'b1;
		end
	end

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 1 - Main output registers
//  -----------------------------------------------------------------------

	always_ff @( posedge clk ) begin
		dc1_message_type             <= output_message_type;
		dc1_message_tshr_hit         <= output_message_tshr_hit;
		dc1_message_tshr_index       <= output_message_tshr_index;
		dc1_message_tshr_entry_info  <= output_message_tshr_entry_info;
		dc1_message_address          <= output_message_address;
		dc1_message_data             <= output_message_data;
		dc1_message_source           <= output_message_source;
		dc1_replacement_state        <= output_replacement_state;
		dc1_replacement_sharers_list <= output_replacement_sharers_list;
		dc1_replacement_owner        <= output_replacement_owner;
	end


	always_ff @( posedge clk, posedge reset ) begin
		if ( reset )
			dc1_message_valid <= 1'b0;
		else
			dc1_message_valid <= output_message_valid;
	end

//  -----------------------------------------------------------------------
//  -- Directory Controller Stage 1 - L2 Tag & valid array
//  -----------------------------------------------------------------------

	generate
		genvar way_idx;
		for ( way_idx = 0; way_idx < `L2_CACHE_WAY; way_idx++ ) begin : WAY_ALLOCATOR

			cache_tag_entry_t                          cache_input;
			cache_tag_entry_t                          cache_output;
			logic             [`L2_CACHE_SET - 1 : 0 ] valid;
			logic                                      update_this_way;

			assign update_this_way                = dc3_update_cache_enable && dc3_update_cache_way == l2_cache_way_idx_t'( way_idx );

			always_ff @( posedge clk, posedge reset ) begin
				if ( reset ) begin
					valid                       <= {`L2_CACHE_SET{1'b0}};
				end else if ( update_this_way ) begin
					valid[dc3_update_cache_set] <= dc3_update_cache_validity_bit;
				end
			end

			always_ff @( posedge clk ) begin
				if ( output_message_valid )
					dc1_message_cache_valid[way_idx] <= valid[output_message_address.index];
			end

			assign cache_input.tag                = dc3_update_cache_tag,
				cache_input.state                 = dc3_update_cache_state;

			memory_bank_1r1w #(
				.SIZE       ( `L2_CACHE_SET              ),
				.ADDR_WIDTH ( $clog2( `L2_CACHE_SET )    ),
				.COL_WIDTH  ( $bits( cache_tag_entry_t ) ),
				.NB_COL     ( 1                          ),
				.WRITE_FIRST( "TRUE"                     )
			) tag_sram (
				.clock        ( clk                          ),
				.read_enable  ( output_message_valid         ),
				.read_address ( output_message_address.index ),
				.write_enable ( update_this_way              ),
				.write_address( dc3_update_cache_set         ),
				.write_data   ( cache_input                  ),
				.read_data    ( cache_output                 )
			);

			assign dc1_message_cache_tag[way_idx] = cache_output.tag,
				dc1_message_cache_state[way_idx]  = cache_output.state;

		end
	endgenerate

`ifdef DISPLAY_COHERENCE

	always_ff @( posedge clk )
		if ( output_message_valid & ~reset ) begin
			$fdisplay( `DISPLAY_COHERENCE_VAR, "=======================" );
			$fdisplay( `DISPLAY_COHERENCE_VAR, "Directory Controller - [Time %.16d] [TILE %.2d] - Message Received", $time( ), TILE_ID );

			if ( can_issue_replacement_request ) begin
				print_rep( rp_request );
			end else if ( can_issue_response ) begin
				print_resp( ni_response );
			end else if ( can_issue_request ) begin
				print_req( ni_request );
			end

			$fflush( `DISPLAY_COHERENCE_VAR );
		end
`endif

endmodule
