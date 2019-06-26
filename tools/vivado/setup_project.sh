#!/bin/bash

set -e

. tools/sim/common.sh

vivado -nolog -nojournal -mode $TOOL_MODE -source tools/vivado/setup_project.tcl -tclargs $KERNEL_NAME $THREAD_MASK $CORE_MASK $SINGLE_CORE
