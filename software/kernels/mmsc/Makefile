NPU_DIR?=$(MANGO_ROOT)/usr/local/llvm-npu

CORE_NUMB?=1
THREAD_NUMB?=8

KFLAGS=-DCORE_NUMB=$(CORE_NUMB) -DTHREAD_NUMB=$(THREAD_NUMB)

include $(NPU_DIR)/misc-npu/NaplesPU.mk

SRCS=mmsc.cpp

OBJS= $(SRCS_TO_OBJS) $(NPU_DIR)/libs-npu/crt0.o $(NPU_DIR)/libs-npu/vectors.o
DEPS=$(SRCS_TO_DEPS)

$(OBJ_DIR)/$(basename($(SRCS))).hex: $(OBJS)
	$(LD) -o $(OBJ_DIR)/$(notdir $(basename $<)).elf $(LDFLAGS) $(OBJS) $(AFLAGS)
	$(ELF2HEX) -o $(OBJ_DIR)/$(notdir $(basename $<)).hex $(OBJ_DIR)/$(notdir $(basename $<)).elf
	$(OBJDUMP) -d -s $(OBJ_DIR)/$(notdir $(basename $<)).elf > $(OBJ_DIR)/$(notdir $(basename $<)).objdump
	

clean:
	rm -rf $(OBJ_DIR)

-include $(DEPS)
