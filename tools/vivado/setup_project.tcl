#        Copyright 2019 NaplesPU
#   
#   	 
#   Redistribution and use in source and binary forms, with or without modification,
#   are permitted provided that the following conditions are met:
#   
#   1. Redistributions of source code must retain the above copyright notice,
#      this list of conditions and the following disclaimer.
#   
#   2. Redistributions in binary form must reproduce the above copyright notice,
#      this list of conditions and the following disclaimer in the documentation
#      and/or other materials provided with the distribution.
#   
#   3. Neither the name of the copyright holder nor the names of its contributors
#      may be used to endorse or promote products derived from this software
#      without specific prior written permission.
#   
#      
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
#   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
#   IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
#   INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#   BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#   DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
#   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
#   OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
#   OF THE POSSIBILITY OF SUCH DAMAGE.

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
