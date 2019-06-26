`ifndef __NPU_COHERENCE_DEFINES
`define __NPU_COHERENCE_DEFINES

`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_network_defines.sv"

//  -----------------------------------------------------------------------
//  -- LDST Defines and Typedefs
//  -----------------------------------------------------------------------

`define DCACHE_SIZE               (`DCACHE_WAY*`DCACHE_SET)

typedef logic [`DCACHE_TAG_LENGTH    - 1 : 0] dcache_tag_t;
typedef logic [`DCACHE_SET_LENGTH    - 1 : 0] dcache_set_t;
typedef logic [`DCACHE_OFFSET_LENGTH - 1 : 0] dcache_offset_t;
typedef logic [`DCACHE_WIDTH         - 1 : 0] dcache_line_t;
typedef logic [`DCACHE_WIDTH/8       - 1 : 0] dcache_store_mask_t;
typedef logic [`DCACHE_WAY           - 1 : 0] dcache_way_mask_t;
typedef logic [$clog2(`DCACHE_WAY)   - 1 : 0] dcache_way_idx_t;

typedef struct packed {
    dcache_tag_t    tag;
    dcache_set_t    index;
    dcache_offset_t offset;
} dcache_address_t;

typedef struct packed {
    instruction_decoded_t instruction;
    dcache_address_t      address;
    dcache_line_t         store_value;
    dcache_store_mask_t   store_mask;
    hw_lane_mask_t        hw_lane_mask;
	logic 				  is_io_map;
} dcache_request_t;

typedef struct packed{
    logic can_read;
    logic can_write;
} dcache_privileges_t;

typedef struct packed {
	instruction_decoded_t 			      inst_scheduled;
	address_t 							  address;
	logic [`NUM_BYTE_LANE - 1 : 0]        fecthed_mask;
	hw_lane_mask_t 						  lane_mask;
	hw_lane_t     						  value;
	thread_mask_t 					      thread_bitmap;
	logic [`DCACHE_OFFSET_LENGTH - 1 : 0] scalar_offset;
} ldst_request_t;

//  -----------------------------------------------------------------------
//  -- L2 Cache and Directory TSHR Defines and Typedefs
//  -----------------------------------------------------------------------

`define L2_CACHE_WIDTH           `CACHE_LINE_WIDTH
`define L2_CACHE_SET             `USER_L2CACHE_SET
`define L2_CACHE_SET_LENGTH      $clog2( `L2_CACHE_SET )
`define L2_CACHE_WAY             `USER_L2CACHE_WAY
`define L2_CACHE_WAY_LENGTH      $clog2( `L2_CACHE_WAY )
`define L2_CACHE_OFFSET_LENGTH   $clog2( `L2_CACHE_WIDTH/8 )
`define L2_CACHE_TAG_LENGTH      (`ADDRESS_SIZE - `L2_CACHE_SET_LENGTH - `L2_CACHE_OFFSET_LENGTH)

//`define DPR_READ_PORTS               2
`define TSHR_SIZE                    8
`define TSHR_LOOKUP_PORTS            3

`define DIRECTORY_STATE_WIDTH        3
`define DIRECTORY_MESSAGE_TYPE_WIDTH 5

typedef logic [`L2_CACHE_TAG_LENGTH - 1 : 0] l2_cache_tag_t;
typedef logic [`L2_CACHE_SET_LENGTH - 1 : 0] l2_cache_set_t;
typedef logic [`L2_CACHE_OFFSET_LENGTH - 1 : 0] l2_cache_offset_t;
typedef logic [$clog2( `L2_CACHE_WAY ) - 1 : 0] l2_cache_way_idx_t;
typedef logic [$clog2( `L2_CACHE_WAY ) - 1 : 0] l2_cache_way_mask_t;

typedef struct packed {
	l2_cache_tag_t    tag;
	l2_cache_set_t    index;
	l2_cache_offset_t offset;
} l2_cache_address_t;

//  -----------------------------------------------------------------------
//  -- Cache Controller and Directory Defines
//  -----------------------------------------------------------------------

`define DIRECTORY_ADDRESS                0
`define MSHR_SIZE                        2*`THREAD_NUMB 
`define MSHR_LOOKUP_PORTS                9 
`define STABLE_STATE_WIDTH               2
`define TRANSIENT_STATE_WIDTH            3

`define MSHR_LOOKUP_PORT_REPLACEMENT       0
`define MSHR_LOOKUP_PORT_STORE             1
`define MSHR_LOOKUP_PORT_LOAD              2
`define MSHR_LOOKUP_PORT_FORWARDED_REQUEST 3
`define MSHR_LOOKUP_PORT_RESPONSE          4
`define MSHR_LOOKUP_PORT_FLUSH             5
`define MSHR_LOOKUP_PORT_DINV              6
`define MSHR_LOOKUP_PORT_RECYCLED          7
`define MSHR_COLLISION_PORT                8

`define CC_COMMAND_LENGTH                2
`define COHERENCE_REQUEST_LENGTH         5
`define COHERENCE_STATE_LENGTH           4
`define MESSAGE_REQUEST_LENGTH           4
`define MESSAGE_FORWARDED_REQUEST_LENGTH 4
`define MESSAGE_RESPONSE_LENGTH          4

typedef logic [$clog2( `TILE_COUNT ) - 1 : 0] sharer_count_t;
typedef logic [$clog2( `MSHR_SIZE ) - 1 : 0 ] mshr_idx_t;

typedef logic [`CC_COMMAND_LENGTH - 1 : 0 ]               cc_command_t;
typedef logic [`COHERENCE_REQUEST_LENGTH - 1 : 0 ] 		  coherence_request_t;
typedef logic [`COHERENCE_STATE_LENGTH - 1 : 0 ]          coherence_state_t;
typedef logic [`MESSAGE_REQUEST_LENGTH - 1 : 0 ] 		  message_request_t;
typedef logic [`MESSAGE_FORWARDED_REQUEST_LENGTH - 1 : 0] message_forwarded_request_t;
typedef logic [`MESSAGE_RESPONSE_LENGTH - 1 : 0 ] 		  message_response_t;

//  -----------------------------------------------------------------------
//  -- Coherence Transactions and States
//  -----------------------------------------------------------------------

typedef enum logic[1 : 0 ] {
	DCACHE = 2'b00,
	ICACHE = 2'b01,
	IO     = 2'b10
} requestor_type_t;

typedef enum cc_command_t {
	CC_REPLACEMENT,
	CC_UPDATE_INFO,
	CC_UPDATE_INFO_DATA
} cc_commands_enum_t;

typedef enum coherence_request_t {
	load                   = 0,
	store                  = 1,
	replacement            = 2,
	Fwd_GetS               = 3,
	Fwd_GetM               = 4,
	Inv                    = 5,
	Put_Ack                = 6,
	Data_from_Dir_ack_eqz  = 7,
	Data_from_Dir_ack_gtz  = 8,
	Data_from_Owner        = 9,
	Inv_Ack                = 10,
	Last_Inv_Ack           = 11,
	recall                 = 12,
	flush                  = 13,
	load_uncoherent        = 14,
	store_uncoherent       = 15,
	replacement_uncoherent = 16,
	flush_uncoherent       = 17,
	Fwd_Flush              = 18,
	dinv                   = 19,
	dinv_uncoherent        = 20
} coherence_requests_enum_t;

typedef enum coherence_state_t {
	M    = 0,
	UW   = 1,
	U    = 2,
	S    = 3,
	I    = 4,
	ISd  = 5,
	IMad = 6,
	IMa  = 7,
	IMd  = 8,
	IUd  = 9,
	SMad = 10,
	SMa  = 11,
	MIa  = 12,
	SIa  = 13,
	IIa  = 14
} coherence_states_enum_t;

typedef enum message_request_t {
	GETS      = 0,
	GETM      = 1,
	PUTS      = 2,
	PUTM      = 3,
	DIR_FLUSH = 13
} message_requests_enum_t;

typedef enum message_forwarded_request_t {
	FWD_GETS  = 4,
	FWD_GETM  = 5,
	INV       = 6,
	BACK_INV  = 8,
	FWD_FLUSH = 15
} message_forwarded_requests_enum_t;

typedef enum message_response_t {
	PUT_ACK = 7,
	DATA    = 9,
	INV_ACK = 10,
	WB      = 11,
	MC_ACK  = 14
} message_responses_enum_t;

typedef struct packed {
	logic             	valid;
	dcache_address_t  	address;
	thread_id_t       	thread_id;
	logic             	wakeup_thread;
	coherence_states_enum_t state;
	logic 			waiting_for_eviction;
	sharer_count_t 	  	ack_count;
	sharer_count_t 	  	inv_ack_received;
	logic 			ack_count_received;
} mshr_entry_t;

//  -----------------------------------------------------------------------
//  -- Coherence Messages
//  -----------------------------------------------------------------------

typedef struct packed {
	dcache_line_t           data;           //SOLO PUTM contiene il dato 512
	tile_address_t          source;         // 4
	message_requests_enum_t packet_type; 	// 2
	dcache_address_t 	memory_address; // 32
} coherence_request_message_t;

typedef struct packed {
	tile_address_t                    source;
	message_forwarded_requests_enum_t packet_type;
	dcache_address_t                  memory_address;
	logic                             req_is_uncoherent;
	requestor_type_t                  requestor;
} coherence_forwarded_message_t;

typedef struct packed {
	dcache_line_t            data;
	dcache_store_mask_t      dirty_mask;
	tile_address_t           source;
	message_responses_enum_t packet_type;
	dcache_address_t         memory_address; //SOLO DATA contiene il dato
	sharer_count_t           sharers_count;    //Deve permettere di codificare il numero massimo di nodi
	logic                    from_directory;
	logic                    req_is_uncoherent;
	requestor_type_t         requestor;
} coherence_response_message_t;

//  -----------------------------------------------------------------------
//  -- Cache Controller Protocol ROM
//  -----------------------------------------------------------------------

typedef struct packed {

	logic hit;
	logic stall;
	coherence_states_enum_t next_state;
	logic next_state_is_stable; // Asserted when the next state is stable.

	// Update MSHR entry
	logic req_has_data;         // Store the data coming from the request in the MSHR entry.
	logic req_has_ack_count;    // Store the sharers count coming from the request in the MSHR entry.
	logic allocate_mshr_entry;
	logic deallocate_mshr_entry;
	logic update_mshr_entry;
	logic incr_ack_count;       // Decrement the ack count in the MSHR entry.
	logic ack_count_eqz;

	// Update LDST Unit
	logic write_data_on_cache;  // Store the data coming from MSHR in the cache.
	logic update_privileges;    // Update the privileges of Load/Store Unit.
	dcache_privileges_t next_privileges;

	// Send message to network
	logic send_request;
	logic send_response;
	logic send_forward;
	message_request_t request;
	message_response_t response;
	message_forwarded_request_t forward;
	logic is_receiver_dir;
	logic is_receiver_req;
	logic is_receiver_mc;
	logic send_data;
	logic send_data_from_cache;
	logic send_data_from_mshr;
	logic send_data_from_request;

} protocol_rom_entry_t;

//  -----------------------------------------------------------------------
//  -- Coherence Support Functions
//  -----------------------------------------------------------------------

function coherence_request_t fwd_2_creq( message_forwarded_request_t m );
	case ( m )
		FWD_GETS  : return Fwd_GetS;
		FWD_GETM  : return Fwd_GetM;
		INV       : return Inv;
		BACK_INV  : return recall;
		FWD_FLUSH : return Fwd_Flush;
		default   : return Inv;
	endcase
endfunction : fwd_2_creq

function coherence_request_t res_2_creq( coherence_response_message_t message, mshr_entry_t mshr_entry );
	case ( message.packet_type )
		PUT_ACK : begin
			return Put_Ack;
		end

		DATA    : begin
			if ( message.from_directory ) begin
				if ( (message.sharers_count == 0) | (message.sharers_count == mshr_entry.inv_ack_received) )
					return Data_from_Dir_ack_eqz;
				else if ( message.from_directory )
					return Data_from_Dir_ack_gtz;
			end else
				return Data_from_Owner;
		end

		INV_ACK : begin
			if ( mshr_entry.ack_count_received & (mshr_entry.ack_count == (mshr_entry.inv_ack_received + 1) )) 
				return Last_Inv_Ack;
			else
				return Inv_Ack;
		end
	endcase
endfunction : res_2_creq

function logic state_is_uncoherent( coherence_state_t s );
	return s == U || s == UW || s == IUd;
endfunction : state_is_uncoherent

`define UNCOHERENCE_MAP_BITS 10
`define UNCOHERENCE_MAP_SIZE 8

typedef struct packed {
	logic [`UNCOHERENCE_MAP_BITS-1:0] start_addr;
	logic [`UNCOHERENCE_MAP_BITS-1:0] end_addr;
	logic valid;
} uncoherent_mmap;

//  -----------------------------------------------------------------------
//  -- Directory Controller States
//  -----------------------------------------------------------------------

typedef enum logic [`DIRECTORY_STATE_WIDTH - 1 : 0 ] {
	STATE_N    = 0, 
	STATE_M    = 1, 
	STATE_S    = 2, 
	STATE_I    = 3, 
	STATE_S_D  = 4, 
	STATE_MN_A = 5, 
	STATE_NS_D = 6, 
	STATE_SN_A = 7
} directory_state_t;

typedef enum logic [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] {
	//Requests
	MESSAGE_GETS      = 0, 
	MESSAGE_GETM      = 1, 
	MESSAGE_PUTS      = 2, 
	MESSAGE_PUTM      = 3, 

	// Forwarded Requests
	MESSAGE_FWD_GETS  = 4,
	MESSAGE_FWD_GETM  = 5,
	MESSAGE_INV       = 6,
	MESSAGE_PUTACK    = 7,
	MESSAGE_BACKINV   = 8,

	// Response
	MESSAGE_DATA      = 9,
	MESSAGE_INV_ACK   = 10,
	MESSAGE_WB        = 11,
	REPLACEMENT       = 12,
	MESSAGE_MC_ACK    = 14,
	
	// Other requests
	MESSAGE_DIR_FLUSH = 13,
	MESSAGE_FWD_FLUSH = 15,
	MESSAGE_WB_GEN    = 16
} directory_message_t;

typedef logic [$clog2( `TSHR_SIZE ) - 1 : 0] tshr_idx_t;

typedef struct packed {
	logic               valid;
	directory_state_t   state;
	l2_cache_address_t  address;
	tile_mask_t         sharers_list;
	tile_address_t      owner;
} tshr_entry_t;

//  -----------------------------------------------------------------------
//  -- Directory Controller Messages and Protocol ROM
//  -----------------------------------------------------------------------

typedef struct packed {
	dcache_line_t       data;
	tile_address_t      source;
	l2_cache_address_t  memory_address;
	directory_state_t   state;
	tile_mask_t         sharers_list;
	tile_address_t      owner ;
} replacement_request_t;

typedef struct packed {
	logic stall;

	// L2 Update
	logic current_state_is_stable;
	logic next_state_is_stable;
	directory_state_t next_state;
	logic store_data;
	logic invalidate_cache_way;

	// Outgoing message
	logic message_response_send;
	logic [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] message_response_type;
	logic message_response_has_data;
	logic message_response_to_requestor;
	logic message_response_to_owner;
	logic message_response_to_sharers;
	logic message_response_to_memory;
	logic message_response_add_wb;

	logic message_forwarded_send;
	logic [`DIRECTORY_MESSAGE_TYPE_WIDTH - 1 : 0] message_forwarded_type;
	logic message_forwarded_to_requestor;
	logic message_forwarded_to_owner;
	logic message_forwarded_to_sharers;
	logic message_forwarded_to_memory;

	// Sharers List Update
	logic sharers_add_requestor;
	logic sharers_add_owner;
	logic sharers_remove_requestor;
	logic sharers_clear;

	// Owner Update
	logic owner_set_requestor;
	logic owner_clear;

} directory_protocol_rom_entry_t;


`endif
