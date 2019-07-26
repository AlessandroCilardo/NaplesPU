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

##---------------------------------
## Function used to describe the 
## usage of the test
##---------------------------------

function logo(){
        clear
        echob "    _   __            __          ____  __  __";
        echob "   / | / /___ _____  / /__  _____/ __ \/ / / /";
        echob "  /  |/ / __ \`/ __ \/ / _ \/ ___/ /_/ / / / / ";
        echob " / /|  / /_/ / /_/ / /  __(__  ) ____/ /_/ /       CeRICT, University of Naples";
        echob "/_/ |_/\__,_/ .___/_/\___/____/_/    \____/                   Federico II";
        echob "           /_/                                ";
        echo ""
}

function wait_process {
  mypid=$1

  echo -ne "$loadingText\r"

  while kill -0 $mypid 2>/dev/null; do
    echo -ne "Waiting.\r"
    sleep 0.5
    echo -ne "Waiting..\r"
    sleep 0.5
    echo -ne "Waiting...\r"
    sleep 0.5
    echo -ne "Waiting\r\033[K"
    echo -ne "Waiting\r"
    sleep 0.5
  done

echo "Waiting...FINISHED"
}

function echob(){
        printf '\033[1;34m'; echo "$@"; printf '\E[0m'
}

exit_script() {
    echo "Exiting NaplesPU test script!"
    echo "Killing all subjobs!"
    trap - SIGINT SIGTERM # clear the trap
    kill -- -$$ # Sends SIGTERM to child/sub processes
}

trap exit_script SIGINT SIGTERM

##--------------------------------
## Useful Path Definition
##--------------------------------

# Project directories definitios
TOOLSDIR=`pwd`
TOPDIR=$TOOLSDIR/..
SIMLOG=$TOPDIR/simulation_log
SOFTWARE=$TOPDIR/software/kernels  
TOOL_MODE="vsim"                   #Default simulation tool
THREAD_NUMB=8                      #Default thread numb
CORE_NUMB=1                        #Default core numb
THREAD_MASK=$(( 16#FF ))           #Default thread mask
CORE_MASK=$(( 16#1 ))              #Default core mask

# Colors definitions
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Checking flags
while test $# -gt 0; do
        case "$1" in
                -h|--help)
                        echo "Configuration scripts"
                        echo " "
                        echo "options:"
                        echo "-h,  --help                  show this help"
                        echo "-t,  --tool vsim or vivado   specify the tool to use, default: vsim"
                        echo "-cn, --core-numb VALUE       specify the core number, default: 1"
                        echo "-tn, --thread-numb VALUE     specify the thread number, default: 8"
                        exit 0
                        ;;
                -t|--tool)
                        shift
                        if test $# -gt 0; then
                                if [ "$1" == "vsim" ] || [ "$1" == "vivado" ]; then
                                    TOOL_MODE=$1
                                    echo "Tool mode: $TOOL_MODE"
                                else
                                    echo "Wrong selected tool. It can be vsim or vivado."
				    exit 1
				fi
                        fi
                        shift
                        ;;
                 -cn|--core-numb)
                        shift
                        if test $# -gt 0; then
                        	CORE_NUMB=$1
                                CORE_MASK=$(( 2**$CORE_NUMB-1 ))
                                echo "Core Numb: $CORE_NUMB"
                                echo "Core Mask: $CORE_MASK"
                        fi
                        shift
                        ;;
                 -tn|--thread-numb)
                        shift
                        if test $# -gt 0; then
                        	THREAD_NUMB=$1
                                THREAD_MASK=$(( 2**$THREAD_NUMB-1 ))
                                echo "Thread Numb: $THREAD_NUMB"
                                echo "Thread Mask: $THREAD_MASK"
                        fi
                        shift
                        ;;

                *)
                        echo "Option not legal"
                        exit 1
                        ;;
        esac
done

# Printing NPU logo
logo

##--------------------------------
## Kernels List and Related Paths
##--------------------------------

# Kernels under test list
# lud_float has rounding errors, the output diverges from 
# the expected one.
KERNELS=( barriertest mmsc mmsc_float mmsc_tiling crc dct_scalar ns ndes fir conv_layer_scalar_mt conv_layer_mvect_mt lud_scalar lud_float matrix_transpose marching_squares vector_test) 

# Checking the NPU toolchain installation
if [ ! -e "$MANGO_ROOT/usr/local/llvm-npu" ]; then
  echo "NaplesPU toolchain not installed!"
  exit 1
fi

# Creating the simulation_log folder if does not exist
if [ ! -e "$SIMLOG" ]; then
  mkdir -p $TOPDIR/simulation_log
fi

##--------------------------------
## Checking tool installations
##--------------------------------

SIM="none"

# Checking ModelSim
if [ $TOOL_MODE == "vsim" ]; then
    if $(hash vsim &> /dev/null); then
        echo "ModelSim installed: $(type vsim 2> /dev/null)"
        SIM="vsim"
    else 
        echo "ModelSim not installed!"
        exit 1
    fi 
fi

if [ $TOOL_MODE == "vivado" ]; then
    if $(hash vivado &> /dev/null); then
      echo "Vivado installed: $(type vivado 2> /dev/null)"     
      SIM="vivado"
      else 
        echo "Vivado not installed!"
        exit 1
    fi
fi
  
if [ $SIM == "none" ]; then
  echo "Nor Vivado or ModelSim are installed!"
  exit 1
fi

##--------------------------------
## Test Core Loop
##--------------------------------

for k in "${KERNELS[@]}"
do
  # Testing the kernel
  echo -e "Running cosimulation test for kernel ${BLUE}${k}${NC}"
 
  # Creating the kernel output folder into the simulation_log
  if [ ! -e "$SIMLOG/$k" ]; then
    mkdir -p $SIMLOG/$k
  else
  # Else remove all previous files
    rm $SIMLOG/$k/*
  fi
  # Creating output files
  touch $SIMLOG/$k/display_memory.txt $SIMLOG/$k/display_simulation.txt 
 
  # Compiling kernles for both NPU and x86
  echo "Compiling kernel ${k} for both NPU and x86"

  if [ ! -e "$SOFTWARE/$k" ]; then
    echo -e "Kernel ${BLUE}${k}${NC} does not exist!"
    exit 1
  fi
   
  cd $SOFTWARE/$k && make clean &> /dev/null && THREAD_NUMB=$THREAD_NUMB CORE_NUMB=$CORE_NUMB make &> /dev/null 
  gcc ${k}.cpp -DTHREAD_NUMB=$THREAD_NUMB -DCORE_NUMB=$CORE_NUMB -o ${k}_cpu > /dev/null	
  
  #Check if the toolchain correctly compiled the requested kernel
  if [ -e "obj/$k.elf" ]; then
    echo -e "Kernel ${BLUE}${k}${NC} compiled!"
  else
    echo -e "Kernel ${BLUE}${k}${NC} compilation ${RED}failed${NC}!"
    exit 1
  fi 
 
  # Saving expected results
  echo "Generating expected result for kernel ${k}"
  mkdir -p $SIMLOG/$k
  cd $SOFTWARE/$k && ./${k}_cpu > $SIMLOG/$k/cpu_results.txt
  rm -f ${k}_cpu
  
  # Running simulation
  cd $TOPDIR
  case $SIM in
    vsim)
      echo "Running ModelSim simulation..."
      tools/modelsim/simulate.sh --kernel $k --mode batch --core-mask $CORE_MASK --thread-mask $THREAD_MASK > tools/cosim.log < /dev/null &
      ;;
    vivado)
      tools/vivado/setup_project.sh --kernel $k --mode batch --core-mask $CORE_MASK --thread-mask $THREAD_MASK > tools/cosim.log < /dev/null &
      ;;
    verilator)
      ;;                 
    *)
      echo "Option not legal"
      exit 1
      ;;
  esac
  wait_process $!

  # Comparing results
  cd $SIMLOG/$k/
  base_addr=$(cat display_simulation.txt | grep "Output Memory:" | awk '{print $8}')
  blocks_numb=$(cat display_simulation.txt | grep "Output Blocks:" | awk '{print $8}')
  blocks_numb=$(( 16#$blocks_numb )) 
  blocks_numb=$(( blocks_numb / 16 ))
  
  if [[ "$k" = *_float ]]; then
  	is_float=1
  else
  	is_float=0
  fi

  python $TOOLSDIR/memcheck.py -a $base_addr -b $blocks_numb -i $is_float > /dev/null 
  diff -E -w -b -B result.txt cpu_results.txt &> /dev/null
  
  if [[ $? == 0 ]]; then
  	echo -e "Test ${GREEN}OK${NC}!"
  else
        echo -e "Test ${RED}FAILED${NC}!"
  fi

  echo " "
  echo " "
done
