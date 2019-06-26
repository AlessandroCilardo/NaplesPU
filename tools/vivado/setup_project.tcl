set projRoot [pwd]

create_project -force npu -part xc7a100tcsg324-1 $projRoot/tools/vivado/project

add_files $projRoot/src/
remove_files */deploy/*
remove_files */dsu/*
remove_files *_dsu.sv*
set_property file_type {Verilog Header} [get_files *src/include/*.sv]

if { $argc == 4 } {
	set kernelName [lindex $argv 0]
	set threadMask [lindex $argv 1]
	set coreMask [lindex $argv 2]
	set singleCore [lindex $argv 3]
} else {
	puts stderr "Wrong number of arguments"
	exit 1
}

set kernelImage $kernelName
append kernelImage "_mem.hex"
set kernelPath "software/kernels/"
append kernelPath $kernelName "/obj/" $kernelImage

add_files $kernelPath
set_property file_type {Memory Initialization Files} [get_files *_mem.hex]
set_property top npu_noc [current_fileset]

set_property top tb_npu [current_fileset -simset]
set_property generic "KERNEL_IMAGE=$kernelImage CORE_MASK=$coreMask THREAD_MASK=$threadMask" [current_fileset -simset]
set projDefines "SIMULATION PROJECT_PATH=\"$projRoot/\" KERNEL_NAME=\"$kernelName\""
if { $singleCore == "yes" } {
	append projDefines " SINGLE_CORE"
}
set_property verilog_define "$projDefines" [current_fileset -simset]

launch_simulation
run all
