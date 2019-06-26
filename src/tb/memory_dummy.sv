`timescale 1ns / 1ps
`include "../include/npu_user_defines.sv"
`include "../include/npu_defines.sv"
`include "../include/npu_debug_log.sv"

module memory_dummy #(
		parameter ADDRESS_WIDTH  = 32,
		parameter DATA_WIDTH     = 512,
		parameter MAX_WIDTH      = 262400, // 0x41000 * 64 byte = 0x01004000
		parameter OFF_WIDTH      = 6,
		parameter FILENAME_INSTR = "" )
	(
		input                                clk,
		input                                reset,

		// From MC
		// To Memory NI
		input  logic [ADDRESS_WIDTH - 1 : 0] n2m_request_address,
		input  logic [63 : 0]                n2m_request_dirty_mask,
		input  logic [DATA_WIDTH - 1 : 0]    n2m_request_data,
		input  logic                         n2m_request_read,
		input  logic                         n2m_request_write,
		input  logic                         mc_avail_o,

		// From Memory NI
		output logic                         m2n_request_available,
		output logic                         m2n_response_valid,
		output logic [ADDRESS_WIDTH - 1 : 0] m2n_response_address,
		output logic [DATA_WIDTH - 1 : 0]    m2n_response_data
	);

	logic   [DATA_WIDTH - 1 : 0]    mem_dummy [MAX_WIDTH];
	logic   [ADDRESS_WIDTH - 1 : 0] address_in;
	logic   [ADDRESS_WIDTH - 1 : 0] address_max;
	logic                           request_was_read;

	typedef enum logic[1 : 0] {IDLE, WAITING} state_t;

	integer                         delay                 = 0;
	state_t                         state                 = IDLE;

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset )
			address_max <= 0;
		else
			if ( n2m_request_write & ( n2m_request_address > address_max ) & ( n2m_request_address < `IO_MAP_BASE_ADDR ) )
				address_max <= n2m_request_address;
	end

	initial begin
		integer fd;

		fd = $fopen( FILENAME_INSTR, "r" );
		assert ( fd != 0 ) else $error( "[MEMORY] Cannot open memory image" );
		$fclose( fd );

		$readmemh( FILENAME_INSTR, mem_dummy );
		$display( "[Time %t] [MEMORY] Memory image %s loaded", $time( ), FILENAME_INSTR );
	end

	integer                         avail_next_cycle;
	always_ff @( posedge clk ) begin
		//avail_next_cycle <= $random % 10;
		avail_next_cycle <= 1;
	end

	assign m2n_request_available = ~( n2m_request_read | n2m_request_write ) & state != WAITING & avail_next_cycle == 1;

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset ) begin
			state              <= IDLE;
			m2n_response_data  <= 0;
			m2n_response_valid <= 1'b0;
			delay              <= 0;
		end else begin

			m2n_response_valid <= 1'b0;

			case( state )
				IDLE    : begin
					state <= IDLE;
					delay <= 0;
					if ( n2m_request_read ) begin
						state            <= WAITING;
						request_was_read <= 1'b1;
						address_in       <= n2m_request_address >> OFF_WIDTH;
						delay            <= 0;
					end else if ( n2m_request_write ) begin
						state            <= WAITING;
						request_was_read <= 1'b0;
						address_in       <= n2m_request_address >> OFF_WIDTH;

						for ( int i = 0; i < 64; i++ ) begin
							if ( n2m_request_dirty_mask[i] ) begin
								mem_dummy[( n2m_request_address >> OFF_WIDTH )][i*8 +: 8] <= n2m_request_data[i*8 +: 8];
							end
						end
					end
				end

				WAITING : begin
					if ( delay == 0 ) begin
						if ( ~request_was_read || mc_avail_o ) begin
							state                <= IDLE;
						end else begin
							state                <= WAITING;
						end

						if ( request_was_read && mc_avail_o ) begin
							m2n_response_valid   <= 1'b1;
							m2n_response_data    <= mem_dummy[address_in[$clog2( MAX_WIDTH ) - 1 : 0]];
							m2n_response_address <= address_in << OFF_WIDTH;
						end
					end else begin
						delay            <= delay - 1;
					end
				end
			endcase
		end
	end

`ifdef DISPLAY_MEMORY

	int memory_file;

	initial memory_file = $fopen ( `DISPLAY_MEMORY_FILE, "wb" ) ;

	final begin
		for ( int i = 0; i <= address_max[ADDRESS_WIDTH - 1 : OFF_WIDTH] + 1; i++ ) begin
			$fdisplay( memory_file, "%h \t %h", ( i * 64 ), mem_dummy[i] );
		end
		$fclose( memory_file );
	end

`endif

`ifdef DISPLAY_MEMORY_TRANS

	int memory_file_trans;

	initial memory_file_trans = $fopen( `DISPLAY_MEMORY_TRANS_FILE, "wb" );

	final begin
		$fclose( memory_file_trans );
	end

	always_ff @( posedge clk ) begin
		if( n2m_request_write )begin
			$fdisplay ( memory_file_trans, "[Time :%t] [MEMORY]: Write request - Address: %h\tMask: %h\tData: %h", $time( ), n2m_request_address, n2m_request_dirty_mask, n2m_request_data );
			$fflush ( memory_file_trans );
		end

		if( n2m_request_read )begin
			$fdisplay ( memory_file_trans, "[Time :%t] [MEMORY]: Read request - Address: %h", $time( ), n2m_request_address );
			$fflush ( memory_file_trans );
		end

		if( m2n_response_valid )begin
			$fdisplay ( memory_file_trans, "[Time :%t] [MEMORY]: Read response - Address: %h\tData: %h", $time( ), m2n_response_address, m2n_response_data );
			$fflush ( memory_file_trans );
		end
	end

`endif

endmodule
