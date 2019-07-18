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

/*
 * Input:
 *      is_store:           Alto in caso di scrittura e basso in caso di lettura.
 *
 *      addresses:          Vettore di indirizzi. L'i-esimo indirizzo indica la locazioni di memoria a cui l'i-esima lane intende accedere.
 *
 *      write_data:         Vettore di word. La word i-esima rappresenta il dato che l'i-esima lane intende scrivere all'indirizzo addresses[i].
 *                          Tale ingresso ha senso solo per le operazioni di scrittura.
 *
 *      byte_mask:          Vettore di maschere. Il bit j-esimo dell'i-esima maschera è alto se la lane i-esima intende scrivere il byte j-esimo della word posta in write_data[i].
 *                          Tale ingresso ha senso solo per le operazioni di scrittura.
 *
 *      mask:               Il bit i-esimo è alto se la i'esima lane intende accedere all'indirizzo addresses[i].
 *
 *      piggyback_data:     Informazioni da far propagare lungo la pipeline insieme alla richiesta d'accesso.
 *
 * Output:
 *      sm_ready:           Viene asserito quando è possibile somministrare richieste alla scratchpad memory.
 *                          Quando è basso i segnali d'ingresso vengono ignorati.
 *
 *      sm_valid:           Viene asserito quando i segnali sm_read_data, sm_read_data, sm_byte_mask e sm_piggyback_data possono essere letti.
 *
 *      sm_read_data:       Vettore di word. L'i-esima word rappresenta il dato chiesto da un'operazione di lettura da parte della lane i-esima.
 *
 *      sm_byte_mask:       byte_mask propagato isieme alla richiesta
 *
 *      sm_piggyback_data:  piggyback_data propagato insieme alla richiesta
 *
 */

module scratchpad_memory (
		input  logic                                            clock,
		input  logic                                            resetn,

		input  logic                                            start,
		input  logic                                            is_store,
		input  sm_address_t   [`SM_PROCESSING_ELEMENTS - 1 : 0] addresses,
		input  sm_data_t      [`SM_PROCESSING_ELEMENTS - 1 : 0] write_data,
		input  sm_byte_mask_t [`SM_PROCESSING_ELEMENTS - 1 : 0] byte_mask,
		input  logic          [`SM_PROCESSING_ELEMENTS - 1 : 0] mask,
		input  logic          [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  piggyback_data,

		output logic                                            sm_ready,
		output logic                                            sm_valid,
		output sm_data_t      [`SM_PROCESSING_ELEMENTS - 1 : 0] sm_read_data,
		output sm_byte_mask_t [`SM_PROCESSING_ELEMENTS - 1 : 0] sm_byte_mask,
		output logic          [`SM_PROCESSING_ELEMENTS - 1 : 0] sm_mask,
		output logic          [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  sm_piggyback_data
	);

	//From stage1
	logic                                                sm1_is_store;
	sm_bank_address_t  [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_bank_indexes;
	sm_entry_address_t [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_bank_offsets;
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_satisfied_mask;
	sm_data_t          [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_write_data;
	sm_byte_mask_t     [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_byte_mask;
	logic                                                sm1_is_last_request;
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] sm1_mask;
	logic              [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  sm1_piggyback_data;

	//From stage2
	logic                                                sm2_is_last_request;
	sm_byte_mask_t     [`SM_PROCESSING_ELEMENTS - 1 : 0] sm2_byte_mask;
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] sm2_mask;
	sm_bank_address_t  [`SM_PROCESSING_ELEMENTS - 1 : 0] sm2_bank_indexes;
	sm_data_t          [`SM_MEMORY_BANKS - 1 : 0]        sm2_read_data;
	logic              [`SM_PROCESSING_ELEMENTS - 1 : 0] sm2_satisfied_mask;
	logic              [`SM_PIGGYBACK_DATA_LEN - 1 : 0]  sm2_piggyback_data;


	//---------------------------------------------------------------------------------------------------------------------------
	// -- Stadio 1
	//
	//      Il primo stadio ha il compito di effettuare la serializzazione delle richieste di accesso ai banchi di memoria.
	//      Il processo di serializzazione parte quando il segnale
	//      sm1_mask diventa diverso da 0 mentre sm1_ready è alto.
	//      Tale stadio presenta dei registri in ingresso abilitati mentre sm1_ready è alto. Quindi il cambiamento degli ingressi
	//      nei periodi in cui sm_ready è basso non ha alcun effetto.
	//
	//---------------------------------------------------------------------------------------------------------------------------


	scratchpad_memory_stage1 scratchpad_memory_stage1_inst (
		.clock              ( clock                                   ),
		.resetn             ( resetn                                  ),
		.is_store           ( is_store                                ),
		.addresses          ( addresses                               ),
		.write_data         ( write_data                              ),
		.byte_mask          ( byte_mask                               ),
		.pending_mask       ( mask & {`SM_PROCESSING_ELEMENTS{start}} ),
		.piggyback_data     ( piggyback_data                          ),
		.sm1_is_store       ( sm1_is_store                            ),
		.sm1_bank_indexes   ( sm1_bank_indexes                        ),
		.sm1_bank_offsets   ( sm1_bank_offsets                        ),
		.sm1_satisfied_mask ( sm1_satisfied_mask                      ),
		.sm1_write_data     ( sm1_write_data                          ),
		.sm1_byte_mask      ( sm1_byte_mask                           ),
		.sm1_is_last_request( sm1_is_last_request                     ),
		.sm1_mask           ( sm1_mask                                ),
		.sm1_ready          ( sm_ready                                ),
		.sm1_piggyback_data ( sm1_piggyback_data                      )
	);

	//---------------------------------------------------------------------------------------------------------------------------
	// -- Stadio 2
	//
	//      Il secondo stadio è quello che ospita i banchi di SRAM. Tale presenta l'interconnessione di ingresso, la quale redirige
	//      le richieste provenienti delle lane all'opportuno banco di memoria in funzione dell'indirizzo.
	//
	//---------------------------------------------------------------------------------------------------------------------------

	scratchpad_memory_stage2 scratchpad_memory_stage2_isnt(
		.clock              ( clock               ),
		.resetn             ( resetn              ),
		.sm1_is_store       ( sm1_is_store        ),
		.sm1_is_last_request( sm1_is_last_request ),
		.sm1_bank_indexes   ( sm1_bank_indexes    ),
		.sm1_bank_offsets   ( sm1_bank_offsets    ),
		.sm1_satisfied_mask ( sm1_satisfied_mask  ),
		.sm1_write_data     ( sm1_write_data      ),
		.sm1_byte_mask      ( sm1_byte_mask       ),
		.sm1_mask           ( sm1_mask            ),
		.sm1_piggyback_data ( sm1_piggyback_data  ),
		.sm2_is_last_request( sm2_is_last_request ),
		.sm2_bank_indexes   ( sm2_bank_indexes    ),
		.sm2_read_data      ( sm2_read_data       ),
		.sm2_satisfied_mask ( sm2_satisfied_mask  ),
		.sm2_byte_mask      ( sm2_byte_mask       ),
		.sm2_mask           ( sm2_mask            ),
		.sm2_piggyback_data ( sm2_piggyback_data  )
	);

	//---------------------------------------------------------------------------------------------------------------------------
	// -- Stadio 3
	//
	//      Il terzo stadio presenta l'interconnesssione d'uscita la quale ha il compito di redirigere i dati provenienti dai
	//      banchi di memoria verso la lane di destinazione. Inoltre possiede dei registri d'uscita i quali collezionano tutte le
	//      risposte.
	//      Il segnale sm3_is_last_request viene asserito quando tutte le letture serializzate provenienti da una stessa richiesta
	//      sono state collezionate e quindi sono presenti in uscita.
	//
	//
	//---------------------------------------------------------------------------------------------------------------------------

	scratchpad_memory_stage3 scratchpad_memory_stage3_inst (
		.clock              ( clock               ),
		.resetn             ( resetn              ),
		.sm2_is_last_request( sm2_is_last_request ),
		.sm2_bank_indexes   ( sm2_bank_indexes    ),
		.sm2_read_data      ( sm2_read_data       ),
		.sm2_satisfied_mask ( sm2_satisfied_mask  ),
		.sm2_byte_mask      ( sm2_byte_mask       ),
		.sm2_mask           ( sm2_mask            ),
		.sm2_piggyback_data ( sm2_piggyback_data  ),
		.sm3_is_last_request( sm_valid            ),
		.sm3_read_data      ( sm_read_data        ),
		.sm3_byte_mask      ( sm_byte_mask        ),
		.sm3_mask           ( sm_mask             ),
		.sm3_piggyback_data ( sm_piggyback_data   )
	);

endmodule
