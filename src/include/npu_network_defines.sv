`ifndef __NPU_NETWORK_DEFINES_SV
`define __NPU_NETWORK_DEFINES_SV

`include "npu_user_defines.sv"

//  -----------------------------------------------------------------------
//  -- Router Defines and Typedefs
//  -----------------------------------------------------------------------

`define VC_PER_PORT         4 // must be power of 2!!!
`define QUEUE_LEN_PER_VC    16 // must be power of 2!!!
`define PORT_NUM            5
`define PAYLOAD_W           64
`define FLIT_TYPE_W         2
`define DEST_TILE_W			2
`define VC_ID_W             $clog2 ( `VC_PER_PORT )
`define PORT_NUM_W          $clog2 ( `PORT_NUM )
`define TOT_X_NODE_W        $clog2 ( `NoC_X_WIDTH )
`define TOT_Y_NODE_W        $clog2 ( `NoC_Y_WIDTH )

typedef logic [`TILE_COUNT - 1 : 0]         tile_mask_t;
typedef logic [$clog2(`TILE_COUNT) - 1 : 0] tile_id_t;

typedef enum logic {
	DC_ID = 0,
	CC_ID = 1
} tile_destination_idx_t;

typedef enum logic [`DEST_TILE_W - 1 : 0] {
	TO_DC = `DEST_TILE_W'b01,
	TO_CC = `DEST_TILE_W'b10//,
//	TO_BOOTM = `DEST_TILE_W'b00100,
//	TO_SYNCM = `DEST_TILE_W'b01000,
//	TO_BARC = `DEST_TILE_W'b10000
} tile_destination_t;

typedef struct packed {
	logic [`TOT_Y_NODE_W-1:0] y;
	logic [`TOT_X_NODE_W-1:0] x;
} tile_address_t;

typedef enum logic [`FLIT_TYPE_W-1 : 0] {
	HEADER,
	BODY,
	TAIL,
	HT
} flit_type_t;

typedef enum logic [`VC_ID_W-1 : 0    ] {
	VC0, // Request
	VC1, // Response Inject
	VC2, // Fwd
	VC3  // Service VC
} vc_id_t;

typedef enum logic [`PORT_NUM_W-1 : 0 ] {
	LOCAL = 0,
	EAST  = 1,
	NORTH = 2,
	WEST  = 3,
	SOUTH = 4
} port_t;

typedef struct packed {
	flit_type_t flit_type;
	vc_id_t vc_id;
	port_t next_hop_port;
	tile_address_t destination;
	tile_destination_t core_destination;
} flit_header_t;

typedef logic [`PAYLOAD_W-1:0] flit_body_t;

typedef struct packed {
	flit_header_t header;
	flit_body_t payload;
} flit_t;

//  -----------------------------------------------------------------------
//  -- Network Interface Defines
//  -----------------------------------------------------------------------

// XXX_FIFO_SIZE must be a power of 2
`define REQ_FIFO_SIZE        8
`define RESP_FIFO_SIZE       8
`define FWD_FIFO_SIZE        8
`define SERV_FIFO_SIZE       8
`define REQ_ALMOST_FULL      `REQ_FIFO_SIZE  - 4 // tanto si bloccano DC e CC
`define RESP_ALMOST_FULL     `RESP_FIFO_SIZE - 4
`define FWD_ALMOST_FULL      `FWD_FIFO_SIZE  - 4
`define SERV_ALMOST_FULL     `SERV_FIFO_SIZE - 4 //da rivedere

// Response FIFO request typedef
typedef struct packed {
	logic vn_packet_fifo_full;
	logic vn_packet_pending;
	logic vn_flit_valid;
	flit_t vn_flit_out;
} core_to_net_pending_t;

`endif
