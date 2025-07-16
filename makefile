AS := nasm
CC := gcc
CXX := g++ 
LD := ld


AS_BIN_FLAGS := -f bin
AS_OBJ_FLAGS := -f elf32
C_FLAGS := -c -m32 -ffreestanding -nostdlib -nostartfiles -fno-builtin -fno-stack-protector \
-nostartfiles -nodefaultlibs -ffreestanding -Wall 
CXX_FLAGS := $(C_FLAGS)
LD_FLAGS :=  -m elf_i386 -T linker.ld -nostdlib 
# LD_FLAGS := -m elf_i386 -Ttext=0x00000000 -e _start -nostdlib

SRC_DIR := src
TARGET_DIR := build

TAEGET := $(TARGET_DIR)/kernel.img
LD_TARGET := $(TARGET_DIR)/kernel


SCAN_DIR := src/boot src/init 

# C_INCLUDE := $(shell find src/include -name *.h)
# C_SOURCE := $(shell find src -name *.c)
# C_TARGET := $(C_SOURCE:src/%.c=$(TARGET_DIR)/%.o)

CXX_INCLUDE := $(shell find src/include -name *.h) $(C_INCLUDE)
CXX_SOURCE := $(shell find $(SCAN_DIR) -name *.cpp)
CXX_TARGET := $(CXX_SOURCE:src/%.cpp=$(TARGET_DIR)/%.o)

ASM_BIN_SOURCE := $(shell find $(SCAN_DIR) -name *.S)
ASM_OBJ_SOURCE := $(shell find $(SCAN_DIR) -name *.s)
ASM_BIN_TARGET := $(ASM_BIN_SOURCE:src/%.S=$(TARGET_DIR)/%.bin)
ASM_OBJ_TARGET := $(ASM_OBJ_SOURCE:src/%.s=$(TARGET_DIR)/%.o)


LINK_TARGET := $(ASM_OBJ_TARGET) $(C_TARGET) $(CXX_TARGET)

COMPILE_TARGET := $(ASM_BIN_TARGET) $(LINK_TARGET)

OUTPUT_DIRS := $(sort $(dir $(COMPILE_TARGET)))


all: $(LD_TARGET) $(ASM_BIN_TARGET) $(LD_TARGET).bin $(SUBDIRS)

$(OUTPUT_DIRS): 
	mkdir -p $@


$(ASM_BIN_TARGET): $(TARGET_DIR)/%.bin: $(SRC_DIR)/%.S | $(OUTPUT_DIRS)
	$(AS) $(AS_BIN_FLAGS) $<  -o $@


$(ASM_OBJ_TARGET):  $(TARGET_DIR)/%.o: $(SRC_DIR)/%.s | $(OUTPUT_DIRS)
	$(AS) $(AS_OBJ_FLAGS) $<  -o $@


$(CXX_TARGET):  $(TARGET_DIR)/%.o: $(SRC_DIR)/%.cpp $(CXX_INCLUDE) | $(OUTPUT_DIRS)
	$(CXX) $(CXX_FLAGS) $<  -o $@ -I src/include

$(C_TARGET):  $(TARGET_DIR)/%.o: $(SRC_DIR)/%.c $(C_INCLUDE) | $(OUTPUT_DIRS)
	$(CC) $(C_FLAGS) $<  -o $@ -I src/include

$(LD_TARGET): $(LINK_TARGET) 
	ld $(LD_FLAGS) $^ -o $@

$(LD_TARGET).bin: $(LD_TARGET)
	objcopy -O binary $(LD_TARGET) $(LD_TARGET).bin





disk.img: $(TARGET_DIR)/boot/bootsect.bin $(TARGET_DIR)/boot/setup.bin $(LD_TARGET).bin
	dd if=build/boot/bootsect.bin of=./disk.img bs=512 count=1 conv=notrunc seek=0
	dd if=build/boot/setup.bin of=./disk.img bs=512 count=4 conv=notrunc seek=1
	dd if=$(LD_TARGET).bin of=./disk.img bs=512 count=512 conv=notrunc seek=5 


debug:
	@echo $(CXX_SOURCE)
	@echo $(CXX_TARGET)

run: all copy
	bochs -q -f bochsrc


copy: disk.img
	

clean:
	rm -f $(shell find $(TARGET_DIR) -name *.bin)
	rm -f $(shell find $(TARGET_DIR) -name *.o)
	rm -f $(shell find $(TARGET_DIR) -name *.elf)
	rm -f $(shell find $(TARGET_DIR) -name *.img)

.PHONY: test clean copy run debug



