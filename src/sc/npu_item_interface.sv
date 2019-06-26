`timescale 1ns / 1ps
`include "npu_defines.sv"

module npu_item_interface #(
		parameter ID               = 0,   // TILE ID (maybe is not needed)
		parameter TLID_w           = 10,  // ID width (maybe is not needed)
		parameter NODE_ID_w        = 10,  // Node ID width (node id width, internal to NPU)
		parameter MEM_ADDR_w       = 32,  // Memory address width (in bits)
		parameter MEM_DATA_BLOCK_w = 512, // Memory data block width (in bits)
		parameter ITEM_w           = 32   // Input and output item width (control interface
	)(
		input                                             clk,
		input                                             reset,              // Input: positive reset signal

		// To NaplesPU
		output                 [`THREAD_NUMB - 1 : 0]     hi_thread_en,
		output logic                                      hi_job_valid,
		output address_t                                  hi_job_pc,
		output thread_id_t                                hi_job_thread_id,

		// To NaplesPU Control Register
		output logic                                      hi_read_cr_valid,
		output register_t                                 hi_read_cr_request,
		output logic                                      hi_write_cr_valid,
		output register_t                                 hi_write_cr_data,
		input  register_t                                 cr_response,

		// interface MEM_TILEREG <-> NPU
		input                  [ITEM_w - 1 : 0]           item_data_i,        // Input: items from outside
		input                                             item_valid_i,       // Input: valid signal associated with item_data_i port
		output                                            item_avail_o,       // Output: avail signal to input port item_data_i
		output                 [ITEM_w - 1 : 0]           item_data_o,        // Output: items to outside
		output                                            item_valid_o,       // Output: valid signal associated with item_data_o port
		input                                             item_avail_i        // Input: avail signal to output port item_data_o

	);

//  -----------------------------------------------------------------------
//  -- NaplesPU Item Interface - Local parameters and typedefs 
//  -----------------------------------------------------------------------
    localparam HOST_COMMAND_NUM   = 32;
    localparam HOST_COMMAND_WIDTH =  $clog2( HOST_COMMAND_NUM );

    typedef enum logic [HOST_COMMAND_WIDTH - 1 : 0] {
        HN_BOOT_COMMAND         = 0, 
        HN_BOOT_ACK             = 1, 
        HN_ENABLE_CORE_COMMAND  = 2, 
        HN_ENABLE_CORE_ACK      = 3, 
        HN_READ_STATUS_COMMAND  = 8, 
        HN_WRITE_STATUS_COMMAND = 9, 
        HN_LOG_REQUEST          = 10 
    } hn_messages_t;

    typedef enum {
        IDLE,
        BOOT_WAIT_THREAD_ID,
        BOOT_WAIT_PC,
        ENABLE_CORE_WAIT_TM,
        READ_STATUS_WAIT_DATA,
        READ_STATUS_WAIT_CR,
        WRITE_STATUS_WAIT_INFO,
        WRITE_STATUS_WAIT_DATA,
        WRITE_STATUS_WAIT_CR 
    } interface_state_t;

    function interface_state_t read_message_from_host ( hn_messages_t message_in );
        interface_state_t next_state;
        unique case ( message_in )
            HN_BOOT_COMMAND         : next_state = BOOT_WAIT_THREAD_ID;
            HN_ENABLE_CORE_COMMAND  : next_state = ENABLE_CORE_WAIT_TM;
            HN_READ_STATUS_COMMAND  : next_state = READ_STATUS_WAIT_DATA;
            HN_WRITE_STATUS_COMMAND : next_state = WRITE_STATUS_WAIT_INFO;
            HN_LOG_REQUEST          : next_state = WAIT_LOG_CMD;
            default : next_state                 = IDLE;
        endcase

        return next_state;

    endfunction : read_message_from_host

//  -----------------------------------------------------------------------
//  -- NaplesPU Item Interface - Internal signals
//  -----------------------------------------------------------------------
	interface_state_t                           state, next_state;
	logic                                       avail_out, valid_out, boot_valid;
	address_t                                   boot_pc;
	logic                [`THREAD_NUMB - 1 : 0] thread_en;
	logic                                       update_thread_en, update_boot_thread_id;

	thread_id_t                                 boot_thread_id;
	hn_messages_t                               message_in;
	logic                [31 : 0]               message_out;

	// Output to the Item network
	assign item_avail_o        = avail_out;
	assign item_valid_o        = valid_out;
	assign item_data_o         = message_out;
	
	// Request from the Host conversion
	assign message_in          = hn_messages_t'( item_data_i );
	
	// Output to the Thread Controller of the Core
	assign hi_thread_en        = thread_en;
	assign hi_job_thread_id    = boot_thread_id;
	assign hi_job_valid        = boot_valid;
	assign hi_job_pc           = boot_pc;
	
//  -----------------------------------------------------------------------
//  -- Control Unit - Counter and Next State sequential
//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			state          <= IDLE;
			thread_en      <= {`THREAD_NUMB{1'b0}};
			boot_thread_id <= thread_id_t'(0);
		end else begin
			state          <= next_state; // default is to stay in current state
			if ( update_thread_en )
				thread_en      <= item_data_i[`THREAD_NUMB - 1 : 0];
			if ( update_boot_thread_id )
				boot_thread_id <= thread_id_t'( item_data_i );
		end

//  -----------------------------------------------------------------------
//  -- Control Unit - Next State Block
//  -----------------------------------------------------------------------
	always_comb begin
		next_state <= state;

		unique case ( state )

			IDLE : begin
				if ( item_valid_i ) begin
					next_state <= read_message_from_host( message_in );
				end else
					next_state <= IDLE;
			end

			// Sets a Thread Program Counter
			BOOT_WAIT_THREAD_ID    : begin
				if ( item_valid_i )
					next_state <= BOOT_WAIT_PC;
				else
					next_state <= BOOT_WAIT_THREAD_ID;
			end

			BOOT_WAIT_PC           : begin
				if ( item_valid_i )
					next_state <= IDLE;
				else
					next_state <= BOOT_WAIT_PC;
			end

			/* --- Control/Performance Registers Communication --- */

			// Sets the Thread enable mask
			ENABLE_CORE_WAIT_TM    : begin
				if ( item_valid_i )
					next_state <= IDLE;
				else
					next_state <= ENABLE_CORE_WAIT_TM;
			end

			// Reads a control register from NaplesPU, and sends it back through the
			// item network
			READ_STATUS_WAIT_DATA  : begin
				if ( item_valid_i )
					next_state <= READ_STATUS_WAIT_CR;
				else
					next_state <= READ_STATUS_WAIT_DATA;
			end

			READ_STATUS_WAIT_CR    : begin
				if ( item_avail_i )
					next_state <= IDLE;
				else
					next_state <= READ_STATUS_WAIT_CR;
			end

			// Writes a NaplesPU control register
			WRITE_STATUS_WAIT_INFO : begin
				if ( item_valid_i )
					next_state <= WRITE_STATUS_WAIT_DATA;
				else
					next_state <= WRITE_STATUS_WAIT_INFO;
			end

			WRITE_STATUS_WAIT_DATA : begin
				if ( item_valid_i )
					next_state <= WRITE_STATUS_WAIT_CR;
				else
					next_state <= WRITE_STATUS_WAIT_DATA;
			end

			WRITE_STATUS_WAIT_CR   : begin
				next_state <= IDLE;
			end

		endcase
	end

//  -----------------------------------------------------------------------
//  -- Control Unit - Output Block
//  -----------------------------------------------------------------------
	always_comb begin
		hi_read_cr_valid        <= 1'b0;
		hi_read_cr_request      <= hi_read_cr_request;
		hi_write_cr_valid       <= 1'b0;
		hi_write_cr_data        <= hi_write_cr_data;
		avail_out               <= 1'b0;
		valid_out               <= 1'b0;
		update_boot_thread_id   <= 1'b0;
		update_thread_en        <= 1'b0;
		boot_valid              <= 1'b0;
		boot_pc                 <= 0;
		message_out             <= message_out;

		tri_snoop_valid_o       <= 1'b0;
		reset_snoop_counter     <= 1'b0;

		unique case ( state )

			IDLE                   : begin
				avail_out         <= 1'b1;
			end

			// Sets the Thread enable mask
			ENABLE_CORE_WAIT_TM    : begin
				avail_out         <= 1'b1;
				if ( item_valid_i ) begin
					update_thread_en      <= 1'b1;
				end
			end

			// Sets a Thread Program Counter
			BOOT_WAIT_THREAD_ID    : begin
				avail_out         <= 1'b1;
				if ( item_valid_i )
					update_boot_thread_id <= 1'b1;
			end

			BOOT_WAIT_PC           : begin
				avail_out         <= 1'b1;
				if ( item_valid_i ) begin
					boot_valid            <= 1'b1;
					boot_pc               <= address_t'( item_data_i );
				end
			end

			/* --- Control/Performance Registers Communication --- */

			// Reads a control register from NaplesPU, and sends it back through the
			// item network
			READ_STATUS_WAIT_DATA  : begin
				if ( item_valid_i ) begin
					hi_read_cr_valid      <= 1'b1;
					hi_read_cr_request    <= item_data_i;
				end
			end

			READ_STATUS_WAIT_CR    : begin
				valid_out         <= 1'b1;
				message_out       <= cr_response;
			end

			// Writes a NaplesPU control register
			WRITE_STATUS_WAIT_INFO : begin
				if ( item_valid_i )
					hi_read_cr_request    <= item_data_i;
			end

			WRITE_STATUS_WAIT_DATA : begin
				if ( item_valid_i )
					hi_write_cr_data      <= item_data_i;
			end

			WRITE_STATUS_WAIT_CR   : begin
				hi_write_cr_valid <= 1'b1;
			end

		endcase
	end

endmodule
