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

`ifndef __NPU_DEFINES_SV
`define __NPU_DEFINES_SV

`include "npu_user_defines.sv"

//  -----------------------------------------------------------------------
//  -- Core Defines
//  -----------------------------------------------------------------------

`define HW_LANE                 16
`define ADDRESS_SIZE            32
`define REGISTER_NUMBER         64
`define REGISTER_SIZE           32
`define REGISTER_SIZE_64        64
`define REGISTER_ADDRESS        $clog2 ( `REGISTER_NUMBER * `THREAD_NUMB )
`define BYTE_PER_REGISTER       ( `REGISTER_SIZE / 8 )
`define REGISTER_INDEX_LENGTH   $clog2( `REGISTER_NUMBER )
`define V_REGISTER_SIZE         ( `HW_LANE * `REGISTER_SIZE )
`define NUM_BYTE_LINE           ( `V_REGISTER_SIZE/8 )
`define IMMEDIATE_SIZE          32
`define OP_CODE_WIDTH           8
`define NUM_EX_PIPE             4
`define NUM_MAX_EX_PIPE         16
`define NUM_INTERNAL_PIPE_WIDTH 4 // inside an exec. pipe there could be other sub-pipes
`define INSTRUCTION_FIFO_SIZE   16
`define SCOREBOARD_LENGTH       ( `REGISTER_NUMBER*2 )
`define CACHE_LINE_WIDTH        ( `V_REGISTER_SIZE )

//  -----------------------------------------------------------------------
//  -- Register Defines
//  -----------------------------------------------------------------------

`define PC_REG                  ( `REGISTER_NUMBER - 1 )
`define RA_REG                  ( `REGISTER_NUMBER - 2 )
`define SP_REG                  ( `REGISTER_NUMBER - 3 )
`define FP_REG                  ( `REGISTER_NUMBER - 4 )
`define MASK_REG                ( `REGISTER_NUMBER - 5 )

//  -----------------------------------------------------------------------
//  -- L1 Cache Defines
//  -----------------------------------------------------------------------

`define INSTRUCTION_LENGTH      32
`define ICACHE_WIDTH            `CACHE_LINE_WIDTH
`define ICACHE_SET              `USER_ICACHE_SET
`define ICACHE_SET_LENGTH       $clog2( `ICACHE_SET )
`define ICACHE_WAY              `USER_ICACHE_WAY
`define ICACHE_WAY_LENGTH       $clog2( `ICACHE_WAY )
`define ICACHE_OFFSET_LENGTH    $clog2( `ICACHE_WIDTH/8 )
`define ICACHE_TAG_LENGTH       ( `ADDRESS_SIZE - `ICACHE_SET_LENGTH - `ICACHE_OFFSET_LENGTH )

`define DCACHE_WIDTH            `CACHE_LINE_WIDTH
`define DCACHE_SET              `USER_DCACHE_SET
`define DCACHE_SET_LENGTH       $clog2( `DCACHE_SET )
`define DCACHE_OFFSET_LENGTH    $clog2( `DCACHE_WIDTH/8 )
`define DCACHE_TAG_LENGTH       ( `ADDRESS_SIZE - `DCACHE_SET_LENGTH - `DCACHE_OFFSET_LENGTH )
`define DCACHE_WAY              `USER_DCACHE_WAY
`define NUM_BYTE_LANE           ( `V_REGISTER_SIZE/8 )

//  -----------------------------------------------------------------------
//  -- Typedef
//  -----------------------------------------------------------------------

typedef logic [`ADDRESS_SIZE - 1           : 0] address_t;
typedef logic [`REGISTER_INDEX_LENGTH - 1  : 0] reg_addr_t;
typedef logic [`REGISTER_SIZE - 1          : 0] register_t;
typedef logic [`REGISTER_SIZE_64 - 1       : 0] register_64_t;
typedef register_t [`HW_LANE - 1           : 0] hw_lane_t;
typedef register_64_t [`HW_LANE/2 - 1      : 0] hw_lane_double_t; 
typedef logic [`HW_LANE - 1 		   : 0] hw_lane_mask_t;
typedef logic [$clog2( `THREAD_NUMB ) - 1  : 0] thread_id_t;
typedef logic [`ICACHE_WIDTH - 1 	   : 0] icache_lane_t;
typedef logic [2*`REGISTER_NUMBER - 1      : 0] scoreboard_t;
typedef logic [`THREAD_NUMB - 1 	   : 0] thread_mask_t;
typedef logic [`NUM_EX_PIPE - 1 	   : 0] ex_pipe_mask_t;
typedef logic [`BYTE_PER_REGISTER - 1 	   : 0] reg_byte_enable_t;

//  -----------------------------------------------------------------------
//  -- IO Memory Space
//  -----------------------------------------------------------------------
typedef enum logic {
	IO_READ,
	IO_WRITE
} io_operation_t;

typedef struct packed {
	logic [`ICACHE_TAG_LENGTH - 1 : 0   ] tag;
	logic [`ICACHE_SET_LENGTH - 1 : 0   ] index;
	logic [`ICACHE_OFFSET_LENGTH - 1 : 0] offset;
} icache_address_t;

//  -----------------------------------------------------------------------
//  -- Operation type definitions
//  -----------------------------------------------------------------------

// ALU operation type - Integer and FP
typedef enum logic [`OP_CODE_WIDTH - 1 : 0          ]{
	NOT      = `OP_CODE_WIDTH'b000000,
	OR       = `OP_CODE_WIDTH'b000001,
	AND      = `OP_CODE_WIDTH'b000010,
	XOR      = `OP_CODE_WIDTH'b000011,

	ADD      = `OP_CODE_WIDTH'b000100,
	SUB      = `OP_CODE_WIDTH'b000101,
	MULHI    = `OP_CODE_WIDTH'b000111,
	MULLO    = `OP_CODE_WIDTH'b000110,
	MULHU    = `OP_CODE_WIDTH'b001000,

	ASHR     = `OP_CODE_WIDTH'b001001,
	SHR      = `OP_CODE_WIDTH'b001010,
	SHL      = `OP_CODE_WIDTH'b001011,
	CLZ      = `OP_CODE_WIDTH'b001100,
	CTZ      = `OP_CODE_WIDTH'b001101,

	CMPEQ    = `OP_CODE_WIDTH'b001110,
	CMPNE    = `OP_CODE_WIDTH'b001111,
	CMPGT    = `OP_CODE_WIDTH'b010000,
	CMPGE    = `OP_CODE_WIDTH'b010001,
	CMPLT    = `OP_CODE_WIDTH'b010010,
	CMPLE    = `OP_CODE_WIDTH'b010011,
	CMPGT_U  = `OP_CODE_WIDTH'b010100,
	CMPGE_U  = `OP_CODE_WIDTH'b010101,
	CMPLT_U  = `OP_CODE_WIDTH'b010110,
	CMPLE_U  = `OP_CODE_WIDTH'b010111,

	SHUFFLE  = `OP_CODE_WIDTH'b011000,
	GETLANE  = `OP_CODE_WIDTH'b011001,
	MOVE     = `OP_CODE_WIDTH'b100000,

	ADD_FP   = `OP_CODE_WIDTH'b100001,
	SUB_FP   = `OP_CODE_WIDTH'b100010,
	MUL_FP   = `OP_CODE_WIDTH'b100011,
	DIV_FP   = `OP_CODE_WIDTH'b100100,
	CMPEQ_FP = `OP_CODE_WIDTH'b100101,
	CMPNE_FP = `OP_CODE_WIDTH'b100110,
	CMPGT_FP = `OP_CODE_WIDTH'b100111,
	CMPGE_FP = `OP_CODE_WIDTH'b101000,
	CMPLT_FP = `OP_CODE_WIDTH'b101001,
	CMPLE_FP = `OP_CODE_WIDTH'b101010,
	SEXT8    = `OP_CODE_WIDTH'b101011,
	SEXT16   = `OP_CODE_WIDTH'b101100,
	SEXT32   = `OP_CODE_WIDTH'b101101,

	ITOF     = `OP_CODE_WIDTH'b110000,
	FTOI     = `OP_CODE_WIDTH'b110001,

	CRT_MASK = `OP_CODE_WIDTH'b110010,
	CRP_V_32 = `OP_CODE_WIDTH'b111111
}alu_op_t;

// Memory operation types
typedef enum logic[`OP_CODE_WIDTH - 1 : 0           ] {
	LOAD_8      = `OP_CODE_WIDTH'b000000,
	LOAD_16     = `OP_CODE_WIDTH'b000001,
	LOAD_32     = `OP_CODE_WIDTH'b000010,
	LOAD_64     = `OP_CODE_WIDTH'b000011,
	LOAD_8_U    = `OP_CODE_WIDTH'b000100,
	LOAD_16_U   = `OP_CODE_WIDTH'b000101,
	LOAD_32_U   = `OP_CODE_WIDTH'b000110,
	LOAD_V_8    = `OP_CODE_WIDTH'b000111,
	LOAD_V_16   = `OP_CODE_WIDTH'b001000,
	LOAD_V_32   = `OP_CODE_WIDTH'b001001,
	LOAD_V_64   = `OP_CODE_WIDTH'b001010,
	LOAD_V_8_U  = `OP_CODE_WIDTH'b001011,
	LOAD_V_16_U = `OP_CODE_WIDTH'b001100,
	LOAD_V_32_U = `OP_CODE_WIDTH'b001101,
	LOAD_G_8    = `OP_CODE_WIDTH'b001110,
	LOAD_G_16   = `OP_CODE_WIDTH'b001111,
	LOAD_G_32   = `OP_CODE_WIDTH'b010000,
	LOAD_G_64   = `OP_CODE_WIDTH'b010001,
	LOAD_G_8_U  = `OP_CODE_WIDTH'b010010,
	LOAD_G_16_U = `OP_CODE_WIDTH'b010011,
	LOAD_G_32_U = `OP_CODE_WIDTH'b010100,
	STORE_8     = `OP_CODE_WIDTH'b100000,
	STORE_16    = `OP_CODE_WIDTH'b100001,
	STORE_32    = `OP_CODE_WIDTH'b100010,
	STORE_64    = `OP_CODE_WIDTH'b100011,
	STORE_V_8   = `OP_CODE_WIDTH'b100100,
	STORE_V_16  = `OP_CODE_WIDTH'b100101,
	STORE_V_32  = `OP_CODE_WIDTH'b100110,
	STORE_V_64  = `OP_CODE_WIDTH'b100111,
	STORE_S_8   = `OP_CODE_WIDTH'b101000,
	STORE_S_16  = `OP_CODE_WIDTH'b101001,
	STORE_S_32  = `OP_CODE_WIDTH'b101010,
	STORE_S_64  = `OP_CODE_WIDTH'b101011
} memory_op_t;

typedef enum logic[`OP_CODE_WIDTH - 1 : 0           ] {
	MOVEI   = `OP_CODE_WIDTH'b000010,
	MOVEI_L = `OP_CODE_WIDTH'b000000,
	MOVEI_H = `OP_CODE_WIDTH'b000001
} movei_t;

typedef enum logic[`OP_CODE_WIDTH - 1 : 0           ] {
	JMP        = `OP_CODE_WIDTH'b000000,
	JMPSR      = `OP_CODE_WIDTH'b000001,
	JSYS       = `OP_CODE_WIDTH'b000010,
	JRET       = `OP_CODE_WIDTH'b000011,
	JERET      = `OP_CODE_WIDTH'b000100,
	BRANCH_EQZ = `OP_CODE_WIDTH'b000101,
	BRANCH_NEZ = `OP_CODE_WIDTH'b000110
} j_op_t;

// Control Operation - Cache and other compiler control mechanism 
typedef enum logic[`OP_CODE_WIDTH - 1 : 0           ] {
	BARRIER_CORE   = `OP_CODE_WIDTH'b000000,
	BARRIER_THREAD = `OP_CODE_WIDTH'b000001,
	FLUSH          = `OP_CODE_WIDTH'b000010,
	READ_CR        = `OP_CODE_WIDTH'b000011,
	WRITE_CR       = `OP_CODE_WIDTH'b000100,
	DCACHE_INV     = `OP_CODE_WIDTH'b000101
} control_op_t;

typedef enum logic [`NUM_INTERNAL_PIPE_WIDTH - 1 : 0] {
	PIPE_MEM,
	PIPE_INT,
	PIPE_CR,
	PIPE_BRANCH,
	PIPE_FP,
	PIPE_SPM,
	PIPE_SFU,
	PIPE_SYNC,
	PIPE_CRP
} pipeline_disp_t;

typedef enum logic [0 : 0                           ] {
	JBA,
	JRA
} branch_type_t;

//  -----------------------------------------------------------------------
//  -- Instruction Format definitions
//  -----------------------------------------------------------------------

//Instruction bodies
typedef struct packed {
	reg_addr_t destination;
	reg_addr_t source0;
	reg_addr_t source1;
	logic unused;
	logic long;
	logic [2 : 0] register_selection;
	logic mask;
} RR_instruction_body_t;

typedef struct packed {
	reg_addr_t destination;
	reg_addr_t source0;
	logic [8 : 0] immediate;
	logic [1 : 0] register_selection;
	logic mask;
} RI_instruction_body_t;

typedef struct packed {
	reg_addr_t destination;
	logic [15 : 0] immediate;
	logic register_selection;
	logic mask;
} MVI_instruction_body_t;

/* verilator lint_off SYMRSVDWORD */
typedef struct packed {
	reg_addr_t src_dest_register;
	reg_addr_t base_register;
	logic [8 : 0] offset;
	logic long;
	logic shared;
	logic mask;
} MEM_instruction_body_t;
/* verilator lint_on SYMRSVDWORD */

typedef struct packed {
	logic [23 : 0] boh;
} MPOLI_instruction_body_t;

typedef struct packed {
	reg_addr_t dest;
	logic [17 : 0] immediate;
} JBA_instruction_body_t;

typedef struct packed {
	logic [23 : 0] immediate;
} JRA_instruction_body_t;

typedef struct packed {
	reg_addr_t source0;
	reg_addr_t source1;
	logic [8 : 0] immediate;
	logic [2 : 0] unused;
} CTR_instruction_body_t;

//=====================================================================================================

typedef union packed {
	RR_instruction_body_t RR_body;
	RI_instruction_body_t RI_body;
	MVI_instruction_body_t MVI_body;
	MEM_instruction_body_t MEM_body;
	MPOLI_instruction_body_t MPOLI_body;
	JBA_instruction_body_t JBA_body;
	JRA_instruction_body_t JRA_body;
	CTR_instruction_body_t CTR_body;
} instruction_body_t;

typedef union packed {
	alu_op_t alu_opcode;
	memory_op_t mem_opcode;
	movei_t movei_opcode;
	j_op_t j_opcode;
	control_op_t contr_opcode;
} opcode_t;

typedef struct packed {
	//instruction_type_t  instruction_type;
	opcode_t opcode;
	instruction_body_t body;
} instruction_t;

//  -----------------------------------------------------------------------
//  -- Decode definitions
//  -----------------------------------------------------------------------

typedef struct packed {
	address_t pc;
	thread_id_t thread_id;
	logic mask_enable;
	logic is_valid;

	// Operand Register Fields
	reg_addr_t source0;
	reg_addr_t source1;
	reg_addr_t destination;
	logic has_source0;
	logic has_source1;
	logic has_destination;
	logic is_source0_vectorial;
	logic is_source1_vectorial;
	logic is_destination_vectorial;
	logic signed [`IMMEDIATE_SIZE - 1 : 0] immediate;
	logic is_source1_immediate;

	// Ex Pipes Fields
	pipeline_disp_t pipe_sel;
	opcode_t op_code;
	logic is_memory_access;
	logic is_memory_access_coherent;
	logic is_int;
	logic is_fp;
	logic is_load;
	logic is_movei;
	logic is_branch;
	logic is_conditional;
	logic is_control;
	logic is_long;

	branch_type_t branch_type;
} instruction_decoded_t;

//  -----------------------------------------------------------------------
//  -- Control Registers
//  -----------------------------------------------------------------------

`define CTR_NUMB                64
`define THREAD_STATUS_BIT       3

typedef enum logic [$clog2( `CTR_NUMB ) - 1 : 0     ]{
	TILE_ID             = 0,
	CORE_ID             = 1,
	THREAD_ID           = 2,
	GLOBAL_ID           = 3,
	GCOUNTER_LOW_ID     = 4,
	GCOUNTER_HIGH_ID    = 5,
	THREAD_EN_ID        = 6,
	MISS_DATA_ID        = 7,
	MISS_INSTR_ID       = 8,
	PC_ID               = 9,
	TRAP_REASON_ID      = 10,
	THREAD_STATUS_ID    = 11,
	ARGC_ID             = 12,
	ARGV_ID             = 13,
	THREAD_NUMB_ID      = 14,
	THREAD_MISS_CC_ID   = 15,
	KERNEL_WORK         = 16,
	CPU_CTRL_REG_ID     = 17,
	PWR_MDL_REG_ID      = 18,
	UNCOHERENCE_MAP_ID  = 19,
    DEBUG_BASE_ADDR     = 20
} control_register_index_t;

typedef enum logic [`THREAD_STATUS_BIT - 1 : 0      ]{
	THREAD_IDLE,
	RUNNING,
	END_MODE,
	TRAPPED,
	WAITING_BARRIER,
	BOOTING
} thread_status_t;

typedef struct packed {
	logic interrupt_enable;
	logic [15 : 0] interrupt_mask;
	logic supervisor;
	logic interrupt_pending;
	logic interrupt_trigger_mode;
	address_t isr_handler;
} control_register_t;

//  -----------------------------------------------------------------------
//  -- Execution Floating Point type definitions
//  -----------------------------------------------------------------------

`define IEEE754_SP_EXP_WIDTH    8
`define IEEE754_SP_MAN_WIDTH    23
`define IEEE754_DP_EXP_WIDTH    11
`define IEEE754_DP_MAN_WIDTH    52

`define FP_ADD_LATENCY          5
`define FP_MULT_LATENCY         2
`define FP_FTOI_LATENCY         4
`define FP_ITOF_LATENCY         6

`define FP_DIV_LATENCY          17
`define FP_ADD_DP_LATENCY       9
`define FP_MULT_DP_LATENCY      10
`define FP_DIV_DP_LATENCY       32

typedef logic [`IEEE754_SP_MAN_WIDTH - 1 : 0        ] mantissa_sp_t;
typedef logic [`IEEE754_SP_EXP_WIDTH - 1 : 0        ] exponent_sp_t;
typedef logic [`IEEE754_DP_MAN_WIDTH - 1 : 0        ] mantissa_dp_t;
typedef logic [`IEEE754_DP_EXP_WIDTH - 1 : 0        ] exponent_dp_t;

typedef struct packed {
	logic sign;
	exponent_sp_t exp;
	mantissa_sp_t frac;
} ieee754_sp_t;

typedef struct packed {
	logic sign;
	exponent_dp_t exp;
	mantissa_dp_t frac;
} ieee754_dp_t;

typedef struct packed {
	ieee754_sp_t fpnum;
	logic is_nan;
	logic is_inf;
} sp_float_t;

//  -----------------------------------------------------------------------
//  -- WB definitions
//  -----------------------------------------------------------------------

typedef struct packed {
	register_t wb_result_pc;
	hw_lane_t wb_result_data;
	reg_addr_t wb_result_register;
	hw_lane_mask_t wb_result_hw_lane_mask;
	reg_byte_enable_t wb_result_write_byte_enable;
	logic wb_result_is_scalar;
} wb_result_t;

//  -----------------------------------------------------------------------
//  -- Traps Defines
//  -----------------------------------------------------------------------

// Trap PCs
`define SPM_ADDR_MISALIGN_ISR   32'h380
`define LDST_ADDR_MISALIGN_ISR  32'h380

// Trap Reasons
`define SPM_ADDR_MISALIGN       32'h40
`define LDST_ADDR_MISALIGN      32'h80

typedef enum {
	NONE          = 0,
	SPM_ADDR_MIS  = `SPM_ADDR_MISALIGN,
	LDST_ADDR_MIS = `LDST_ADDR_MISALIGN
} core_trap_t;

`endif
