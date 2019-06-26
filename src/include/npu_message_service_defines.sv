`ifndef __NPU_MESSAGE_SERVICE_DEFINES
`define __NPU_MESSAGE_SERVICE_DEFINES

`include "npu_defines.sv"
`include "npu_network_defines.sv"
`include "npu_system_defines.sv"
`include "npu_synchronization_defines.sv"

`define HOST_COMMAND_NUM                 16
`define HOST_COMMAND_WIDTH               ( $clog2( `HOST_COMMAND_NUM ) )

typedef enum logic [`HOST_COMMAND_WIDTH - 1 : 0] {
	//COMMAND FOR BOOT
	BOOT_COMMAND         = 0,
	ENABLE_THREAD        = 1,
	GET_CONTROL_REGISTER = 2,
	SET_CONTROL_REGISTER = 3,
	GET_CONSOLE_STATUS   = 4,
	GET_CONSOLE_DATA     = 5,
	WRITE_CONSOLE_DATA   = 6,
	//Core Logger CMD
	CORE_LOG             = 9
} host_message_type_t;

typedef struct packed {                            // XXX: Worst case = 63 - if so it can fit into a single FLIT
	address_t                    hi_job_pc;        //32
	logic                        hi_job_valid;     //1
	thread_id_t                  hi_job_thread_id; //2
	logic [`THREAD_NUMB - 1 : 0] hi_thread_en;     //4
	host_message_type_t          message;          //4
} host_message_t;

typedef struct packed {
	tile_id_t      io_source;
	thread_id_t    io_thread;
	io_operation_t io_operation;
	address_t      io_address;
	register_t     io_data;
} io_message_t;

// This define should be set to the size of the greatest structure that should
// be carried as a payload
`define SERVICE_MESSAGE_LENGTH ( $bits( io_message_t ))
typedef logic [`SERVICE_MESSAGE_LENGTH - 1 : 0] service_message_data_t;

`define MESSAGE_TYPE_LENGTH              2
typedef enum logic [`MESSAGE_TYPE_LENGTH - 1 : 0] {
	HOST    = 0,
	SYNC    = 1,
	IO_OP   = 2,
    HT_CORE = 3
} service_message_type_t;

typedef struct packed {
	service_message_type_t message_type;
	service_message_data_t data;
} service_message_t;

`endif
