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

`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_message_service_defines.sv"

module debug_message_handler # (
		parameter TILE_ID = 0 )
	(
		input                                                    clk,
		input                                                    reset,

		// From Network
		input  logic                                             network_available,
		input  service_message_t                                 message_in,
		input  logic                                             message_in_valid,
		output logic                                             n2c_mes_service_consumed,

		// To Network
		output service_message_t                                 message_out,
		output logic                                             message_out_valid,
		output tile_mask_t                                       destination_valid,

		// Interface To NPU

		input  address_t             [`THREAD_NUMB - 1 : 0]      dsu_bp_instruction,
		input  thread_id_t                                       dsu_bp_thread_id,
		input                                                    dsu_serial_reg,
		input                                                    dsu_stop_shift,
		input                                                    dsu_hit_breakpoint,

		output logic                                             dsu_enable,
		output logic                                             dsu_single_step,
		output address_t             [7 : 0]                     dsu_breakpoint,
		output logic                                             dsu_breakpoint_enable,
		output logic                                             dsu_resume_core,
		output logic                                             dsu_thread_selection,
		output thread_id_t                                       dsu_thread_id,
		output logic                                             dsu_en_vector,
		output logic                                             dsu_en_scalar,
		output logic                                             dsu_start_shift,
		output logic                 [`REGISTER_ADDRESS - 1 : 0] dsu_reg_addr

	);

	typedef struct packed {
		logic enable_bit;
		logic [`REGISTER_SIZE*`HW_LANE - 1 : 0] data;
		host_message_type_t message;
	} dsu_message_t;

	typedef enum {
		IDLE_DSU,
		ENABLE_DSU,
		SET_BREAKPOINT,
		ENABLE_BREAKPOINT,
		ENABLE_SIGNLE_STEP,
		SELCT_THREAD,
		READ_V_REGISTER,
		READ_S_REGISTER,
		WAIT_REGISTER_DATA,
		SEND_DATA,
		PREPARE_ACK,
		WAIT_BP_INFO,
		RESUME_CORE
	}debug_state_t;

	debug_state_t                                  state, next_state;
	tile_mask_t                                    one_hot_destination;
	dsu_message_t                                  message_to_net, message_from_net;
	logic         [7 : 0]                          dsu_bp_mask;
	address_t     [7 : 0]                          dsu_breakpoint_list;

	logic         [$clog2 ( `TILE_COUNT ) - 1 : 0] index;
	logic                                          update_enable_dsu, update_disable_dsu;
	logic                                          update_breakpoint;
	logic                                          update_enable_bp, update_disable_bp;
	logic                                          update_enable_ss, update_disable_ss;
	logic                                          update_select_thread, update_deselect_thread;
	logic                                          update_register_out;
	logic                                          update_bp_info;
	logic                                          update_ack_message;

	assign message_from_net         = dsu_message_t' ( message_in.data ) ;

	assign message_out.message_type = DEBUG;
	assign message_out.destination  = 0;
	assign message_out.data         = service_message_data_t' ( message_to_net ) ;
	assign destination_valid        = one_hot_destination;
	assign dsu_reg_addr             = message_from_net.data[`REGISTER_ADDRESS - 1 : 0];


	//  -----------------------------------------------------------------------
	//  -- Control Unit - Next State sequential
	//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			state <= IDLE_DSU;
		end else begin
			state <= next_state; // default is to stay in current state
		end
	end


	//  -----------------------------------------------------------------------
	//  -- Control Unit - Next State and updating signal set block
	//  -----------------------------------------------------------------------
	always_comb begin
		n2c_mes_service_consumed <= 1'b0;
		update_enable_dsu        <= 1'b0;
		update_disable_dsu       <= 1'b0;
		update_breakpoint        <= 1'b0;
		update_enable_bp         <= 1'b0;
		update_disable_bp        <= 1'b0;
		update_enable_ss         <= 1'b0;
		update_disable_ss        <= 1'b0;
		update_select_thread     <= 1'b0;
		update_deselect_thread   <= 1'b0;
		dsu_en_vector            <= 1'b0;
		dsu_en_scalar            <= 1'b0;
		dsu_start_shift          <= 1'b0;
		update_bp_info           <= 1'b0;
		update_register_out      <= 1'b0;
		update_ack_message       <= 1'b0;
		message_out_valid        <= 1'b0;
		dsu_resume_core          <= 1'b0;

		next_state               <= state;
		unique case ( state )

			IDLE_DSU           : begin
				if ( message_in_valid ) begin
					next_state             <= read_debugger_command ( message_from_net.message ) ;
				end else if ( dsu_hit_breakpoint ) begin
					next_state             <= WAIT_BP_INFO;
				end
			end

			ENABLE_DSU         : begin
				if ( message_from_net.enable_bit )
					update_enable_dsu      <= 1'b1;
				else
					update_disable_dsu     <= 1'b1;

				n2c_mes_service_consumed <= 1'b1;
				next_state               <= PREPARE_ACK;
			end

			SET_BREAKPOINT     : begin
				update_breakpoint        <= 1'b1;
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= PREPARE_ACK;
			end

			ENABLE_BREAKPOINT  : begin
				if ( message_from_net.enable_bit )
					update_enable_bp       <= 1'b1;
				else
					update_disable_bp      <= 1'b1;
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= PREPARE_ACK;
			end

			ENABLE_SIGNLE_STEP : begin
				if ( message_from_net.enable_bit )
					update_enable_ss       <= 1'b1;
				else
					update_disable_ss      <= 1'b1;
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= PREPARE_ACK;
			end

			SELCT_THREAD       : begin
				if ( message_from_net.enable_bit )
					update_select_thread   <= 1'b1;
				else
					update_deselect_thread <= 1'b1;
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= PREPARE_ACK;
			end

			READ_V_REGISTER    : begin
				dsu_en_vector            <= 1'b1;
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= WAIT_REGISTER_DATA;
			end

			READ_S_REGISTER    : begin
				dsu_en_scalar            <= 1'b1;
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= WAIT_REGISTER_DATA;
			end

			WAIT_REGISTER_DATA : begin
				dsu_start_shift          <= 1'b1;
				if ( ~dsu_stop_shift )
					update_register_out    <= 1'b1;
				else
					next_state             <= SEND_DATA;
			end

			WAIT_BP_INFO       : begin
				update_bp_info           <= 1'b1;
				next_state               <= SEND_DATA;
			end

			PREPARE_ACK        : begin
				update_ack_message       <= 1'b1;
				next_state               <= SEND_DATA;
			end

			SEND_DATA          : begin
				if ( network_available ) begin
					message_out_valid      <= 1'b1;
					next_state             <= IDLE_DSU;
				end
			end

			RESUME_CORE        : begin
				dsu_resume_core          <= 1'b1;
				next_state               <= PREPARE_ACK;
			end

		endcase
	end



	//  -----------------------------------------------------------------------
	//  -- Control Unit - Update Signal Output
	//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset ) begin
		if( reset ) begin
			dsu_enable            <= 1'b0;
			dsu_breakpoint_enable <= 1'b0;
			dsu_single_step       <= 1'b0;
			dsu_thread_selection  <= 1'b0;
		end else begin
			if ( update_enable_dsu )
				dsu_enable                                                           <= 1'b1;
			else if ( update_disable_dsu )
				dsu_enable                                                           <= 1'b0;

			if ( update_breakpoint ) begin
				dsu_breakpoint_list                                                  <= message_from_net.data[( `ADDRESS_SIZE * 8 ) - 1 : 0];
				dsu_bp_mask                                                          <= message_from_net.data[( `ADDRESS_SIZE * 8 ) + 7 : ( `ADDRESS_SIZE * 8 )];
			end

			if ( update_enable_bp )
				dsu_breakpoint_enable                                                <= 1'b1;
			else if ( update_disable_bp )
				dsu_breakpoint_enable                                                <= 1'b0;

			if ( update_enable_ss )
				dsu_single_step                                                      <= 1'b1;
			else if ( update_disable_ss )
				dsu_single_step                                                      <= 1'b0;

			if ( update_select_thread ) begin
				dsu_thread_selection                                                 <= 1'b1;
				dsu_thread_id                                                        <= thread_id_t' ( message_from_net.data ) ;
			end else if ( update_deselect_thread ) begin
				dsu_thread_selection                                                 <= 1'b0;
				dsu_thread_id                                                        <= thread_id_t' ( 1'b0 ) ;
			end

			if ( update_register_out ) begin
				message_to_net.enable_bit                                            <= 1'b0;
				message_to_net.data[`REGISTER_SIZE*`HW_LANE - 1 : 0]                 <= {message_to_net.data[`REGISTER_SIZE*`HW_LANE - 2 : 0], dsu_serial_reg};
				message_to_net.message                                               <= DSU_REG_VALUE_RSP;
			end

			if ( update_bp_info ) begin
				message_to_net.enable_bit                                            <= 1'b0;
				message_to_net.data[$clog2 ( `THREAD_NUMB ) + `ADDRESS_SIZE - 1 : 0] <= {dsu_bp_thread_id,dsu_bp_instruction[dsu_bp_thread_id]};
				message_to_net.message                                               <= DSU_BP_VALUE_RSP;
			end

			if ( update_ack_message ) begin
				message_to_net.enable_bit                                            <= 1'b0;
				message_to_net.data                                                  <= 0;
				message_to_net.message                                               <= DSU_ACK_RSP;
			end
		end

	end


	always_comb
		index <= `TILE_H2C_ID;


	genvar                                         bp_id;
	generate
		for ( bp_id = 0; bp_id < 8; bp_id++ ) begin
			always_comb begin
				if( dsu_bp_mask[bp_id] )
					dsu_breakpoint[bp_id] = dsu_breakpoint_list[bp_id];
				else
					dsu_breakpoint[bp_id] = 32'hffffffff;
			end
		end
	endgenerate


	idx_to_oh # (
		.NUM_SIGNALS ( $bits ( tile_mask_t )  ) ,
		.DIRECTION   ( "LSB0"                 ) ,
		.INDEX_WIDTH ( $clog2 ( `TILE_COUNT ) )
	)
	u_idx_to_oh (
		.one_hot ( one_hot_destination ) ,
		.index   ( index               )
	) ;
endmodule
