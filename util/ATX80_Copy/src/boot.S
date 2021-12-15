
; ****************************************************************************
;
;                BOOT section (used to write into internal Flash)
;
; ****************************************************************************

#include "include.inc"

; ------ flash image section

	.section .flashimage, "ax", @progbits

	.align 7		; align to 128 bytes

.global FlashStart
FlashStart:			; start of flash image

; ------ boot section

	.section .bootloader, "ax", @progbits

.global FlashEnd
FlashEnd:			; end of flash image
	.ascii	"FE"		; flash-end magic
	.word	FlashStart	; start of flash image

#ifndef SELFPRGEN
#define SELFPRGEN SPMEN
#endif

#ifndef SPMCSR
#define SPMCSR SPMCR
#endif

; ----------------------------------------------------------------------------
;                        Wait SPM operation to complete
; ----------------------------------------------------------------------------
; DESTROYS: R22
; ----------------------------------------------------------------------------

SpmWait:
	in	R22,_SFR_IO_ADDR(SPMCSR)
	sbrc	R22,SELFPRGEN
	rjmp	SpmWait
	ret

; ----------------------------------------------------------------------------
;                           Do SPM instruction
; ----------------------------------------------------------------------------
; INPUT: R23 = command
; DESTROYS: R22
; ----------------------------------------------------------------------------
; - after all operations, additional SpmWait should be proceed
; - all previous EEPROM operations must be completed
; - interrupts must be disabled

SpmCmd:
	; wait for previous SPM instruction to complete
	rcall	SpmWait

	; start SPM instruction
	out	_SFR_IO_ADDR(SPMCSR),R23
	spm
	ret

; ----------------------------------------------------------------------------
;               Write one Flash SPM page (64 bytes = SPM_PAGESIZE)
; ----------------------------------------------------------------------------
; INPUT: R31:R30 (Z) = destination address in Flash (must be aligned to 64 bytes = SPM_PAGESIZE)
;	 R27:R26 (X) = source address, page data in SRAM (of size 64 bytes = SPM_PAGESIZE)
; OUTPUT: R31:R30 (Z) = next destination address
;	  R27:R26 (X) = next source address
; DESTROYS: R23, R22, R1, R0
; ----------------------------------------------------------------------------

.global SpmWrite
SpmWrite:
	; push registers
	push	R24

	; erase the page
	ldi	R23,BIT(PGERS) | BIT(SELFPRGEN)
; INPUT: R23 = command
; DESTROYS: R22
	rcall	SpmCmd

	; transfer data from RAM to Flash page buffer
	ldi	R24,SPM_PAGESIZE/2 ; page size = 128 bytes
2:	ld	r0,X+		; get 2 bytes to write
	ld	r1,X+
	ldi	R23,BIT(SELFPRGEN)
; INPUT: R23 = command
; DESTROYS: R22
	rcall	SpmCmd		; add 2 bytes to Flash page buffer
	adiw	R30,2		; increase destinatin address
	dec	R24
	brne	2b

	; execute page write
	subi	R30,lo8(SPM_PAGESIZE) ; restore start address
	sbci	R31,hi8(SPM_PAGESIZE)
	ldi	R23,BIT(PGWRT) | BIT(SELFPRGEN)
; INPUT: R23 = command
; DESTROYS: R22
	rcall	SpmCmd		; write page

	; re-enable RWW section, wait if RWW busy
4:	ldi	R23,BIT(RWWSRE) | BIT(SELFPRGEN)
; INPUT: R23 = command
; DESTROYS: R22
	rcall	SpmCmd

	in	R23,_SFR_IO_ADDR(SPMCSR)
	sbrc	R23,RWWSB
	rjmp	4b		; wait if RWW is busy

	; wait for last SPM instruction to complete
; DESTROYS: R22
	rcall	SpmWait

	; shift destination pointer
	subi	R30,lo8(-SPM_PAGESIZE)
	sbci	R31,hi8(-SPM_PAGESIZE)

	; pop registers
	pop	R24
	ret
