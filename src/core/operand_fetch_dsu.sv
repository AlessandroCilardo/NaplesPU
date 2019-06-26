`timescale 1ns / 1ps
`include "npu_user_defines.sv"
`include "npu_defines.sv"

/*
 * Operand_fetch module contains two register files: a scalar register file (SRF) and a vector register file (VRF).
 * A SRF register size is `REGISTER_SIZE bits (default 32), a VRF register size is scalar register file for each
 * hardware lane (`REGISTER_SIZE x `HW_LANE, default 32 bit x 16 hw lane). Both, SRF and VRF, have same register
 * number (`REGISTER_NUMBER define in npu_define.sv).
 *
 * Each thread has its own register file, this is done allocating a bigger SRAM (REGISTER_NUMBER x `THREAD_NUMB).
 *
 * When a masked instruction is issued, register `MASK_REG (default scalar register $60) is stores in opf_fecthed_mask.
 * When source 1 is immediate, its value is replied on each vector element.
 * Memory access and branch operation require a base address. In both cases Decode module maps base address in source0.
 *
 */

module operand_fetch_dsu (
		input                                                    clk,
		input                                                    reset,
		input                                                    enable,                  //this signal is also used to change the mux mode of the registers

		// Interface with Instruction Scheduler Module (Issue)
		input                                                    issue_valid,
		input  thread_id_t                                       issue_thread_id,
		input  instruction_decoded_t                             issue_inst_scheduled,
		input  scoreboard_t                                      issue_destination_bitmap,

		// Interface with Rollback Handler
		input                        [`THREAD_NUMB - 1 : 0]      rollback_valid,

		// Interface with Writeback Module
		input                                                    wb_valid,
		input  thread_id_t                                       wb_thread_id,
		input  wb_result_t                                       wb_result,

		//Interface with DSU
		input  logic                                             dsu_en_vector,
		input  logic                                             dsu_en_scalar,
		input  logic                                             dsu_start_shift,
		input  logic                 [`REGISTER_ADDRESS - 1 : 0] dsu_reg_addr,
		input  logic                                             dsu_load_shift_reg,
		input  logic                                             dsu_write_scalar,
		input  logic                                             dsu_write_vector,
		input  logic                                             dsu_serial_reg_in,
		output logic                                             dsu_serial_reg_out,
		output logic                                             dsu_stop_shift,

		// To Execution Pipes
		output logic                                             opf_valid,
		output instruction_decoded_t                             opf_inst_scheduled,
		output hw_lane_t                                         opf_fecthed_op0,
		output hw_lane_t                                         opf_fecthed_op1,
		output hw_lane_mask_t                                    opf_hw_lane_mask,
		output scoreboard_t                                      opf_destination_bitmap

	//TODO: Insert interface from/to debugger
	);

	typedef logic [`BYTE_PER_REGISTER - 1 : 0] byte_width_t;
	typedef byte_width_t [`HW_LANE - 1 : 0] lane_byte_width_t;

	logic                                             next_valid;
	thread_id_t                                       next_issue_thread_id;
	instruction_decoded_t                             next_issue_inst_scheduled;
	reg_addr_t                                        next_source0;
	reg_addr_t                                        next_source1;
	address_t                                         next_pc;

	// Scalar RF signals
	logic                                             rd_en0_scalar, rd_en1_scalar, wr_en_scalar;
	register_t                                        rd_out0_scalar, rd_out1_scalar, rd_data_scalar, dsu_rd_data_scalar;
	//logic [`REGISTER_SIZE + 3 : 0]dsu_wr_data_scalar; //i primi 4 bit servono per la maschera dei byte da scrivere nel registro scalare, gli altri sono il dato scalare
	reg_addr_t                                        rd_src1_eff_addr;
	logic                                             dsu_scalar_out;
	logic                                             dsu_stop_vector_shift, dsu_stop_scalar_shift;

	// Vector RF signals
	logic                                             rd_en0_vector, rd_en1_vector, wr_en_vector;
	hw_lane_t                                         rd_out0_vector, rd_out1_vector, rd_data_vector, dsu_rd_data_vector;
	//logic [`REGISTER_SIZE * `HW_LANE + 15 : 0]dsu_wr_data_vector; //i primi 16 bit servono per la maschera dei byte da scrivere nel registro vettoriale, gli altri sono il dato vettoriale
	logic                                             dsu_vector_out;

	logic                 [`REGISTER_ADDRESS - 1 : 0] reg_address;
	logic                                             en_read_vector;

	scoreboard_t                                      next_opf_destination_bitmap;
	hw_lane_mask_t                                    opf_hw_lane_mask_buff;
	hw_lane_t                                         opf_fecthed_op0_buff;
	hw_lane_t                                         opf_fecthed_op1_buff;

	lane_byte_width_t                                 write_en_byte;
	//lane_byte_width_t     dsu_write_en_vector;
	//logic [`BYTE_PER_REGISTER - 1 : 0] dsu_write_en_scalar;

	//assign dsu_write_en_scalar = dsu_wr_data_scalar[`REGISTER_SIZE + `BYTE_PER_REGISTER - 1 : `REGISTER_SIZE ];
	//assign dsu_write_en_vector = dsu_wr_data_vector[(`REGISTER_SIZE + `BYTE_PER_REGISTER - 2) * (`HW_LANE -1) : `REGISTER_SIZE * `HW_LANE ];
//  -----------------------------------------------------------------------
//  -- Register Files read - 1 Stage
//  -----------------------------------------------------------------------

	genvar                                            lane_id;
	generate
		for ( lane_id = 0; lane_id < `HW_LANE; lane_id ++ ) begin : LANE_WRITE_EN
			// This for-generate calculates the write enable for each HW lane. The HW lane mask signal
			// handles which lane is affected by the current operation. Each vector register has a
			// byte wise write enable. In case of moveh and movel just half word has to be written,
			// the other half word has no changes.
			assign write_en_byte[lane_id] = wb_result.wb_result_write_byte_enable &
				{( `BYTE_PER_REGISTER ){wb_result.wb_result_hw_lane_mask[lane_id] & wr_en_vector}};//(~enable) ? dsu_write_en_vector;
		end
	endgenerate

	// Vector RF
	memory_bank_2r1w #(
		.SIZE   ( `REGISTER_NUMBER * `THREAD_NUMB ),
		.NB_COL ( `BYTE_PER_REGISTER * `HW_LANE   )
	)
	vector_reg_file (
		.clock        ( clk                                             ),

		.read1_enable ( rd_en0_vector                                   ),
		.read1_address( {issue_thread_id, issue_inst_scheduled.source0} ),
		.read1_data   ( rd_out0_vector                                  ),

		.read2_enable ( rd_en1_vector                                   ),
		.read2_address( reg_address                                     ),
		.read2_data   ( rd_data_vector                                  ),

		.write_enable ( write_en_byte                                   ),
		.write_address( {wb_thread_id, wb_result.wb_result_register}    ),
		.write_data   ( wb_result.wb_result_data                        )

//      .write_enable ( write_en_byte                                   ),
//      .write_address( (enable) ? {wb_thread_id, wb_result.wb_result_register} : reg_address ),
//      .write_data   ( (enable) ? wb_result.wb_result_data : dsu_wr_data_vector[`REGISTER_NUMBER * `HW_LANE - 1 : 0] )
	);

	assign rd_en0_vector         = issue_valid && issue_inst_scheduled.is_source0_vectorial;
	assign wr_en_vector          = wb_valid && !wb_result.wb_result_is_scalar;

	// Scalar RF
	memory_bank_2r1w #(
		.SIZE   ( `REGISTER_NUMBER * `THREAD_NUMB ),
		.NB_COL ( `BYTE_PER_REGISTER              )
	)
	scalar_reg_file (
		.clock        ( clk                                                                            ),

		.read1_enable ( rd_en0_scalar                                                                  ),
		.read1_address( {issue_thread_id, issue_inst_scheduled.source0}                                ),
		.read1_data   ( rd_out0_scalar                                                                 ),

		.read2_enable ( rd_en1_scalar                                                                  ),
		.read2_address( {issue_thread_id, rd_src1_eff_addr}                                            ),
		.read2_data   ( rd_data_scalar                                                                 ),

		.write_enable ( wb_result.wb_result_write_byte_enable & {( `BYTE_PER_REGISTER ){wr_en_scalar}} ),
		.write_address( {wb_thread_id, wb_result.wb_result_register}                                   ),
		.write_data   ( wb_result.wb_result_data[0]                                                    )

//      .write_enable ( (enable) ? wb_result.wb_result_write_byte_enable & {( `BYTE_PER_REGISTER ){wr_en_scalar}} : dsu_write_en_scalar),
//      .write_address( (enable) ? {wb_thread_id, wb_result.wb_result_register} : reg_address          ),
//      .write_data   ( (enable) ? wb_result.wb_result_data[0] : dsu_wr_data_scalar[`REGISTER_NUMBER - 1 : 0] )
	);

	assign rd_en0_scalar         = issue_valid && !issue_inst_scheduled.is_source0_vectorial;
	assign wr_en_scalar          = wb_valid && wb_result.wb_result_is_scalar;

	// We support a fixed lane mask register. If an instruction is masked, we statically load the mask register.
	assign rd_src1_eff_addr      = ( issue_inst_scheduled.mask_enable ) ? `MASK_REG                             : issue_inst_scheduled.source1;


	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset )
			next_valid                  <= 1'b0;
		else if ( enable ) begin
			next_valid                  <= issue_valid & ~rollback_valid[issue_thread_id];
			next_issue_thread_id        <= issue_thread_id;
			next_issue_inst_scheduled   <= issue_inst_scheduled;
			next_opf_destination_bitmap <= issue_destination_bitmap;
			next_source0                <= issue_inst_scheduled.source0;
			next_source1                <= issue_inst_scheduled.source1;
			next_pc                     <= issue_inst_scheduled.pc;
		end
	end

//  -----------------------------------------------------------------------
//  -- Multiplexer from normal to debug mode and serializer- 1 Stage
//  -----------------------------------------------------------------------
	always_comb begin
		if ( enable ) begin
			//Read
			rd_en1_vector      = issue_valid && issue_inst_scheduled.is_source1_vectorial;
			rd_en1_scalar      = issue_valid && ( !issue_inst_scheduled.is_source1_vectorial | issue_inst_scheduled.mask_enable );
			rd_out1_vector     = rd_data_vector;
			rd_out1_scalar     = rd_data_scalar;
			dsu_rd_data_vector = hw_lane_t'( 1'b0 );
			dsu_rd_data_scalar = register_t'( 1'b0 );
			if( rd_en1_vector )
				reg_address = {issue_thread_id, issue_inst_scheduled.source1};
			else if( rd_en1_scalar )
				reg_address = {issue_thread_id, rd_src1_eff_addr};
			else
				reg_address = {`REGISTER_ADDRESS{1'b0}};
		end else begin
			//Read
			rd_en1_vector      = dsu_en_vector;
			rd_en1_scalar      = dsu_en_scalar;
			rd_out1_vector     = hw_lane_t'( 1'b0 );
			rd_out1_scalar     = register_t'( 1'b0 );
			dsu_rd_data_vector = rd_data_vector;
			dsu_rd_data_scalar = rd_data_scalar;
			reg_address        = dsu_reg_addr;
		end
	end

	always_ff @ ( posedge clk, posedge reset ) begin
		if ( reset ) begin
			en_read_vector <= 1'b0;
		end else if( ~enable ) begin
			if( rd_en1_vector )
				en_read_vector <= 1'b1;
			else if( rd_en1_scalar )
				en_read_vector <= 1'b0;
		end else begin
			en_read_vector <= 1'b0;
		end
	end

	serializer # (
		.REG_SIZE ( `REGISTER_SIZE )
	)
	scalar_serializer (
		.clk         ( clk                   ) ,
		.reset       ( reset                 ) ,
		.data_in     ( dsu_rd_data_scalar    ) ,
		.data_out    ( dsu_scalar_out        ) ,
		.load        ( dsu_load_shift_reg    ) ,
		.start_shift ( dsu_start_shift       ) ,
		.stop_shift  ( dsu_stop_scalar_shift )
	) ;

	serializer # (
		.REG_SIZE ( `REGISTER_SIZE * `HW_LANE )
	)
	vecror_serializer (
		.clk         ( clk                   ) ,
		.reset       ( reset                 ) ,
		.data_in     ( dsu_rd_data_vector    ) ,
		.data_out    ( dsu_vector_out        ) ,
		.load        ( dsu_load_shift_reg    ) ,
		.start_shift ( dsu_start_shift       ) ,
		.stop_shift  ( dsu_stop_vector_shift )
	) ;


//  deserializer # (
//      .REG_SIZE (`REGISTER_SIZE + `BYTE_PER_REGISTER)
//  )
//  scalar_deserializer   (
//      .clk         (clk                  ) ,
//      .reset       (reset                ) ,
//      .enable      (dsu_write_scalar     ) ,
//      .data_in     (dsu_serial_reg_in    ) ,
//      .start_shift (dsu_start_shift      ) ,
//      .data_out    (dsu_wr_data_scalar   )
//      ) ;
//
//  deserializer # (
//      .REG_SIZE ((`REGISTER_SIZE + `BYTE_PER_REGISTER) * `HW_LANE )
//  )
//  vector_deserializer   (
//      .clk         (clk                  ) ,
//      .reset       (reset                ) ,
//      .enable      (dsu_write_vector     ) ,
//      .data_in     (dsu_serial_reg_in    ) ,
//      .start_shift (dsu_start_shift      ) ,
//      .data_out    (dsu_wr_data_vector   )
//  ) ;

	assign dsu_serial_reg_out    = en_read_vector ? dsu_vector_out                                              : dsu_scalar_out;
	assign dsu_stop_shift        = en_read_vector ? dsu_stop_vector_shift                                       : dsu_stop_scalar_shift;

//  -----------------------------------------------------------------------
//  -- Operand Fetch - 2 Stage
//  -----------------------------------------------------------------------

	// Load lane mask register. If the current instruction is not masked the mask is set to all 1
	assign opf_hw_lane_mask_buff = ( next_issue_inst_scheduled.mask_enable ) ? rd_out1_scalar[`HW_LANE - 1 : 0] : {`HW_LANE{1'b1}};

	always_comb begin
		// Operand 0 - Memory access and branch operation require a base address.
		// In both cases Decode module maps base address in source0. Otherwise
		// operand 0 holds the value from the required register file.
		if ( next_issue_inst_scheduled.is_source0_vectorial )
			opf_fecthed_op0_buff <= rd_out0_vector;
		else
			if ( next_source0 == `PC_REG ) begin
				if ( next_issue_inst_scheduled.is_memory_access )
					opf_fecthed_op0_buff <= next_pc + register_t'( next_issue_inst_scheduled.immediate );
				else
					opf_fecthed_op0_buff <= {`HW_LANE{next_pc}};
			end else if ( next_issue_inst_scheduled.is_memory_access ) begin
				// In case of memory access, opf_fecthed_op0 holds the effective memory address
				opf_fecthed_op0_buff <= {`HW_LANE{rd_out0_scalar + register_t'( next_issue_inst_scheduled.immediate )}};
			end else
				opf_fecthed_op0_buff <= {`HW_LANE{rd_out0_scalar}};

		// Operand 1 - If the current instruction has in immediate, this is replicated
		// on each vector element of operand 1. Otherwise operand 1 holds the value from
		// the required register file.
		if ( next_issue_inst_scheduled.is_source1_immediate )
			opf_fecthed_op1_buff <= {`HW_LANE{next_issue_inst_scheduled.immediate}};
		else if( next_issue_inst_scheduled.is_source1_vectorial )
			opf_fecthed_op1_buff <= rd_out1_vector;
		else
			if ( next_source1 == `PC_REG )
				opf_fecthed_op1_buff <= {`HW_LANE{next_pc}};
			else
				opf_fecthed_op1_buff <= {`HW_LANE{rd_out1_scalar}};
	end

	always_ff @ ( posedge clk, posedge reset )
		if ( reset )
			opf_valid <= 1'b0;
		else if ( enable ) begin
			opf_valid <= next_valid & ~rollback_valid[next_issue_thread_id];
		end

	always_ff @ ( posedge clk ) begin
		if ( enable ) begin
			opf_inst_scheduled     <= next_issue_inst_scheduled;
			opf_destination_bitmap <= next_opf_destination_bitmap;
			opf_hw_lane_mask       <= opf_hw_lane_mask_buff;
			opf_fecthed_op0        <= opf_fecthed_op0_buff;
			opf_fecthed_op1        <= opf_fecthed_op1_buff;
		end
	end

endmodule
