#################################################################################################
# << CELLRV32 - Application Makefile >>                                                         #
# ********************************************************************************************* #

# -----------------------------------------------------------------------------
# USER CONFIGURATION
# -----------------------------------------------------------------------------
# User's application sources (*.c, *.cpp, *.s, *.S); add additional files here
APP_SRC ?= $(wildcard ./*.c) $(wildcard ./*.s) $(wildcard ./*.cpp) $(wildcard ./*.S)

# User's application include folders (don't forget the '-I' before each entry)
APP_INC ?= -I .
# User's application include folders - for assembly files only (don't forget the '-I' before each entry)
ASM_INC ?= -I .

# Optimization
EFFORT ?= -Os

# Compiler toolchain
RISCV_PREFIX ?= riscv32-unknown-elf-

# CPU architecture and ABI
MARCH ?= rv32imc_zicsr
#MARCH ?= rv32i_zicsr
MABI  ?= ilp32

# User flags for additional configuration (will be added to compiler flags)
USER_FLAGS ?=

# Relative or absolute path to the CELLRV32 home folder
CELLRV32_HOME ?= ../../..
CELLRV32_LOCAL_RTL ?= $(CELLRV32_HOME)/rtl


# -----------------------------------------------------------------------------
# CELLRV32 framework
# -----------------------------------------------------------------------------
# Path to CELLRV32 linker script and startup file
CELLRV32_COM_PATH = $(CELLRV32_HOME)/sw/common
# Path to main CELLRV32 library include files
CELLRV32_INC_PATH = $(CELLRV32_HOME)/sw/lib/include
# Path to main CELLRV32 library source files
CELLRV32_SRC_PATH = $(CELLRV32_HOME)/sw/lib/source
# Path to CELLRV32 executable generator
CELLRV32_EXG_PATH = $(CELLRV32_HOME)/sw/image_gen
# Path to CELLRV32 core rtl folder
CELLRV32_RTL_PATH = $(CELLRV32_LOCAL_RTL)/core
# Path to CELLRV32 sim folder
CELLRV32_SIM_PATH = $(CELLRV32_HOME)/sim
# Marker file to check for CELLRV32 home folder
CELLRV32_HOME_MARKER = $(CELLRV32_INC_PATH)/cellrv32.h

# Core libraries (peripheral and CPU drivers)
CORE_SRC  = $(wildcard $(CELLRV32_SRC_PATH)/*.c)
# Application start-up code
CORE_SRC += $(CELLRV32_COM_PATH)/crt0.S

# Linker script
LD_SCRIPT = $(CELLRV32_COM_PATH)/cellrv32.ld

# Main output files
APP_EXE  = cellrv32_exe.bin
APP_ELF  = main.elf
APP_HEX  = cellrv32_raw_exe.hex
APP_BIN  = cellrv32_raw_exe.bin
APP_ASM  = main.asm
APP_IMG  = cellrv32_application_image.svh
BOOT_IMG = cellrv32_bootloader_image.svh


# -----------------------------------------------------------------------------
# Sources and objects
# -----------------------------------------------------------------------------
# Define all sources
SRC  = $(APP_SRC)
SRC += $(CORE_SRC)

# Define all object files
OBJ = $(SRC:%=%.o)


# -----------------------------------------------------------------------------
# Tools and flags
# -----------------------------------------------------------------------------
# Compiler tools
CC      = $(RISCV_PREFIX)gcc
OBJDUMP = $(RISCV_PREFIX)objdump
OBJCOPY = $(RISCV_PREFIX)objcopy
SIZE    = $(RISCV_PREFIX)size

# Host native compiler
CC_X86 = gcc -Wall -O -g

# CELLRV32 executable image generator
IMAGE_GEN = $(CELLRV32_EXG_PATH)/image_gen

# Compiler & linker flags
CC_OPTS  = -march=$(MARCH) -mabi=$(MABI) $(EFFORT) -Wall -ffunction-sections -fdata-sections -nostartfiles -mno-fdiv
CC_OPTS += -Wl,--gc-sections -lm -lc -lgcc -lc -g
CC_OPTS += $(USER_FLAGS)


# -----------------------------------------------------------------------------
# Application output definitions
# -----------------------------------------------------------------------------
.PHONY: check info help elf_info clean clean_all bootloader
.DEFAULT_GOAL := help

# 'compile' is still here for compatibility
asm:     $(APP_ASM)
elf:     $(APP_ELF)
exe:     $(APP_EXE)
hex:     $(APP_HEX)
bin:     $(APP_BIN)
compile: $(APP_EXE)
image:   $(APP_IMG)
install: image install-$(APP_IMG)
all:     $(APP_ASM) $(APP_EXE) $(APP_IMG) install hex bin

# Check if making bootloader
# Use different base address and length for instruction memory/"rom" (BOOTROM instead of IMEM)
# Also define "make_bootloader" symbol for crt0.S, add debug symbols and use link-time optimization
target bootloader: CC_OPTS += -Wl,--defsym=make_bootloader=1 -Dmake_bootloader -g -flto
target bl_image:   CC_OPTS += -Wl,--defsym=make_bootloader=1 -Dmake_bootloader -g -flto


# -----------------------------------------------------------------------------
# Image generator targets
# -----------------------------------------------------------------------------
# install/compile tools
$(IMAGE_GEN): $(CELLRV32_EXG_PATH)/image_gen.c
	@echo Compiling $(IMAGE_GEN)
	@$(CC_X86) $< -o $(IMAGE_GEN)


# -----------------------------------------------------------------------------
# General targets: Assemble, compile, link, dump
# -----------------------------------------------------------------------------
# Compile app *.s sources (assembly)
%.s.o: %.s
	@$(CC) -c $(CC_OPTS) -I $(CELLRV32_INC_PATH) $(ASM_INC) $< -o $@

# Compile app *.S sources (assembly + C pre-processor)
%.S.o: %.S
	@$(CC) -c $(CC_OPTS) -I $(CELLRV32_INC_PATH) $(ASM_INC) $< -o $@

# Compile app *.c sources
%.c.o: %.c
	@$(CC) -c $(CC_OPTS) -I $(CELLRV32_INC_PATH) $(APP_INC) $< -o $@

# Compile app *.cpp sources
%.cpp.o: %.cpp
	@$(CC) -c $(CC_OPTS) -I $(CELLRV32_INC_PATH) $(APP_INC) $< -o $@

# Link object files and show memory utilization
$(APP_ELF): $(OBJ)
	@$(CC) $(CC_OPTS) -T $(LD_SCRIPT) $(OBJ) -o $@ -lm
	@echo "Memory utilization:"
	@$(SIZE) $(APP_ELF)

# Assembly listing file (for debugging)
$(APP_ASM): $(APP_ELF)
	@$(OBJDUMP) -d -S -z  $< > $@

# Generate final executable from .text + .rodata + .data (in THIS order!)
main.bin: $(APP_ELF)
	@$(OBJCOPY) -I elf32-little $< -j .text   -O binary text.bin
	@$(OBJCOPY) -I elf32-little $< -j .rodata -O binary rodata.bin
	@$(OBJCOPY) -I elf32-little $< -j .data   -O binary data.bin
	@cat text.bin rodata.bin data.bin > $@
	@rm -f text.bin rodata.bin data.bin


# -----------------------------------------------------------------------------
# Application targets: Generate executable formats
# -----------------------------------------------------------------------------
# Generate CELLRV32 executable image for upload via bootloader
$(APP_EXE): main.bin $(IMAGE_GEN)
	@set -e
	@$(IMAGE_GEN) -app_bin $< $@ $(shell basename $(CURDIR))
	@echo "Executable ($(APP_EXE)) size in bytes:"
	@wc -c < $(APP_EXE)

# Generate CELLRV32 executable SystemVerilog boot image
$(APP_IMG): main.bin $(IMAGE_GEN)
	@set -e
	@$(IMAGE_GEN) -app_img $< $@ $(shell basename $(CURDIR))

# Install SystemVerilog memory initialization file
install-$(APP_IMG): $(APP_IMG)
	@set -e
	@echo "Installing application image to $(CELLRV32_RTL_PATH)/packages/$(APP_IMG)"
	@cp $(APP_IMG) $(CELLRV32_RTL_PATH)/packages/.

# Generate CELLRV32 RAW executable image in plain hex format
$(APP_HEX): main.bin $(IMAGE_GEN)
	@set -e
	@$(IMAGE_GEN) -raw_hex $< $@ $(shell basename $(CURDIR))

# Generate CELLRV32 RAW executable image in binary format
$(APP_BIN): main.bin $(IMAGE_GEN)
	@set -e
	@$(IMAGE_GEN) -raw_bin $< $@ $(shell basename $(CURDIR))


# -----------------------------------------------------------------------------
# Bootloader targets
# -----------------------------------------------------------------------------
# Create and install bootloader SystemVerilog init image
$(BOOT_IMG): main.bin $(IMAGE_GEN)
	@set -e
	@$(IMAGE_GEN) -bld_img $< $(BOOT_IMG) $(shell basename $(CURDIR))

install-$(BOOT_IMG): $(BOOT_IMG)
	@set -e
	@echo "Installing bootloader image to $(CELLRV32_RTL_PATH)/packages/$(BOOT_IMG)"
	@cp $(BOOT_IMG) $(CELLRV32_RTL_PATH)/packages/.

# Just an alias
bl_image: $(BOOT_IMG)
bootloader: bl_image install-$(BOOT_IMG)


# -----------------------------------------------------------------------------
# Check toolchain
# -----------------------------------------------------------------------------
check: $(IMAGE_GEN)
	@echo "---------------- Check: CELLRV32_HOME folder ----------------"
ifneq ($(shell [ -e $(CELLRV32_HOME_MARKER) ] && echo 1 || echo 0 ), 1)
$(error CELLRV32_HOME folder not found!)
endif
	@echo "CELLRV32_HOME: $(CELLRV32_HOME)"
	@echo "---------------- Check: Shell ----------------"
	@echo ${SHELL}
	@readlink -f ${SHELL}
	@echo "---------------- Check: $(CC) ----------------"
	@$(CC) -v
	@echo "---------------- Check: $(OBJDUMP) ----------------"
	@$(OBJDUMP) -V
	@echo "---------------- Check: $(OBJCOPY) ----------------"
	@$(OBJCOPY) -V
	@echo "---------------- Check: $(SIZE) ----------------"
	@$(SIZE) -V
	@echo "---------------- Check: CELLRV32 image_gen ----------------"
	@$(IMAGE_GEN) -help
	@echo "---------------- Check: Native GCC ----------------"
	@$(CC_X86) -v
	@echo
	@echo "Toolchain check OK"


# -----------------------------------------------------------------------------
# In-console simulation using default/simple testbench and GHDL
# -----------------------------------------------------------------------------
sim: $(APP_IMG) install
	@echo "Simulating $(APP_IMG)..."
	@rm -rf $(CELLRV32_SIM_PATH)/simple/build
	@mkdir -p $(CELLRV32_SIM_PATH)/simple/build
	@cp $(CELLRV32_SIM_PATH)/simple/*.sh $(CELLRV32_SIM_PATH)/simple/build
	@sh $(CELLRV32_SIM_PATH)/simple/build/questa.sh

# -----------------------------------------------------------------------------
# Show final ELF details (just for debugging)
# -----------------------------------------------------------------------------
elf_info: $(APP_ELF)
	@$(OBJDUMP) -x $(APP_ELF)


# -----------------------------------------------------------------------------
# Clean up
# -----------------------------------------------------------------------------
clean:
	@rm -f *.elf *.o *.bin *.out *.asm *.hex *.svh *.sv

clean_all: clean
	@rm -f $(OBJ) $(IMAGE_GEN)


# -----------------------------------------------------------------------------
# Show configuration
# -----------------------------------------------------------------------------
info:
	@echo "---------------- Info: Project ----------------"
	@echo "Project folder:        $(shell basename $(CURDIR))"
	@echo "Source files:          $(APP_SRC)"
	@echo "Include folder(s):     $(APP_INC)"
	@echo "ASM include folder(s): $(ASM_INC)"
	@echo "---------------- Info: CELLRV32 ----------------"
	@echo "CELLRV32 home folder (CELLRV32_HOME): $(CELLRV32_HOME)"
	@echo "IMAGE_GEN: $(IMAGE_GEN)"
	@echo "Core source files:"
	@echo "$(CORE_SRC)"
	@echo "Core include folder:"
	@echo "$(CELLRV32_INC_PATH)"
	@echo "---------------- Info: Objects ----------------"
	@echo "Project object files:"
	@echo "$(OBJ)"
	@echo "---------------- Info: RISC-V CPU ----------------"
	@echo "MARCH:      $(MARCH)"
	@echo "MABI:       $(MABI)"
	@echo "---------------- Info: Toolchain ----------------"
	@echo "Toolchain:  $(RISCV_TOLLCHAIN)"
	@echo "CC:         $(CC)"
	@echo "OBJDUMP:    $(OBJDUMP)"
	@echo "OBJCOPY:    $(OBJCOPY)"
	@echo "SIZE:       $(SIZE)"
	@echo "---------------- Info: Compiler Configuration ----------------"
	@$(CC) -v
	@echo "---------------- Info: Compiler Libraries ----------------"
	@echo "LIBGCC:"
	@$(CC) -print-libgcc-file-name
	@echo "SEARCH-DIRS:"
	@$(CC) -print-search-dirs
	@echo "---------------- Info: Flags ----------------"
	@echo "USER_FLAGS: $(USER_FLAGS)"
	@echo "CC_OPTS:    $(CC_OPTS)"
	@echo "---------------- Info: Host Native GCC Flags ----------------"
	@echo "CC_X86:     $(CC_X86)"


# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
help:
	@echo "<<< CELLRV32 SW Application Makefile >>>"
	@echo "Make sure to add the bin folder of RISC-V GCC to your PATH variable."
	@echo ""
	@echo "=== Targets ==="
	@echo " help       - show this text"
	@echo " check      - check toolchain"
	@echo " info       - show makefile/toolchain configuration"
	@echo " asm        - compile and generate <$(APP_ASM)> assembly listing file for manual debugging"
	@echo " elf        - compile and generate <$(APP_ELF)> ELF file"
	@echo " exe        - compile and generate <$(APP_EXE)> executable for upload via default bootloader (binary file, with header)"
	@echo " bin        - compile and generate <$(APP_BIN)> RAW executable file (binary file, no header)"
	@echo " hex        - compile and generate <$(APP_HEX)> RAW executable file (hex char file, no header)"
	@echo " image      - compile and generate SystemVerilog IMEM boot image (for application, no header) in local folder"
	@echo " install    - compile, generate and install SystemVerilog IMEM boot image (for application, no header)"
	@echo " sim        - in-console simulation using default/simple testbench and GHDL"
	@echo " all        - exe + install + hex + bin + asm"
	@echo " elf_info   - show ELF layout info"
	@echo " clean      - clean up project home folder"
	@echo " clean_all  - clean up whole project, core libraries and image generator"
	@echo " bl_image   - compile and generate SystemVerilog BOOTROM boot image (for bootloader only, no header) in local folder"
	@echo " bootloader - compile, generate and install SystemVerilog BOOTROM boot image (for bootloader only, no header)"
	@echo ""
	@echo "=== Variables ==="
	@echo " USER_FLAGS   - Custom toolchain flags [append only]: \"$(USER_FLAGS)\""
	@echo " EFFORT       - Optimization level: \"$(EFFORT)\""
	@echo " MARCH        - Machine architecture: \"$(MARCH)\""
	@echo " MABI         - Machine binary interface: \"$(MABI)\""
	@echo " APP_INC      - C include folder(s) [append only]: \"$(APP_INC)\""
	@echo " ASM_INC      - ASM include folder(s) [append only]: \"$(ASM_INC)\""
	@echo " RISCV_PREFIX - Toolchain prefix: \"$(RISCV_PREFIX)\""
	@echo " CELLRV32_HOME - CELLRV32 home folder: \"$(CELLRV32_HOME)\""
	@echo ""
