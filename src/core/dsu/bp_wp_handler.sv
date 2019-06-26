`include "npu_defines.sv"

module bp_wp_handler (

		input    address_t             [7 : 0]                  dsu_breakpoint,
		input    logic                 [7 : 0]					dsu_breakpoint_enable,
		input    logic											dsu_single_step,

		//From Instruction Scheduler
		input    logic                                           is_instruction_valid,
		input    instruction_decoded_t 						     is_instruction,
		
		output   logic                 [`THREAD_NUMB - 1 : 0]   dsu_breakpoint_detected
	) ;


	assign dsu_breakpoint_detected = ((
							 (dsu_breakpoint[7]==is_instruction.pc && dsu_breakpoint_enable[7])
                          || (dsu_breakpoint[6]==is_instruction.pc && dsu_breakpoint_enable[6])
                          || (dsu_breakpoint[5]==is_instruction.pc && dsu_breakpoint_enable[5])
                          || (dsu_breakpoint[4]==is_instruction.pc && dsu_breakpoint_enable[4])
                          || (dsu_breakpoint[3]==is_instruction.pc && dsu_breakpoint_enable[3])
                          || (dsu_breakpoint[2]==is_instruction.pc && dsu_breakpoint_enable[2])
                          || (dsu_breakpoint[1]==is_instruction.pc && dsu_breakpoint_enable[1])
                          || (dsu_breakpoint[0]==is_instruction.pc && dsu_breakpoint_enable[0])) 
						  || dsu_single_step) && is_instruction_valid;

//	assign dsu_breakpoint_detected = (((
//							 (dsu_breakpoint[7]==is_instruction.pc)
//                          || (dsu_breakpoint[6]==is_instruction.pc)
//                          || (dsu_breakpoint[5]==is_instruction.pc)
//                          || (dsu_breakpoint[4]==is_instruction.pc)
//                          || (dsu_breakpoint[3]==is_instruction.pc)
//                          || (dsu_breakpoint[2]==is_instruction.pc)
//                          || (dsu_breakpoint[1]==is_instruction.pc)
//                          || (dsu_breakpoint[0]==is_instruction.pc) )
//                      && dsu_breakpoint_enable) || dsu_single_step) && is_instruction_valid;
endmodule
