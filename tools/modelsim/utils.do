proc AddNuPlus {row col} {
	view wave -new -title "TILE_$row\_$col"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col"              -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE"        -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_TC"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_thread_controller/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_IF"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_instruction_fetch_stage/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_DECODE" -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_decode/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_IB"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_instruction_buffer/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_IS"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_instruction_scheduler/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_OF"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_operand_fetch/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_INT"    -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_int_pipe/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_CR"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_control_register/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_BRC"    -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_branch_control/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_FP"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_fp_pipe/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_SPM"    -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_scratchpad_memory_pipe/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_RH"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_rollback_handler/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_BC"     -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_barrier_core/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_LDST"   -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_load_store_unit/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_LDST1"  -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_load_store_unit/u_load_store_unit_stage1/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_LDST2"  -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_load_store_unit/u_load_store_unit_stage2/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CORE_LDST3"  -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_nuplus_core/u_load_store_unit/u_load_store_unit_stage3/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CI"          -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_l1d_cache/u_core_interface/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CC"          -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_l1d_cache/u_cache_controller/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CC1"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_l1d_cache/u_cache_controller/u_cache_controller_stage1/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CC2"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_l1d_cache/u_cache_controller/u_cache_controller_stage2/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CC3"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_l1d_cache/u_cache_controller/u_cache_controller_stage3/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_CC4"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_l1d_cache/u_cache_controller/u_cache_controller_stage4/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_DC"          -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_directory_controller/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_DC1"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_directory_controller/u_directory_controller_stage1/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_DC2"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_directory_controller/u_directory_controller_stage2/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_DC3"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_directory_controller/u_directory_controller_stage3/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_SC"          -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_synchronization_core/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_SC1"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_synchronization_core/Stage1/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_SC2"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_synchronization_core/Stage2/*"
	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_SC3"         -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_synchronization_core/Stage3/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_IO"          -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_io_intf/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_SS"          -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_c2n_service_scheduler/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_NI"          -window "TILE_$row\_$col" -position end "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_network_interface_core/*"

	add wave -allowconstants -noupdate -group "TILE_$row\_$col\_ROUTER"      -window "TILE_$row\_$col" -position end -ports "sim:/tb_nuplus/u_nuplus_noc/NOC_ROW_GEN\[$row\]/NOC_COL_GEN\[$col\]/TILE_NUPLUS_INST/u_tile_nuplus/u_router/*"
}

proc AddH2C {row col} {
}

proc AddMC {row col} {
}

proc AddSC {} {
	view wave -new -title "SINGLE_CORE"

	add wave -allowconstants -noupdate -group "SYSTEM"      -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/*"

	add wave -allowconstants -noupdate -group "H2C"         -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/h2c_control_unit/*"

	add wave -allowconstants -noupdate -group "CORE"        -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/*"
	add wave -allowconstants -noupdate -group "CORE_TC"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_thread_controller/*"
	add wave -allowconstants -noupdate -group "CORE_IF"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_instruction_fetch_stage/*"
	add wave -allowconstants -noupdate -group "CORE_DECODE" -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_decode/*"
	add wave -allowconstants -noupdate -group "CORE_IB"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_instruction_buffer/*"
	add wave -allowconstants -noupdate -group "CORE_IS"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_instruction_scheduler/*"
	add wave -allowconstants -noupdate -group "CORE_OF"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_operand_fetch/*"
	add wave -allowconstants -noupdate -group "CORE_INT"    -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_int_pipe/*"
	add wave -allowconstants -noupdate -group "CORE_CR"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_control_register/*"
	add wave -allowconstants -noupdate -group "CORE_BRC"    -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_branch_control/*"
	add wave -allowconstants -noupdate -group "CORE_FP"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_fp_pipe/*"
	add wave -allowconstants -noupdate -group "CORE_SPM"    -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_scratchpad_memory_pipe/*"
	add wave -allowconstants -noupdate -group "CORE_RB"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_rollback_handler/*"
	add wave -allowconstants -noupdate -group "CORE_BC"     -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_barrier_core/*"
	add wave -allowconstants -noupdate -group "CORE_LDST"   -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_load_store_unit/*"
	add wave -allowconstants -noupdate -group "CORE_LDST1"  -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_load_store_unit/u_load_store_unit_stage1/*"
	add wave -allowconstants -noupdate -group "CORE_LDST2"  -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_load_store_unit/u_load_store_unit_stage2/*"
	add wave -allowconstants -noupdate -group "CORE_LDST3"  -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/nuplus_core/u_load_store_unit/u_load_store_unit_stage3/*"

	add wave -allowconstants -noupdate -group "CI"          -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/u_core_interface/*"

	add wave -allowconstants -noupdate -group "CC"          -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/u_sc_cache_controller/*"

	add wave -allowconstants -noupdate -group "SC"          -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/u_synchronization_core/*"
	add wave -allowconstants -noupdate -group "SC1"         -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/u_synchronization_core/Stage1/*"
	add wave -allowconstants -noupdate -group "SC2"         -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/u_synchronization_core/Stage2/*"
	add wave -allowconstants -noupdate -group "SC3"         -window "SINGLE_CORE" -position end "sim:/tb_nuplus/nuplus_system/u_synchronization_core/Stage3/*"
}
