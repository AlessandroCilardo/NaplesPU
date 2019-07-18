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
`include "npu_spm_defines.sv"


module requests_issue_unit (
        input   logic                                                       clock,
        input   logic                                                       resetn,

        input   logic                                                       input_is_store,
        input   sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_bank_indexes,
        input   sm_entry_address_t  [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_bank_offsets,
        input   sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_write_data,
        input   sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_byte_mask,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_pending_mask,
        input   logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    input_still_pending_mask,
        input   logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    input_piggyback_data,

        output  logic                                                       output_is_store,
        output  sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    output_bank_indexes,
        output  sm_entry_address_t  [`SM_PROCESSING_ELEMENTS    - 1 : 0]    output_bank_offsets,
        output  sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0]    output_write_data,
        output  sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    output_byte_mask,
        output  logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    output_pending_mask,
        output  logic                                                       output_is_last_request,
        output  logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    output_piggyback_data,

        output  logic               [`SM_PROCESSING_ELEMENTS     - 1 : 0]   mask,
        output  logic                                                       ready
    );

    logic                                                       conflict;
    logic                                                       input_reg_enable;
    logic                                                       output_selection;

    logic                                                       reg_input_is_store;
    sm_bank_address_t   [`SM_PROCESSING_ELEMENTS    - 1 : 0]    reg_input_bank_indexes;
    sm_entry_address_t  [`SM_PROCESSING_ELEMENTS    - 1 : 0]    reg_input_bank_offsets;
    sm_data_t           [`SM_PROCESSING_ELEMENTS    - 1 : 0]    reg_input_write_data;
    sm_byte_mask_t      [`SM_PROCESSING_ELEMENTS    - 1 : 0]    reg_input_byte_mask;
    logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    reg_input_pending_mask;
    logic               [`SM_PROCESSING_ELEMENTS    - 1 : 0]    reg_input_still_pending_mask;
    logic               [`SM_PIGGYBACK_DATA_LEN     - 1 : 0]    reg_input_piggyback_data;

    assign conflict = (|input_still_pending_mask != 0);

//=================================================================================
//Input Registers
//=================================================================================

    always_ff @(posedge clock, negedge resetn) begin : input_registers
        if (!resetn) begin
            reg_input_is_store          <= 0;
            reg_input_bank_indexes      <= 0;
            reg_input_bank_offsets      <= 0;
            reg_input_write_data        <= 0;
            reg_input_byte_mask         <= 0;
            reg_input_pending_mask      <= 0;
            reg_input_piggyback_data    <= 0;
        end else if (input_reg_enable) begin
            reg_input_is_store          <= input_is_store;
            reg_input_bank_indexes      <= input_bank_indexes;
            reg_input_bank_offsets      <= input_bank_offsets;
            reg_input_write_data        <= input_write_data;
            reg_input_byte_mask         <= input_byte_mask;
            reg_input_pending_mask      <= input_pending_mask;
            reg_input_piggyback_data    <= input_piggyback_data;
        end
    end

    always_ff @(posedge clock, negedge resetn) begin
        if (!resetn)
            reg_input_still_pending_mask <= 0;
        else
            reg_input_still_pending_mask <= input_still_pending_mask;
    end

    always_comb begin : output_multiplexer
        if (output_selection == 0) begin
            output_is_store         = input_is_store;
            output_bank_indexes     = input_bank_indexes;
            output_bank_offsets     = input_bank_offsets;
            output_write_data       = input_write_data;
            output_pending_mask     = input_pending_mask;
            output_byte_mask        = input_byte_mask;
            output_piggyback_data   = input_piggyback_data;
            mask                    = input_pending_mask;
        end else begin
            output_is_store         = reg_input_is_store;
            output_bank_indexes     = reg_input_bank_indexes;
            output_bank_offsets     = reg_input_bank_offsets;
            output_write_data       = reg_input_write_data;
            output_pending_mask     = reg_input_still_pending_mask;
            output_byte_mask        = reg_input_byte_mask;
            output_piggyback_data   = reg_input_piggyback_data;
            mask                    = reg_input_pending_mask;
        end
    end

//=================================================================================
//FSM
//=================================================================================

    typedef enum logic [0:0] {
        READY,
        ISSUING_REQUESTS
    } state_t;

    state_t current_state, next_state;

    // State Sequencer
    always_ff @(posedge clock, negedge resetn) begin
        if (!resetn)
            current_state <= READY;
        else
            current_state <= next_state;
    end

    // Next State Decoder
    always_comb begin
        next_state = current_state;
        case (current_state)
            READY :
                if (conflict)
                    next_state = ISSUING_REQUESTS;
            ISSUING_REQUESTS :
                if (!conflict)
                    next_state = READY;
        endcase
    end

    // Output Decoder
    always_comb begin
        case (current_state)
            READY :
            begin
                output_selection        = 1'b0;
                input_reg_enable        = 1'b1;
                ready                   = 1'b1;
                output_is_last_request  = !conflict && (|input_pending_mask != 0);
            end
            ISSUING_REQUESTS :
            begin
                output_selection        = 1'b1;
                input_reg_enable        = 1'b0;
                ready                   = 1'b0;
                output_is_last_request  = !conflict;
            end
        endcase
    end

endmodule
