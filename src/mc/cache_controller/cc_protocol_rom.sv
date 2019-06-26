`timescale 1ns / 1ps
`include "npu_coherence_defines.sv"

/* verilator lint_off WIDTHCONCAT */
function dcache_privileges_t state_2_privileges ( coherence_state_t state );
	dcache_privileges_t result;
	unique case ( state )
		M    : begin
			result.can_read  = 1'b1;
			result.can_write = 1'b1;
		end

		UW   : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b1;
		end

		U    : begin
			result.can_read  = 1'b1;
			result.can_write = 1'b1;
		end

		S    : begin
			result.can_read  = 1'b1;
			result.can_write = 1'b0;
		end

		I    : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b0;
		end

		ISd  : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b0;
		end

		IMad : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b0;
		end

		IMa  : begin
			result.can_read  = 1'b1;
			result.can_write = 1'b0;
		end

		IUd  : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b1;
		end

		SMad : begin
			result.can_read  = 1'b1;
			result.can_write = 1'b0;
		end

		SMa  : begin
			result.can_read  = 1'b1;
			result.can_write = 1'b0;
		end

		MIa  : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b0;
		end

		SIa  : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b0;
		end

		IIa  : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b0;
		end

		default : begin
			result.can_read  = 1'b0;
			result.can_write = 1'b0;
		end


	endcase

	return result;

endfunction : state_2_privileges

module cc_protocol_rom (
		input  logic                clk,
		input  coherence_state_t    current_state,
		input  coherence_request_t  current_request,
		input  logic				request_valid,
		output protocol_rom_entry_t pr_output
	);
	
	coherence_states_enum_t current_state_enum;
	coherence_requests_enum_t current_request_enum;

	// Protocol ROM debug signal
	logic not_admitted;
	
	assign current_state_enum = coherence_states_enum_t'(current_state);
	assign current_request_enum = coherence_requests_enum_t'(current_request);
	
	always_comb begin
		not_admitted                     = 1'b0;
		pr_output.stall                  = 1'b0;
		pr_output.hit                    = 1'b0;
		pr_output.send_request           = 1'b0;
		pr_output.send_response          = 1'b0;
		pr_output.send_forward           = 1'b0;
		pr_output.request                = GETS;
		pr_output.response               = INV_ACK;
		pr_output.forward                = FWD_GETM;
		pr_output.send_data              = 1'b0;
		pr_output.is_receiver_dir        = 1'b0;
		pr_output.is_receiver_req        = 1'b0;
		pr_output.is_receiver_mc         = 1'b0;
		pr_output.incr_ack_count         = 1'b0;
		pr_output.next_state             = current_state_enum;
		pr_output.next_state_is_stable   = 1'b0;

		pr_output.allocate_mshr_entry    = 1'b0;
		pr_output.deallocate_mshr_entry  = 1'b0;
		pr_output.update_mshr_entry      = 1'b0;

		pr_output.write_data_on_cache    = 1'b0;
		pr_output.send_data_from_cache   = 1'b0;
		pr_output.send_data_from_mshr    = 1'b0;
		pr_output.send_data_from_request = 1'b0;
		pr_output.req_has_data           = 1'b0;

		pr_output.req_has_ack_count      = current_request == Data_from_Dir_ack_gtz;
		pr_output.ack_count_eqz          = current_request == Data_from_Dir_ack_eqz;



		unique case ( {current_state, current_request} )

			//--------------------------------------------------------------------------------
			// -- STATE I
			//--------------------------------------------------------------------------------

			{I, dinv},
			{I, dinv_uncoherent}          : begin				//dinv, dinv_uncoherent

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;

				pr_output.hit = 1'b1;
			end

			{I, load}                     : begin				//load

				//Send GetS to Directory
				pr_output.send_request           = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.request                = GETS;

				//Next state: ISd
				pr_output.next_state             = ISd;
				pr_output.allocate_mshr_entry    = 1'b1;
			end

			{I, store}                    : begin				//store

				//Send GetM to Directory
				pr_output.send_request           = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.request                = GETM;

				//Next state: IMad
				pr_output.next_state             = IMad;
				pr_output.allocate_mshr_entry    = 1'b1;
			end

			{I, Fwd_Flush},
			{I, flush}                    : begin				//flush, fwd_flush

				//Send Flush to Directory
				pr_output.send_request           = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.request                = DIR_FLUSH;

				//Next state: I
				pr_output.next_state             = I;
			end

			{I, load_uncoherent}          : begin				//load uncoherent

				//Forward GetM to MC
				pr_output.send_forward           = 1'b1;
				pr_output.forward                = FWD_GETM;

				//Next state: IUd
				pr_output.next_state             = IUd;
				pr_output.allocate_mshr_entry    = 1'b1;
			end

			{I, store_uncoherent}         : begin				//store uncoherent

				//Cache hit
				pr_output.hit                    = 1'b1;
				pr_output.write_data_on_cache    = 1'b1;

				//Next state: UW
				pr_output.next_state             = UW;
				pr_output.next_state_is_stable   = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE ISd
			//--------------------------------------------------------------------------------

			{ISd, load},
			{ISd, store},
			{ISd, replacement},
			{ISd, Fwd_Flush},
			{ISd, recall},
			{ISd, Inv}                    : begin				//load, store, replacement, fwd-flush, recall, inv
				pr_output.stall                  = 1'b1;
			end

			{ISd, Data_from_Dir_ack_eqz},
			{ISd, Data_from_Dir_ack_gtz}, //XXX: NB questa riga � differente dal protocollo del primer
			{ISd, Data_from_Owner}        : begin				//data from dir (ack=0), data from dir (ack>0), data from owner

				//Next state: S
				pr_output.next_state             = S;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
				pr_output.write_data_on_cache    = 1'b1;
				pr_output.req_has_data           = 1'b1;
				pr_output.ack_count_eqz          = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE IMad
			//--------------------------------------------------------------------------------
			
			{IMad, Fwd_Flush},
			{IMad, flush},
			{IMad, load},
			{IMad, store},
			{IMad, replacement},
			{IMad, recall},
			{IMad, Fwd_GetS},
			{IMad, Fwd_GetM}              : begin				//fwd-flush, flush, load, store, replacement, recall, fwd-getS, fwd-getM
				pr_output.stall                  = 1'b1;
			end

			{IMad, Data_from_Dir_ack_eqz},
			{IMad, Data_from_Owner}       : begin				//data from dir (ack=0), data from owner

				//Next state: M
				pr_output.next_state             = M;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
				pr_output.write_data_on_cache    = 1'b1;
				pr_output.req_has_data           = 1'b1;
				pr_output.ack_count_eqz          = 1'b1;
			end

			{IMad, Data_from_Dir_ack_gtz} : begin				//data from dir (ack>0)

				//Next state: IMa
				pr_output.next_state             = IMa;
				pr_output.update_mshr_entry      = 1'b1;
				pr_output.req_has_data           = 1'b1;
			end

			{IMad, Inv_Ack}               : begin				//inv-ack

				//Decrement ack count  
				pr_output.incr_ack_count         = 1'b1;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{IMad, Last_Inv_Ack}               : begin			//last-inv-ack

				//Decrement ack count  
				pr_output.incr_ack_count         = 1'b1;
				pr_output.update_mshr_entry      = 1'b1;
				pr_output.ack_count_eqz          = 1'b1;

				//Next state: IMd
				pr_output.next_state             = IMd;
			end

			//--------------------------------------------------------------------------------
			// -- STATE IMd
			//--------------------------------------------------------------------------------
			
			{IMd, Fwd_Flush},
			{IMd, flush},
			{IMd, load},
			{IMd, store},
			{IMd, replacement},
			{IMd, recall},
			{IMd, Fwd_GetS},
			{IMd, Fwd_GetM}              : begin				//fwd-flush, flush, load, store, replacement, recall, fwd-getS, fwd-getM
				pr_output.stall                  = 1'b1;
			end

			{IMd, Data_from_Dir_ack_gtz},
			{IMd, Data_from_Dir_ack_eqz},
			{IMd, Data_from_Owner}       : begin				//data from dir (ack=0), data from dir (ack>0), data from owner
				
				//Next state: M
				pr_output.next_state             = M;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
				pr_output.write_data_on_cache    = 1'b1;
				pr_output.req_has_data           = 1'b1;
				pr_output.ack_count_eqz          = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE IUd
			//--------------------------------------------------------------------------------

			{IUd, load_uncoherent},
			{IUd, store_uncoherent},
			{IUd, replacement_uncoherent},
			{IUd, flush_uncoherent}       : begin				//load-unchoherent, store-uncoherent, replacement-uncoherent, flush-uncoherent
				pr_output.stall                  = 1'b1;
			end

			{IUd, Data_from_Owner}        : begin				//data from owner

				//Next state: U
				pr_output.next_state             = U;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
				pr_output.write_data_on_cache    = 1'b1;
				pr_output.req_has_data           = 1'b1;
				pr_output.ack_count_eqz          = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE IMa
			//--------------------------------------------------------------------------------

			{IMa, Fwd_Flush},
			{IMa, flush},
			{IMa, load},
			{IMa, store},
			{IMa, replacement},
			{IMa, recall},
			{IMa, Fwd_GetS},
			{IMa, Fwd_GetM}               : begin				//fwd-flush, flush, load, store, replacement, recall, fwd-getS, fwd-getM
				pr_output.stall                  = 1'b1;
			end

			{IMa, Inv_Ack}                : begin				//inv-ack

				//Decrement ack count 
				pr_output.incr_ack_count         = 1'b1;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{IMa, Last_Inv_Ack}           : begin				//last inv-ack
				
				//Next state: M
				pr_output.next_state             = M;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
				pr_output.write_data_on_cache    = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE S
			//--------------------------------------------------------------------------------

			{S, load}                     : begin				//load

				//Cache hit
				pr_output.hit                    = 1'b1;
				pr_output.next_state_is_stable   = 1'b1;
			end

			{S, store}                    : begin				//store

				//Send getM to directory
				pr_output.send_request           = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.request                = GETM;

				//Next state: SMad
				pr_output.next_state             = SMad;
				pr_output.allocate_mshr_entry    = 1'b1;
			end

			{S, replacement}              : begin				//replacement

				//send putS to directory
				pr_output.send_request           = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.request                = PUTS;

				//Next state: SIa
				pr_output.next_state             = SIa;
				pr_output.allocate_mshr_entry    = 1'b1;
			end

			{S, dinv}                     : begin				//dinv

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
			end

			{S, recall}                   : begin				//recall

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
			end

			{S, Inv}                      : begin				//inv

				//send inv-ack to requestor
				pr_output.send_response          = 1'b1;
				pr_output.is_receiver_req        = 1'b1;
				pr_output.response               = INV_ACK;

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
			//  non alloca nessuna entry nel MSHR ma manda solo il messaggio in rete ed aggiorna i privilegi
			end

			{S, Fwd_Flush},
			{S, flush}                    : begin				//fwd-flush, flush

				//Send WB to Memory Controller
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;
				pr_output.send_data_from_cache   = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE SMad
			//--------------------------------------------------------------------------------

			{SMad, load}                  : begin				//load

				//Cache hit
				pr_output.hit                    = 1'b1;
			end
			
			{SMad, Fwd_Flush},
			{SMad, flush},
			{SMad, store},
			{SMad, replacement},
			//{SMad, recall},
			{SMad, Fwd_GetS},
			{SMad, Fwd_GetM}              : begin				//fwd-flush, flush, store, replacement, recall, fwd-getS, fwd-getM
				pr_output.stall                  = 1'b1;
			end

			{SMad, recall}                    : begin				//recall
				//Next state: IMad
				pr_output.next_state             = IMad;
				pr_output.update_mshr_entry      = 1'b1;
			end      

			{SMad, Inv}                   : begin				//inv

				//Send inv-ack to requestor
				pr_output.send_response          = 1'b1;
				pr_output.is_receiver_req        = 1'b1;
				pr_output.response               = INV_ACK;

				//Next state: IMad
				pr_output.next_state             = IMad;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{SMad, Data_from_Dir_ack_eqz},
			{SMad, Data_from_Owner}       : begin				//data from dir (ack=0), data from owner

				//Next state: M
				pr_output.next_state             = M;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
				// pr_output.write_data_on_cache    = 1'b1; non serve, gi� � in cache
			end

			{SMad, Data_from_Dir_ack_gtz} : begin				//data from dir (ack>0)

				//Next state: SMa
				pr_output.next_state             = SMa;
				pr_output.update_mshr_entry      = 1'b1;
				pr_output.req_has_data           = 1'b1;
				// pr_output.write_data_on_cache    = 1'b1; non serve, gi� � in cache
			end

			{SMad, Inv_Ack}               : begin				//inv-ack

				//Decrement ack count 
				pr_output.incr_ack_count         = 1'b1;
				pr_output.update_mshr_entry      = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE SMa
			//--------------------------------------------------------------------------------

			{SMa, load}                   : begin				//load
				//Cache hit
				pr_output.hit                    = 1'b1;
			end
			
			{SMa, Fwd_Flush},
			{SMa, flush},
			{SMa, store},
			{SMa, replacement},
			{SMa, Fwd_GetS},
			{SMa, Fwd_GetM}               : begin				//fwd-flush, flush, store, replacement, recall, fwd-getS, fwd-getM
				pr_output.stall                  = 1'b1;
			end

			{SMa, recall}            : begin
				//Next state: IMa
				pr_output.next_state             = IMa;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{SMa, Inv}                    : begin				//inv

				//send inv-ack to requestor
				pr_output.send_response          = 1'b1;
				pr_output.is_receiver_req        = 1'b1;
				pr_output.response               = INV_ACK;

				//Next state: IMa
				pr_output.next_state             = IMa;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{SMa, Inv_Ack}                : begin				//inv-ack

				//Decrement ack count 
				pr_output.incr_ack_count         = 1'b1;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{SMa, Last_Inv_Ack}           : begin				//last inv-ack

				//Next state: M
				pr_output.next_state             = M;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
				// pr_output.write_data_on_cache    = 1'b1; non serve, gi� � in cache
			end

			//--------------------------------------------------------------------------------
			// -- STATE M
			//--------------------------------------------------------------------------------

			{M, load},
			{M, store}                    : begin				//load, store

				//Cache hit
				pr_output.hit                    = 1'b1;
				pr_output.next_state_is_stable   = 1'b1;
			end

			{M, replacement},
			{M, dinv}                     : begin				//replacement, dinv

				//Send PutM to Directory
				pr_output.req_has_data           = 1'b1;
				pr_output.send_request           = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.request                = PUTM;

				//Next state: Mia
				pr_output.next_state             = MIa;
				pr_output.allocate_mshr_entry    = 1'b1;
				pr_output.send_data_from_request = 1'b1;
			end

			{M, recall}                   : begin				//recall

				//Send WB to Dir and MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.send_data_from_cache   = 1'b1;
			end

			{M, Fwd_Flush},
			{M, flush}                    : begin				//fwd-flush, flush

				//Send WB to MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;
				pr_output.send_data_from_cache   = 1'b1;
			end

			{M, Fwd_GetS}                 : begin				//fwd-getS

				//Send Data to Dir and Requestor
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.is_receiver_req        = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.send_data_from_cache   = 1'b1;
				pr_output.send_response          = 1'b1;
				pr_output.response               = DATA;

				//Next state: S
				pr_output.next_state             = S;
				pr_output.next_state_is_stable   = 1'b1;
			end

			{M, Fwd_GetM}                 : begin				//fwd-getM

				//Send Data to Requestor
				pr_output.send_response          = 1'b1;
				pr_output.is_receiver_req        = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.send_data_from_cache   = 1'b1;
				pr_output.response               = DATA;

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE U
			//--------------------------------------------------------------------------------

			{U, load_uncoherent},
			{U, store_uncoherent}         : begin				//load-uncoherent, store-uncoherent

				//Cache hit
				pr_output.hit                    = 1'b1;
				pr_output.next_state_is_stable   = 1'b1;
			end

			{U, replacement_uncoherent},
			{U, dinv_uncoherent}          : begin				//replacement-uncoherent, dinv-uncoherent

				//Send WB to MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.send_data_from_request = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = current_request == replacement_uncoherent;
				pr_output.hit                    = current_request == dinv_uncoherent;
			end

			{U, flush_uncoherent}         : begin

				//Send WB to MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;
				pr_output.send_data_from_cache   = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE UW
			//--------------------------------------------------------------------------------

			{UW, load_uncoherent}          : begin				//load-uncoherent

				//Send fwd-getM 
				//[è una load, si potrebbe fare una getS?]
				pr_output.send_forward           = 1'b1;
				pr_output.forward                = FWD_GETM;

				//Next state: IUd
				pr_output.next_state             = IUd;
				pr_output.allocate_mshr_entry    = 1'b1;
			end

			{UW, store_uncoherent}         : begin				//store-uncoherent

				//Cache hit
				pr_output.hit                    = 1'b1;
				pr_output.next_state_is_stable   = 1'b1;
			end

			{UW, replacement_uncoherent},
			{UW, dinv_uncoherent}          : begin				//replacement-uncoherent, dinv-uncoherent

				//Send WB to MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.send_data_from_request = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = current_request == replacement_uncoherent;
				pr_output.hit                    = current_request == dinv_uncoherent;
			end

			{UW, flush_uncoherent}         : begin				//flush-uncoherent

				//Send WB to MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;
				pr_output.send_data_from_cache   = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE MIa
			//--------------------------------------------------------------------------------

			{MIa, load},
			{MIa, store} 				  : begin				//load, store
				pr_output.stall                  = 1'b1;
			end

			{MIa, replacement}            : begin				//replacement
			        pr_output.req_has_data           = 1'b1;
				pr_output.stall                  = 1'b1;
			end

			{MIa, recall}                 : begin				//recall

				//Send WB to Dir and MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;

				//Next state: IIa
				pr_output.next_state             = IIa;
				pr_output.update_mshr_entry      = 1'b1;
				pr_output.send_data_from_mshr    = 1'b1;
			end

			{MIa, Fwd_Flush},
			{MIa, flush}                  : begin				//fwd-flush, flush

				//Send WB to MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;
				pr_output.send_data_from_mshr    = 1'b1;
			end

			{MIa, Fwd_GetS}               : begin				//fwd-getS

				//Send Data to Dir and Requestor
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.is_receiver_req        = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.send_data_from_mshr    = 1'b1;
				//[in (M, fwd-getM) è stato messo anche .response = DATA qui non ci va?]
				//[sto in MIa e mi arriva una getS, non dovrei spostarmi in SIa ?]
				pr_output.response				 = DATA;
				pr_output.next_state			 = SIa;
				pr_output.next_state_is_stable	 = 1'b0;
			end

			{MIa, Fwd_GetM}               : begin				//fwd-getM
				//Send Data to Requestor 
				pr_output.is_receiver_req        = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.send_data_from_mshr    = 1'b1;

				//Next state: IIa
				pr_output.next_state             = IIa;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{MIa, Put_Ack}                : begin				//put-ack

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE SIa
			//--------------------------------------------------------------------------------

			{SIa, load},
			{SIa, store},
			{SIa, replacement}            : begin				//load, store, replacement
				pr_output.stall                  = 1'b1;
			end

			{SIa, recall}                 : begin               //recall
				// No Actions!
			end 

			{SIa, Put_Ack}                : begin				//put-ack

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
			end

			{SIa, Inv}                    : begin				//inv

				//Send inv-ack to requestor
				pr_output.send_response          = 1'b1;
				pr_output.response               = INV_ACK;
				pr_output.is_receiver_req        = 1'b1;

				//Next state: IIa
				pr_output.next_state             = IIa;
				pr_output.update_mshr_entry      = 1'b1;
			end

			{SIa, Fwd_Flush}              : begin				//fwd-flush

				//Send WB to MC
				pr_output.send_response          = 1'b1;
				pr_output.send_data              = 1'b1;
				pr_output.is_receiver_mc         = 1'b1;
				pr_output.response               = WB;
				pr_output.send_data_from_cache   = 1'b1;
			end

			//--------------------------------------------------------------------------------
			// -- STATE IIa
			//--------------------------------------------------------------------------------

			{IIa, load},
			{IIa, store},
			{IIa, recall},
			{IIa, replacement}            : begin				//load, store, recall, replacement
				pr_output.stall                  = 1'b1;
			end

			{IIa, Put_Ack}                : begin				//put-ack

				//Next state: I
				pr_output.next_state             = I;
				pr_output.next_state_is_stable   = 1'b1;
				pr_output.deallocate_mshr_entry  = 1'b1;
			end

			{IIa, Fwd_Flush}              : begin				//fwd-flush

				//Send Dir-Flush to Directory 
				pr_output.send_request           = 1'b1;
				pr_output.is_receiver_dir        = 1'b1;
				pr_output.request                = DIR_FLUSH;

			end

			default : begin
				not_admitted                     = 1'b1;
				pr_output.stall                  = 0;
				pr_output.next_state             = coherence_states_enum_t'(0);
				pr_output.next_state_is_stable   = 0;
				pr_output.request                = 0;
				pr_output.response               = 0;
				pr_output.send_request           = 0;
				pr_output.send_response          = 0;
				pr_output.is_receiver_dir        = 0;
				pr_output.is_receiver_req        = 0;
				pr_output.send_data              = 0;
				pr_output.incr_ack_count         = 0;
				pr_output.update_privileges      = 0;
				pr_output.allocate_mshr_entry    = 0;
				pr_output.deallocate_mshr_entry  = 0;
				pr_output.update_mshr_entry      = 0;
				pr_output.write_data_on_cache    = 0;
				pr_output.send_data_from_cache   = 0;
				pr_output.send_data_from_mshr    = 0;
				pr_output.send_data_from_request = 0;
				pr_output.req_has_data           = 0;
				pr_output.req_has_ack_count      = 0;
				`ifdef COHERENCE_INJECTION
					pr_output.hit = 1'b1;
					pr_output.next_state_is_stable   = 1'b1;
				`endif
			end

		endcase

		pr_output.next_privileges        = state_2_privileges( pr_output.next_state );
		pr_output.update_privileges      = state_2_privileges( current_state ) != pr_output.next_privileges;
	end

`ifdef SIMULATION
	always_ff @ (posedge clk) begin : PROM_DEBUG_ASSERT
		if ( request_valid & not_admitted ) begin
			$error("[Time %t] [CC - ROM]: Invalid state detected! Current State: %s,  Current Request: %s", 
			$time(), current_state_enum.name(), current_request_enum.name());
		end
	end
`endif

endmodule
/* verilator lint_on WIDTHCONCAT */
