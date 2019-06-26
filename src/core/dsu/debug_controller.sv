`include "npu_defines.sv"
`include "npu_user_defines.sv"

module debug_controller (
		input                                               clk,
		input                                               reset,
		input                                               resume,
		input                                               ext_freeze,

		input                                               dsu_enable,
		input  logic                                        dsu_single_step,
		input  address_t             [7 : 0]                dsu_breakpoint,
		input  logic                 [7 : 0]                dsu_breakpoint_enable,
		input  logic                                        dsu_thread_selection,
		input  thread_id_t                                  dsu_thread_id,

		//From Instruction Scheduler
		input  logic                                        is_instruction_valid,
		input  instruction_decoded_t                        is_instruction,
		input  thread_id_t                                  is_thread_id,
		input  logic                 [`THREAD_NUMB - 1 : 0] scoreboard_empty,

		//From Load Store
		input  logic                 [`THREAD_NUMB - 1 : 0] no_load_store_pending,

		//From Rollback
		input  thread_mask_t                                rollback_valid,


		output address_t             [`THREAD_NUMB - 1 : 0] dsu_bp_instruction,
		output thread_id_t                                  dsu_bp_thread_id,
		output logic                 [`THREAD_NUMB - 1 : 0] dsu_stop_issue,
		output logic                                        dsu_hit_breakpoint,
		output logic                                        freeze
	);

	typedef enum {
		IDLE_MODE,
		RUN_NORMAL_MODE,
		RUN_DEBUG_MODE,
		HALT_MODE,
		WAIT_INSTRUCTION_END,
		WAIT_LOAD_STORE,
		STOP_MODE
	} core_state_t;

	core_state_t                                 state, next_state;
	logic                                        new_bp_instruction;
	logic                                        dsu_breakpoint_detected;
	logic                                        reset_hit_bp;

	instruction_decoded_t [`THREAD_NUMB - 1 : 0] instruction;

	//assign dsu_hit_breakpoint = new_bp_instruction;

	bp_wp_handler u_bp_wp_handler (
		.dsu_breakpoint          ( dsu_breakpoint          ) ,
		.dsu_breakpoint_detected ( dsu_breakpoint_detected ) ,
		.dsu_breakpoint_enable   ( dsu_breakpoint_enable   ) ,
		.dsu_single_step         ( dsu_single_step         ) ,
		.is_instruction          ( is_instruction          ) ,
		//From Instruction Scheduler
		.is_instruction_valid    ( is_instruction_valid    )
	) ;

	//The following FSM governs the state of the core and single step execution
	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			state              <= IDLE_MODE;
			dsu_hit_breakpoint <= 1'b0;
		end else begin
			state              <= next_state;
			if ( new_bp_instruction ) begin
				dsu_hit_breakpoint <= 1'b1;
			end else if( reset_hit_bp ) begin
				dsu_hit_breakpoint <= 1'b0;
			end
		end
	end


	always_ff @ ( posedge clk ) begin
		if ( new_bp_instruction ) begin
			dsu_bp_instruction[is_thread_id] <= is_instruction.pc;
			instruction[is_thread_id]        <= is_instruction;
			dsu_bp_thread_id                 <= is_thread_id;
		end
	end

	always_comb begin
		next_state         <= state;
		freeze             <= 1'b0;
		new_bp_instruction <= 1'b0;
		reset_hit_bp       <= 1'b0;
		dsu_stop_issue     <= {`THREAD_NUMB{1'b0}};
		unique case ( state )

			IDLE_MODE           : begin
				next_state     <= RUN_NORMAL_MODE;
			end

			RUN_NORMAL_MODE     : begin
				if ( dsu_enable )
					next_state     <= RUN_DEBUG_MODE;
			end


			RUN_DEBUG_MODE      : begin
				if( ~dsu_enable )
					/* This check ensure that the core 0 does not enter debug
					 * mode at the system start. Indeed at the system initialization
					 * the core_id from host is 0 regardless of whether the debugging
					 * core is 0 or not.
					 * */
					next_state     <= RUN_NORMAL_MODE;
				else begin
					if( dsu_thread_selection ) begin
						if( dsu_breakpoint_detected && is_thread_id==dsu_thread_id ) begin
							next_state         <= HALT_MODE;
							dsu_stop_issue     <= {`THREAD_NUMB{1'b1}};
							new_bp_instruction <= 1'b1;
						end
					end else begin
						if ( dsu_breakpoint_detected || ext_freeze ) begin
							next_state         <= HALT_MODE;
							dsu_stop_issue     <= {`THREAD_NUMB{1'b1}};
							new_bp_instruction <= 1'b1;
						end
					end
				end
			end

			HALT_MODE           : begin
				if( rollback_valid[dsu_bp_thread_id] ) begin
					next_state     <= RUN_DEBUG_MODE;
				end else begin
					dsu_stop_issue <= {`THREAD_NUMB{1'b1}};
					next_state     <= WAIT_INSTRUCTION_END;
				end
			end

			WAIT_INSTRUCTION_END: begin
				dsu_stop_issue <= {`THREAD_NUMB{1'b1}};
				if( instruction[dsu_bp_thread_id].pipe_sel == PIPE_MEM )
					next_state     <= WAIT_LOAD_STORE;
				else begin
					if( ~|scoreboard_empty )
						next_state <= STOP_MODE;
				end
			end

			WAIT_LOAD_STORE     : begin
				dsu_stop_issue <= {`THREAD_NUMB{1'b1}};
				if ( ~|scoreboard_empty && &no_load_store_pending )
					next_state     <= STOP_MODE;
			end

			STOP_MODE           : begin
				freeze         <= 1'b1;
				dsu_stop_issue <= {`THREAD_NUMB{1'b1}};
				if ( resume ) begin
					reset_hit_bp   <= 1'b1;
					next_state     <= RUN_DEBUG_MODE;
				end
			end
		endcase
	end

endmodule
