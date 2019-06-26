`ifndef __NPU_SYNCHRONIZATION_DEFINES
`define __NPU_SYNCHRONIZATION_DEFINES

`include "npu_user_defines.sv"
`include "npu_network_defines.sv"

`ifdef DIRECTORY_BARRIER // if defined allocates a distributed directory master

	`define BARRIER_NUMB          (`TILE_COUNT) * 4 * `THREAD_NUMB
	`define BARRIER_NUMB_FOR_TILE `THREAD_NUMB * 4

`else

	`define BARRIER_NUMB          (`TILE_COUNT) * 4 * `THREAD_NUMB
	`define BARRIER_NUMB_FOR_TILE (`TILE_COUNT) * 4 * `THREAD_NUMB

`endif

typedef logic [$clog2(`BARRIER_NUMB) - 1 : 0] barrier_t;
typedef logic [$clog2(`TILE_COUNT*`THREAD_NUMB) - 1 : 0] cnt_barrier_t;

`define BARRIER_SIZE_MEM          $clog2(`TILE_COUNT*`THREAD_NUMB) + (`TILE_COUNT-1) + 1

typedef enum logic {
	ACCOUNT,
	RELEASE
} sync_message_type_t;

// sync_account_message_t and sync_release_message_t must have the same bit size

typedef struct packed {
	barrier_t     id_barrier;
	cnt_barrier_t cnt_setup;
	tile_id_t     tile_id_source;
} sync_account_message_t;

typedef struct packed {
	barrier_t id_barrier;
	logic [$bits(cnt_barrier_t)+$bits(tile_id_t)-1:0] padding;
} sync_release_message_t;

// Synchronization traffic gets encapsulated in a sync_message_t and then in
// a service_message_t
typedef struct packed {
	sync_message_type_t sync_type;

	union packed {
		sync_account_message_t account_mess;
		sync_release_message_t release_mess;
	} sync_mess;
} sync_message_t;

typedef struct packed{
	cnt_barrier_t cnt;
	tile_mask_t mask_slave;
} barrier_data_t;

`endif
