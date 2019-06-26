#!/bin/sh

# Default values
KERNEL_NAME=""
SINGLE_CORE="no"
CORE_MASK=1
THREAD_MASK=FF
TOOL_MODE="gui"

# Checking flags
while test $# -gt 0; do
        case "$1" in
                -h|--help)
                        echo "Configuration scripts"
                        echo " "
                        echo "options:"
                        echo "-h, --help                  show this help"
                        echo "-k, --kernel=KERNEL_NAME    specify the kernel to use"
                        echo "-s, --single-core           select the single core configuration, by default the manycore is selected"
                        echo "-c, --core-mask=VALUE       specify the core activation mask, default: 1"
                        echo "-t, --thread-mask=VALUE     specify the thread activation mask, default FF"
                        echo "-m, --mode="gui" or "batch" specify the tool mode, it can run in either gui or batch mode, default: gui"
                        exit 0
                        ;;
                -k|--kernel)
                        shift
                        if test $# -gt 0; then
                                KERNEL_NAME=$1
                                echo "Kernel name: $KERNEL_NAME"
                        else
                                echo "Specify a kernel name"
                                exit 1
                        fi
                        shift
                        ;;
                -s|--single-core)
                        SINGLE_CORE="yes"
                        shift
                        ;;
                -c|--core-mask)
                        shift
                        if test $# -gt 0; then
                                CORE_MASK=$1                   
                              	echo "Core activation mask: $CORE_MASK" 
                        fi
                        shift
                        ;;
                -t|--thread-mask)
                        shift
                        if test $# -gt 0; then
                                THREAD_MASK=$1                   
                              	echo "Thread activation mask: $THREAD_MASK" 
                        fi
			shift
                        ;;
                 -m|--mode)
                        shift
                        if test $# -gt 0; then
                                if [ "$1" == "gui" ] || [ "$1" == "batch" ]; then
                                    TOOL_MODE=$1
                                    echo "Tool mode: $TOOL_MODE"
                                else
                                    echo "Wrong selected mode. It can be gui or batch."
				    exit 1
				fi
                        fi
                        shift
                        ;;
                *)
                        echo "Option not legal"
                        exit 1
                        ;;
        esac
done

# Building paths
KERNEL_PATH="software/kernels/$KERNEL_NAME/obj/${KERNEL_NAME}_mem.hex"
LOG_DIR="simulation_log/$KERNEL_NAME/"

echo " -- PROJECT SETUP SCRIPT"

if [ "$KERNEL_NAME" != "" ]; then
	echo " -- SELECTED KERNEL: $KERNEL_NAME"
else
	echo " -- ERROR: NO KERNEL SPECIFIED"

	exit 1
fi

if [ ! -f "$KERNEL_PATH" ]; then
	echo " -- ERROR: KERNEL $KERNEL_NAME NOT FOUND"

	exit 1
fi

# Creating log directory
mkdir -vp "$LOG_DIR"
rm -vf "$LOG_DIR/*"
