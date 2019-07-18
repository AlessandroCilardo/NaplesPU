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
`include "npu_coherence_defines.sv"
`include "npu_message_service_defines.sv"

//  The Memory Interface provides a transparent way to interact with the coherence
//  system. The memory interface implements a simple valid/available handshake per
//  thread, different thread might issue different memory transaction and those are
//  concurrently handled by the coherence system. When a thread has a memory request,
//  it first checks the avaliability bit related to its ID, if this is high the 
//  thread issues a nenory transaction setting the valid bit and loading all the 
//  needed information on the Memory Interface. Supported memory operations are
//  reported below along with their opcodes:
//
//      LOAD_8      = 'h0  - 'b000000    
//      LOAD_16     = 'h1  - 'b000001
//      LOAD_32     = 'h2  - 'b000010
//      LOAD_V_8    = 'h7  - 'b000111
//      LOAD_V_16   = 'h8  - 'b001000
//      LOAD_V_32   = 'h9  - 'b001001
//      STORE_8     = 'h20 - 'b100000
//      STORE_16    = 'h21 - 'b100001
//      STORE_32    = 'h22 - 'b100010
//      STORE_V_8   = 'h24 - 'b100100
//      STORE_V_16  = 'h25 - 'b100101
//      STORE_V_32  = 'h26 - 'b100110
//
//  The Synchronization Interface connects the user logic with the synchronization
//  module core-side allocated within the tile (namely the barrier_core unit). 
//  Such interface allows user logic to synchronize on a thread grain. The 
//  synchronization mechanism supports inter- and intra- tile barrier 
//  synchronization.
//  When a thread hits a synchronization point, it issues a request to the 
//  distributed synchronization master through the Synchronization Interface.
//  Then, the thread is stalled (up to the user logic) till its release signal is
//  high again. 

module het_core_example  #(
        parameter TILE_ID       = 0,                   // Tile ID in the Network
        parameter THREAD_NUMB   = 8,                   // Supported thread number, each thread has a separate FIFO in the LSU and requests from different threads are elaborated concurrently - Must be a power of two
        parameter THREAD_IDX_W  = $clog2(THREAD_NUMB), // Do not change, used for declaring signals in the interface, and should be left as it is
        parameter ADDRESS_WIDTH = 32,                  // Memory address width - has to be coherent with the system
        parameter DATA_WIDTH    = 512,                 // Data bus width - has to be coherent with the system
        parameter BYTES_PERLINE = DATA_WIDTH/8         // Bytes per line - Do not change, used for declaring signals in the interface, and should be left as it is
    )
	(
		input  logic                                 clk,
		input  logic                                 reset,
        
        /* Memory Interface */
		// To Heterogeneous LSU
		output logic                                 req_out_valid,     // Valid signal for issued memory requests
        output logic [31 : 0]                        req_out_id,        // ID of the issued request, mainly used for debugging
        output logic [THREAD_IDX_W - 1 : 0]          req_out_thread_id, // Thread ID of issued request. Requests running on different threads are dispatched to the CC conccurrently 
		output logic [7 : 0]                         req_out_op,        // Operation performed
		output logic [ADDRESS_WIDTH - 1 : 0]         req_out_address,   // Issued request address
		output logic [DATA_WIDTH - 1    : 0]         req_out_data,      // Data output

		// From Heterogeneous LSU
		input  logic                                 resp_in_valid,      // Valid signal for the incoming responses
        input  logic [31 : 0]                        resp_in_id,         // ID of the incoming response, mainly used for debugging
        input  logic [THREAD_IDX_W - 1 : 0]          resp_in_thread_id,  // Thread ID of the incoming response
		input  logic [7 : 0]                         resp_in_op,         // Operation code
		input  logic [DATA_WIDTH - 1 : 0]            resp_in_cache_line, // Incoming data
		input  logic [BYTES_PERLINE - 1 : 0]         resp_in_store_mask, // Bitmask of the position of the requesting bytes in the incoming data bus
		input  logic [ADDRESS_WIDTH - 1 : 0]         resp_in_address,    // Incoming response address

        // From Heterogeneous LSU - Performance counters
		input  logic                                 resp_in_miss,  // LSU miss on resp_in_address
		input  logic                                 resp_in_evict, // LSU eviction (replacement) on resp_in_address
		input  logic                                 resp_in_flush, // LSU flush on resp_in_address
		input  logic                                 resp_in_dinv,  // LSU data cache invalidatio on resp_in_address

		// From Heterogeneous accelerator - Backpressure signals
		input  logic [THREAD_NUMB - 1 : 0]           lsu_het_almost_full,           // Thread bitmask, if i-th bit is high, i-th thread cannot issue requests. 
		input  logic [THREAD_NUMB - 1 : 0]           lsu_het_no_load_store_pending, // Thread bitmask, if i-th bit is low, i-th thread has no pending operations. 

        // Heterogeneous accelerator - Flush and Error signals
		output logic                                 lsu_het_ctrl_cache_wt,   // Enable Write-Through cache configuration.
		input  logic                                 lsu_het_error_valid,     // Error coming from LSU
		input  register_t                            lsu_het_error_id,        // Error ID - Misaligned = 380
		input  logic [THREAD_IDX_W - 1 : 0]          lsu_het_error_thread_id, // Thread involved in the Error

        /* Synchronization Interface */
        // To Barrier Core
        output logic                                 breq_valid,       // Hit barrier signal, sends a synchronization request
        output logic [31 : 0]                        breq_op_id,       // Synchronization operation ID, mainly used for debugging 
        output logic [THREAD_NUMB - 1 : 0]           breq_thread_id,   // ID of the thread perfoming the synchronization operation
        output logic [31 : 0]                        breq_barrier_id,  // Barrier ID, has to be unique in case of concurrent barriers
        output logic [31 : 0]                        breq_thread_numb, // Total number - 1 of synchronizing threads on the current barrier ID

        // From Barrier Core
        input  logic [THREAD_NUMB - 1 : 0]           bc_release_val, // Stalled threads bitmask waiting for release (the i-th bit low stalls the i-th thread)

        /* Service Message Interface */
		// From Service Network
		input  logic                                 message_in_valid,         // Valid bit for incoming Service Message 
		input  service_message_t                     message_in,               // Incoming message from Service Network
		output logic                                 n2c_mes_service_consumed, // Service Message consumed

		// To Service Network
		output logic                                 message_out_valid, // Valid bit for outcoming Service Message
		output service_message_t                     message_out,       // Outcoming Service Message data
		input  logic                                 network_available, // Service Network availability bit
		output tile_mask_t                           destination_valid  // One-Hot destinations bitmap
	);
    
    localparam LOCAL_BARRIER_NUMB = 4;
    localparam TOTAL_BARRIER_NUMB = LOCAL_BARRIER_NUMB * `TILE_HT;
    localparam LOCAL_READ_REQS    = 128;
    localparam LOCAL_WRITE_REQS   = 128;
    localparam STARTING_ADDRESS   = 32'h604;

    // Local typedef
    typedef logic  [7  : 0] byte_t;
    typedef byte_t [63 : 0] mem_line_t;

    // Output data declaration
    byte_t [63 : 0] tmp_data_out;
    assign req_out_data = tmp_data_out;

    // Control signals
    logic [$clog2(`TILE_COUNT) - 1 : 0] next_dest;
    logic [`TILE_HT - 1            : 0] ht_count;
	logic [`TILE_COUNT - 1         : 0] service_message_destinations;
    logic pending_barriers, pending_reads, pending_writes, barrier_served, read_served, write_served, incr_address, reset_address;
    int   rem_barriers, rem_reads, rem_writes, thread_id_read, thread_id_write, addr; 
    int   write_counts;

//  -----------------------------------------------------------------------
//  -- Het Core FSM - Local parameters and typedefs
//  -----------------------------------------------------------------------
    // FSM possible states definition
    typedef enum {
        IDLE,
        SEND_BARRIER,
        START_MEM_READ_TRANS,
        START_MEM_WRITE_TRANS,
        WAIT_SYNCH,
        DONE
    } het_fsm_state_t;

	het_fsm_state_t state, next_state;

//  -----------------------------------------------------------------------
//  -- Het Core FSM - Counter and Next State sequential
//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset )
		if ( reset ) begin
			state        <= IDLE;
            rem_barriers <= LOCAL_BARRIER_NUMB;
            rem_reads    <= LOCAL_READ_REQS;
            rem_writes   <= LOCAL_WRITE_REQS;
            addr         <= STARTING_ADDRESS;
            write_counts <= 0;
		end else begin
			state <= next_state; 
            if (barrier_served)
                rem_barriers <= rem_barriers - 1;

            if (read_served)
                rem_reads <= rem_reads - 1;

            if (write_served) begin
                rem_writes   <= rem_writes - 1;
                write_counts <= write_counts + 1;
            end

            if(reset_address)
                addr <= STARTING_ADDRESS; // Memory requests strating address
            else if (incr_address)
                addr <= addr + 1;
		end
    
    assign pending_barriers = (rem_barriers > 0) ? 1'b1 : 1'b0;
    assign pending_reads    = (rem_reads > 0) ? 1'b1 : 1'b0;
    assign pending_writes   = (rem_writes > 0) ? 1'b1 : 1'b0;

    // The following signal enables Write-Through configuration for the L1 cache.
    // If enabled each store flushes data to both L1 cache and the main memory.
    assign lsu_het_ctrl_cache_wt = 1'b1;

//  -----------------------------------------------------------------------
//  -- Het Core FSM - Next State Block
//  -----------------------------------------------------------------------
    // This FSM first synchronizes with other ht in the NoC. Each dummy core in 
    // a ht tile requires a synchronization for LOCAL_BARRIER_NUMB threads
    // (default = 4). 
    // The SEND_BARRIER state sends LOCAL_BARRIER_NUMB requests with barrier ID 
    // 42 through the Synchronization interface. It sets the total number of threads 
    // synchronizing on the barrier ID 42 equal to TOTAL_BARRIER_NUMB (= 
    // LOCAL_BARRIER_NUMB x `TILE_HT, number of heterogeneous tile in the system). 
    // When the last barrier is issued, SEND_BARRIER jumps to WAIT_SYNCH waiting for 
    // the ACK from the synchronization master. 
    // At this point all threads in each ht tile are synchronized, and the FSM starts 
    // all pending memory transactions. 
    // The START_MEM_READ_TRANS performs LOCAL_WRITE_REQS read operations (default = 
    // 128), performing a LOAD_8 operation (op code = 0) each time. In the default 
    // configuration, 128 LOAD_8 operations on consecutive addresses are spread among 
    // all threads and issued to the LSU through the Memory interface.
    // When read operations are over, the FSM starts write operations in a similar way. 
    // The START_MEM_WRITE_TRANS performs LOCAL_WRITE_REQS (default = 128) write 
    // operations on consecutive addresses through the Memory interface. This
    // time the operation performed is a STORE_8, and all ht tile are issuing
    // the same store operation on same addresses compiting for the ownership
    // in a transparent way. The coherence is totally handled by the LSU and
    // CC, on the core side lsu_het_almost_full bitmap states the availability
    // of the LSU for each thread (both writing and reading). In both states, 
    // a thread first checks the availability stored in a position equal to
    // its ID (lsu_het_almost_full[thread_id]), then performs a memory
    // transaction. 
	always_comb begin
		next_state       <= state;
        breq_valid       <= 1'b0;
        barrier_served   <= 1'b0;
        breq_op_id       <= 11;
        breq_thread_id   <= rem_barriers;
        breq_thread_numb <= 0;
        
        incr_address     <= 1'b0;
        reset_address    <= 1'b0;
        read_served      <= 1'b0;
        write_served     <= 1'b0;
        thread_id_read   <= rem_reads[THREAD_IDX_W - 1 : 0];
        thread_id_write  <= rem_writes[THREAD_IDX_W - 1 : 0];
        req_out_valid    <= 1'b0;
        req_out_id       <= 0;
        req_out_op       <= 0;
        req_out_address  <= addr;
        tmp_data_out     <= {DATA_WIDTH{1'b0}};
        breq_barrier_id  <= 0;

		unique case ( state )

            // Checks pending requests.
			IDLE : begin
				if ( pending_barriers ) 
					next_state <= SEND_BARRIER;
                else if ( pending_reads ) 
					next_state <= START_MEM_READ_TRANS;
                else if ( pending_writes ) 
					next_state <= START_MEM_WRITE_TRANS;
				else
					next_state <= IDLE;
			end

			// Issue synchronization requests
			SEND_BARRIER    : begin
                breq_valid       <= 1'b1;
                breq_barrier_id  <= 42;
                barrier_served   <= 1'b1;
                breq_thread_numb <= TOTAL_BARRIER_NUMB - 1;

                if(rem_barriers == 1) 
                    next_state <= WAIT_SYNCH;
                else
                    next_state <= IDLE;
            end

			// Starting multiple read operations
			START_MEM_READ_TRANS    : begin
                if ( rem_reads == 1 )
                    next_state <= DONE;
                else
                    next_state <= IDLE;

                if(lsu_het_almost_full[thread_id_read] == 1'b0) begin
                    read_served       <= 1'b1;
                    req_out_valid     <= 1'b1;
                    req_out_id        <= rem_reads;
                    req_out_op        <= 0; // LOAD_8
                    incr_address      <= 1'b1;
                    req_out_thread_id <= thread_id_read;
                end
            end

			// Starting multiple write operations
			START_MEM_WRITE_TRANS    : begin
                if ( pending_writes )
                    next_state <= IDLE;
                else
                    next_state <= DONE;

                if(lsu_het_almost_full[thread_id_write] == 1'b0 ) begin
                    write_served      <= 1'b1;
                    req_out_valid     <= 1'b1;
                    req_out_id        <= rem_writes;
                    req_out_thread_id <= thread_id_write;
                    req_out_op        <= 'b100000; // STORE_8
                    tmp_data_out[0]   <= 8'hee;
                    incr_address      <= 1'b1;
                end
            end

            // Synchronizes all dummy cores
			WAIT_SYNCH : begin
                if(&bc_release_val)
				    next_state    <= IDLE;
			end
            
			DONE : begin
				next_state    <= IDLE;
                reset_address <= 1'b1;
			end
		endcase
	end

//  -----------------------------------------------------------------------
//  -- Het Core FSM - Service Message Interface
//  -----------------------------------------------------------------------
    // The first HT Core receives a Message from the Host, then it sends the same 
    // message to the next HT in the NoC, which will forwards it to the next node 
    // and so on. 
    // The message from the Host will flow over the Service Network untill all
    // HT cores receive the same message at least once on the Service Network.

    // Service Message consumed as soon as it is received. A message is
    // consumed if its
    assign n2c_mes_service_consumed = message_in_valid & network_available;
    
    // Calculate the next HT core to contact on the Service Network
    always_comb begin
        next_dest = TILE_ID + 1;
        //ht_count  = message_in.data[$clog2(`TILE_COUNT) + `TILE_HT - 1 : $clog2(`TILE_COUNT)] + 1;
    end

	idx_to_oh #(
		.NUM_SIGNALS( `TILE_COUNT ),
		.DIRECTION  ( "LSB0"      ),
		.INDEX_WIDTH( 4           )
	)
	u_address_conv_idx_to_oh (
		.one_hot( service_message_destinations ),
		.index  ( next_dest                    )
	);

    always_ff @ (posedge clk, posedge reset) begin
        if (reset) 
            message_out_valid <= 1'b0;
        else
            if (message_in_valid && ht_count < `TILE_HT) 
                message_out_valid <= 1'b1;
            else
                message_out_valid <= 1'b0;
    end

    always_ff @ (posedge clk) begin
        if (message_in_valid & network_available) begin
            $display("[Time %t] [TILE %2d] [HETERCORE] Incoming Service Message - Message Type: %s - Data: %h", $time(), TILE_ID, message_in.message_type.name(), message_in.data);
            message_out.message_type <= HT_CORE;
            message_out.data         <= {message_in.data[`SERVICE_MESSAGE_LENGTH - 1 : $clog2(`TILE_COUNT) + `TILE_HT], ht_count, next_dest};
            destination_valid        <= service_message_destinations;
        end
    end

//  -----------------------------------------------------------------------
//  -- Het Core FSM - Simulation 
//  -----------------------------------------------------------------------
`ifdef SIMULATION
    localparam MAX_WIDTH      = 262400; 
    localparam FILENAME_INSTR = "/home/mirko/workspace_newnuplus/nuplus/software/kernels/mmsc/obj/mmsc_mem.hex";

    typedef struct packed {
        logic [31 : 0] address_in;
		logic [31 : 0] thread_in;
        logic [31 : 0] op_id;
		logic [7  : 0] op_in;
        logic          checked;
    } pending_req_t;

    pending_req_t read_reqs [LOCAL_READ_REQS];

    int tid, opid;

	logic   [DATA_WIDTH - 1 : 0]    mem_dummy [MAX_WIDTH];

	initial begin
		integer fd;

		fd = $fopen( FILENAME_INSTR, "r" );
		assert ( fd != 0 ) else $error( "[MEMORY] Cannot open memory image" );
		$fclose( fd );

		$readmemh( FILENAME_INSTR, mem_dummy );
	end

    int read_counts = 0;
    
    always @ (posedge clk) begin
        if(req_out_valid) begin
            read_reqs[req_out_id - 1].address_in <= req_out_address; 
            read_reqs[req_out_id - 1].thread_in  <= req_out_thread_id; 
            read_reqs[req_out_id - 1].op_in      <= req_out_op; 
            read_reqs[req_out_id - 1].op_id      <= req_out_id; 
            read_reqs[req_out_id - 1].checked    <= 1'b0;
        end
    end

    always @ (posedge clk) begin
        if (resp_in_valid) begin
            if (read_reqs[resp_in_id - 1].address_in == resp_in_address && 
                read_reqs[resp_in_id - 1].thread_in == resp_in_thread_id && 
                read_reqs[resp_in_id - 1].op_in == resp_in_op && 
                mem_dummy[read_reqs[resp_in_id - 1].address_in[31:6]] == resp_in_cache_line) begin
                read_reqs[resp_in_id - 1].checked = 1'b1;
                read_counts++;
            end 
        end
    end
    always @ (read_counts, write_counts) 
        if (read_counts == LOCAL_READ_REQS && write_counts == LOCAL_WRITE_REQS)
            #40000 $finish(); 
`endif

endmodule
