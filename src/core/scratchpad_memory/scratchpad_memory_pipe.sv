`timescale 1ns / 1ps
`include "npu_defines.sv"
`include "npu_spm_defines.sv"
`include "npu_debug_log.sv"

module scratchpad_memory_pipe (
		input  logic                 clk,
		input  logic                 reset,

		//From Operand Fetch
		input  logic                 opf_valid,
		input  instruction_decoded_t opf_inst_scheduled,
		input  hw_lane_t             opf_fetched_op0,
		input  hw_lane_t             opf_fetched_op1,
		input  hw_lane_mask_t        opf_hw_lane_mask,

		//To Writeback
		output logic                 spm_valid,
		output instruction_decoded_t spm_inst_scheduled,
		output hw_lane_t             spm_result,
		output hw_lane_mask_t        spm_hw_lane_mask,

		//To Dynamic Scheduler
		output logic                 spm_can_issue,

		//To Rollback Handler
		output logic                 spm_rollback_en,
		output register_t            spm_rollback_pc,
		output thread_id_t           spm_rollback_thread_id
	);

	typedef struct packed {
		logic is_store;
		sm_address_t [`SM_PROCESSING_ELEMENTS   - 1 : 0] addresses;
		sm_data_t [`SM_PROCESSING_ELEMENTS      - 1 : 0] write_data;
		sm_byte_mask_t [`SM_PROCESSING_ELEMENTS - 1 : 0] byte_mask;
		logic [`SM_PROCESSING_ELEMENTS          - 1 : 0] mask;
		logic [`SM_PIGGYBACK_DATA_LEN           - 1 : 0] piggyback_data;
	} scratchpad_memory_request_t;

    localparam FIFO_SIZE                    = 4;
    localparam FIFO_ALMOST_FULL_THRESHOLD   = (FIFO_SIZE - 3);
    localparam FIFO_WIDTH                   = $bits(scratchpad_memory_request_t);


	//From scratchpad_memory

	logic                                                         sm_ready;
	logic                                                         sm_valid;
	sm_data_t                   [`SM_PROCESSING_ELEMENTS - 1 : 0] sm_read_data;
	sm_byte_mask_t              [`SM_PROCESSING_ELEMENTS - 1 : 0] sm_byte_mask;
	logic                       [`SM_PROCESSING_ELEMENTS - 1 : 0] sm_mask;
	logic                       [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  sm_piggyback_data;

//  -----------------------------------------------------------------------------------------
//  -- Input Stage
//  -----------------------------------------------------------------------------------------

	logic                                                         instruction_valid;
	logic                                                         is_doubleword_op;
	logic                                                         is_word_op;
	logic                                                         is_halfword_op;
	logic                                                         is_byte_op;

	hw_lane_t                                                     effective_addresses;
	logic                       [`HW_LANE - 1 : 0]                is_word_aligned;
	logic                       [`HW_LANE - 1 : 0]                is_halfword_aligned;

	logic                                                         is_misaligned;
	logic                                                         is_out_of_memory;

	hw_lane_t                                                     byte_aligned_data;
	sm_byte_mask_t              [`HW_LANE - 1 : 0]                byte_aligned_byte_mask;
	hw_lane_t                                                     halfword_aligned_data;
	sm_byte_mask_t              [`HW_LANE - 1 : 0]                halfword_aligned_byte_mask;
	register_t                                                    mask;

	scratchpad_memory_request_t                                   fifo_input_scratchpad_request;
	scratchpad_memory_request_t                                   fifo_output_scratchpad_request;
	logic                                                         fifo_empty;
	logic                                                         fifo_almost_full;

	assign instruction_valid = opf_valid && ( opf_inst_scheduled.pipe_sel == PIPE_SPM );
	assign is_out_of_memory  = 1'b0;

//-----------------------------------------------------------------------------------------
// Building Operands
//-----------------------------------------------------------------------------------------

	assign is_doubleword_op  = opf_inst_scheduled.op_code.mem_opcode == LOAD_64 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_64 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_64 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_64 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_V_64 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_S_64;

	assign is_word_op        = opf_inst_scheduled.op_code.mem_opcode == LOAD_32 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_32_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_32 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_32_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_32 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_32_U ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_32 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_V_32 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_S_32;

	assign is_halfword_op    = opf_inst_scheduled.op_code.mem_opcode == LOAD_16 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_16_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_16 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_16_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_16 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_16_U ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_16 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_V_16 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_S_16;

	assign is_byte_op        = opf_inst_scheduled.op_code.mem_opcode == LOAD_8 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_8_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_8 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_V_8_U ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_8 ||
		opf_inst_scheduled.op_code.mem_opcode == LOAD_G_8_U ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_8 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_V_8 ||
		opf_inst_scheduled.op_code.mem_opcode == STORE_S_8;


	genvar                                                        lane_idx;
	generate
		for ( lane_idx = 0; lane_idx < `HW_LANE; lane_idx++ ) begin
			assign effective_addresses[lane_idx]     = opf_fetched_op0[0] + 4 * lane_idx;// + opf_fecthed_op1[lane_idx];    //TODO: Permettere altri modi di indirizzamento.
			assign is_word_aligned[lane_idx]         = !( |( effective_addresses[lane_idx][1 : 0] ) );
			assign is_halfword_aligned[lane_idx]     = !effective_addresses[lane_idx][0];
			always_comb begin : byte_aligner
				logic [1 : 0] byte_offset;
				byte_offset = effective_addresses[lane_idx][1 : 0];
				case ( byte_offset )
					2'b00 :
					begin
						byte_aligned_data[lane_idx][7 : 0  ]        = opf_fetched_op1[lane_idx][7 : 0] ;
						byte_aligned_byte_mask[lane_idx]            = 4'b0001;
					end

					2'b01 :
					begin
						byte_aligned_data[lane_idx][15 : 8 ]        = opf_fetched_op1[lane_idx][7 : 0];
						byte_aligned_byte_mask[lane_idx]            = 4'b0010;
					end

					2'b10 :
					begin
						byte_aligned_data[lane_idx][23 : 16]        = opf_fetched_op1[lane_idx][7 : 0];
						byte_aligned_byte_mask[lane_idx]            = 4'b0100;
					end

					2'b11 :
					begin
						byte_aligned_data[lane_idx][31 : 24]        = opf_fetched_op1[lane_idx][7 : 0];
						byte_aligned_byte_mask[lane_idx]            = 4'b1000;
					end

					default :
					begin
						byte_aligned_data[lane_idx][31 : 0 ]        = 32'bX;
						byte_aligned_byte_mask[lane_idx]            = 4'b0000;
					end
				endcase
			end

			always_comb begin : halfword_aligner
				logic halfword_offset;
				halfword_offset = effective_addresses[lane_idx][1];
				case ( halfword_offset )
					1'b0 :
					begin
						halfword_aligned_data[lane_idx     ][15 : 0 ]  = opf_fetched_op1[lane_idx][15 : 0];
						halfword_aligned_byte_mask[lane_idx]           = 4'b0011;
					end

					1'b1 :
					begin
						halfword_aligned_data[lane_idx     ][31 : 16]  = opf_fetched_op1[lane_idx][15 : 0];
						halfword_aligned_byte_mask[lane_idx]           = 4'b1100;
					end

					default : begin
						halfword_aligned_data[lane_idx     ][31 : 0 ]  = 32'bX;
						halfword_aligned_byte_mask[lane_idx]           = 4'b0000;
					end
				endcase
			end


		end
	endgenerate

	always_comb begin : mask_generator
		case ( opf_inst_scheduled.op_code.mem_opcode )
			// Scalar operations
			LOAD_8,
			LOAD_8_U,
			LOAD_16,
			LOAD_16_U,
			LOAD_32,
			LOAD_32_U,
			STORE_8,
			STORE_16,
			STORE_32   : mask = register_t'( 1'b1 );

			// Vectorial operations
			LOAD_V_8,
			LOAD_V_8_U,
			LOAD_V_16,
			LOAD_V_16_U,
			LOAD_V_32,
			LOAD_V_32_U,
			STORE_V_8,
			STORE_V_16,
			STORE_V_32,
			LOAD_G_8,
			LOAD_G_8_U,
			LOAD_G_16,
			LOAD_G_16_U,
			LOAD_G_32,
			LOAD_G_32_U,
			STORE_S_8,
			STORE_S_16,
			STORE_S_32 : mask = opf_hw_lane_mask;

			// Double
			LOAD_64,
			STORE_64   : ; 

			LOAD_V_64,
			STORE_V_64,
			LOAD_G_64,
			STORE_S_64 : ; //XXX: Currently not supported
			default :
			begin
				mask          = register_t'( 1'b0 );
			end
		endcase

	end

	assign is_misaligned     = ( is_word_op && ( |( ~is_word_aligned & mask[`HW_LANE - 1 : 0] ) ) ) ||
		( is_halfword_op && ( |( ~is_halfword_aligned & mask[`HW_LANE - 1 : 0] ) ) );

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			spm_rollback_en <= 1'b0;
		else
			spm_rollback_en <= instruction_valid & ( is_misaligned | is_out_of_memory );

	always_ff @ ( posedge clk ) begin
		spm_rollback_pc        <= `SPM_ADDR_MISALIGN_ISR;
		spm_rollback_thread_id <= opf_inst_scheduled.thread_id;
	end

	generate
		for ( lane_idx = 0; lane_idx < `HW_LANE; lane_idx++ )
			assign
				fifo_input_scratchpad_request.addresses[lane_idx] = effective_addresses[lane_idx][`SM_ADDRESS_LEN - 1 : 0];
	endgenerate

	always_comb begin
		fifo_input_scratchpad_request.is_store       = ~opf_inst_scheduled.is_load;

		if ( is_word_op ) begin
			fifo_input_scratchpad_request.write_data = opf_fetched_op1;
			fifo_input_scratchpad_request.byte_mask  = {`HW_LANE{{`REGISTER_SIZE/8{1'b1}}}}; 
		end else if ( is_halfword_op ) begin
			fifo_input_scratchpad_request.write_data = halfword_aligned_data;
			fifo_input_scratchpad_request.byte_mask  = halfword_aligned_byte_mask;
		end else if ( is_byte_op ) begin
			fifo_input_scratchpad_request.write_data = byte_aligned_data;
			fifo_input_scratchpad_request.byte_mask  = byte_aligned_byte_mask;
		end

		fifo_input_scratchpad_request.mask           = mask[`HW_LANE - 1 : 0];
		fifo_input_scratchpad_request.piggyback_data = opf_inst_scheduled; 
	end


	// Request queue
	sync_fifo #(
		.WIDTH                ( FIFO_WIDTH                 ),
		.SIZE                 ( FIFO_SIZE                  ),
		.ALMOST_FULL_THRESHOLD( FIFO_ALMOST_FULL_THRESHOLD )
	) requests_fifo (
		.clk         ( clk                                   ),
		.reset       ( reset                                 ),
		.flush_en    ( 1'b0                                  ),
		.full        (                                       ),
		.almost_full ( fifo_almost_full                      ),
		.enqueue_en  ( instruction_valid && !spm_rollback_en ),
		.value_i     ( fifo_input_scratchpad_request         ),
		.empty       ( fifo_empty                            ),
		.almost_empty(                                       ),
		.dequeue_en  ( sm_ready && !fifo_empty               ),
		.value_o     ( fifo_output_scratchpad_request        )
	);

	assign spm_can_issue     = ~fifo_almost_full;


//-----------------------------------------------------------------------------------------
// --   Scratchpad memory
//-----------------------------------------------------------------------------------------

	scratchpad_memory scratchpad_memory (
		.clock            ( clk                                           ),
		.resetn           ( ~reset                                        ),

		.start            ( ~fifo_empty                                   ),
		.is_store         ( fifo_output_scratchpad_request.is_store       ),
		.addresses        ( fifo_output_scratchpad_request.addresses      ),
		.write_data       ( fifo_output_scratchpad_request.write_data     ),
		.byte_mask        ( fifo_output_scratchpad_request.byte_mask      ),
		.mask             ( fifo_output_scratchpad_request.mask           ),
		.piggyback_data   ( fifo_output_scratchpad_request.piggyback_data ),

		.sm_ready         ( sm_ready                                      ),
		.sm_valid         ( sm_valid                                      ),
		.sm_read_data     ( sm_read_data                                  ),
		.sm_byte_mask     ( sm_byte_mask                                  ),
		.sm_mask          ( sm_mask                                       ),
		.sm_piggyback_data( sm_piggyback_data                             )
	);


//  -----------------------------------------------------------------------------------------
//  --  Output Stage
//  -----------------------------------------------------------------------------------------

	generate
		for ( lane_idx = 0; lane_idx < `HW_LANE; lane_idx++ ) begin
			always_ff @( posedge clk ) begin : output_data_aligner
				case ( sm_byte_mask[lane_idx] )
					4'b0001 : begin
						spm_result[lane_idx][31 : 8 ]    <= 0;
						spm_result[lane_idx][7 : 0  ]    <= sm_read_data[lane_idx][7 : 0  ];
					end
					4'b0010 : begin
						spm_result[lane_idx][31 : 8 ]    <= 0;
						spm_result[lane_idx][7 : 0  ]    <= sm_read_data[lane_idx][15 : 8 ];
					end
					4'b0100 : begin
						spm_result[lane_idx][31 : 8 ]    <= 0;
						spm_result[lane_idx][7 : 0  ]    <= sm_read_data[lane_idx][23 : 16];
					end
					4'b1000 : begin
						spm_result[lane_idx][31 : 8 ]    <= 0;
						spm_result[lane_idx][7 : 0  ]    <= sm_read_data[lane_idx][31 : 24];
					end
					4'b0011 : begin
						spm_result[lane_idx][31 : 16]    <= 0;
						spm_result[lane_idx][15 : 0 ]    <= sm_read_data[lane_idx][15 : 0 ];
					end
					4'b1100 : begin
						spm_result[lane_idx][31 : 16]    <= 0;
						spm_result[lane_idx][15 : 0 ]    <= sm_read_data[lane_idx][31 : 16];
					end
					4'b1111 : spm_result[lane_idx]    <= sm_read_data[lane_idx];
					default : ;
				endcase
			end
		end
	endgenerate

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			spm_valid          <= 1'b0;
		end else begin
			spm_valid          <= sm_valid;
			spm_inst_scheduled <= sm_piggyback_data;
			spm_hw_lane_mask   <= sm_mask;
		end

	end

`ifdef DISPLAY_SPM
			always_ff @ ( posedge clk, posedge reset ) begin
				if ( instruction_valid ) begin

					$fdisplay( `DISPLAY_SPM_VAR, "=======================" );
					$fdisplay( `DISPLAY_SPM_VAR, "SPM Unit - [Time %.16d] [TILE %.2h] - ", $time( ), TILE_ID );
					$fdisplay( `DISPLAY_SPM_VAR, "Address:   %08h", effective_addresses[0] );
					$fdisplay( `DISPLAY_SPM_VAR, "Operation: %s", opf_inst_scheduled.op_code.mem_opcode.name() );

					$fflush( `DISPLAY_SPM_VAR );
				end
			end
`endif

endmodule
