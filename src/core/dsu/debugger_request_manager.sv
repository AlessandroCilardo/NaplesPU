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
`include "npu_network_defines.sv"

`ifdef DISPLAY_REQUESTS_MANAGER
`include "npu_debug_log.sv"
`endif

module debugger_request_manager #(
		parameter TILE_ID = 0,
		parameter ITEM_w  = 32 // Input and output item width (control interface)

	)
	(
		input                                         clk,
		input                                         reset,

		// Interface to Host
		input                        [ITEM_w - 1 : 0] item_data_i,                       // Input: items from outside
		input                                         item_valid_i,                      // Input: valid signal associated with item_data_i port
		output logic                                  item_avail_o,                      // Output: avail signal to input port item_data_i
		output logic                 [ITEM_w - 1 : 0] item_data_o,                       // Output: items to outside
		output logic                                  item_valid_o,                      // Output: valid signal associated with item_data_o port
		input                                         item_avail_i,                      // Input: avail signal to ouput port item_data_o

		output logic                                  hit_breakpoint,
		// To host interface component
		output logic                                  wait_dsu,
		output logic                                  valid_arbiter,

		//Network Interface
		input  service_message_t                      n2c_mes_service,
		input  logic                                  n2c_mes_valid,
		input  logic                                  ni_network_available,
		output logic                                  n2c_mes_service_consumed,

		output service_message_t                      c2n_mes_service,
		output logic                                  c2n_mes_valid,
		output logic                                  c2n_has_data,
		output tile_mask_t                            c2n_mes_service_destinations_valid

	);

	typedef struct packed {
		logic enable_bit;
		logic [`REGISTER_SIZE*`HW_LANE - 1 : 0] data;
		host_message_type_t message;
	} dsu_message_t;

	typedef enum {
		START_DSU_INTERFACE,
		IDLE_DSU_INTERFACE,
		WAIT_HOST_DB_CMD,
		WAIT_DSU_DEST,
		ENABLE_DSU_STATE,
		DISABLE_DSU_STATE,
		SET_BP_STATE,
		STOP_SET_BP_STATE,
		WAIT_BP_MASK,
		RESUME_CORE_STATE,
		SELECT_THREAD,
		RECEIVE_ADDRESS_REG,
		READ_REGISTER,
		SEND_REG_HOST,
		SEND_DATA_DSU,
		WAIT_DSU_ACK,
		SEND_DSU_ACK_HOST,
		STOP_SEND_SCALAR_REG,
		STOP_SEND_VECTOR_REG,
		BP_INFO_STATE,
		STOP_SEND_BP_INFO,
		SEND_DATA_HOST
	}debug_interface_state_t;

	debug_interface_state_t                                   state,next_state, state_control_supp_next, state_control_receive_reg;

	logic                                                     has_data;
	host_message_type_t                                       cmd_host_in, cmd_to_dsu;
	tile_mask_t                                               one_hot_destination_valid;
	logic                   [$clog2( `TILE_COUNT ) - 1 : 0]   message_to_net_destinations_valid;
	dsu_message_t                                             message_to_net;
	dsu_message_t                                             message_from_net;
	logic                   [`REGISTER_SIZE*`HW_LANE - 1 : 0] message_data;

	logic                                                     update_destination;
	logic                                                     update_enable;
	logic                                                     update_disable;
	logic                                                     update_dsu_cmd;
	logic                                                     update_ack_host;
	logic                                                     update_bp_reg_value;
	logic                                                     update_cmd_msg;
	logic                                                     update_reg_value;
	logic                                                     update_data_reg;
	logic                                                     update_addr_reg;
	logic                                                     update_thread_selection;
	logic                                                     update_bp_mask;
	logic                                                     reset_word_cnt, increment_word_cnt;

	logic                   [3 : 0]                           word_sent;
	assign c2n_mes_service_destinations_valid = one_hot_destination_valid;

	//Message from host
	assign cmd_host_in                        = host_message_type_t'( item_data_i );

	//Message to Network
	assign c2n_mes_service.message_type       = DEBUG;
	assign c2n_mes_service.destination        = 0;
	assign c2n_mes_service.data               = service_message_data_t'( message_to_net );

	//Message from net
	assign message_from_net                   = dsu_message_t'( n2c_mes_service.data );
	//  -----------------------------------------------------------------------------------------------
	//  -- Useful to set the has_data bit in the network to send a packet bigger than one flit (64 bit)
	//  -----------------------------------------------------------------------------------------------
	generate
		if ( $bits( service_message_t ) <= `PAYLOAD_W )
			assign has_data = 1'b0;
		else
			assign has_data = 1'b1;
	endgenerate


	//  -----------------------------------------------------------------------
	//  -- Control Unit - Next State sequential
	//  -----------------------------------------------------------------------

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			state <= START_DSU_INTERFACE;
		end else begin
			state <= next_state; // default is to stay in current state
		end
	end


	//  -----------------------------------------------------------------------
	//  -- Control Unit - Next State and updating signal set block
	//  -----------------------------------------------------------------------
	always_comb begin
		item_valid_o              <= 1'b0;
		item_avail_o              <= 1'b0;

		update_destination        <= 1'b0;
		update_enable             <= 1'b0;
		update_disable            <= 1'b0;
		update_dsu_cmd            <= 1'b0;
		update_ack_host           <= 1'b0;
		update_bp_reg_value       <= 1'b0;
		update_cmd_msg            <= 1'b0;
		update_reg_value          <= 1'b0;
		update_data_reg           <= 1'b0;
		update_addr_reg           <= 1'b0;
		update_thread_selection   <= 1'b0;
		update_bp_mask            <= 1'b0;

		increment_word_cnt        <= 1'b0;
		reset_word_cnt            <= 1'b0;

		n2c_mes_service_consumed  <= 1'b0;
		c2n_mes_valid             <= 1'b0;
		valid_arbiter             <= 1'b1;
		wait_dsu                  <= 1'b1;
		hit_breakpoint            <= 1'b0;

		state_control_receive_reg <= state_control_receive_reg;
		state_control_supp_next   <= state_control_supp_next;
		next_state                <= state;
		unique case ( state )

			START_DSU_INTERFACE  : begin
				wait_dsu                 <= 1'b0;
				valid_arbiter            <= 1'b0;
				next_state               <= WAIT_HOST_DB_CMD;
			end

			WAIT_HOST_DB_CMD     : begin
				item_avail_o             <= 1'b1;

				if( item_valid_i ) begin
					unique case ( cmd_host_in )
						DSU_ENABLE_CMD               : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= WAIT_DSU_DEST;
							state_control_supp_next   <= ENABLE_DSU_STATE;
						end
						DSU_DISABLE_CMD              : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= WAIT_DSU_DEST;
							state_control_supp_next   <= DISABLE_DSU_STATE;
						end
						DSU_ENABLE_BP_CMD            : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= ENABLE_DSU_STATE;
						end
						DSU_DISABLE_BP_CMD           : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= DISABLE_DSU_STATE;
						end
						DSU_ENABLE_SS_CMD            : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= ENABLE_DSU_STATE;
						end
						DSU_DISABLE_SS_CMD           : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= DISABLE_DSU_STATE;
						end
						DSU_ENABLE_SELECTION_TH_CMD  : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= SELECT_THREAD;
						end
						DSU_DISABLE_SELECTION_TH_CMD : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= DISABLE_DSU_STATE;
						end
						DSU_SET_BP_CMD               : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= SET_BP_STATE;
						end
						DSU_READ_BP_INFO_CMD         : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= BP_INFO_STATE;
						end
						DSU_RESUME_CMD               : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= RESUME_CORE_STATE;
						end
						DSU_READ_S_REG_CMD           : begin
							update_dsu_cmd            <= 1'b1;
							next_state                <= RECEIVE_ADDRESS_REG;
							state_control_supp_next   <= READ_REGISTER;
							state_control_receive_reg <= STOP_SEND_SCALAR_REG;
						end
						DSU_READ_V_REG_CMD           : begin
							update_dsu_cmd            <= 1'b1;
							reset_word_cnt            <= 1'b1;
							next_state                <= RECEIVE_ADDRESS_REG;
							state_control_supp_next   <= READ_REGISTER;
							state_control_receive_reg <= STOP_SEND_VECTOR_REG;
						end
					endcase
				end else begin
					if( n2c_mes_valid & n2c_mes_service.message_type == DEBUG ) begin
						if ( message_from_net.message == DSU_BP_VALUE_RSP ) begin
							update_data_reg <= 1'b1;
							next_state      <= BP_INFO_STATE;
						end
					end else begin
						wait_dsu                 <= 1'b0;
						valid_arbiter            <= 1'b0;
					end
				end
			end

			WAIT_DSU_DEST        : begin
				item_avail_o             <= 1'b1;
				if ( item_valid_i ) begin
					update_destination       <= 1'b1;
					next_state               <= state_control_supp_next;
				end
			end

			//One State for all enable command
			ENABLE_DSU_STATE     : begin
				update_enable            <= 1'b1;
				next_state               <= SEND_DATA_DSU;
				state_control_supp_next  <= WAIT_DSU_ACK;
			end

			//One state for all disable command
			DISABLE_DSU_STATE    : begin
				update_disable           <= 1'b1;
				next_state               <= SEND_DATA_DSU;
				state_control_supp_next  <= WAIT_DSU_ACK;
			end

			SEND_DATA_DSU        : begin
				if( ni_network_available ) begin
					c2n_mes_valid            <= 1'b1;
					next_state               <= state_control_supp_next;
				end
			end

			WAIT_DSU_ACK         : begin
				if( ni_network_available ) begin
					if ( n2c_mes_valid & message_from_net.message == DSU_ACK_RSP ) begin
						update_ack_host          <= 1'b1;
						n2c_mes_service_consumed <= 1'b1;
						next_state               <= SEND_DSU_ACK_HOST;
					end
				end
			end

			SEND_DSU_ACK_HOST    : begin
				if( item_avail_i ) begin
					item_valid_o             <= 1'b1;
					next_state               <= WAIT_HOST_DB_CMD;
				end
			end

			SET_BP_STATE         : begin
				item_avail_o             <= 1'b1;
				if ( item_valid_i ) begin
					next_state               <= STOP_SET_BP_STATE;
				end
			end

			STOP_SET_BP_STATE    : begin
				if( item_data_i == 32'hffffffff ) begin //se ricevo tutte f allora ho finito di ricevere il dato che in questo caso sono i breakpoint
					next_state               <= SEND_DATA_DSU;
					state_control_supp_next  <= WAIT_BP_MASK;
				end else begin
					update_bp_reg_value      <= 1'b1;
					next_state               <= SET_BP_STATE;
				end
			end

			WAIT_BP_MASK         : begin
				if ( item_valid_i ) begin
					update_bp_mask           <= 1'b1;
					next_state               <= WAIT_DSU_ACK;
				end
			end

			RESUME_CORE_STATE    : begin
				update_cmd_msg           <= 1'b1;
				next_state               <= SEND_DATA_DSU;
				state_control_supp_next  <= WAIT_DSU_ACK;
			end

			RECEIVE_ADDRESS_REG  : begin
				item_avail_o             <= 1'b1;
				if ( item_valid_i ) begin
					update_addr_reg          <= 1'b1;
					next_state               <= SEND_DATA_DSU;
				end
			end

			SELECT_THREAD        : begin
				item_avail_o             <= 1'b1;
				if ( item_valid_i ) begin
					update_thread_selection  <= 1'b1;
					next_state               <= SEND_DATA_DSU;
				end
			end

			READ_REGISTER        : begin
				if( ni_network_available & n2c_mes_valid ) begin
					if ( message_from_net.message == DSU_REG_VALUE_RSP ) begin
						update_data_reg          <= 1'b1;
						next_state               <= SEND_REG_HOST;
					end
				end
			end

			SEND_REG_HOST        : begin
				update_reg_value         <= 1'b1;
				next_state               <= SEND_DATA_HOST;
				state_control_supp_next  <= state_control_receive_reg;
			end

			SEND_DATA_HOST       : begin
				if( item_avail_i ) begin
					item_valid_o             <= 1'b1;
					next_state               <= state_control_supp_next;
				end
			end

			STOP_SEND_VECTOR_REG : begin
				if( word_sent == 4'b1111 ) begin
					reset_word_cnt           <= 1'b1;
					n2c_mes_service_consumed <= 1'b1;
					next_state               <= WAIT_HOST_DB_CMD;
				end else begin
					increment_word_cnt       <= 1'b1;
					update_reg_value         <= 1'b1;
					next_state               <= SEND_DATA_HOST;
					state_control_supp_next  <= STOP_SEND_VECTOR_REG;
				end
			end

			STOP_SEND_SCALAR_REG : begin
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= WAIT_HOST_DB_CMD;
			end

			BP_INFO_STATE        : begin
				update_reg_value         <= 1'b1;
				next_state               <= SEND_DATA_HOST;
				state_control_supp_next  <= STOP_SEND_BP_INFO;
			end

			STOP_SEND_BP_INFO    : begin
				update_reg_value         <= 1'b1;
				hit_breakpoint           <= 1'b1;
				n2c_mes_service_consumed <= 1'b1;
				next_state               <= SEND_DATA_HOST;
				state_control_supp_next  <= WAIT_HOST_DB_CMD;
			end
		endcase
	end

	//  -----------------------------------------------------------------------
	//  -- Control Unit - Update Signal Output
	//  -----------------------------------------------------------------------
	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			c2n_has_data <= 1'b0;
			cmd_to_dsu   <= host_message_type_t'( 1'b0 );
			word_sent    <= 4'b0000;
		end else begin
			c2n_has_data <= has_data;
			if( update_destination ) begin
				message_to_net_destinations_valid                                      <= item_data_i[$clog2( `TILE_COUNT )- 1 : 0];
			end

			if( update_dsu_cmd ) begin
				cmd_to_dsu                                                             <= cmd_host_in;
			end

			if( update_thread_selection ) begin
				message_to_net.enable_bit                                              <= 1'b1;
				message_to_net.data[`REGISTER_SIZE*`HW_LANE - 1 : 0]                   <= {message_to_net.data[( `REGISTER_SIZE*`HW_LANE ) - ( ITEM_w - 1 ) : 0], item_data_i};
				message_to_net.message                                                 <= cmd_to_dsu;
			end

			if( update_data_reg )begin
				message_data                                                           <= message_from_net.data;
			end

			if( update_enable ) begin
				message_to_net.enable_bit                                              <= 1'b1;
				message_to_net.data                                                    <= {`REGISTER_SIZE*`HW_LANE{1'hf}};
				message_to_net.message                                                 <= cmd_to_dsu;
			end else if( update_disable ) begin
				message_to_net.enable_bit                                              <= 1'b0;
				message_to_net.data                                                    <= {`REGISTER_SIZE*`HW_LANE{1'hf}};
				message_to_net.message                                                 <= cmd_to_dsu;
			end

			if( update_bp_reg_value ) begin
				message_to_net.enable_bit                                              <= 1'b0;
				message_to_net.data[`REGISTER_SIZE*`HW_LANE - 1 : 0]                   <= {message_to_net.data[( `REGISTER_SIZE*`HW_LANE ) - ( ITEM_w - 1 ) : 0], item_data_i};

				message_to_net.message                                                 <= cmd_to_dsu;
			end

			if( update_bp_mask ) begin
				message_to_net.enable_bit                                              <= 1'b0;
				message_to_net.data[( `ADDRESS_SIZE * 8 ) + 7 : ( `ADDRESS_SIZE * 8 )] <= item_data_i[7 : 0];
				message_to_net.message                                                 <= cmd_to_dsu;
			end

			if( update_addr_reg ) begin
				message_to_net.enable_bit                                              <= 1'b0;
				message_to_net.data[`REGISTER_SIZE*`HW_LANE - 1 : 0]                   <= {message_to_net.data[`REGISTER_SIZE*`HW_LANE - 1 : ITEM_w], item_data_i};
				message_to_net.message                                                 <= cmd_to_dsu;
			end

			if( update_ack_host ) begin
				item_data_o                                                            <= message_from_net.message;
			end

			if( update_cmd_msg ) begin
				message_to_net.enable_bit                                              <= 1'b0;
				message_to_net.data                                                    <= {`REGISTER_SIZE*`HW_LANE{1'hf}};
				message_to_net.message                                                 <= cmd_to_dsu;
			end

			if( update_reg_value )begin
				item_data_o                                                            <= message_data[`REGISTER_SIZE - 1 : 0];
				message_data[`REGISTER_SIZE*`HW_LANE - 1 : 0]                          <= {32'h00000000,message_data[`REGISTER_SIZE*`HW_LANE - 1 : `REGISTER_SIZE]};
			end

			if( reset_word_cnt ) begin
				word_sent                                                              <= 4'b0000;
			end else if( increment_word_cnt ) begin
				word_sent                                                              <= word_sent + 4'b0001;
			end

		end
	end


	idx_to_oh #(
		.NUM_SIGNALS( $bits( tile_mask_t  ) ),
		.DIRECTION  ( "LSB0"                ),
		.INDEX_WIDTH( $clog2( `TILE_COUNT ) )
	)
	idx_to_oh (
		.one_hot( one_hot_destination_valid         ),
		.index  ( message_to_net_destinations_valid )
	);

endmodule 
