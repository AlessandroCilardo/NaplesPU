`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_network_defines.sv"
`include "npu_debug_log.sv"

/*
 *  CORRECT INTERPRETATION OF TILE POSITION:
 *
 *     EXAMPLE: 3 x 3
 *
 *                       N
 *                       |
 *      TILE 4:     W -- 4 -- E
 *                       |
 *                       S
 *
 *
 *          0 ---- 1 ---- 2
 *          |      |      |
 *          |      |      |
 *          3 ---- 4 ---- 5
 *          |      |      |
 *          |      |      |
 *          6 ---- 7 ---- 8
 */

module npu_noc #(
		parameter ID               = 0, // TILE ID (maybe is not needed)
		parameter TLID_w           = 10, // ID width (maybe is not needed)
		parameter NODE_ID_w        = 10, // Node ID width (node id width, internal to NaplesPU)
		parameter MEM_ADDR_w       = 32, // Memory address width (in bits)
		parameter MEM_DATA_BLOCK_w = 512, // Memory data block width (in bits)
		parameter ITEM_w           = 32 )
	(
		input                             clk,
		input                             reset,
		input                             enable,

		// interface MEM_TILEREG <-> NaplesPU
		input  [ITEM_w - 1 : 0]           item_data_i,          // Input: items from outside
		input                             item_valid_i,         // Input: valid signal associated with item_data_i port
		output                            item_avail_o,         // Output: avail signal to input port item_data_i
		output [ITEM_w - 1 : 0]           item_data_o,          // Output: items to outside
		output                            item_valid_o,         // Output: valid signal associated with item_data_o port
		input                             item_avail_i,         // Input: avail signal to output port item_data_o

		// interface MC
		output                            n2m_request_is_instr, // XXX: Debug signal!!
		//output [7 : 0]                    nu_leds_out,          // XXX: Debug signal!!
		//output [3 : 0]                    nu_thread_en,

		output [MEM_ADDR_w - 1 : 0]       mc_address_o,         // output: Address to MC
		output             [63 : 0]       mc_dirty_mask_o,         // output: Address to MC
		output [MEM_DATA_BLOCK_w - 1 : 0] mc_block_o,           // output: Data block to MC
		output                            mc_avail_o,           // output: available bit from UNIT
		output [NODE_ID_w - 1 : 0]        mc_sender_o,          // output: sender to MC
		output                            mc_read_o,            // output: read request to MC
		output                            mc_write_o,           // output: write request to MC
		input  [MEM_ADDR_w - 1 : 0]       mc_address_i,         // input: Address from MC
		input  [MEM_DATA_BLOCK_w - 1 : 0] mc_block_i,           // input: Data block from MC
		input  [NODE_ID_w - 1 : 0]        mc_dst_i,             // input: destination from MC
		input  [NODE_ID_w - 1 : 0]        mc_sender_i,          // input: Sender from MC
		input                             mc_read_avail_i,      // input: read available signal from MC
		input                             mc_write_avail_i,     // input: write available signal from MC
		input                             mc_valid_i,           // input: valid bit from MC
		input                             mc_request_i          // input: Read/Write request from MC
	);

	localparam NoC_ROW = `NoC_Y_WIDTH;
	localparam NoC_COL = `NoC_X_WIDTH;


	logic      [MEM_ADDR_w - 1 : 0]                      n2m_request_address;
	logic                  [63 : 0]                      n2m_request_dirty_mask;
	logic      [MEM_DATA_BLOCK_w - 1 : 0]                n2m_request_data;
	logic                                                n2m_request_read;
	logic                                                n2m_request_write;

	logic      [`THREAD_NUMB - 1 : 0]                    thread_en [NoC_ROW][NoC_COL];
	logic      [`PORT_NUM - 1 : 1]                       tile_wr_en_in [NoC_ROW][NoC_COL];
	flit_t     [`PORT_NUM - 1 : 1]                       tile_flit_in [NoC_ROW][NoC_COL];
	logic      [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_in [NoC_ROW][NoC_COL];
	logic      [`PORT_NUM - 1 : 1]                       tile_flit_out_valid [NoC_ROW][NoC_COL];
	flit_t     [`PORT_NUM - 1 : 1]                       tile_flit_out [NoC_ROW][NoC_COL];
	logic      [`PORT_NUM - 1 : 1][`VC_PER_PORT - 1 : 0] tile_on_off_out [NoC_ROW][NoC_COL];
	assign mc_address_o = n2m_request_address;
	assign mc_dirty_mask_o = n2m_request_dirty_mask;
	assign mc_block_o   = n2m_request_data;
	assign mc_read_o    = n2m_request_read;
	assign mc_write_o   = n2m_request_write;
	assign mc_sender_o  = 0;

	genvar                                               col, row;
	generate
		for ( row = 0; row < NoC_ROW; row++ ) begin : NOC_ROW_GEN
			for ( col = 0; col < NoC_COL; col++ ) begin : NOC_COL_GEN

				if ( ( row * NoC_COL + col ) == `TILE_MEMORY_ID ) begin : TILE_MC_INST
					tile_mc #(
						.TILE_ID            ( `TILE_MEMORY_ID  ),
						.TILE_MEMORY_ID     ( `TILE_MEMORY_ID  ),
						.MEM_ADDRESS_WIDTH( MEM_ADDR_w       ),
						.MEM_DATA_WIDTH   ( MEM_DATA_BLOCK_w )
					)
					u_tile_mc (
						.clk                         ( clk                           ),
						.reset                       ( reset                         ),
						.enable                      ( enable                        ),
						//From Network
						.tile_wr_en_in               ( tile_wr_en_in[row][col]       ),
						.tile_flit_in                ( tile_flit_in[row][col]        ),
						.tile_on_off_in              ( tile_on_off_in[row][col]      ),
						//To Network
						.tile_flit_out_valid         ( tile_flit_out_valid[row][col] ),
						.tile_flit_out               ( tile_flit_out[row][col]       ),
						.tile_on_off_out             ( tile_on_off_out[row][col]     ),
						//To MEM NI
						.n2m_request_address         ( n2m_request_address           ),
						.n2m_request_dirty_mask      ( n2m_request_dirty_mask        ),
						.n2m_request_data            ( n2m_request_data              ),
						.n2m_request_read            ( n2m_request_read              ),
						.n2m_request_write           ( n2m_request_write             ),
						.n2m_request_is_instr        ( n2m_request_is_instr          ),
						.n2m_avail                   ( mc_avail_o                    ),
						//From MEM NI
						.m2n_request_read_available  ( mc_read_avail_i               ),
						.m2n_request_write_available ( mc_write_avail_i              ),
						.m2n_response_valid          ( mc_valid_i                    ),
						.m2n_response_address        ( mc_address_i                  ),
						.m2n_response_data           ( mc_block_i                    )
					);

				end else if (( row * NoC_COL + col ) == `TILE_H2C_ID ) begin: TILE_H2C_INST
					tile_h2c #(
						.TILE_ID       ( `TILE_H2C_ID    ),
						.TILE_MEMORY_ID( `TILE_MEMORY_ID ),
						.ITEM_w        ( ITEM_w          )
					)
					u_tile_h2c (
						.clk                ( clk                           ),
						.reset              ( reset                         ),
						.enable             ( enable                        ),
						//From Network
						.tile_wr_en_in      ( tile_wr_en_in[row][col]       ),
						.tile_flit_in       ( tile_flit_in[row][col]        ),
						.tile_on_off_in     ( tile_on_off_in[row][col]      ),
						//To Network
						.tile_flit_out_valid( tile_flit_out_valid[row][col] ),
						.tile_flit_out      ( tile_flit_out[row][col]       ),
						.tile_on_off_out    ( tile_on_off_out[row][col]     ),
						//Interface to Host
						.item_data_i        ( item_data_i                   ), //Input: items from outside
						.item_valid_i       ( item_valid_i                  ), //Input: valid signal associated with item_data_i port
						.item_avail_o       ( item_avail_o                  ), //Output: avail signal to input port item_data_i
						.item_data_o        ( item_data_o                   ), //Output: items to outside
						.item_valid_o       ( item_valid_o                  ), //Output: valid signal associated with item_data_o port
						.item_avail_i       ( item_avail_i                  )  //Input: avail signal to ouput port item_data_o
					);
				end else if ( ( row * NoC_COL + col ) < `TILE_NPU ) begin: TILE_NPU_INST
					tile_npu #(
						.TILE_ID       ( ( row * NoC_COL + col ) ),
						.TILE_MEMORY_ID( `TILE_MEMORY_ID         ),
						.CORE_ID       ( 0                       ),
		                .SCRATCHPAD    ( `NPU_SPM                ),
		                .FPU           ( `NPU_FPU                )
					)
					u_tile_npu (
						.clk                ( clk                           ),
						.reset              ( reset                         ),
						.enable             ( enable                        ),
						//From Network
						.tile_wr_en_in      ( tile_wr_en_in[row][col]       ),
						.tile_flit_in       ( tile_flit_in[row][col]        ),
						.tile_on_off_in     ( tile_on_off_in[row][col]      ),
						//To Network
						.tile_flit_out_valid( tile_flit_out_valid[row][col] ),
						.tile_flit_out      ( tile_flit_out[row][col]       ),
						.tile_on_off_out    ( tile_on_off_out[row][col]     )
					);
				end else if ( ( row * NoC_COL + col ) < ( `TILE_NPU + `TILE_HT ) ) begin: TILE_HT_INST
					tile_ht #(
						.TILE_ID       ( ( row * NoC_COL + col ) ),
						.TILE_MEMORY_ID( `TILE_MEMORY_ID         ),
						.CORE_ID       ( 0                       )
					)
					u_tile_ht (
						.clk                ( clk                           ),
						.reset              ( reset                         ),
						.enable             ( enable                        ),
						//From Network
						.tile_wr_en_in      ( tile_wr_en_in[row][col]       ),
						.tile_flit_in       ( tile_flit_in[row][col]        ),
						.tile_on_off_in     ( tile_on_off_in[row][col]      ),
						//To Network
						.tile_flit_out_valid( tile_flit_out_valid[row][col] ),
						.tile_flit_out      ( tile_flit_out[row][col]       ),
						.tile_on_off_out    ( tile_on_off_out[row][col]     )
					);
				end else begin: TILE_NONE_INST
					tile_none #(
						.TILE_ID( ( row * NoC_COL + col ) )
					)
					u_tile_none (
						.clk                ( clk                           ),
						.reset              ( reset                         ),
						.enable             ( enable                        ),
						//From Network
						.tile_wr_en_in      ( tile_wr_en_in[row][col]       ),
						.tile_flit_in       ( tile_flit_in[row][col]        ),
						.tile_on_off_in     ( tile_on_off_in[row][col]      ),
						//To Network
						.tile_flit_out_valid( tile_flit_out_valid[row][col] ),
						.tile_flit_out      ( tile_flit_out[row][col]       ),
						.tile_on_off_out    ( tile_on_off_out[row][col]     )
					);
				end
			end
		end
	endgenerate

	generate
		for ( row = 0; row < NoC_ROW; row++ ) begin: row_inst

			assign tile_on_off_in[row][0 ][WEST]           = {`VC_PER_PORT{1'b1}};
			assign tile_wr_en_in [row][0 ][WEST]           = 1'b0;
			assign tile_on_off_in[row][NoC_COL - 1 ][EAST] = {`VC_PER_PORT{1'b1}};
			assign tile_wr_en_in [row][NoC_COL - 1 ][EAST] = 1'b0;

			for ( col = 0; col < NoC_COL - 1; col++ ) begin
				assign tile_wr_en_in [row][col ][EAST]    = tile_flit_out_valid[row][col + 1][WEST];
				assign tile_flit_in [row][col ][EAST]     = tile_flit_out [row][col + 1][WEST];
				assign tile_on_off_in[row][col ][EAST]    = tile_on_off_out [row][col + 1][WEST];

				assign tile_wr_en_in [row][col + 1][WEST] = tile_flit_out_valid[row][col ][EAST];
				assign tile_flit_in [row][col + 1][WEST]  = tile_flit_out [row][col ][EAST];
				assign tile_on_off_in[row][col + 1][WEST] = tile_on_off_out [row][col ][EAST];
			end
		end
	endgenerate


	generate

		for ( col = 0; col < NoC_COL; col++ ) begin: col_inst

			assign tile_on_off_in[0 ][col][NORTH]          = {`VC_PER_PORT{1'b1}};
			assign tile_wr_en_in [0 ][col][NORTH]          = 1'b0;
			assign tile_on_off_in[NoC_ROW - 1][col][SOUTH] = {`VC_PER_PORT{1'b1}};
			assign tile_wr_en_in [NoC_ROW - 1][col][SOUTH] = 1'b0;

			for ( row = 0; row < NoC_ROW - 1; row++ ) begin
				assign tile_wr_en_in [row + 1][col][NORTH] = tile_flit_out_valid[row ][col][SOUTH];
				assign tile_flit_in [row + 1][col][NORTH]  = tile_flit_out [row ][col][SOUTH];
				assign tile_on_off_in[row + 1][col][NORTH] = tile_on_off_out [row ][col][SOUTH];

				assign tile_wr_en_in [row ][col][SOUTH]    = tile_flit_out_valid[row + 1][col][NORTH];
				assign tile_flit_in [row ][col][SOUTH]     = tile_flit_out [row + 1][col][NORTH];
				assign tile_on_off_in[row ][col][SOUTH]    = tile_on_off_out [row + 1][col][NORTH];

			end
		end
	endgenerate
	
endmodule
