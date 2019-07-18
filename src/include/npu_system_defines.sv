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
