# *****************************************************************************
# USER CONFIGURATION
# *****************************************************************************
# User's application sources (*.c, *.cpp, *.s, *.S); add additional files here
APP_SRC ?= $(wildcard ./*.c) $(wildcard ./*.s) $(wildcard ./*.cpp) $(wildcard ./*.S)

# User's application include folders (don't forget the '-I' before each entry)
APP_INC ?= -I .
# User's application include folders - for assembly files only (don't forget the '-I' before each entry)
ASM_INC ?= -I .

# Optimization
EFFORT ?= -Os

# CPU architecture and ABI
MARCH ?= rv32i
MABI  ?= ilp32

# User flags for additional configuration (will be added to compiler flags)
USER_FLAGS ?=
# *****************************************************************************


# -----------------------------------------------------------------------------
# FreeRTOS
# -----------------------------------------------------------------------------
ifneq (,$(findstring RUN_FREERTOS_DEMO,$(USER_FLAGS)))
# FreeRTOS home folder (adapt this!)
FREERTOS_HOME ?= /mnt/n/Projects/FreeRTOS

# FreeRTOS RISC-V specific
APP_SRC += $(wildcard $(FREERTOS_HOME)/FreeRTOS/Source/portable/GCC/RISC-V/*.c)
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Source/portable/GCC/RISC-V/portASM.S

APP_INC += -I $(FREERTOS_HOME)/FreeRTOS/Source/portable/GCC/RISC-V

# FreeRTOS core
APP_SRC += $(wildcard $(FREERTOS_HOME)/FreeRTOS/Source/*.c)
APP_SRC += $(wildcard $(FREERTOS_HOME)/FreeRTOS/Source/portable/MemMang/heap_4.c)

APP_INC += -I $(FREERTOS_HOME)/FreeRTOS/Source/include

# FreeRTOS sources for the full_demo
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/blocktim.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/dynamic.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/EventGroupsDemo.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/GenQTest.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/recmutex.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/TaskNotify.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/TaskNotifyArray.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS/Demo/Common/Minimal/TimerDemo.c

APP_INC += -I $(FREERTOS_HOME)/FreeRTOS/Demo/Common/include

# CELLRV32 specific
ASM_INC += -DportasmHANDLE_INTERRUPT=SystemIrqHandler

APP_INC += -I chip_specific_extensions/cellrv32

ASM_INC += -I chip_specific_extensions/cellrv32

# Demo application
APP_SRC += blinky_demo/main_blinky.c
APP_SRC += full_demo/main_full.c
APP_SRC += full_demo/RegTest.s
endif

# -----------------
# FreeRTOS-Plus-CLI
# -----------------
ifneq (,$(findstring FREERTOS_PLUS_CLI,$(USER_FLAGS)))
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-CLI/FreeRTOS_CLI.c

APP_INC += -I $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-CLI
endif

# -----------------
# FreeRTOS-Plus-TCP
# -----------------
ifneq (,$(findstring FREERTOS_PLUS_TCP,$(USER_FLAGS)))
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_ARP.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_DHCP.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_DNS.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_IP.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_Sockets.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_Stream_Buffer.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_TCP_IP.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_TCP_WIN.c
APP_SRC += $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/FreeRTOS_UDP_IP.c

APP_INC += -I $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/include
APP_INC += -I $(FREERTOS_HOME)/FreeRTOS-Plus/Source/FreeRTOS-Plus-TCP/portable/Compiler/GCC
endif


# Modify this variable to fit your CELLRV32 setup (cellrv32 home folder)
CELLRV32_HOME ?= ../../..

include $(CELLRV32_HOME)/sw/common/common.mk
