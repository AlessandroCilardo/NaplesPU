TOPDIR=../../
NUP_DIR?=/usr/local/llvm-nuplus
include $(NUP_DIR)/misc-nuplus/NuPlus.mk

SRCS=fir_filter.cpp

OBJS= $(SRCS_TO_OBJS) $(NUP_DIR)/libs-nuplus/crt0.o $(NUP_DIR)/libs-nuplus/vectors.o
DEPS=$(SRCS_TO_DEPS)

$(OBJ_DIR)/$(basename($(SRCS))).hex: $(OBJS)
	$(LD) -o $(OBJ_DIR)/$(notdir $(basename $<)).elf $(LDFLAGS) $(OBJS) $(AFLAGS)
	$(ELF2HEX) -o $(OBJ_DIR)/$(notdir $(basename $<)).hex $(OBJ_DIR)/$(notdir $(basename $<)).elf
	$(OBJDUMP) -disassemble-all $(OBJ_DIR)/$(notdir $(basename $<)).elf > $(OBJ_DIR)/$(notdir $(basename $<)).objdump
	

clean:
	rm -rf $(OBJ_DIR)

-include $(DEPS)
