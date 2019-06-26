#!/bin/bash

DIRS=$(find src/ -type d)

INCLUDES=""

for d in $DIRS; do
	if [ ${d} != *"fpu"* ]; then
		INCLUDES="$INCLUDES -I$d"
	fi
done

verilator --error-limit 100 --lint-only system/nuplus_noc.sv $INCLUDES &> verilator_log
echo "verilator_log file created"
