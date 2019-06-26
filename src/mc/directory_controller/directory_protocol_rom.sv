`timescale 1ns / 1ps
`include "npu_coherence_defines.sv"

/* verilator lint_off WIDTHCONCAT */
module directory_protocol_rom (
		input  logic                                         clk,
		input  logic [`DIRECTORY_STATE_WIDTH - 1 : 0]        input_state,
		input        [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] input_request,
		input  logic                                         request_valid,
		input  logic                                         input_is_from_owner,
		input  logic                                         input_there_is_one_sharers,
		output directory_protocol_rom_entry_t                dpr_output
	);

	directory_state_t   current_state_enum;
	directory_message_t current_request_enum;
	
	// Directory protocol ROM debug signal
	logic not_admitted;

	assign current_state_enum = directory_state_t'(input_state);
	assign current_request_enum = directory_message_t'(input_request);

	always_comb begin

		not_admitted                              = 1'b0;
		dpr_output.current_state_is_stable        = 1'b1;
		dpr_output.next_state_is_stable           = 1'b1;
		dpr_output.next_state                     = directory_state_t'(input_state);

		dpr_output.stall                          = 0;

		dpr_output.message_response_send          = 0;
		dpr_output.message_response_type          = 0;
		dpr_output.message_response_has_data      = 0;
		dpr_output.message_response_to_requestor  = 0;
		dpr_output.message_response_to_owner      = 0;
		dpr_output.message_response_to_sharers    = 0;
		dpr_output.message_response_to_memory     = 0;
		dpr_output.message_response_add_wb        = 0;

		dpr_output.message_forwarded_send         = 0;
		dpr_output.message_forwarded_type         = 0;
		dpr_output.message_forwarded_to_requestor = 0;
		dpr_output.message_forwarded_to_owner     = 0;
		dpr_output.message_forwarded_to_sharers   = 0;
		dpr_output.message_forwarded_to_memory    = 0;


		dpr_output.sharers_add_requestor          = 0;
		dpr_output.sharers_add_owner              = 0;
		dpr_output.sharers_remove_requestor       = 0;
		dpr_output.sharers_clear                  = 0;
		dpr_output.owner_set_requestor            = 0;
		dpr_output.owner_clear                    = 0;
		dpr_output.store_data                     = 0;

		dpr_output.invalidate_cache_way           = 0;

		casex ( {input_state, input_request, input_is_from_owner, input_there_is_one_sharers } )

			//--------------------------------------------------------------------------------
			// -- STATE I
			//--------------------------------------------------------------------------------

			{STATE_I, REPLACEMENT, 1'b?, 1'b?} : begin // Replacement

				// Send WB To Memory Controller
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_WB;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_memory     = 1'b1;

				// Next State N
				dpr_output.next_state                     = STATE_MN_A;
				dpr_output.next_state_is_stable           = 1'b0;
				//dpr_output.invalidate_cache_way           = 1; 

			end

			{STATE_I, MESSAGE_DIR_FLUSH, 1'b?, 1'b?} : begin // Flush from directory

				// Send WB To Memory Controller
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_WB;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_memory     = 1'b1;

				// Next State I
				dpr_output.next_state                     = STATE_I;
			end

			{STATE_I, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Send Data To Requestor
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_DATA;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_requestor  = 1'b1;

				// Add Requestor To Sharers
				dpr_output.sharers_add_requestor          = 1'b1;

				// Next State S
				dpr_output.next_state                     = STATE_S;

			end

			{STATE_I, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Send Data To Requestor
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_DATA;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_requestor  = 1'b1;

				// Set Owner To Requestor
				dpr_output.owner_set_requestor            = 1'b1;

				// Next State M
				dpr_output.next_state                     = STATE_M;

			end

			{STATE_I, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end

			{STATE_I, MESSAGE_PUTS, 1'b?, 1'b1} : begin // PutS-Last

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end


			{STATE_I, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_I, MESSAGE_PUTM, 1'b0, 1'b?} : begin // PutM+data from NonOwner

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end

			{STATE_I, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_I, MESSAGE_WB, 1'b?, 1'b?} : begin // WB
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_I, MESSAGE_MC_ACK, 1'b?, 1'b?} : begin // MC_ACK
				
				//No Actions!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
			end

			//--------------------------------------------------------------------------------
			// -- STATE S
			//--------------------------------------------------------------------------------

			{STATE_S, REPLACEMENT, 1'b?, 1'b?} : begin // Replacement

				// Send BACKINV To Sharers
				dpr_output.message_forwarded_send         = 1'b1;
				dpr_output.message_forwarded_type         = MESSAGE_BACKINV;
				dpr_output.message_forwarded_to_sharers   = 1'b1;

				// Send WB To Memory Controller
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_WB;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_memory     = 1'b1;

				// Next State N
				dpr_output.next_state                     = STATE_SN_A;
				dpr_output.next_state_is_stable           = 1'b0;
				//dpr_output.invalidate_cache_way           = 1; 

			end

			{STATE_S, MESSAGE_DIR_FLUSH, 1'b?, 1'b?} : begin // Flush from directory

				// Send WB To Memory Controller
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_WB;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_memory     = 1'b1;

				// Next State I
				dpr_output.next_state                     = STATE_I;
			end

			{STATE_S, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Send Data To Requestor
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_DATA;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_requestor  = 1'b1;

				// Add Requestor To Sharers
				dpr_output.sharers_add_requestor          = 1'b1;

			end

			{STATE_S, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Send Data To Requestor
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_DATA;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_requestor  = 1'b1;

				// Send INV To Sharers
				dpr_output.message_forwarded_send         = 1;
				dpr_output.message_forwarded_type         = MESSAGE_INV;
				dpr_output.message_forwarded_to_sharers   = 1;

				// Clear Sharers
				dpr_output.sharers_clear                  = 1'b1;

				// Set Owner To Requestor
				dpr_output.owner_set_requestor            = 1'b1;

				// Next State M
				dpr_output.next_state                     = STATE_M;

			end

			{STATE_S, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast

				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end

			{STATE_S, MESSAGE_PUTS, 1'b?, 1'b1} : begin // PutS-Last

				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				// Next State I
				dpr_output.next_state                     = STATE_I;

			end


			{STATE_S, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_S, MESSAGE_PUTM, 1'b0, 1'b?} : begin // PutM+data from NonOwner

				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end

			{STATE_S, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_S, MESSAGE_WB, 1'b?, 1'b?} : begin // WB
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_S, MESSAGE_MC_ACK, 1'b?, 1'b?} : begin // MC_ACK
				
				//No Actions!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
			end

			//--------------------------------------------------------------------------------
			// -- STATE M
			//--------------------------------------------------------------------------------

			{STATE_M, REPLACEMENT, 1'b?, 1'b?} : begin // Replacement

				// Send BACKINV To Owner
				dpr_output.message_forwarded_send         = 1'b1;
				dpr_output.message_forwarded_type         = MESSAGE_BACKINV;
				dpr_output.message_forwarded_to_owner     = 1'b1;

				// Next State MN_A
				dpr_output.next_state                     = STATE_MN_A;
				dpr_output.next_state_is_stable           = 1'b0;
				// dpr_output.invalidate_cache_way           = 1; 

			end

			{STATE_M, MESSAGE_DIR_FLUSH, 1'b?, 1'b?} : begin // Flush from directory

				// Send WB To Memory Controller
				dpr_output.message_forwarded_send         = 1'b1;
				dpr_output.message_forwarded_type         = MESSAGE_FWD_FLUSH;
				dpr_output.message_forwarded_to_owner     = 1'b1;

				// Next State M
				dpr_output.next_state                     = STATE_M;
			end

			{STATE_M, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Send Fwd-GetS To Owner
				dpr_output.message_forwarded_send         = 1;
				dpr_output.message_forwarded_type         = MESSAGE_FWD_GETS;
				dpr_output.message_forwarded_to_owner     = 1;

				// Add Requestor To Sharers
				dpr_output.sharers_add_requestor          = 1'b1;

				// Add Owner To Sharers
				dpr_output.sharers_add_owner              = 1'b1;

				// Clear Owner
				dpr_output.owner_clear                    = 1'b1;

				// Next State S_D
				dpr_output.next_state                     = STATE_S_D;
				dpr_output.next_state_is_stable           = 1'b0;
				
				dpr_output.invalidate_cache_way           = 1; //

			end

			{STATE_M, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Send Fwd-GetM To Owner
				dpr_output.message_forwarded_send         = 1;
				dpr_output.message_forwarded_type         = MESSAGE_FWD_GETM;
				dpr_output.message_forwarded_to_owner     = 1;

				// Set Owner To Requestor
				dpr_output.owner_set_requestor            = 1'b1;

			end

			{STATE_M, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end

			{STATE_M, MESSAGE_PUTS, 1'b?, 1'b1} : begin // PutS-Last

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end


			{STATE_M, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner

				// Copy Data To Memory
				dpr_output.store_data                     = 1'b1;

				// Clear Owner
				dpr_output.owner_clear                    = 1'b1;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				// Next State I
				dpr_output.next_state                     = STATE_I;

			end

			{STATE_M, MESSAGE_PUTM,1'b0, 1'b?} : begin // PutM+data from NonOwner

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end

			{STATE_M, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data
				
				// NOT ADMITED! 
				not_admitted                              = 1'b1;
			end

			{STATE_M, MESSAGE_WB, 1'b?, 1'b?} : begin // WB
				
				// NOT ADMITED! 
				not_admitted                              = 1'b1;
			end

			{STATE_M, MESSAGE_MC_ACK, 1'b?, 1'b?} : begin // WB
				
				//No Actions!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
			end

			//--------------------------------------------------------------------------------
			// -- STATE S_D
			//--------------------------------------------------------------------------------

			{STATE_S_D, REPLACEMENT, 1'b?, 1'b?} : begin // Replacement

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_S_D, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_S_D, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_S_D, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast

				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_S_D, MESSAGE_PUTS, 1'b?, 1'b1} : begin // PutS-Last

				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end


			{STATE_S_D, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;

			end

			{STATE_S_D, MESSAGE_PUTM, 1'b0, 1'b?} : begin // PutM+data from NonOwner

				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				dpr_output.current_state_is_stable        = 1'b0;

			end

			{STATE_S_D, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data

				// Copy Data To Memory
				dpr_output.store_data                     = 1'b1;
				dpr_output.next_state                     = STATE_S; 
				
				//dpr_output.next_state_is_stable           = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;

			end

			{STATE_S_D, MESSAGE_WB, 1'b?, 1'b?} : begin // WB
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			//--------------------------------------------------------------------------------
			// -- STATE N
			//--------------------------------------------------------------------------------

			{STATE_N, REPLACEMENT, 1'b?, 1'b?} : begin // Replacement
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_N, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Add Requestor To Sharers
				dpr_output.sharers_add_requestor          = 1'b1;

				// Send Fwd-GetS To Memory
				dpr_output.message_forwarded_send         = 1'b1;
				dpr_output.message_forwarded_type         = MESSAGE_FWD_GETS;
				dpr_output.message_forwarded_to_memory    = 1'b1;

				//Next State NS_D
				dpr_output.next_state                     = STATE_NS_D;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_N, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Set Owner To Requestor
				dpr_output.owner_set_requestor            = 1'b1;

				// Send Fwd-GetM To Memory
				dpr_output.message_forwarded_send         = 1'b1;
				dpr_output.message_forwarded_type         = MESSAGE_FWD_GETM;
				dpr_output.message_forwarded_to_memory    = 1'b1;

				//Next State M
				dpr_output.next_state                     = STATE_M;

			end

			{STATE_N, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast
				
				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				// NOT ADMITTED!
				//not_admitted                              = 1'b1;
			end

			{STATE_N, MESSAGE_PUTS, 1'b?, 1'b1} : begin // PutS-Last
				
				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				// NOT ADMITTED!
				//not_admitted                              = 1'b1;
			end

			{STATE_N, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner
				
				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				// NOT ADMITTED!
				//not_admitted                              = 1'b1;
			end

			{STATE_N, MESSAGE_PUTM, 1'b0, 1'b?} : begin // PutM+data from NonOwner
				
				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				// NOT ADMITTED!
				//not_admitted                              = 1'b1;
			end

			{STATE_N, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_N, MESSAGE_WB, 1'b?, 1'b?} : begin // WB
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end

			{STATE_N, MESSAGE_MC_ACK, 1'b?, 1'b?} : begin // MC_ACK
				
				// NOT ADMITTED!
				not_admitted                              = 1'b1;
			end
			
			{STATE_N, MESSAGE_DIR_FLUSH, 1'b?, 1'b?} : begin // MC_ACK
				
				//No Actions!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
			end

			//--------------------------------------------------------------------------------
			// -- STATE MN_A
			//--------------------------------------------------------------------------------

			{STATE_MN_A, REPLACEMENT, 1'b?, 1'b?}: begin // Replacement

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_MN_A, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_MN_A, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_MN_A, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_MN_A, MESSAGE_PUTS,  1'b?, 1'b1} : begin // PutS-Last
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_MN_A, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner

				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

				//Generate a WB message for the main memory
				dpr_output.message_response_add_wb        = 1;

			end

			{STATE_MN_A, MESSAGE_PUTM, 1'b0, 1'b?} : begin // PutM+data from NonOwner
				
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;
				
			end

			{STATE_MN_A, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				
			end

			{STATE_MN_A, MESSAGE_WB, 1'b?, 1'b?} : begin // WB

				//No Actions!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				
			end

			{STATE_MN_A, MESSAGE_MC_ACK, 1'b?, 1'b?} : begin // mc_ack

				// Next State N
				dpr_output.next_state                     = STATE_N;
				dpr_output.current_state_is_stable        = 1'b0;
				
				dpr_output.invalidate_cache_way           = 1;

			end

			//--------------------------------------------------------------------------------
			// -- STATE SN_A
			//--------------------------------------------------------------------------------

			{STATE_SN_A, REPLACEMENT, 1'b?, 1'b?}: begin // Replacement

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_SN_A, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_SN_A, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_SN_A, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast
				
				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;

			end

			{STATE_SN_A, MESSAGE_PUTS,  1'b?, 1'b1} : begin // PutS-Last
				
				// Remove Requestor From Sharers
				dpr_output.sharers_remove_requestor       = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

				// Send PutAck To Requestor
				dpr_output.message_response_send          = 1;
				dpr_output.message_response_type          = MESSAGE_PUTACK;
				dpr_output.message_response_to_requestor  = 1;
				
			end

			{STATE_SN_A, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner

				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;

			end

			{STATE_SN_A, MESSAGE_PUTM, 1'b0, 1'b?} : begin // PutM+data from NonOwner
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_SN_A, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_SN_A, MESSAGE_WB, 1'b?, 1'b?} : begin // WB

				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_SN_A, MESSAGE_MC_ACK, 1'b?, 1'b?} : begin // mc_ack

				// Next State N
				dpr_output.next_state                     = STATE_N;
				dpr_output.current_state_is_stable        = 1'b0;
				
				dpr_output.invalidate_cache_way           = 1;

			end

			//--------------------------------------------------------------------------------
			// -- STATE NS_D
			//--------------------------------------------------------------------------------

			{STATE_NS_D, REPLACEMENT, 1'b?, 1'b?} : begin // Replacement

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_NS_D, MESSAGE_GETS, 1'b?, 1'b?} : begin // Gets

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_NS_D, MESSAGE_GETM, 1'b?, 1'b?} : begin // GetM

				// Stall
				dpr_output.stall                          = 1'b1;
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;

			end

			{STATE_NS_D, MESSAGE_PUTS, 1'b?, 1'b0} : begin // PutS-NotLast
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_NS_D, MESSAGE_PUTS, 1'b?, 1'b1} : begin // PutS-Last
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_NS_D, MESSAGE_PUTM, 1'b1, 1'b?} : begin // PutM+data from Owner
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_NS_D, MESSAGE_PUTM, 1'b0, 1'b?} : begin // PutM+data from NonOwner
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			{STATE_NS_D, MESSAGE_DATA, 1'b?, 1'b?} : begin // Data
				// Copy data to memory
				dpr_output.store_data                     = 1'b1;

				// Next State S
				dpr_output.next_state                     = STATE_S;
				dpr_output.current_state_is_stable        = 1'b0;

			end

			{STATE_NS_D, MESSAGE_WB, 1'b?, 1'b?} : begin // WB
				
				// NOT ADMITTED!
				dpr_output.current_state_is_stable        = 1'b0;
				dpr_output.next_state_is_stable           = 1'b0;
				not_admitted                              = 1'b1;
				
			end

			//--------------------------------------------------------------------------------
			// -- Others
			//--------------------------------------------------------------------------------

			{'h?, MESSAGE_WB_GEN, 1'b?, 1'b?} : begin // Flush from directory

				// Send WB To Memory Controller
				dpr_output.message_response_send          = 1'b1;
				dpr_output.message_response_type          = MESSAGE_WB;
				dpr_output.message_response_has_data      = 1'b1;
				dpr_output.message_response_to_memory     = 1'b1;
			end
			
			default : begin
				not_admitted                              = 1'b1;
			end

		endcase

	end

`ifdef SIMULATION
	always_ff @ ( posedge clk ) begin
		if( request_valid & not_admitted & (current_request_enum != MESSAGE_MC_ACK & current_request_enum != MESSAGE_WB) ) begin
			$error("[Time %t] [DC - ROM]: Invalid state detected! Current State: %s,  Current Request: %s", 
				$time(), current_state_enum.name(), current_request_enum.name());
		end
	end 
`endif

endmodule
/* verilator lint_on WIDTHCONCAT */
