##########################
# On command line use:
#   make all APPNAME=application_name MCU=mcu_type F_CPU=frequency

##########################
# Project definitions

# target platform
TRGT = avr-

# list of ASM source files
ASRC += src/data.S
ASRC += src/wait.S
ASRC += src/video.S
ASRC += src/main.S
ASRC += src/eeprom.S
ASRC += src/i2c.S
ASRC += src/bios.S
#ASRC += src/z80.S

ASRC += src/boot.S

# list of C source files
SRC += 
#src/test2.c

# optimisation level
OPT += -Os

# BOOT section
ifeq ($(MCU),atmega8)
	BOOTADDR = 0x1F00
else
	ifeq ($(MCU),atmega88)
		BOOTADDR = 0x1F00
	else
		ifeq ($(MCU),atmega168)
			BOOTADDR = 0x3F00
		else
			BOOTADDR = 0x7E00
		endif
	endif
endif

OPT += -Wl,--section-start=.bootloader=$(BOOTADDR)

# 1) eliminate unused sections ... 2) do not eliminate unused sections
#OPT += -ffunction-sections -fdata-sections -Wl,--gc-sections
OPT += -fno-function-sections -fno-data-sections -Wl,--no-gc-sections

# other setups
#   -Wl,--relax ... replace CALL and JMP by shorter RCALL and RJMP
#   -ffreestanding ... startup code may not be usual form of main()
#   -fno-tree-scev-cprop ... disable vectorization of outer loops
#   -fno-split-wide-types ... disable split long types
#   -fno-inline-small-functions ... disable inline small functions
OPT += -ffreestanding -fno-tree-scev-cprop -fno-split-wide-types -fno-inline-small-functions
# -Wl,--relax 

# tools
CC = $(TRGT)gcc
LN = $(TRGT)gcc
OC = $(TRGT)objcopy
AS = $(TRGT)gcc -x assembler-with-cpp
HEX = $(OC) -O ihex
BIN = $(OC) -O binary

# flags
CCFLAGS = $(OPT) -Wall -std=gnu99 -gstabs -mmcu=$(MCU) -D$(MCU) -c $(CDEF) -D F_CPU=$(F_CPU)
LNFLAGS = $(OPT) -mmcu=$(MCU) -D$(MCU) -D F_CPU=$(F_CPU)
#OCFLAGS = -j .text -j .data
#ASFLAGS = -mmcu=$(MCU) -D$(MCU) -nostartfiles -g -D F_CPU=$(F_CPU) -Wa,-amhls=$(<:.s=.lst)

##########################
# Makefile rules

OBJS = $(ASRC:.s=.o) $(SRC:.c=.o)

all: $(OBJS) $(APPNAME).elf $(APPNAME).hex $(APPNAME).bin 

%.o : %.c
	$(CC) -c $(CCFLAGS) $< -o $@

%elf: $(OBJS)
	$(LN) $(LNFLAGS) -o $@ $(OBJS)
  
%hex: %elf
	$(HEX) $< $@

%bin: %elf
	$(BIN) $< $@
