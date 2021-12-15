
; ****************************************************************************
;
;                                  Includes
;
; ****************************************************************************

#include <avr/io.h>

; ===== CPU class
#if defined atmega8
#define MCU8				// ATmega8, ATmega8L
#elif defined atmega328p || defined atmega328 || defined atmega168 || defined atmega168p || defined atmega88 || defined atmega88p
#define MCU88				// ATmega88, ATmega88P, ATmega168, ATmega168P, ATmega328, ATmega328P
#else
#error Unsupported MCU!
#endif

; ===== Constants

#define	B0 (1<<0)
#define	B1 (1<<1)
#define	B2 (1<<2)
#define	B3 (1<<3)
#define	B4 (1<<4)
#define	B5 (1<<5)
#define	B6 (1<<6)
#define	B7 (1<<7)
#define	B8 (1<<8)
#define	B9 (1<<9)
#define	B10 (1<<10)
#define	B11 (1<<11)
#define	B12 (1<<12)
#define	B13 (1<<13)
#define	B14 (1<<14)
#define	B15 (1<<15)

#define BIT(pos) (1<<(pos))

; ===== Memory

; RAM address and size
#ifdef MCU8
#define RAM_BEG		0x0060	// SRAM begin
#else
#define RAM_BEG		0x0100	// SRAM begin
#endif
#define RAM_END		(RAMEND+1) // SRAM end + 1
#define RAM_SIZE	(RAM_END-RAM_BEG) // SRAM size
#define STACK		RAMEND // end of stack in RAM (= last byte)

; ROM address and  size
#define ROM_BEG		0x0000	// ROM begin
#define ROM_END		(FLASHEND+1) // ROM end + 1
#define ROM_SIZE	(ROM_END-ROM_BEG) // ROM size

; EEPROM address and size
#define EEPROM_BEG	0x0000	// EEPROM begin
#define EEPROM_END	(E2END+1) // EEPROM end + 1
#define EEPROM_SIZE	(EEPROM_END-EEPROM_BEG)	// EEPROM size

; BOOT section
#if ROM_SIZE > 24000
#define BOOT_SIZE	512	// size of BOOT section (ATmega328)
#else
#define BOOT_SIZE	256	// size of BOOT section (ATmega8, ATmega88, ATmega168)
#endif

#define BOOT_END	ROM_END	// end of BOOT section
#define BOOT_BEG	(ROM_END-BOOT_SIZE) // start of BOOT section

; Flash program slot
#define SLOT_SIZE	1024	// slot size in flash ROM memory
#define SLOT_END	BOOT_BEG // end of Flash program slot
#define SLOT_BEG	(BOOT_BEG-SLOT_SIZE) // start of Flash program slot
; SPM_PAGESIZE		128	// size of one SPM flash memory page (64 for ATmega8x and ATmega168, 128 for ATmega328)
#define SLOT_PAGES	(SLOT_SIZE/SPM_PAGESIZE) // number of SPM pages per Flash program slot

; ===== Program control, macros

#define	nop2		rjmp	.+0	; [2] shorter form of "nop nop"

#if ROM_SIZE <= 0x2000 // Flash ROM size is max. 8 KB
#define call	rcall
#define jmp	rjmp
#endif

; ===== Registers
; R1 and R0 = temporary, result of multiplication, can be destroyed

#define ZERO	R2	// zero register, contains 0
