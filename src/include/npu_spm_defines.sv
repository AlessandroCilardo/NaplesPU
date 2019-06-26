`ifndef __NPU_SPM_DEFINES_SV
`define __NPU_SPM_DEFINES_SV

`include "npu_defines.sv"

 `define SM_PROCESSING_ELEMENTS      16		//Numero di SIMD Lane
 `define SM_ENTRIES                  1024	//Numero di entry per banco
 `define SM_MEMORY_BANKS             16		//Numero di banchi di memoria
 `define SM_BYTE_PER_ENTRY           4		//Numero di byte per singola entry di un banco
 `define SM_PIGGYBACK_DATA_LEN       $bits(instruction_decoded_t)

`define SM_ENTRY_ADDRESS_LEN        $clog2(`SM_ENTRIES)
`define SM_MEMORY_BANK_ADDRESS_LEN  $clog2(`SM_MEMORY_BANKS)
`define SM_BYTE_ADDRESS_LEN         $clog2(`SM_BYTE_PER_ENTRY)
`define SM_ADDRESS_LEN              `SM_ENTRY_ADDRESS_LEN + `SM_MEMORY_BANK_ADDRESS_LEN + `SM_BYTE_ADDRESS_LEN

typedef logic   [`SM_BYTE_PER_ENTRY * 8         - 1 : 0] sm_data_t;
typedef logic   [`SM_ADDRESS_LEN                - 1 : 0] sm_address_t;          //Indirizzo di un byte all'interno della shared memory
typedef logic   [`SM_ENTRY_ADDRESS_LEN          - 1 : 0] sm_entry_address_t;    //Indirizzo della entri all'interno di un banco
typedef logic   [`SM_MEMORY_BANK_ADDRESS_LEN    - 1 : 0] sm_bank_address_t;     //Indirizzo del banco di memoria
typedef logic   [`SM_BYTE_ADDRESS_LEN           - 1 : 0] sm_byte_address_t;     //Indirizzo bel byte all'interno di una singola entry
typedef logic   [`SM_BYTE_PER_ENTRY             - 1 : 0] sm_byte_mask_t;

`endif
