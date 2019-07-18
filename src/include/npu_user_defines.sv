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

`ifndef __NPU_USER_DEFINES_SV
`define __NPU_USER_DEFINES_SV

/*
 * This project provides a simulation testbench (tb_manycore), which simulates the host
 * communication, the main memory and the synchronization core used during memory barriers.
 * It initializes and lunches the NaplesPU processor, then waits the end of the kernel computation.
 *
 * In order to run a kernel in simulation, the below paths should be up-to-date. The testbench relies
 * on a memory dummy module which is pre-loaded with the hex image produced by the LLVM tool-chain.
 * The selected memory image file is linked through the MEMORY_BIN variable defined below.
 *
 * Furthermore, DISPLAY variables are defined, all commented by default. When a DISPLAY variable is
 * active, it generates a file, under a folder named after the selected kernel. Each DISPLAY variable
 * logs a defined kind of transaction, namely:
 *
 *  1  - DISPLAY_MEMORY: logs on file the memory state at the end of the kernel execution.
 *  2  - DISPLAY_MEMORY_TRANS: logs on file all requests to the main memory.
 *  3  - DISPLAY_MEMORY_CONTROLLER: displays on shell memory requests to the memory controller and its responses. 
 *  4  - DISPLAY_INT: logs every integer operation in the integer pipeline, and their results.
 *  5  - DISPLAY_CORE: enables log from the core (file display_core.txt).
 *  6  - DISPLAY_ISSUE: logs all scheduled instructions, and tracks the scheduled PC and the issued Thread, when DISPLAY_CORE is defined.
 *  7  - DISPLAY_INT: logs all results from the integer module, when DISPLAY_CORE is defined.
 *  8  - DISPLAY_WB: logs all results from the writeback module, when DISPLAY_CORE is defined.
 *  9  - DISPLAY_LDST: enables logging into the load/store unit (file display_ldst.txt).
 *  10  - DISPLAY_CACHE_CONTROLLER: logs memory transactions between Load/Store unit and the main memory.
 *  11 - DISPLAY_SYNCH_CORE: logs synchronization requests within the core.
 *  12 - DISPLAY_BARRIER_CORE: logs synchronization releases from the Synchronization master.
 *  13 - DISPLAY_COHERENCE: logs all coherence transactions among CCs, DCs and MC.
 *  14 - DISPLAY_THREAD_STATUS: displays all active threads status and trap reason.
 *
 */

//  -----------------------------------------------------------------------
//  -- Architecture Parameters
//  -----------------------------------------------------------------------

// Core user defines
`define THREAD_NUMB              8  // Must be power of 2
`define USER_ICACHE_SET          32 // Must be power of 2
`define USER_ICACHE_WAY          4  // Must be power of 2
`define USER_DCACHE_SET          32 // Must be power of 2
`define USER_DCACHE_WAY          4  // Must be power of 2
`define USER_L2CACHE_SET         128 // Must be power of 2
`define USER_L2CACHE_WAY         8  // Must be power of 2

`define DIRECTORY_BARRIER        // When defined the system supports a distributed directory over all tiles. Otherwise, it allocates a single synchronization master.
`define CENTRAL_SYNCH_ID         0 // Single synchronization master ID, used only when DIRECTORY_BARRIER is undefined

// IO memory space
`define IO_MAP_BASE_ADDR         32'hFF00_0000
`define IO_MAP_SIZE              32'h00FF_FF00

// Implement scratchpad memory
`define NPU_SPM                  1
// Implement FP pipe
`define NPU_FPU                  1

// NoC user defines
//`define NoC_WIDTH      2
`define NoC_X_WIDTH              4 // Must be power of 2
`define NoC_Y_WIDTH              4 // Must be power of 2
`define TILE_COUNT               ( `NoC_X_WIDTH * `NoC_Y_WIDTH )
`define TILE_MEMORY_ID           ( `TILE_COUNT - 1 )
`define TILE_H2C_ID              ( `TILE_COUNT - 2 )
`define TILE_NPU                 8 // ( `TILE_COUNT - 8 ) // core tiles count
`define TILE_HT                  0 // heterogeneous tiles count

//  -----------------------------------------------------------------------
//  -- Simulation Parameters
//  -----------------------------------------------------------------------

`ifdef SIMULATION

    /* Mandatory Logs variables - Do not comment */
	`define DISPLAY_THREAD_STATUS
	`define DISPLAY_MEMORY
	`define DISPLAY_SIMULATION_LOG
    
    /* Optional Logs */
	//`define DISPLAY_COHERENCE
	//`define DISPLAY_SPM
	//`define DISPLAY_DEBUG_REG
	//`define DISPLAY_CORE
	//`define DISPLAY_ISSUE
	//`define DISPLAY_INT
	//`define DISPLAY_WB
	//`define DISPLAY_LDST
	//`define DISPLAY_MEMORY_CONTROLLER
	//`define DISPLAY_MEMORY_TRANS
	//`define DISPLAY_REQUESTS_MANAGER
	`define DISPLAY_SYNC
	`define DISPLAY_BARRIER_CORE
	`define DISPLAY_SYNCH_CORE
	//`define DISPLAY_IO
	//`define COHERENCE_INJECTION

`endif

`endif
