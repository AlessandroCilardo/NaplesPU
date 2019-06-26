`ifndef __NPU_SYSTEM_DEFINES_SV
`define __NPU_SYSTEM_DEFINES_SV

`include "npu_defines.sv"

`define BUS_MASTER                       2
`define CLOCK_RATE                       50000000
`define CLOCK_PERIOD_NS                  10

//  -----------------------------------------------------------------------
//  -- Logger Defines
//  -----------------------------------------------------------------------

`define LOG_SNOOP_COMMANDS 8
`define LOG_SNOOP_COMMANDS_WIDTH $clog2( `LOG_SNOOP_COMMANDS )

typedef logic [`LOG_SNOOP_COMMANDS_WIDTH - 1 : 0] log_snoop_req_t;

typedef enum logic [`LOG_SNOOP_COMMANDS_WIDTH - 1 : 0]{
	SNOOP_CORE,
	SNOOP_MEM,
	GET_CORE_EVENTS,
	GET_MEM_EVENTS,
	GET_EVENT_COUNTER
} log_snoop_req_enum_t;

`endif
