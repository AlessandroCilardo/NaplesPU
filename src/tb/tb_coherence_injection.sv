`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"
`include "npu_system_defines.sv"
`include "npu_coherence_defines.sv"
`include "npu_network_defines.sv"
`include "npu_message_service_defines.sv"
`include "npu_debug_log.sv"

module tb_coherence_injection #(
		parameter KERNEL_IMAGE = "mmsc_mem.hex",
		parameter THREAD_MASK  = 8'hFF,
		parameter CORE_MASK    = 32'h03 )
	( );

	logic                                 clk                              = 1'b1;
	logic                                 reset                            = 1'b1;
	logic                                 enable                           = 1'b1;

	int                                   sim_log_file;

//  -----------------------------------------------------------------------
//  -- TB parameters and signals
//  -----------------------------------------------------------------------

	//Parameters

    localparam NoC_ROW          		  = `NoC_Y_WIDTH;
    localparam NoC_COL          		  = `NoC_X_WIDTH;
    localparam MEM_ADDR_w      			  = `ADDRESS_SIZE;
    localparam MEM_DATA_BLOCK_w 		  = `DCACHE_WIDTH;
    localparam ITEM_w           		  = 32;
    localparam CLK_PERIOD_NS    		  = `CLOCK_PERIOD_NS;
    localparam PC_DEFAULT       		  = 32'h0000_0400;
    localparam TB_REQUEST_NUMBER 		  = 8; //after 1000 requests the TB will end
	localparam TB_DEADLOCK_THRESHOLD	  = 100; //20 clock ticks in stall mean core's deadlock

	//Noc signals

	logic             [ITEM_w - 1 : 0]    item_data_i;
	logic                                 item_valid_i = 1'b0;
	logic                                 item_avail_o;
	logic             [ITEM_w - 1 : 0]    item_data_o;
	logic                                 item_valid_o;
	logic                                 item_avail_i;
	logic                                 mc_avail_o;

	//Memory <-> Noc signals

	address_t                             n2m_request_address;
	logic             [63 : 0]            n2m_request_dirty_mask;
	dcache_line_t                         n2m_request_data;
	logic                                 n2m_request_read;
	logic                                 n2m_request_write;

	logic                                 m2n_request_available;
	logic                                 m2n_response_valid;
	address_t                             m2n_response_address;
	dcache_line_t                         m2n_response_data;
	
	//Injection signals
	instruction_decoded_t                 t_00_ldst_instruction_inject;		
    dcache_address_t                      t_00_ldst_address_inject;			
    logic                                 t_00_ldst_miss_inject;				
    logic                                 t_00_ldst_evict_inject;			
    dcache_line_t                         t_00_ldst_cache_line_inject;			
    logic                                 t_00_ldst_flush_inject;			
    logic                                 t_00_ldst_dinv_inject;			
    dcache_store_mask_t                   t_00_ldst_dirty_mask_inject;			

	instruction_decoded_t                 t_01_ldst_instruction_inject;			
    dcache_address_t                      t_01_ldst_address_inject;			
    logic                                 t_01_ldst_miss_inject;				
    logic                                 t_01_ldst_evict_inject;			
    dcache_line_t                         t_01_ldst_cache_line_inject;			
    logic                                 t_01_ldst_flush_inject;			
    logic                                 t_01_ldst_dinv_inject;			
    dcache_store_mask_t                   t_01_ldst_dirty_mask_inject;

	//Stall logic signals
	logic 								  t_00_wakeup;
	thread_id_t 						  t_00_wakeup_thread_id;
	logic 								  t_01_wakeup;
	thread_id_t 						  t_01_wakeup_thread_id;
	logic [`THREAD_NUMB-1:0]			  t_00_stall_mask = 'b0;
	logic [`THREAD_NUMB-1:0]			  t_01_stall_mask = 'b0;

	//TB execution logic signals
	logic 								  thread_en;

	//TB termination logic
	int 								  t_00_cnt = 0;
	int 								  t_01_cnt = 0;

	//TB watchdog logic
	int									  t_00_kill_cnt = TB_DEADLOCK_THRESHOLD;
	int									  t_01_kill_cnt = TB_DEADLOCK_THRESHOLD;

//  -----------------------------------------------------------------------
//  -- TB Common Declarations
//  -----------------------------------------------------------------------	

	typedef enum {
		//In this TB, we communicate with the CC acting like the Core NU+, so we must be able to
		//submit all and only the REQUEST class message for the core. 
		LOAD						= 0,
		LOAD_UNCOHERENT				= 1,
		STORE 						= 2,
		STORE_UNCOHERENT 			= 3,
		REPLACEMENT					= 4,
		REPLACEMENT_UNCOHERENT 		= 5,
		DINV 						= 6,
		DINV_UNCOHERENT 			= 7,
		FLUSH						= 8,
		FLUSH_UNCOHERENT			= 9

	} tb_request_type_t;	

	typedef struct packed {
		logic [$clog2(CORE_MASK) -1 : 0] 	tile_id;
		thread_id_t							tid;
	} requestor_t;

	typedef struct packed {
		tb_request_type_t 		request_type;
		dcache_address_t		address;
		requestor_t				requestor;
		dcache_line_t			cache_line;
		dcache_store_mask_t 	dirty_mask;
	} tb_coherence_request_t;

//  -----------------------------------------------------------------------
//  -- TB Unit Under Test
//  -----------------------------------------------------------------------

	npu_noc #(
		.MEM_ADDR_w      ( MEM_ADDR_w       ),
		.MEM_DATA_BLOCK_w( MEM_DATA_BLOCK_w ),
		.ITEM_w          ( ITEM_w           )
	)
	u_npu_noc (
		.clk                 ( clk                    ),
		.reset               ( reset                  ),
		.enable              ( enable                 ),
		//interface Memory <-> NaplesPU
		.item_data_i         ( item_data_i            ), //Input: items from outside
		.item_valid_i        ( item_valid_i           ), //Input: valid signal associated with item_data_i port
		.item_avail_o        ( item_avail_o           ), //Output: avail signal to input port item_data_i
		.item_data_o         ( item_data_o            ), //Output: items to outside
		.item_valid_o        ( item_valid_o           ), //Output: valid signal associated with item_data_o port
		.item_avail_i        ( item_avail_i           ), //Input: avail signal to output port item_data_o
		//interface MC
		.n2m_request_is_instr(                        ),

		.mc_address_o        ( n2m_request_address    ), //output: Address to MC
		.mc_dirty_mask_o     ( n2m_request_dirty_mask ),
		.mc_block_o          ( n2m_request_data       ), //output: Data block to MC
		.mc_avail_o          ( mc_avail_o             ), //output: available bit from UNIT
		.mc_sender_o         (                        ), //output: sender to MC
		.mc_read_o           ( n2m_request_read       ), //output: read request to MC
		.mc_write_o          ( n2m_request_write      ), //output: write request to MC

		.mc_address_i        ( m2n_response_address   ), //input: Address from MC
		.mc_block_i          ( m2n_response_data      ), //input: Data block from MC
		.mc_dst_i            ( 10'd0                  ), //input: destination from MC
		.mc_sender_i         ( 10'd0                  ), //input: Sender from MC
		.mc_read_avail_i     ( m2n_request_available  ), //input: read available signal from MC
		.mc_write_avail_i    ( m2n_request_available  ), //input: write available signal from MC
		.mc_valid_i          ( m2n_response_valid     ), //input: valid bit from MC
		.mc_request_i        ( 1'b0                   )  //input: Read/Write request from MC
	);

	memory_dummy #(
		.OFF_WIDTH      ( `ICACHE_OFFSET_LENGTH ),
		.FILENAME_INSTR ( KERNEL_IMAGE          ),
		.ADDRESS_WIDTH  ( MEM_ADDR_w            ),
		.DATA_WIDTH     ( MEM_DATA_BLOCK_w      ),
		.MANYCORE       ( 1                     )
	)
	u_memory_dummy (
		.clk                    ( clk                    ),
		.reset                  ( reset                  ),
		//From MC
		//To Memory NI
		.n2m_request_address    ( n2m_request_address    ),
		.n2m_request_dirty_mask ( n2m_request_dirty_mask ),
		.n2m_request_data       ( n2m_request_data       ),
		.n2m_request_read       ( n2m_request_read       ),
		.n2m_request_write      ( n2m_request_write      ),
		.mc_avail_o             ( mc_avail_o             ),
		//From Memory NI
		.m2n_request_available  ( m2n_request_available  ),
		.m2n_response_valid     ( m2n_response_valid     ),
		.m2n_response_address   ( m2n_response_address   ),
		.m2n_response_data      ( m2n_response_data      )
	);

//  -----------------------------------------------------------------------
//  -- Testbench Body
//  -----------------------------------------------------------------------

	always #(CLK_PERIOD_NS/2) clk = ~clk;

	initial begin
		setup_injection_channel( );

		#(10 * CLK_PERIOD_NS);
		reset        = 1'b0;

		#10;
		thread_en = 1'b1;

	end

//  -----------------------------------------------------------------------
//  -- TB Tasks
//  -----------------------------------------------------------------------

	task setup_injection_channel;

		/*
			This task sets up the injection channel with the Noc Tiles 00 and 01, wiring the signals that drive the Cache Controller.
			It also links the signals used by the LDST unit to handle the stall logic
		*/

		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_instruction_inject = t_00_ldst_instruction_inject;
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_address_inject 	 = t_00_ldst_address_inject;
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_miss_inject        = t_00_ldst_miss_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_evict_inject       = t_00_ldst_evict_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_cache_line_inject  = t_00_ldst_cache_line_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_flush_inject       = t_00_ldst_flush_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_dinv_inject        = t_00_ldst_dinv_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.ldst_dirty_mask_inject  = t_00_ldst_dirty_mask_inject;   

		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_instruction_inject = t_01_ldst_instruction_inject;
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_address_inject 	 = t_01_ldst_address_inject;
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_miss_inject        = t_01_ldst_miss_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_evict_inject       = t_01_ldst_evict_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_cache_line_inject  = t_01_ldst_cache_line_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_flush_inject       = t_01_ldst_flush_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_dinv_inject        = t_01_ldst_dinv_inject;   
		assign u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.ldst_dirty_mask_inject  = t_01_ldst_dirty_mask_inject; 

		assign t_00_wakeup			 = u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.u_l1d_cache.cc_wakeup;
		assign t_00_wakeup_thread_id = u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[0].TILE_NPU_INST.u_tile_npu.u_l1d_cache.cc_wakeup_thread_id;

		assign t_01_wakeup			 = u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.u_l1d_cache.cc_wakeup;
		assign t_01_wakeup_thread_id = u_npu_noc.NOC_ROW_GEN[0].NOC_COL_GEN[1].TILE_NPU_INST.u_tile_npu.u_l1d_cache.cc_wakeup_thread_id;
	
		t_00_ldst_instruction_inject        = 'b0;
		t_00_ldst_address_inject            = 'b0; 
		t_00_ldst_miss_inject               = 'b0;				
		t_00_ldst_evict_inject              = 'b0;			
		t_00_ldst_cache_line_inject         = 'b0;	
		t_00_ldst_flush_inject              = 'b0;			
		t_00_ldst_dinv_inject               = 'b0;			
		t_00_ldst_dirty_mask_inject         = 64'hFFFFFFFFFFFFFFFF;	

		t_01_ldst_instruction_inject        = 'b0;
		t_01_ldst_address_inject            = 'b0;		
		t_01_ldst_miss_inject               = 'b0;				
		t_01_ldst_evict_inject              = 'b0;			
		t_01_ldst_cache_line_inject         = 'b0;	
		t_01_ldst_flush_inject              = 'b0;			
		t_01_ldst_dinv_inject               = 'b0;			
		t_01_ldst_dirty_mask_inject         = 64'hFFFFFFFFFFFFFFFF;

	endtask

	task submit_request(
		input tb_coherence_request_t 			coherence_request
	);

	/*
		This task generates and submits a coherence request to a cache controller:
			- request_type		Indicates the type of the request. See tb_request_type_t struct for further details.
			- address			Indicates the address to which submit the request.
			- cache_line		Input requested by REPLACEMENT-FLUSH-DINV request (see Core Interface for further details)
			- requestor			Indicates the tile and the thread id that is submitting the request
			- dirty_mask		Used only in non-coherent transactions
	*/

		//automatic variables are placed on the stack, so they are de-allocated when the task ends.
        automatic instruction_decoded_t 	ldst_instruction;   
		automatic dcache_address_t 			ldst_address;
		automatic logic 					ldst_miss = 1'b0;               				
		automatic logic 					ldst_evict= 1'b0;              			
		automatic dcache_line_t				ldst_cache_line;         
		automatic logic 					ldst_flush= 1'b0;              			
		automatic logic 					ldst_dinv= 1'b0;             	
		automatic dcache_store_mask_t		ldst_dirty_mask;

		//set the correct values to the previous variables, based on the input of the task
		case(coherence_request.request_type)
			LOAD:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b1 			),
					.is_coherent	( 1'b1 			),
					.is_control		( 1'b0 			)
				);
				ldst_miss = 1'b1;
				ldst_address = coherence_request.address;
			end

			LOAD_UNCOHERENT:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b1 			),
					.is_coherent	( 1'b0 			),
					.is_control		( 1'b0 			)
				);
				ldst_miss = 1'b1;
				ldst_address = coherence_request.address;
			end

			STORE:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b0 			),
					.is_coherent	( 1'b1 			),
					.is_control		( 1'b0 			)
				);
				ldst_miss = 1'b1;
				ldst_address = coherence_request.address;
			end

			STORE_UNCOHERENT:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b0 			),
					.is_coherent	( 1'b0 			),
					.is_control		( 1'b0 			)
				);
				ldst_miss = 1'b1;
				ldst_address = coherence_request.address;
			end

			REPLACEMENT:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b0 			),
					.is_coherent	( 1'b1 			),
					.is_control		( 1'b0 			)
				);
				ldst_evict = 1'b1;
				ldst_address = coherence_request.address;
				ldst_cache_line = coherence_request.cache_line;
				ldst_dirty_mask = 64'hFFFFFFFFFFFFFFFF;
			end

			REPLACEMENT_UNCOHERENT:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b0 			),
					.is_coherent	( 1'b0 			),
					.is_control		( 1'b0 			)
				);
				ldst_evict = 1'b1;
				ldst_address = coherence_request.address;
				ldst_cache_line = coherence_request.cache_line;
				ldst_dirty_mask = coherence_request.dirty_mask;
			end

			FLUSH, FLUSH_UNCOHERENT:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ), //this will be ignored in core interface
					.is_load		( 1'b0 			),
					.is_coherent	( 1'b1 			), //flush coherence is evaluated inside cache controller
					.is_control		( 1'b1 			)
				);
				ldst_flush = 1'b1;
				ldst_address = coherence_request.address;
				ldst_cache_line = coherence_request.cache_line;
				if( coherence_request.request_type == FLUSH ) ldst_dirty_mask = 64'hFFFFFFFFFFFFFFFF;
				else                        ldst_dirty_mask = coherence_request.dirty_mask;
			end

			DINV:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b0 			),
					.is_coherent	( 1'b1 			),
					.is_control		( 1'b1 			)
				);
				ldst_dinv = 1'b1;
				ldst_address = coherence_request.address;
				ldst_cache_line = coherence_request.cache_line;
				ldst_dirty_mask = 64'hFFFFFFFFFFFFFFFF;
			end

			DINV_UNCOHERENT:
			begin
				ldst_instruction = create_new_instr(
					.tid			( coherence_request.requestor.tid ),
					.is_load		( 1'b0 			),
					.is_coherent	( 1'b0 			),
					.is_control		( 1'b1 			)
				);
				ldst_dinv = 1'b1;
				ldst_address = coherence_request.address;
				ldst_cache_line = coherence_request.cache_line;
				ldst_dirty_mask = coherence_request.dirty_mask;
			end

        endcase

		//From the parsing of the requestor, the task decides to inject the request to tile 0 or tile 1
		case(coherence_request.requestor.tile_id)
			2'b0:
			begin
				$display("[Time %t] [TESTBENCH] Trying to inject a %s request from tile #%2b - TID %1d", $time(), coherence_request.request_type.name, coherence_request.requestor.tile_id, coherence_request.requestor.tid);

				t_00_ldst_instruction_inject = ldst_instruction;
				t_00_ldst_address_inject     = ldst_address; 
				t_00_ldst_miss_inject        = ldst_miss;				
				t_00_ldst_evict_inject       = ldst_evict;			
				t_00_ldst_cache_line_inject  = ldst_cache_line;	
				t_00_ldst_flush_inject       = ldst_flush;			
				t_00_ldst_dinv_inject        = ldst_dinv;
				t_00_ldst_dirty_mask_inject  = ldst_dirty_mask;

			end

			2'b1:
			begin
				$display("[Time %t] [TESTBENCH] Trying to inject a %s request from tile #%2b - TID %1d", $time(), coherence_request.request_type.name, coherence_request.requestor.tile_id, coherence_request.requestor.tid);
				
				t_01_ldst_instruction_inject = ldst_instruction;
				t_01_ldst_address_inject     = ldst_address; 
				t_01_ldst_miss_inject        = ldst_miss;				
				t_01_ldst_evict_inject       = ldst_evict;			
				t_01_ldst_cache_line_inject  = ldst_cache_line;	
				t_01_ldst_flush_inject       = ldst_flush;			
				t_01_ldst_dinv_inject        = ldst_dinv;
				t_01_ldst_dirty_mask_inject  = ldst_dirty_mask;
				
			end

			default:
			begin
				$fatal("[Time %t] [TESTBENCH] Request injection should be done only from nu+ tiles. Trying to inject from tile #%2b", $time( ), coherence_request.requestor.tile_id);
			end
		endcase

	endtask

//  -----------------------------------------------------------------------
//  -- TB Auxiliaries Functions
//  -----------------------------------------------------------------------

    function instruction_decoded_t create_new_instr;
        input thread_id_t 	tid;
		input logic 		is_load;
		input logic 		is_coherent;
		input logic 		is_control;

		/*
			This function is used to ease the construction of a coherence request, since in this context we are interested only in
			some fields of the decoded instruction.
			This fields are:
				- thread_id			that indicates the thread id that is making the request
				- is_load			that indicates if the instruction is a load or store (ignored in other cases)
				- is_coherent		that indicates if the request will be coherent or not
				- is_control		that indicates if the request is a control instruction (should be 1 for FLUSH and DINV, 0 otherwise)
		*/

        create_new_instr = '{
            32'h400, 								//.pc (address_t)
            tid, 									//.thread_id (thread_id_t)
            1'b0, 									//.mask_enable
            1'b1,									//.is_valid
            {`REGISTER_INDEX_LENGTH{1'b0}},			//.source0 (reg_addr_t)
            {`REGISTER_INDEX_LENGTH{1'b0}},			//.source1 (reg_addr_t)
            {`REGISTER_INDEX_LENGTH{1'b0}},			//.destination (reg_addr_t)
            1'b0,									//.has_source0
            1'b0,									//.has_source1
            1'b0,									//.has_destination
            1'b0,									//.is_source0_vectorial
            1'b0,									//.is_source1_vectorial
            1'b0,									//.is_destination_vectorial
            {`IMMEDIATE_SIZE{1'b0}},				//.immediate (logic signed [`IMMEDIATE_SIZE - 1 : 0])
            1'b0,									//.is_source1_immediate
            PIPE_MEM,								//.pipe_sel (pipeline_disp_t)
            'b0,									//.op_code (opcode_t)
            1'b1,									//.is_memory_access
            is_coherent,							//.is_memory_access_coherent
            1'b0,									//.is_int
            1'b0,									//.is_fp
            is_load,								//.is_load
            1'b0,									//.is_movei
            1'b0,									//.is_branch
            1'b0,									//.is_conditional
            1'b0,									//.is_control
            1'b0,									//.is_long
            JBA										//.branch_type (branch_type_t)
        };

    endfunction

	function tb_coherence_request_t create_random_coherence_request;
		input requestor_t 		requestor;
		input dcache_address_t 	address;
		
		//request_type assignament
        automatic int req_type = STORE; //$urandom() % 8; 
        create_random_coherence_request.request_type = tb_request_type_t'(req_type);

        //requestor assignament
		create_random_coherence_request.requestor = '{ requestor.tile_id, requestor.tid };

		//address assignament
		if( address == 32'b0 ) begin
			create_random_coherence_request.address = $urandom();
		end else begin
			create_random_coherence_request.address = address;
		end

		//dirty_mask assignament
		case( create_random_coherence_request.request_type )
			LOAD, STORE, REPLACEMENT, FLUSH, DINV:
				create_random_coherence_request.dirty_mask = 64'hFFFFFFFFFFFFFFFF;
			LOAD_UNCOHERENT, STORE_UNCOHERENT, REPLACEMENT_UNCOHERENT, FLUSH_UNCOHERENT, DINV_UNCOHERENT:
			begin
				automatic int dirty_mask_l = $urandom();
				automatic int dirty_mask_r = $urandom();

				create_random_coherence_request.dirty_mask = { dirty_mask_l, dirty_mask_r };
			end

			default:
				$fatal("[Time %t] [TESTBENCH] Trying to generate invalid request type: %s", $time(), create_random_coherence_request.request_type.name);
		endcase


		//cache line assignament //FIXME: assegnare cache_line
		case( create_random_coherence_request.request_type )
		  FLUSH, REPLACEMENT, DINV, FLUSH_UNCOHERENT, REPLACEMENT_UNCOHERENT, DINV_UNCOHERENT:
			create_random_coherence_request.cache_line = 512'b0;
		  
		      
		endcase		

	endfunction

//  -----------------------------------------------------------------------
//  -- NU+ Thread Emulation Logic
//  -----------------------------------------------------------------------

	//This section emulates the 8 thread for each tile, generating coherence requests for each one.
	dcache_address_t addr_base;

	always_ff @( posedge clk ) begin : TILE0
		addr_base.index  = 0;
		addr_base.tag    = t_00_cnt + 1;//$urandom();
		addr_base.offset = 0;
		if ( ~reset & thread_en & (&t_00_stall_mask == 0) & ( t_00_cnt < TB_REQUEST_NUMBER )) begin
		
			automatic int thread_id = 0;
			while( t_00_stall_mask[thread_id] == 1'b1 )
			begin
			 	thread_id = $urandom() % 8;
				 
			end
			$display("[Time %t] [TESTBENCH] [TILE0] Thread %d was chosen", $time(), thread_id);

			if( ( thread_id < 0 ) ||  ( thread_id > 7 ) )
				$display("[Time %t] [TESTBENCH] [TILE0] Invalid thread_id: %d. Skipping generation.", $time(), thread_id);
			else
			begin
				automatic tb_coherence_request_t request = create_random_coherence_request('{ 'b0, thread_id }, addr_base);
				t_00_stall_mask[thread_id] <= 1'b1;
				submit_request (request);
				t_00_cnt++;
			end
		end else
			begin
				t_00_ldst_instruction_inject = 'b0;
				t_00_ldst_address_inject     = 32'b0; 
				t_00_ldst_miss_inject        = 1'b0;				
				t_00_ldst_evict_inject       = 1'b0;			
				t_00_ldst_cache_line_inject  = 'b0;	
				t_00_ldst_flush_inject       = 1'b0;			
				t_00_ldst_dinv_inject        = 1'b0;
				t_00_ldst_dirty_mask_inject  = 64'hFFFFFFFFFFFFFFFF;
			end
	end

	dcache_address_t addr_base1;
	always_ff @( posedge clk ) begin : TILE1
		addr_base1.index  = 0;
		addr_base1.tag    = t_01_cnt + 100; //$urandom();
		addr_base1.offset = 0;
		if ( ~reset & thread_en & (&t_01_stall_mask == 0) & (t_01_cnt < TB_REQUEST_NUMBER) ) begin
		
			automatic int thread_id = 0;
			while( t_01_stall_mask[thread_id] == 1'b1 )
			begin
			 	thread_id = $urandom() % 8;
				 
			end
			$display("[Time %t] [TESTBENCH] [TILE1] Thread %d was chosen", $time(), thread_id);

			if( ( thread_id < 0 ) ||  ( thread_id > 7 ) )
				$display("[Time %t] [TESTBENCH] [TILE1] Invalid thread_id: %d. Skipping generation.", $time(), thread_id);
			else
			begin
				automatic tb_coherence_request_t request = create_random_coherence_request('{ 'b1, thread_id }, addr_base1);
				t_01_stall_mask[thread_id] <= 1'b1;
				submit_request (request);
				t_01_cnt++;
			end
		end else
			begin
				t_01_ldst_instruction_inject = 'b0;
				t_01_ldst_address_inject     = 32'b0; 
				t_01_ldst_miss_inject        = 1'b0;				
				t_01_ldst_evict_inject       = 1'b0;			
				t_01_ldst_cache_line_inject  = 'b0;	
				t_01_ldst_flush_inject       = 1'b0;			
				t_01_ldst_dinv_inject        = 1'b0;
				t_01_ldst_dirty_mask_inject  = 64'hFFFFFFFFFFFFFFFF;
			end
	end

//  -----------------------------------------------------------------------
//  -- Thread waking up logic
//  -----------------------------------------------------------------------

	always_ff @( posedge clk ) begin : TILE0_WAKEUP
		if(t_00_wakeup)
		begin
			t_00_stall_mask[t_00_wakeup_thread_id] <= 1'b0;
			$display("[Time %t] [TESTBENCH] [TILE0] Waking up thread %d", $time(), t_00_wakeup_thread_id);
		end

	end

	always_ff @( posedge clk ) begin : TILE1_WAKEUP
		if(t_01_wakeup)
		begin
			t_01_stall_mask[t_01_wakeup_thread_id] <= 1'b0;
			$display("[Time %t] [TESTBENCH] [TILE1] Waking up thread %d", $time(), t_01_wakeup_thread_id);
		end

	end

//  -----------------------------------------------------------------------
//  -- TB Termination logic
//  -----------------------------------------------------------------------

	always_ff @(posedge clk) begin 
		if ( ( t_00_cnt == TB_REQUEST_NUMBER) && ( t_01_cnt == TB_REQUEST_NUMBER ) )
		begin
			$display("[Time %t] [TESTBENCH] Target request number reached. Tile0: %d requests. Tile 1: %d requests. Closing testbench.", $time(), t_00_cnt, t_01_cnt);
			//$finish();
		end
	end

	always_ff @(posedge clk) begin
		if ( (&t_00_stall_mask) == 1 )
			t_00_kill_cnt--;
		else
			t_00_kill_cnt = TB_DEADLOCK_THRESHOLD;
	end

	always_ff @(posedge clk) begin
		if ( (&t_01_stall_mask) == 1 )
			t_01_kill_cnt--;
		else
			t_01_kill_cnt = TB_DEADLOCK_THRESHOLD;
	end

	always_ff @(posedge clk) begin
		assert (t_00_kill_cnt > 0) 
		else   $fatal( "[Time %t] [TESTBENCH] Tile 0 seems to be in deadlock. Closing testbench", $time() );
	end

	always_ff @(posedge clk) begin
		assert (t_01_kill_cnt > 0) 
		else   $fatal( "[Time %t] [TESTBENCH] Tile 1 seems to be in deadlock. Closing testbench", $time() );
	end

//  -----------------------------------------------------------------------
//  -- TB Simulation File log
//  -----------------------------------------------------------------------

`ifdef DISPLAY_SIMULATION_LOG
	initial sim_log_file = $fopen ( `DISPLAY_SIMULATION_LOG_FILE, "wb" ) ;

	final $fclose ( sim_log_file ) ;
`endif

`ifdef DISPLAY_CORE
	int core_file;
	initial core_file = $fopen( `DISPLAY_CORE_FILE, "wb" );
	final 	$fclose( core_file );
`endif

`ifdef DISPLAY_LDST
	int ldst_file;
	initial ldst_file = $fopen( `DISPLAY_LDST_FILE, "wb" );
	final 	$fclose( ldst_file );
`endif

`ifdef DISPLAY_COHERENCE
	int coherence_file;
	initial coherence_file = $fopen( `DISPLAY_COHERENCE_FILE, "wb" );
	final $fclose( coherence_file );
`endif

`ifdef DISPLAY_SYNC
	int barrier_file;
	initial barrier_file = $fopen( `DISPLAY_BARRIER_FILE, "w" );
	final $fclose( barrier_file );

	int sync_file;
	initial sync_file = $fopen( `DISPLAY_SYNC_FILE, "w" );
	final $fclose( sync_file );

`ifdef PERFORMANCE_SYNC
	int perf_sync_perf;
	initial perf_sync_perf = $fopen( `DISPLAY_SYNC_PERF_FILE, "w" );
	final $fclose( perf_sync_perf );
`endif
`endif

`ifdef DISPLAY_REQUESTS_MANAGER
	int requests_file;
	initial requests_file = $fopen( `DISPLAY_REQ_MANAGER_FILE, "w" );
	final $fclose( requests_file );
`endif

`ifdef DISPLAY_IO
	int io_file;
	initial io_file = $fopen( `DISPLAY_IO_FILE, "w" );
	final $fclose( io_file );
`endif

endmodule
