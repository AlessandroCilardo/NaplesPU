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
`include "npu_coherence_defines.sv"

/*
 * Miss Status Handling Register is used to handle cache lines data whose coherence transactions 
 * are pending; that is the case in which a cache block is in a non-stable state. Bear in mind 
 * that only one request per thread can be issued, MSHR has the same entry as the number of 
 * hardware threads.
 * 
 * An MSHR entry comprises the following data:
 *      - Valid: entry has valid data
 *      - Address: entry memory address
 *      - Thread ID: requesting HW thread id
 *      - Wakeup Thread: wakeup thread when the transaction is over 
 *      - State: actual coherence state
 *      - Waiting for eviction: asserted for replacement requests
 *      - Ack count: remaining acks to receive
 *      - Data: data associated to request
 *
 * Note that entry's Data are stored in a separate SRAM memory in order to ease the lookup process.
 */ 

module mshr_cc #(
	FULL_THRESHOLD = 3,
	SET_COLLWIDTH  = 5,
        WRITE_FIRST    = "FALSE"
    )(
        input  logic                                     clk,
        input  logic                                     enable,
        input  logic                                     reset,

        input  dcache_tag_t [`MSHR_LOOKUP_PORTS - 1 : 0] lookup_tag,
        input  dcache_set_t [`MSHR_LOOKUP_PORTS - 1 : 0] lookup_set,
        output logic        [`MSHR_LOOKUP_PORTS - 1 : 0] lookup_hit,
        output logic        [`MSHR_LOOKUP_PORTS - 1 : 0] lookup_hit_set,
        output mshr_idx_t   [`MSHR_LOOKUP_PORTS - 1 : 0] lookup_index,
        output mshr_entry_t [`MSHR_LOOKUP_PORTS - 1 : 0] lookup_entry,

        output logic                                     full,
        output mshr_idx_t                                empty_index,

        input  logic                                     update_en,
        input  mshr_idx_t                                update_index,
        input  mshr_entry_t                              update_entry
    );
    localparam EFFECTIVE_SET_WIDTH = 2 ** SET_COLLWIDTH;
    mshr_entry_t [`MSHR_SIZE - 1        : 0] data;
    mshr_entry_t [`MSHR_SIZE - 1        : 0] data_updated;
    logic        [`MSHR_SIZE - 1        : 0] empty_oh;
    logic                                    is_not_full;
    logic     [$clog2(`MSHR_SIZE) - 1 	: 0] set_counter[EFFECTIVE_SET_WIDTH];
    logic        [31                    : 0] is_set_full;

`ifdef SIMULATION
    logic [$clog2(`MSHR_SIZE) - 1 	: 0] vset_counter[EFFECTIVE_SET_WIDTH];
`endif 

//  --------------------------------------
//  -- MSHR write port
//  --------------------------------------

    generate
        genvar mshr_id;
        for ( mshr_id = 0; mshr_id < `MSHR_SIZE; mshr_id++ ) begin : mshr_entries

            logic 				update_this_index;

            assign update_this_index = update_en & (update_index == mshr_idx_t'(mshr_id));

            if (WRITE_FIRST == "TRUE")
                assign data_updated[mshr_id] = (enable && update_this_index) ? update_entry : data[mshr_id];
            else
                assign data_updated[mshr_id] = data[mshr_id];

            assign empty_oh[mshr_id] = ~(data_updated[mshr_id].valid);

	    always_ff @(posedge clk, posedge reset) begin : ENTRY_ALLOCATION_LOGIC
	    	if (reset) begin
			data[mshr_id] <= 0;
		end else if (enable && update_this_index) begin
			if (data[mshr_id].valid == 1 && (data[mshr_id].address.index != update_entry.address.index) && (data[mshr_id].address.tag != update_entry.address.tag) && update_entry.waiting_for_eviction == 0)
				assert (0) else $fatal(0, "MSHR entry overwritten!");
				data[mshr_id] <= update_entry;
			end
		end
    	end
    endgenerate
    
    // The following structure tracks all pending entries in the MSHR, and
    // checks that the same set is pending in no more than N-1 entries,
    // where N is the number of ways of the Cache L1. 
    //
    // If that condition is reached, the Cache Controller stage 1 stops
    // scheduling both load and store requests from the core, that are the
    // only which allocate a new entry in the MSHR. 
    //
    // This mechanism is meant to prevent a live lock condition which incurs 
    // when a pending transaction cannot be deallocated from the MSHR and 
    // stored in the L1, since all the valid ways of the same set are pending 
    // in the MSHR as well, and they cannot be replaced. 
    generate
    	genvar set_id;

        for ( set_id = 0; set_id < EFFECTIVE_SET_WIDTH; set_id++ ) begin : SET_COUNTER_GEN
            logic is_allocation;
            logic is_deallocation;
            logic is_new_entry;

            assign is_new_entry      = (data[update_index].address[`ADDRESS_SIZE - 1 : 6] == update_entry.address[`ADDRESS_SIZE - 1 : 6]) ? ~data[update_index].valid : 1'b0; 
            assign is_allocation     = update_en & (update_entry.address.index[SET_COLLWIDTH - 1 : 0] == set_id) & update_entry.valid & ~update_entry.waiting_for_eviction & ( (data[update_index].address[`ADDRESS_SIZE - 1 : 6] != update_entry.address[`ADDRESS_SIZE - 1 : 6]) | is_new_entry );
            assign is_deallocation   = update_en & (update_entry.address.index[SET_COLLWIDTH - 1 : 0] == set_id) & ~update_entry.valid;
            
            always_ff @ (posedge clk, posedge reset) begin : SET_COUNTER_LOGIC
               if ( reset )
                   set_counter[set_id] <= 0;
               else
                   if (is_allocation & ~is_deallocation)
                    set_counter[set_id] <= set_counter[set_id] + 1;
                   else
                       if (~is_allocation & is_deallocation)
                           set_counter[set_id] <= set_counter[set_id] - 1;
                       else
                        set_counter[set_id] <= set_counter[set_id];
            end 

	    always_comb begin 
		    if(set_counter[set_id] >= FULL_THRESHOLD)
			    is_set_full[set_id] = 1'b1;
		    else
			    is_set_full[set_id] = 1'b0;
	    end 
`ifdef SIMULATION
            int i;
            always @ (data)
            begin
            	vset_counter[set_id] = 0;
		for(i=0; i < `MSHR_SIZE; i = i+1) begin : VALIDATION_FOR 
           		if (data[i].valid & data[i].address.index[SET_COLLWIDTH - 1 : 0] == set_id)
                   		vset_counter[set_id] = vset_counter[set_id] + 1;
		end 

		if ( ~reset )
			assert( vset_counter[set_id] == set_counter[set_id] ) else $error("[MSHR_CC] Set count mismatch! HW Count: %d\tSW Count: %d\n", set_counter[set_id], vset_counter[set_id]);
            end
`endif
	end 

    endgenerate

    assign full = |is_set_full;

//  --------------------------------------
//  -- MSHR lookup read port
//  --------------------------------------
    generate
        genvar lookup_port_idx;
        for (lookup_port_idx = 0; lookup_port_idx < `MSHR_LOOKUP_PORTS; lookup_port_idx++) begin :lookup_ports

            mshr_cc_lookup_unit lookup_unit (
                .tag          ( lookup_tag[lookup_port_idx]     ),
                .index        ( lookup_set[lookup_port_idx]     ),
                .mshr_entries ( data_updated                    ),
                .hit          ( lookup_hit[lookup_port_idx]     ),
                .hit_set      ( lookup_hit_set[lookup_port_idx] ),
                .mshr_index   ( lookup_index[lookup_port_idx]   ),
                .mshr_entry   ( lookup_entry[lookup_port_idx]   )
            );

        end
    endgenerate

//  --------------------------------------
//  -- MSHR empty index generation
//  --------------------------------------

    priority_encoder_npu #(
        .INPUT_WIDTH (`MSHR_SIZE ),
        .MAX_PRIORITY("LSB"      )
    )
    u_priority_encoder (
        .decode(empty_oh   ),
        .encode(empty_index),
        .valid (is_not_full)
    );


endmodule

module mshr_cc_lookup_unit (
        input  dcache_tag_t                      tag,
        input  dcache_set_t                      index,
        input  mshr_entry_t [`MSHR_SIZE - 1 : 0] mshr_entries,

        output logic                             hit,
        output logic                             hit_set,
        output mshr_idx_t                        mshr_index,
        output mshr_entry_t                      mshr_entry
    );

    logic      [`MSHR_SIZE - 1 : 0] hit_map;
    logic      [`MSHR_SIZE - 1 : 0] hit_set_map;
    mshr_idx_t                      hit_index;
    mshr_idx_t                      hit_set_index;

    genvar                          i;
    generate
        for ( i = 0; i < `MSHR_SIZE; i++ ) begin : lookup_logic
            assign hit_set_map[i] = ( mshr_entries[i].address.index == index ) && mshr_entries[i].valid;
            assign hit_map[i]     = ( mshr_entries[i].address.tag == tag ) && hit_set_map[i];
        end
    endgenerate


    oh_to_idx #(
        .NUM_SIGNALS( `MSHR_SIZE ),
        .DIRECTION  ( "LSB0"     )
    )
    u_hit_oh_to_idx (
        .index  ( hit_index ),
        .one_hot( hit_map   )
    );

    oh_to_idx #(
        .NUM_SIGNALS( `MSHR_SIZE ),
        .DIRECTION  ( "LSB0"     )
    )
    u_hit_set_oh_to_idx (
        .index  ( hit_set_index ),
        .one_hot( hit_set_map   )
    );

    assign mshr_entry = hit ? mshr_entries[hit_index] : mshr_entries[hit_set_index];
    assign hit        = |hit_map;
    assign hit_set    = |hit_set_map;
    assign mshr_index = hit ? hit_index : hit_set_index;
    
endmodule
