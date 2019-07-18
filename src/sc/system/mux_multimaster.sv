//        Copyright 2019 NaplesPU
//   
//   	 
//   Redistribution and use in source and binary forms, with or without modification,
//   are permitted provided that the following conditions are met:
//   
//   1. Redistributions of source code must retain the above copyright notice,
//      this list of conditions and the following disclaimer.
//   
//   2. Redistributions in binary form must reproduce the above copyright notice,
//      this list of conditions and the following disclaimer in the documentation
//      and/or other materials provided with the distribution.
//   
//   3. Neither the name of the copyright holder nor the names of its contributors
//      may be used to endorse or promote products derived from this software
//      without specific prior written permission.
//   
//      
//   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
//   IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//   INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//   BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
//   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
//   OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
//   OF THE POSSIBILITY OF SUCH DAMAGE.

`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_system_defines.sv"
`include "npu_coherence_defines.sv"

module mux_multimaster #(
		NUM_MASTER = 2,
		NUM_SLAVE  = 2 )
	(
		input                                     clk,
		input                                     reset,

		input  address_t     [NUM_MASTER - 1 : 0] m_n2m_request_address,
		input  dcache_line_t [NUM_MASTER - 1 : 0] m_n2m_request_data,
		input  logic         [NUM_MASTER - 1 : 0] m_n2m_request_read,
		input  logic         [NUM_MASTER - 1 : 0] m_n2m_request_write,
		input  logic         [NUM_MASTER - 1 : 0] m_mc_avail_o,

		output logic         [NUM_MASTER - 1 : 0] m_m2n_request_available,
		output logic         [NUM_MASTER - 1 : 0] m_m2n_response_valid,
		output address_t     [NUM_MASTER - 1 : 0] m_m2n_response_address,
		output dcache_line_t [NUM_MASTER - 1 : 0] m_m2n_response_data,

		output address_t                          s_n2m_request_address,
		output dcache_line_t                      s_n2m_request_data,
		output logic         [NUM_SLAVE - 1 : 0]  s_n2m_request_read,
		output logic         [NUM_SLAVE - 1 : 0]  s_n2m_request_write,
		output logic                              s_mc_avail_o,

		input  logic         [NUM_SLAVE - 1 : 0]  s_m2n_request_available,
		input  logic         [NUM_SLAVE - 1 : 0]  s_m2n_response_valid,
		input  address_t     [NUM_SLAVE - 1 : 0]  s_m2n_response_address,
		input  dcache_line_t [NUM_SLAVE - 1 : 0]  s_m2n_response_data
	);

    localparam IOM_BASE_ADDR  = `IO_MAP_BASE_ADDR;
    localparam IOM_SIZE       = `IO_MAP_SIZE;
    localparam MAIN_MEMORY_ID = 1;
    localparam IOM_ID         = 0;
    localparam FIFO_SIZE      = 2;

	typedef struct packed {
		address_t m_n2m_request_address;
		dcache_line_t m_n2m_request_data;
		logic m_n2m_request_read;
		logic m_n2m_request_write;
	} input_fifo_t;

	input_fifo_t                                m_input[NUM_MASTER], m_output[NUM_MASTER];
	logic        [NUM_MASTER - 1 : 0]           m_fifo_en, m_fifo_full, m_fifo_dequeue, m_fifo_empty;
	logic        [NUM_MASTER - 1 : 0]           m_fifo_pending, m_fifo_grant;
	logic        [$clog2( NUM_MASTER ) - 1 : 0] m_fifo_grant_id, master_id_pending;
	logic                                       request_pending;
	logic        [NUM_SLAVE - 1 : 0]            requested_slave_id [NUM_MASTER];

	genvar                                      master_id;
	generate
		for ( master_id = 0; master_id < NUM_MASTER; master_id = master_id + 1 ) begin : MASTER_GEN

			logic                     request_is_iom;
			logic [NUM_SLAVE - 1 : 0] requested_slave_id_aux;

			always_comb begin : INPUT_ASSIGN
				m_input[master_id].m_n2m_request_address = m_n2m_request_address[master_id];
				m_input[master_id].m_n2m_request_data    = m_n2m_request_data[master_id];
				m_input[master_id].m_n2m_request_read    = m_n2m_request_read[master_id];
				m_input[master_id].m_n2m_request_write   = m_n2m_request_write[master_id];
				m_fifo_en[master_id]                     = m_n2m_request_read[master_id] | m_n2m_request_write[master_id];
				m_fifo_pending[master_id]                = ~m_fifo_empty[master_id];
			end

			sync_fifo #(
				.WIDTH                 ( $bits( input_fifo_t ) ),
				.SIZE                  ( FIFO_SIZE             ),
				.ALMOST_FULL_THRESHOLD ( FIFO_SIZE - 1         )
			)
			u_sync_fifo_m0 (
				.clk         ( clk                       ),
				.reset       ( reset                     ),
				.flush_en    ( 1'b0                      ),
				.full        (                           ),
				.almost_full ( m_fifo_full[master_id]    ),
				.enqueue_en  ( m_fifo_en[master_id]      ),
				.value_i     ( m_input[master_id]        ),
				.empty       ( m_fifo_empty[master_id]   ),
				.almost_empty(                           ),
				.dequeue_en  ( m_fifo_dequeue[master_id] ),
				.value_o     ( m_output[master_id]       )
			);

			// Check if the current request is for the IO Mapped space or the Main Memory
			assign request_is_iom         = m_output[master_id].m_n2m_request_address >= ( IOM_BASE_ADDR ) & m_output[master_id].m_n2m_request_address <= ( IOM_BASE_ADDR + IOM_SIZE);

			// Select the right slave. At the moment, only two slaves are connected. In order to
			// add further slaves, the user must expand this case adding the new slave id, and
			// check when the request falls in the slave memory space.
			always_comb begin : SLAVE_DETECTION
				case ( request_is_iom )
					1'b0 : requested_slave_id[master_id]    = MAIN_MEMORY_ID;
					1'b1 : requested_slave_id[master_id]    = IOM_ID;
					default : requested_slave_id[master_id] = MAIN_MEMORY_ID;
				endcase
			end

			assign requested_slave_id_aux = requested_slave_id[master_id];

			always_comb begin : OUTPUT_ASSIGN
				m_m2n_request_available[master_id] = s_m2n_request_available[requested_slave_id_aux] & ~request_pending & ~m_fifo_full[master_id];
				m_m2n_response_address[master_id]  = s_m2n_response_address[requested_slave_id_aux];
				m_m2n_response_data[master_id]     = s_m2n_response_data[requested_slave_id_aux];
				m_m2n_response_valid[master_id]    = ( master_id == master_id_pending ) & s_m2n_response_valid[requested_slave_id_aux];
				m_fifo_dequeue[master_id]          = ( master_id == m_fifo_grant_id ) &
				( ( m_output[master_id].m_n2m_request_write & s_m2n_request_available[requested_slave_id_aux] & ~m_fifo_empty[master_id] ) |
					( m_output[master_id].m_n2m_request_read & s_m2n_response_valid[requested_slave_id_aux] & ~m_fifo_empty[master_id] ) );
			end

		end
	endgenerate

	round_robin_arbiter #(
		.SIZE( NUM_MASTER )
	)
	u_round_robin_arbiter (
		.clk         ( clk            ),
		.reset       ( reset          ),
		.en          ( 1'b0           ),
		.requests    ( m_fifo_pending ),
		.decision_oh ( m_fifo_grant   )
	);

	oh_to_idx #(
		.NUM_SIGNALS( NUM_MASTER ),
		.DIRECTION  ( "LSB0"     )
	)
	u_oh_to_idx (
		.one_hot( m_fifo_grant    ),
		.index  ( m_fifo_grant_id )
	);

	// The winning master issues a memory request when its slave is ready. This logic
	// keeps track that a pending request is ongoing and blocks from further requests,
	// until the current one is accomplished.
	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			request_pending <= 1'b0;
		else
			if ( s_m2n_request_available[requested_slave_id[m_fifo_grant_id]] )
				request_pending <= m_output[m_fifo_grant_id].m_n2m_request_read & ~m_fifo_empty[m_fifo_grant_id];

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			master_id_pending <= 0;
		else
			if ( m_output[m_fifo_grant_id].m_n2m_request_read & ~m_fifo_empty[m_fifo_grant_id] )
				master_id_pending <= m_fifo_grant_id;

	// All slaves receive same data and information.
	always_comb begin : DATA_TO_SLAVES
		s_n2m_request_address = m_output[m_fifo_grant_id].m_n2m_request_address;
		s_n2m_request_data    = m_output[m_fifo_grant_id].m_n2m_request_data;
		s_mc_avail_o          = m_mc_avail_o[master_id_pending];
	end

	genvar                                      slave_id;
	generate
		for ( slave_id = 0; slave_id < NUM_SLAVE; slave_id = slave_id + 1 ) begin
			always_comb begin : SLAVE_CONTROL_OUTPUT_ASSIGN
				if ( requested_slave_id[m_fifo_grant_id] == slave_id ) begin
					s_n2m_request_read [slave_id]  = m_output[m_fifo_grant_id].m_n2m_request_read & ~m_fifo_empty[m_fifo_grant_id] & ~request_pending;
					s_n2m_request_write [slave_id] = m_output[m_fifo_grant_id].m_n2m_request_write & ~m_fifo_empty[m_fifo_grant_id];
				end else begin
					s_n2m_request_read [slave_id]  = 1'b0;
					s_n2m_request_write [slave_id] = 1'b0;
				end
			end
		end
	endgenerate

`ifdef SIMULATION
	always_comb begin
		assert( $onehot( NUM_MASTER ) ) else $fatal( "NUM_MASTER must be power of 2!" );
		assert( $onehot( NUM_SLAVE ) ) else $fatal( "NUM_SLAVE must be power of 2!" );
	end
`endif

endmodule
