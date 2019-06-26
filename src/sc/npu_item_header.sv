`ifndef __NPU_BOOT_SV
`define __NPU_BOOT_SV

// Host - NPU commands
`define HOST_COMMAND_NUM   32
`define HOST_COMMAND_WIDTH ( $clog2( `HOST_COMMAND_NUM ) )

typedef enum logic [`HOST_COMMAND_WIDTH - 1 : 0] {
	HN_BOOT_COMMAND         = 0, 
	HN_BOOT_ACK             = 1, 
	HN_ENABLE_CORE_COMMAND  = 2, 
	HN_ENABLE_CORE_ACK      = 3, 
	HN_READ_STATUS_COMMAND  = 8, 
	HN_WRITE_STATUS_COMMAND = 9, 
	HN_LOG_REQUEST          = 10 
} hn_messages_t;

`endif
