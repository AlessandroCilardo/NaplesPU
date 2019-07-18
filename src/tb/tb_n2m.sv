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
`include "../include/npu_user_defines.sv"
`include "../include/npu_defines.sv"
`include "../include/npu_system_defines.sv"
`include "../include/npu_coherence_defines.sv"
`include "../include/npu_network_defines.sv"
`include "../include/npu_message_service_defines.sv"
`include "../include/npu_debug_log.sv"

module tb_n2m #(
		parameter KERNEL_IMAGE = "mmsc_mem.hex",
		parameter THREAD_MASK  = 8'hFF,
		parameter CORE_MASK    = 32'h03 )
	( );

	logic                                 clk                              = 1'b1;
	logic                                 reset                            = 1'b1;
	logic                                 enable                           = 1'b1;

	int                                   sim_log_file, sim_start, sim_end;
	logic                                 simulation_end                   = 1'b0;

//  -----------------------------------------------------------------------
//  -- TB parameters and signals
//  -----------------------------------------------------------------------

    localparam MEM_ADDR_w       = `ADDRESS_SIZE;
    localparam MEM_DATA_BLOCK_w = `DCACHE_WIDTH;
    localparam ITEM_w           = 32;
    localparam CLK_PERIOD_NS    = `CLOCK_PERIOD_NS;
    localparam PC_DEFAULT       = 32'h0000_0400;

	

	address_t                             n2m_request_address;
	logic             [63 : 0]            n2m_request_dirty_mask;
	dcache_line_t                         n2m_request_data;
	logic                                 n2m_request_read;
	logic                                 n2m_request_write;

	logic                                 m2n_request_available;
	logic                                 m2n_response_valid;
	address_t                             m2n_response_address;
	dcache_line_t                         m2n_response_data;

    logic                                 n2m_avail;
	logic 								  m2n_request_read_available;
	logic 								  m2n_request_write_available;

	//---- NI-MC Signals ----//
	// From MC to NI
	coherence_response_message_t                                            n2m_response;
	logic                                                                   n2m_response_valid;
	logic                                                                   n2m_response_has_data;
	logic                                                                   ni_response_network_available;
	logic                                                                   n2m_forwarded_request_available;

	// From NI to MC
	coherence_forwarded_message_t                                           ni_forwarded_request;
	logic                                                                   ni_forwarded_request_valid;
	logic                                                                   n2m_forwarded_request_consumed;

	// Response Eject
	coherence_response_message_t                                            ni_response;
	logic                                                                   ni_response_valid;
	logic                                                                   n2m_response_consumed;
	logic																	n2m_response_available;

	// Response Inject
	logic                                                                   n2m_response_to_cc_valid;
	tile_address_t                                                          n2m_response_to_cc;
	logic                                                                   n2m_response_to_dc_valid;
	tile_address_t                                                          n2m_response_to_dc;


//  -----------------------------------------------------------------------
//  -- TB Unit Under Test
//  -----------------------------------------------------------------------

    npu2memory #(
		.TILE_ID            ( `TILE_MEMORY_ID             ),
		.MEM_ADDRESS_WIDTH( 32						  ),
		.MEM_DATA_WIDTH   ( 512    					  )
		)
	npu2memory (
		.clk                             ( clk                             ), //input
		.reset                           ( reset                           ), //input
		.enable                          ( enable                          ), //input
		//From NI
		.ni_forwarded_request            ( ni_forwarded_request            ), //input (coherence_forwarded_message_t)
		.ni_forwarded_request_valid      ( ni_forwarded_request_valid      ), //input
		.ni_response_network_available   ( ni_response_network_available   ), //input
		.ni_response                     ( ni_response                     ), //input (coherence_response_message_t)
		.ni_response_valid               ( ni_response_valid        	   ), //input
		//Response Inject
		.n2m_response                    ( n2m_response                    ), //output (coherence_message_response_t)
		.n2m_response_valid              ( n2m_response_valid              ), //output
		.n2m_response_has_data           ( n2m_response_has_data           ), //output
		.n2m_response_to_cc_valid        ( n2m_response_to_cc_valid        ), //output
		.n2m_response_to_cc              ( n2m_response_to_cc              ), //output (tile_address_t)
		.n2m_response_to_dc_valid        ( n2m_response_to_dc_valid        ), //output
		.n2m_response_to_dc              ( n2m_response_to_dc              ), //output (tile_address_t)
		.n2m_forwarded_request_consumed  ( n2m_forwarded_request_consumed  ), //output
		.n2m_response_consumed           ( n2m_response_consumed           ), //output
		.n2m_response_available			 ( n2m_response_available          ), //output
		.n2m_forwarded_request_available ( n2m_forwarded_request_available ), //output
		//To MEM NI
		.n2m_request_address             ( n2m_request_address             ), //output [MEM_ADDRESS_WIDTH]
		.n2m_request_dirty_mask          ( n2m_request_dirty_mask          ), //output [64]
		.n2m_request_data                ( n2m_request_data                ), //output [MEM_DATA_WIDTH]
		.n2m_request_read                ( n2m_request_read                ), //output
		.n2m_request_write               ( n2m_request_write               ), //output
		.n2m_request_is_instr            (                                 ), //output
		.n2m_avail                       ( n2m_avail                       ), //output
		//From MEM NI
		.m2n_request_read_available      ( m2n_request_read_available      ), //input
		.m2n_request_write_available     ( m2n_request_write_available     ), //input
		.m2n_response_valid              ( m2n_response_valid              ), //input
		.m2n_response_address            ( m2n_response_address            ), //input [MEM_ADDRESS_WIDTH]
		.m2n_response_data               ( m2n_response_data               )  //input [MEM_DATA_WIDTH]
	);

	memory_dummy #(
		.OFF_WIDTH      ( `ICACHE_OFFSET_LENGTH ),
		.FILENAME_INSTR ( KERNEL_IMAGE          ),
		.ADDRESS_WIDTH  ( MEM_ADDR_w            ),
		.DATA_WIDTH     ( MEM_DATA_BLOCK_w      ),
		.MANYCORE       ( 1                     )
	)
	u_memory_dummy (
		.clk                    ( clk                    ), //input
		.reset                  ( reset                  ), //input
		//From MC
		//To MEM NI
		.n2m_request_address    ( n2m_request_address    ), //input [ADDRESS_WIDTH]
		.n2m_request_dirty_mask ( n2m_request_dirty_mask ), //input [64]
		.n2m_request_data       ( n2m_request_data       ), //input [DATA_WIDTH]
		.n2m_request_read       ( n2m_request_read       ), //input
		.n2m_request_write      ( n2m_request_write      ), //input
		.mc_avail_o             ( n2m_avail              ), //input
		//From MEM NI
		.m2n_request_available  ( m2n_request_available  ), //output
		.m2n_response_valid     ( m2n_response_valid     ), //output
		.m2n_response_address   ( m2n_response_address   ), //output [ADDRESS_WIDTH]
		.m2n_response_data      ( m2n_response_data      )  //output [DATA_WIDTH]
	);

	assign m2n_request_read_available = m2n_request_available;
	assign m2n_request_write_available = m2n_request_available;
	assign ni_response_network_available = 1'b1; //questo segnale dovrebbe essere piloatato dalla noc


//  -----------------------------------------------------------------------
//  -- TB termination logic
//  -----------------------------------------------------------------------

    localparam NUMBER_OF_REQS = 128;

	int cnt_fwd, cnt_res, cnt_invalid;

	always_ff @( posedge clk, posedge reset ) begin
		if ( reset )
		begin
			cnt_fwd <= 0;
			cnt_res <= 0;
			cnt_invalid <= 0;
		end
		else if ( n2m_response_valid )
		begin
			if ( n2m_response.packet_type == DATA )
			begin	
				cnt_fwd++;
				$display("[Time %t] [TESTBENCH] Fwd Request #%d consumed successfully", $time(), cnt_fwd);
			end else if ( n2m_response.packet_type == MC_ACK )
			begin
				cnt_res++;
				$display("[Time %t] [TESTBENCH] Response Request #%d consumed successfully", $time(), cnt_res);
			end
		end
	end

//  -----------------------------------------------------------------------
//  -- Testbench Body
//  -----------------------------------------------------------------------

	always #5 clk = ~clk;

	initial begin
		
		ni_forwarded_request_valid = 1'b0;
		ni_response_valid = 1'b0;

		#100
		reset = 1'b0;

		generate_random_requests();

		wait( cnt_fwd + cnt_res + cnt_invalid == NUMBER_OF_REQS );
		$display("[Time %t] [TESTBENCH] Closing testbench", $time());
		$finish();

	end

	task generate_random_requests;
	
		for(int i=0; i<NUMBER_OF_REQS; i++)
		begin
			if($urandom(i) % 2 == 0)
			begin
				//$display("[Time %t] [TESTBENCH] Generating request %3d [%3d of forward]", $time(), i, cnt_fwd);
				
				automatic message_forwarded_requests_enum_t     packet_type         = FWD_GETM;
				automatic dcache_address_t 					    memory_address 		= $urandom(i);
				submit_fwd_msg( 
					.packet_type    ( packet_type                                  ), 
					.memory_address ( memory_address                               ), 
					.source         ( '{$urandom_range(1,0), $urandom_range(1,0)}  ), 
                    .is_uncoherent  ( '{$urandom_range(1,0)}                       ), 
                    .requestor      ( requestor_type_t.first()                     )  
				);

				/*****************
				UNCOMMENT SERIALIZE AND VALIDATE FWD REQUESTS

				wait(n2m_response_valid);
				#5; //wait for counter to be updated
				//$display("[Time %t] [TESTBENCH] Arrived response for request #%3d [#%3d of fwd]", $time(), i, cnt_fwd);
				validate_fwd(packet_type, memory_address);
				*****************/
			end else
			begin
				//$display("[Time %t] [TESTBENCH] Generating request #%3d [#%3d of response]", $time(), i, cnt_res);
				
				automatic message_responses_enum_t 			packet_type 		= WB;
				automatic dcache_address_t 					memory_address 		= $urandom(i);
				submit_response_msg(
					.packet_type	 ( packet_type                         			), //FIXME: metterlo random
					.memory_address	 ( memory_address                               ), //numero random su 32 bit con seed=10
					.data			 ( {$urandom(i)} 					            ), //intero unsigned su 32 bit esteso a 512
					.source        	 ( '{$urandom_range(1,0), $urandom_range(1,0)}  ), //e.g. [1,0]
					.sharers_count 	 ( $urandom_range(`TILE_COUNT-1, 0) 			), //random tra 0 e tile_count-1
					.from_directory	 ( '{$urandom_range(1,0)} 						), // t/f
					.is_uncoherent	 ( '{$urandom_range(1,0)} 						), // t/f
					.requestor       ( requestor_type_t.first()                     ), //FIXME: metterlo random
					.dirty_mask 	 ( {`DCACHE_WIDTH/8{1'b1}}						)  //FIXME: metterlo random
				);

				/*****************
				UNCOMMENT SERIALIZE AND VALIDATE RESPONSE REQUESTS
				wait(n2m_response_valid);
				#5; //wait for counter to be updated
				//$display("[Time %t] [TESTBENCH] Arrived response for request #%3d [#%3d of response]", $time(), i, cnt_res);

				validate_response(packet_type, memory_address);
				*****************/
			end
			
		end


	endtask

	task submit_fwd_msg(
	   
	   message_forwarded_requests_enum_t 	packet_type 	= FWD_GETS,
	   dcache_address_t 					memory_address 	= 32'b0,
	   tile_address_t 						source 			= '{2'b0, 2'b0},
	   input logic 							is_uncoherent 	= 1'b0,
	   requestor_type_t 					requestor 		= DCACHE
	);

		assert(packet_type == FWD_GETS || packet_type == FWD_GETM) else 
		begin
			$error("[Time %t] [TESTBENCH] Trying to issue a fwd message of type %s. Expected type is FWD-GETS or FWD-GETM", $time(), packet_type.name);
			cnt_invalid++;
			return;
        end
		#5;

		ni_forwarded_request.packet_type 		= packet_type;
		ni_forwarded_request.memory_address 	= memory_address;
		ni_forwarded_request.source 			= source;
		ni_forwarded_request.req_is_uncoherent 	= is_uncoherent;
		ni_forwarded_request.requestor 			= requestor;
		wait(n2m_forwarded_request_available == 1'b1); //if n2m_forwarded_request_available is 0, then the fwd fifo is full. I have to wait.

		ni_forwarded_request_valid 				= 1'b1;

		#10
		ni_forwarded_request_valid 				= 1'b0;
		$display("[Time %t] [TESTBENCH] [FWD #%3d] Issued a fwd message of type %s for address 0x%8h", $time(), cnt_fwd, packet_type.name, memory_address);

	endtask;

	task submit_response_msg(
	   
	   message_responses_enum_t 		packet_type 	= WB,
	   dcache_address_t 				memory_address 	= 32'b0,
	   dcache_line_t 					data 			= {`DCACHE_WIDTH{1'b0}},
	   tile_address_t 					source 			= '{2'b0, 2'b0},
	   sharer_count_t 					sharers_count 	= {$clog2( `TILE_COUNT ){1'b0}},
	   input logic 						from_directory 	= 1'b0,
	   input logic 						is_uncoherent 	= 1'b0,
	   requestor_type_t 				requestor 		= DCACHE,
	   dcache_store_mask_t 				dirty_mask 		= {`DCACHE_WIDTH/8{1'b1}}

	);

		assert(packet_type == WB) else 
		begin
			$error("[Time %t] [TESTBENCH] Trying to issue a response message of type %s. Expected type is WB", $time(), packet_type.name);
			cnt_invalid++;
			return;
        end;
		#5;

		ni_response.packet_type 		= packet_type;
		ni_response.memory_address 		= memory_address;
		ni_response.source 				= source;
		ni_response.data 				= data;
		ni_response.sharers_count 		= sharers_count;
		ni_response.from_directory 		= from_directory;
		ni_response.req_is_uncoherent 	= is_uncoherent;
		ni_response.requestor 			= DCACHE;
		ni_response.dirty_mask 			= dirty_mask;
		wait(n2m_response_available == 1'b1); //if n2m_response_available is 0, then the response fifo is full. I have to wait.

		ni_response_valid 				= 1'b1;

		#10
		ni_response_valid 				= 1'b0;
		$display("[Time %t] [TESTBENCH] [RES #%3d] Issued a response message of type %s for address 0x%8h", $time(), cnt_res, packet_type.name, memory_address);
		if(packet_type == WB)
			$display("[Time %t] [TESTBENCH] Saving value 0x%h to memory", $time(), data);

	endtask

	task validate_fwd(
		message_forwarded_requests_enum_t 	  packet_type      	= FWD_GETS,
	   	dcache_address_t 				      memory_address 	= 32'b0
	);
		case(packet_type)
			FWD_GETS, FWD_GETM:
			begin
				assert(n2m_response.packet_type == DATA) else
				$error("[Time %t] [TESTBENCH] Response of type %s received for address %8h (on a %s request). Expected was DATA on address %8h", 
					$time(), 
					n2m_response.packet_type.name,
					n2m_response.memory_address,
					packet_type.name,
					memory_address
				);
			end

			default:
			begin
				$error("[Time %t] [TESTBENCH] Impossible to validate response for address %8h. Injection of %s response is not admitted", 
					$time(), 
					memory_address,
					packet_type.name
				);

			end
		endcase

	endtask

	task validate_response(
		message_responses_enum_t 		packet_type 	= WB,
	   	dcache_address_t 				memory_address 	= 32'b0
	);
		case(packet_type)
			WB:
			begin
				assert(n2m_response.packet_type == MC_ACK) 
				else $error("[Time %t] [TESTBENCH] Response of type %s received for address %8h (on a %s request). Expected was MC_ACK on address %8h", 
					$time(), 
					n2m_response.packet_type.name,
					n2m_response.memory_address,
					packet_type,
					memory_address
				);
			end

			default:
			begin
				$error("[Time %t] [TESTBENCH] Impossible to validate response for address %8h. Injection of %s response is not admitted", 
					$time(), 
					memory_address,
					packet_type.name
				);

			end
		endcase

	endtask

	always @(posedge n2m_response_valid) begin
		//Memory tile is (1,1). Responses are expected from Memory tile.

		assert(n2m_response.source.x == 1'b1 ) 
		else $error("[Time %t] [TESTBENCH] Wrong response source.x: %1d. Expected %1d", $time( ), n2m_response.source.x, 1);

		assert(n2m_response.source.y == 1'b1 ) 
		else $error("[Time %t] [TESTBENCH] Wrong response source.y: %1d. Expected %1d", $time( ), n2m_response.source.y, 1);
	end

	always @(posedge n2m_response_valid) begin
		//Responses are expected to be of type DATA or MC_ACK.

		assert(n2m_response.packet_type == DATA || n2m_response.packet_type == MC_ACK) 
		else $error("[Time %t] [TESTBENCH] Wrong response type: %s. Expected DATA or MC_ACK", $time( ), n2m_response.packet_type.name);

	end

endmodule
