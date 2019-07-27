#!/bin/bash

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

set -e

. tools/sim/common.sh

if [[ "$SINGLE_CORE" == "yes" ]]; then
	ADDITIONAL_CFLAGS="+define+SINGLE_CORE"
fi

TOP="tb_npu"

if [[ "$TOOL_MODE" == "batch" ]]; then
	TOOL_MODE="-c"
else
        TOOL_MODE=''
fi

PROJECT_PATH=`pwd`/
COMPILE_FLAGS="+define+SIMULATION +define+PROJECT_PATH=\"$PROJECT_PATH\" +define+KERNEL_NAME=\"$KERNEL_NAME\" $ADDITIONAL_CFLAGS -suppress 2583"

cd tools/modelsim

vlib work

vlog $COMPILE_FLAGS -sv "+incdir+../../src/include" "+incdir+../../src/include" \
"../../src/common/priority_encoder_npu.sv" \
"../../src/common/memory_bank_async_2r1w.sv" \
"../../src/common/oh_to_idx.sv" \
"../../src/common/memory_bank_1r1w.sv" \
"../../src/core/scratchpad_memory/memory_bank.sv" \
"../../src/core/scratchpad_memory/bank_steering_unit.sv" \
"../../src/core/scratchpad_memory/broadcast_selection.sv" \
"../../src/core/scratchpad_memory/address_decode_unit.sv" \
"../../src/core/scratchpad_memory/decision_logic.sv" \
"../../src/core/scratchpad_memory/conflict_detection.sv" \
"../../src/mc/cache_controller/mshr_cc.sv" \
"../../src/mc/cache_controller/cc_protocol_rom.sv" \
"../../src/mc/cache_controller/stall_protocol_rom.sv" \
"../../src/common/memory_bank_2r1w.sv" \
"../../src/common/tree_plru.sv" \
"../../src/common/round_robin_arbiter.sv" \
"../../src/common/sync_fifo.sv" \
"../../src/common/idx_to_oh.sv" \
"../../src/core/scratchpad_memory/address_remapping_unit.sv" \
"../../src/core/scratchpad_memory/banked_memory.sv" \
"../../src/core/scratchpad_memory/requests_issue_unit.sv" \
"../../src/core/scratchpad_memory/address_conflict_logic.sv" \
"../../src/core/scratchpad_memory/input_interconnect.sv" \
"../../src/core/scratchpad_memory/output_interconnect.sv" \
"../../src/mc/cache_controller/cache_controller_stage1.sv" \
"../../src/mc/cache_controller/cache_controller_stage3.sv" \
"../../src/mc/cache_controller/cache_controller_stage4.sv" \
"../../src/mc/cache_controller/cache_controller_stage2.sv" \
"../../src/mc/cache_controller/l1d_cache.sv" \
"../../src/mc/network_interface/routing_xy.sv" \
"../../src/core/load_store_unit_stage1.sv" \
"../../src/core/load_store_unit_stage2.sv" \
"../../src/ht/load_store_unit_stage1_par.sv" \
"../../src/ht/load_store_unit_stage2_par.sv" \
"../../src/ht/load_store_unit_stage3_par.sv" \

vcom -93 \
"../../src/core/fpu/flopoco.vhdl" \
"../../src/core/fpu/flopoco_add_mult.vhdl" \

vlog $COMPILE_FLAGS "+incdir+../../src/include" "+incdir+../../src/include" \
"../../src/core/fpu/fp_addsub_pipeline.v" \

vlog $COMPILE_FLAGS -sv "+incdir+../../src/include" "+incdir+../../src/include" \
"../../src/core/load_store_unit_stage3.sv" \
"../../src/core/scratchpad_memory/scratchpad_memory_stage3.sv" \
"../../src/core/scratchpad_memory/scratchpad_memory_stage2.sv" \
"../../src/core/scratchpad_memory/scratchpad_memory_stage1.sv" \
"../../src/mc/router/grant_hold_round_robin_arbiter.sv" \
"../../src/mc/router/mux_npu.sv" \
"../../src/mc/cache_controller/cache_controller.sv" \
"../../src/mc/network_interface/control_unit_flit_to_packet.sv" \
"../../src/mc/network_interface/control_unit_packet_to_flit.sv" \
"../../src/mc/directory_controller/directory_protocol_rom.sv" \
"../../src/mc/directory_controller/dc_stall_protocol_rom.sv" \
"../../src/core/load_store_unit.sv" \
"../../src/ht/load_store_unit_par.sv" \
"../../src/core/int_single_lane.sv" \
"../../src/core/dsu/bp_wp_handler.sv" \
"../../src/core/instruction_fetch_stage.sv" \
"../../src/core/core_interface.sv" \
"../../src/core/fpu/fp_dp_fp2fix.sv" \
"../../src/core/fpu/fp_dp_mult.sv" \
"../../src/core/fpu/fp_addsub.sv" \

vlog $COMPILE_FLAGS -sv "+incdir+../../src/include" "+incdir+../../src/include" \
"../../src/core/fpu/fp_dp_div.sv" \
"../../src/core/fpu/fp_dp_addsub.sv" \
"../../src/core/fpu/fp_mult.sv" \

vlog $COMPILE_FLAGS -sv "+incdir+../../src/include" "+incdir+../../src/include" \
"../../src/core/fpu/fp_ftoi.sv" \
"../../src/core/fpu/fp_dp_fix2fp.sv" \
"../../src/core/fpu/fp_itof.sv" \
"../../src/core/fpu/fp_div.sv" \
"../../src/core/load_miss_queue.sv" \
"../../src/core/scratchpad_memory/scratchpad_memory.sv" \
"../../src/mc/router/input_port.sv" \
"../../src/mc/router/crossbar.sv" \
"../../src/mc/router/look_ahead_routing.sv" \
"../../src/mc/router/allocator_core.sv" \
"../../src/mc/network_interface/virtual_network_net_to_core.sv" \
"../../src/mc/network_interface/virtual_network_core_to_net.sv" \
"../../src/mc/directory_controller/l2_tshr.sv" \
"../../src/mc/directory_controller/directory_controller_stage2.sv" \
"../../src/mc/directory_controller/directory_controller_stage1.sv" \
"../../src/mc/directory_controller/directory_controller_stage3.sv" \
"../../src/mc/synchronization/synchronization_core_stage1.sv" \
"../../src/mc/synchronization/barrier_core.sv" \
"../../src/mc/synchronization/synchronization_core_stage2.sv" \
"../../src/mc/synchronization/synchronization_core_stage3.sv" \
"../../src/core/thread_controller.sv" \
"../../src/core/operand_fetch.sv" \
"../../src/core/decode.sv" \
"../../src/core/dsu/debug_controller.sv" \
"../../src/core/writeback.sv" \
"../../src/core/fp_pipe.sv" \
"../../src/core/branch_control.sv" \
"../../src/core/control_register.sv" \
"../../src/core/rollback_handler.sv" \
"../../src/core/instruction_scheduler.sv" \
"../../src/core/instruction_buffer.sv" \
"../../src/core/int_pipe.sv" \
"../../src/core/scratchpad_memory/scratchpad_memory_pipe.sv" \
"../../src/mc/router/router.sv" \
"../../src/mc/system/npu2memory.sv" \
"../../src/mc/network_interface/network_interface_core.sv" \
"../../src/mc/service_support/boot_manager.sv" \
"../../src/mc/service_support/io_interface.sv" \
"../../src/mc/directory_controller/directory_controller.sv" \
"../../src/mc/synchronization/synchronization_core.sv" \
"../../src/mc/synchronization/c2n_service_scheduler.sv" \
"../../src/core/npu_core.sv" \
"../../src/mc/tile/tile_mc.sv" \
"../../src/mc/tile/tile_h2c.sv" \
"../../src/mc/tile/tile_none.sv" \
"../../src/mc/tile/tile_npu.sv" \
"../../src/mc/tile/tile_ht.sv" \
"../../src/tb/memory_dummy.sv" \
"../../src/mc/system/npu_noc.sv" \
"../../src/tb/${TOP}.sv" \
\
"../../src/sc/system/npu_system.sv" \
"../../src/sc/system/mux_multimaster.sv" \
"../../src/sc/system/npu_item_interface.sv" \
"../../src/sc/cache_controller/sc_cache_controller.sv" \
"../../src/sc/io_device/io_device_test.sv" \
"../../src/sc/io_device/io_device_simple.sv" \
"../../src/sc/io_device/io_device_mem.sv" \
"../../src/sc/logger/npu_core_logger.sv" \
"../../src/ht/lsu_het_wrapper.sv" \
"../../src/ht/load_store_unit_par.sv" \
"../../src/ht/load_store_unit_stage1_par.sv" \
"../../src/ht/load_store_unit_stage2_par.sv" \
"../../src/ht/load_store_unit_stage3_par.sv" \
"../../src/ht/het_core_example.sv" \

TOP_OPT="${TOP}_opt"

vopt -64 +acc "$TOP" -o "$TOP_OPT" -g KERNEL_IMAGE="kernel_image.hex" -g CORE_MASK=$CORE_MASK -g THREAD_MASK=$THREAD_MASK

ln -sfv "../../$KERNEL_PATH" kernel_image.hex

vsim $TOOL_MODE -do simulate.do "$TOP_OPT"
