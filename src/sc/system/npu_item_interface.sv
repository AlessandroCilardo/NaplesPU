`timescale 1ns / 1ps
`include "npu_defines.sv"
`include "npu_coherence_defines.sv"
`include "npu_message_service_defines.sv"

module npu_item_interface #(
		parameter ID               = 0,   // TILE ID (maybe is not needed)
		parameter TLID_w           = 10,  // ID width (maybe is not needed)
		parameter NODE_ID_w        = 10,  // Node ID width (node id width, internal to NaplesPU)
		parameter MEM_ADDR_w       = 32,  // Memory address width (in bits)
		parameter MEM_DATA_BLOCK_w = 512, // Memory data block width (in bits)
		parameter ITEM_w           = 32  // Input and output item width (control interface
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

		// Console communication
		output logic                                      io_intf_available,
		input  logic                                      ldst_io_valid,
		input  thread_id_t                                ldst_io_thread,
		input  logic [$bits(io_operation_t)-1 : 0]        ldst_io_operation,
		input  address_t                                  ldst_io_address,
		input  register_t                                 ldst_io_data,
		output logic                                      io_intf_resp_valid,
		output thread_id_t                                io_intf_wakeup_thread,
		output register_t                                 io_intf_resp_data,
		input  logic                                      ldst_io_resp_consumed,

		// Service Network interface
		output service_message_t                          c2n_mes_service,
		output logic                                      c2n_mes_valid,
		input  service_message_t                          n2c_mes_service,
		input  logic                                      n2c_mes_valid,
		output logic                                      n2c_mes_service_consumed,
		input  logic                                      ni_network_available,
		output tile_mask_t                                c2n_mes_service_destinations_valid,

		// interface MEM_TILEREG <-> NaplesPU
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

	typedef enum {
		IDLE,
		BOOT_WAIT_THREAD_ID,
		BOOT_WAIT_PC,
		ENABLE_CORE_WAIT_TM,
		READ_CR_WAIT_DATA,
		READ_CR_WAIT_CR,
		WRITE_CR_WAIT_INFO,
		WRITE_CR_WAIT_DATA,
		READ_CONSOLE_STATUS_WAIT_AVAIL,
		READ_CONSOLE_DATA_WAIT_AVAIL,
		WRITE_CONSOLE_DATA_WAIT_AVAIL,
		WAIT_SERVICE_NETWORK
	} host_interface_state_t;

	function host_interface_state_t read_message_from_host ( host_message_type_t message_in );
		host_interface_state_t next_state;
		unique case ( message_in )
			BOOT_COMMAND         : next_state = BOOT_WAIT_THREAD_ID;
			ENABLE_THREAD        : next_state = ENABLE_CORE_WAIT_TM;
			GET_CONTROL_REGISTER : next_state = READ_CR_WAIT_DATA;
			SET_CONTROL_REGISTER : next_state = WRITE_CR_WAIT_INFO;
			GET_CONSOLE_STATUS   : next_state = READ_CONSOLE_STATUS_WAIT_AVAIL;
			GET_CONSOLE_DATA     : next_state = READ_CONSOLE_DATA_WAIT_AVAIL;
			WRITE_CONSOLE_DATA   : next_state = WRITE_CONSOLE_DATA_WAIT_AVAIL;
			default              : next_state = IDLE;
		endcase

		return next_state;
	endfunction : read_message_from_host

	// IO Register map
	localparam CONSOLE_DATA_OFFSET   = 0;
	localparam CONSOLE_STATUS_OFFSET = 4;

	typedef struct packed {
		thread_id_t thread;
		io_operation_t operation;
		dcache_address_t address;
		register_t data;
	} io_fifo_t;

	typedef enum {
		IO_IDLE,
		IO_RESP
	} io_interface_state_t;

//  -----------------------------------------------------------------------
//  -- NaplesPU Item Interface - Internal signals
//  -----------------------------------------------------------------------
	host_interface_state_t                      state, next_state;
	logic                                       avail_out, valid_out, boot_valid;
	logic                [`THREAD_NUMB - 1 : 0] thread_en;
	register_t                                  cr_to_write;
	logic                                       update_thread_en, update_boot_thread, update_boot_core, update_cr_to_write, update_boot_pc;

	thread_id_t                                 boot_thread_id;
	host_message_type_t                         message_in;
	logic                [31 : 0]               message_out;

	// Output to the Item network
	assign item_avail_o        = avail_out;
	assign item_valid_o        = valid_out;
	assign item_data_o         = message_out;
	
	// Request from the Host conversion
	assign message_in          = host_message_type_t'( item_data_i );
	
	// Output to the Thread Controller of the Core
	assign hi_thread_en        = thread_en;
	assign hi_job_thread_id    = boot_thread_id;
	assign hi_job_valid        = boot_valid;
	assign hi_job_pc           = address_t'(item_data_i);

	// Console FIFO to host
	logic console_to_host_full, console_to_host_empty, console_to_host_enq, console_to_host_deq;
	logic [7:0] console_to_host_out;
	// Console FIFO from host
	logic console_from_host_full, console_from_host_empty, console_from_host_enq, console_from_host_deq;
	logic [7:0] console_from_host_out;
	// IO bus
	io_fifo_t iom_request_in, iom_request_out, iom_resp_in, iom_resp_out;
	logic empty_iom, iom_almost_full, dequeue_iom;

	// Service Network interface
	host_message_t boot_message_to_net;
	tile_id_t mes_destination;

//  -----------------------------------------------------------------------
//  -- Service Network interface
//  -----------------------------------------------------------------------

	assign c2n_mes_service.message_type = HOST;
	assign c2n_mes_service.data         = service_message_data_t'(boot_message_to_net);
	assign n2c_mes_service_consumed     = n2c_mes_valid;

	idx_to_oh # (
		.NUM_SIGNALS ( $bits ( tile_mask_t  ) ),
		.DIRECTION   ( "LSB0"                 ),
		.INDEX_WIDTH ( $clog2 ( `TILE_COUNT ) )
	)
	u_idx_to_oh (
		.one_hot ( c2n_mes_service_destinations_valid ),
		.index   ( mes_destination                    )
	);

		//input  logic                                      ni_network_available,

//  -----------------------------------------------------------------------
//  -- Console Buffers and IO bus handling
//  -----------------------------------------------------------------------

	assign iom_request_in.thread       = ldst_io_thread;
	assign iom_request_in.operation    = io_operation_t'(ldst_io_operation);
	assign iom_request_in.address      = ldst_io_address;
	assign iom_request_in.data         = ldst_io_data;

	assign io_intf_available = ~iom_almost_full;

	sync_fifo #(
		.WIDTH                 ( $bits( io_fifo_t ) ),
		.SIZE                  ( 4                  ),
		.ALMOST_FULL_THRESHOLD ( 2                  )
	)
	iom_fifo (
		.clk         ( clk             ),
		.reset       ( reset           ),
		.flush_en    ( 1'b0            ),
		.full        (                 ),
		.almost_full ( iom_almost_full ),
		.enqueue_en  ( ldst_io_valid & ~iom_almost_full   ),
		.value_i     ( iom_request_in  ),
		.empty       ( empty_iom       ),
		.almost_empty(                 ),
		.dequeue_en  ( dequeue_iom     ),
		.value_o     ( iom_request_out )
	);

	sync_fifo #(
		.WIDTH                 ( 8 ),
		.SIZE                  ( 8 ),
		.ALMOST_FULL_THRESHOLD ( 6 )
	)
	console_to_host (
		.clk          ( clk                       ),
		.reset        ( reset                     ),
		.flush_en     ( 1'b0                      ),
		.full         ( console_to_host_full      ),
		.almost_full  (                           ),
		.enqueue_en   ( console_to_host_enq       ),
		.value_i      ( iom_request_out.data[7:0] ),
		.empty        ( console_to_host_empty     ),
		.almost_empty (                           ),
		.dequeue_en   ( console_to_host_deq       ),
		.value_o      ( console_to_host_out       )
	);

	sync_fifo #(
		.WIDTH                 ( 8 ),
		.SIZE                  ( 8 )
	)
	console_from_host (
		.clk          ( clk                     ),
		.reset        ( reset                   ),
		.flush_en     ( 1'b0                    ),
		.full         ( console_from_host_full  ),
		.almost_full  (                         ),
		.enqueue_en   ( console_from_host_enq   ),
		.value_i      ( item_data_i[7:0]        ),
		.empty        ( console_from_host_empty ),
		.almost_empty (                         ),
		.dequeue_en   ( console_from_host_deq   ),
		.value_o      ( console_from_host_out   )
	);

	io_interface_state_t io_state;

	assign io_intf_wakeup_thread = iom_request_out.thread;

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			io_state          <= IO_IDLE;
		end else begin
			case (io_state)
				IO_IDLE: begin
					if (~empty_iom & io_operation_t'(iom_request_out.operation) == IO_READ) begin
						io_state <= IO_RESP;
					end
				end

				IO_RESP: begin
					if (ldst_io_resp_consumed) begin
						io_state <= IO_IDLE;
					end
				end
			endcase
		end
	end

	always_comb begin
		dequeue_iom           <= 1'b0;
		console_to_host_enq   <= 1'b0;
		console_from_host_deq <= 1'b0;
		io_intf_resp_data     <= 32'd0;
		io_intf_resp_valid    <= 1'b0;

		case (io_state)
			IO_IDLE: begin
				if (~empty_iom) begin
					if (io_operation_t'(iom_request_out.operation) == IO_WRITE & iom_request_out.address == `IO_MAP_BASE_ADDR + CONSOLE_DATA_OFFSET) begin
						console_to_host_enq   <= 1'b1;
						dequeue_iom           <= 1'b1;

						if (console_to_host_full) begin
							dequeue_iom         <= 1'b0;
							console_to_host_enq <= 1'b0;
						end
					end else if (io_operation_t'(iom_request_out.operation) == IO_READ & iom_request_out.address == `IO_MAP_BASE_ADDR + CONSOLE_STATUS_OFFSET) begin
					end
				end
			end

			IO_RESP: begin
				io_intf_resp_valid      <= 1'b1;

				if (ldst_io_resp_consumed) begin
					dequeue_iom <= 1'b1;
				end

				if (iom_request_out.address == `IO_MAP_BASE_ADDR + CONSOLE_DATA_OFFSET) begin
					io_intf_resp_data <= {24'd0, console_from_host_out};

					if (ldst_io_resp_consumed & ~console_from_host_empty) begin
						console_from_host_deq <= 1'b1;
					end
				end else if (iom_request_out.address == `IO_MAP_BASE_ADDR + CONSOLE_STATUS_OFFSET) begin
					io_intf_resp_data <= {31'd0, ~console_from_host_empty};
				end
			end
		endcase
	end

//  -----------------------------------------------------------------------
//  -- Control Unit - Counter and Next State sequential
//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			state               <= IDLE;
			thread_en           <= {`THREAD_NUMB{1'b0}};
			boot_thread_id      <= thread_id_t'(0);
			cr_to_write         <= register_t'(0);
			boot_message_to_net <= host_message_t'(0);
		end else begin
			state          <= next_state; // default is to stay in current state

			if ( update_thread_en ) begin
				thread_en                        <= item_data_i[`THREAD_NUMB - 1 : 0];
				boot_message_to_net.hi_job_valid <= 1'b0;
				boot_message_to_net.hi_thread_en <= item_data_i[`THREAD_NUMB - 1 : 0];
				boot_message_to_net.message      <= ENABLE_THREAD;
			end

			if ( update_boot_thread ) begin
				boot_thread_id                       <= thread_id_t'( item_data_i );
				boot_message_to_net.hi_job_thread_id <= item_data_i[$bits(thread_id_t)-1 : 0];
			end

			if ( update_boot_core ) begin
				mes_destination                      <= item_data_i[$bits(tile_id_t)-1+16 : 16];
			end

			if ( update_boot_pc ) begin
				boot_message_to_net.hi_job_valid <= 1'b1;
				boot_message_to_net.hi_job_pc    <= address_t' ( item_data_i );
				boot_message_to_net.hi_thread_en <= thread_mask_t' ( 0 );
				boot_message_to_net.message      <= BOOT_COMMAND;
			end

			if ( update_cr_to_write )
				cr_to_write <= register_t'( item_data_i );
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
					next_state <= WAIT_SERVICE_NETWORK;
				else
					next_state <= BOOT_WAIT_PC;
			end

			/* --- Control/Performance Registers Communication --- */

			// Sets the Thread enable mask
			ENABLE_CORE_WAIT_TM    : begin
				if ( item_valid_i )
					next_state <= WAIT_SERVICE_NETWORK;
				else
					next_state <= ENABLE_CORE_WAIT_TM;
			end

			// Reads a control register from NaplesPU, and sends it back through the
			// item network
			READ_CR_WAIT_DATA  : begin
				if ( item_valid_i )
					next_state <= READ_CR_WAIT_CR;
				else
					next_state <= READ_CR_WAIT_DATA;
			end

			READ_CR_WAIT_CR    : begin
				if ( item_avail_i )
					next_state <= IDLE;
				else
					next_state <= READ_CR_WAIT_CR;
			end

			// Writes a NaplesPU control register
			WRITE_CR_WAIT_INFO : begin
				if ( item_valid_i ) begin
					next_state         <= WRITE_CR_WAIT_DATA;
				end else begin
					next_state <= WRITE_CR_WAIT_INFO;
				end
			end

			WRITE_CR_WAIT_DATA : begin
				if ( item_valid_i )
					next_state <= IDLE;
				else
					next_state <= WRITE_CR_WAIT_DATA;
			end

			READ_CONSOLE_STATUS_WAIT_AVAIL : begin
				if ( item_avail_i )
					next_state <= IDLE;
				else
					next_state <= READ_CONSOLE_STATUS_WAIT_AVAIL;
			end

			READ_CONSOLE_DATA_WAIT_AVAIL : begin
				if ( item_avail_i )
					next_state <= IDLE;
				else
					next_state <= READ_CONSOLE_DATA_WAIT_AVAIL;
			end

			WRITE_CONSOLE_DATA_WAIT_AVAIL : begin
				if ( item_valid_i & ~console_from_host_full )
					next_state <= IDLE;
				else
					next_state <= WRITE_CONSOLE_DATA_WAIT_AVAIL;
			end

			WAIT_SERVICE_NETWORK : begin
				if ( ni_network_available )
					next_state <= IDLE;
				else
					next_state <= WAIT_SERVICE_NETWORK;
			end

		endcase
	end

//  -----------------------------------------------------------------------
//  -- Control Unit - Output Block
//  -----------------------------------------------------------------------
	always_comb begin
		hi_read_cr_valid        <= 1'b0;
		hi_read_cr_request      <= 32'd0;
		hi_write_cr_valid       <= 1'b0;
		hi_write_cr_data        <= 32'd0;
		avail_out               <= 1'b0;
		valid_out               <= 1'b0;
		update_boot_thread      <= 1'b0;
		update_boot_core        <= 1'b0;
		update_boot_pc          <= 1'b0;
		update_thread_en        <= 1'b0;
		update_cr_to_write      <= 1'b0;
		boot_valid              <= 1'b0;
		message_out             <= cr_response;
		console_to_host_deq     <= 1'b0;
		console_from_host_enq   <= 1'b0;
		c2n_mes_valid           <= 1'b0;

		unique case ( state )

			IDLE                   : begin
				avail_out         <= 1'b1;
			end

			// Sets the Thread enable mask
			ENABLE_CORE_WAIT_TM    : begin
				avail_out          <= 1'b1;
				if ( item_valid_i ) begin
					update_thread_en <= 1'b1;
					update_boot_core <= 1'b1;
				end
			end

			// Sets a Thread Program Counter
			BOOT_WAIT_THREAD_ID    : begin
				avail_out         <= 1'b1;
				if ( item_valid_i ) begin
					update_boot_thread <= 1'b1;
					update_boot_core   <= 1'b1;
				end
			end

			BOOT_WAIT_PC           : begin
				if ( item_valid_i ) begin
					update_boot_pc <= 1'b1;
					avail_out      <= 1'b1;
					boot_valid     <= 1'b1;
				end
			end

			/* --- Control/Performance Registers Communication --- */

			// Reads a control register from NaplesPU, and sends it back through the
			// item network
			READ_CR_WAIT_DATA  : begin
				avail_out         <= 1'b1;

				if ( item_valid_i ) begin
					hi_read_cr_valid      <= 1'b1;
					hi_read_cr_request    <= item_data_i;
				end
			end

			READ_CR_WAIT_CR    : begin
				valid_out         <= 1'b1;
			end

			WRITE_CR_WAIT_INFO : begin
				avail_out         <= 1'b1;

				if ( item_valid_i ) begin
					update_cr_to_write <= 1'b1;
				end
			end

			WRITE_CR_WAIT_DATA : begin
				avail_out         <= 1'b1;

				if ( item_valid_i ) begin
					hi_read_cr_request <= cr_to_write;
					hi_write_cr_data   <= item_data_i;
					hi_write_cr_valid  <= 1'b1;
				end
			end

			READ_CONSOLE_STATUS_WAIT_AVAIL : begin
				valid_out   <= 1'b1;
				message_out <= {31'd0, ~console_to_host_empty};
			end

			READ_CONSOLE_DATA_WAIT_AVAIL : begin
				valid_out           <= 1'b1;
				console_to_host_deq <= ~console_to_host_empty & item_avail_i;
				message_out         <= {24'd0, console_to_host_out};
			end

			WRITE_CONSOLE_DATA_WAIT_AVAIL : begin
				if (item_valid_i & ~console_from_host_full) begin
					console_from_host_enq <= 1'b1;
					avail_out             <= 1'b1;
				end
			end

			WAIT_SERVICE_NETWORK : begin
				c2n_mes_valid <= 1'b1;
			end

		endcase
	end

endmodule
