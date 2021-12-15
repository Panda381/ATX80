
; ****************************************************************************
;
;                BOOT section (used to write into internal Flash)
;
; ****************************************************************************
; Flash program slot
;#define SLOT_SIZE	1024	// slot size in flash ROM memory
;#define SLOT_END	BOOT_BEG // end of Flash program slot
;#define SLOT_BEG	(BOOT_BEG-SLOT_SIZE) // start of Flash program slot
; SPM_PAGESIZE		64	// size of one SPM flash memory page (64 for ATmega8x, 128 for ATmega328)
;#define SLOT_PAGES	(SLOT_SIZE/SPM_PAGESIZE) // number of SPM pages per Flash program slot

#include "include.inc"

	.section .bootloader, "ax", @progbits

#ifndef SELFPRGEN
#define SELFPRGEN SPMEN
#endif

#ifndef SPMCSR
#define SPMCSR SPMCR
#endif

; ----------------------------------------------------------------------------
;                        Wait SPM operation to complete
; ----------------------------------------------------------------------------
; DESTROYS: F
; ----------------------------------------------------------------------------

SpmWait:
	in	F,_SFR_IO_ADDR(SPMCSR)
	sbrc	F,SELFPRGEN
	rjmp	SpmWait
	ret

; ----------------------------------------------------------------------------
;                           Do SPM instruction
; ----------------------------------------------------------------------------
; INPUT: A = command
; DESTROYS: F
; ----------------------------------------------------------------------------
; - after all operations, additional SpmWait should be proceed
; - all previous EEPROM operations must be completed
; - interrupts must be disabled

SpmCmd:
	; wait for previous SPM instruction to complete
	rcall	SpmWait

	; start SPM instruction
	out	_SFR_IO_ADDR(SPMCSR),A
	spm
	ret

; ----------------------------------------------------------------------------
;               Write one Flash SPM page (64 bytes = SPM_PAGESIZE)
; ----------------------------------------------------------------------------
; INPUT: HL = destination address in Flash (must be aligned to 64 bytes = SPM_PAGESIZE)
;	 DE = source address, page data in SRAM (of size 64 bytes = SPM_PAGESIZE)
; OUTPUT: HL = next destination address
;	  DE = next source address
; DESTROYS: AF, R1, R0
; ----------------------------------------------------------------------------
; Enables interrupts. All previous EEPROM operations must be completed.

SpmWrite:
	; disable interrupts
	cli

	; push registers
	push	C

	; erase the page
	ldi	A,BIT(PGERS) | BIT(SELFPRGEN)
; INPUT: A = command
; DESTROYS: F
	rcall	SpmCmd		; destroys only R20

	; transfer data from RAM to Flash page buffer
	ldi	C,SPM_PAGESIZE/2 ; page size = 64 bytes
2:	ld	r0,MDE+		; get 2 bytes to write
	ld	r1,MDE+
	ldi	A,BIT(SELFPRGEN)
; INPUT: A = command
; DESTROYS: F
	rcall	SpmCmd		; add 2 bytes to Flash page buffer
	adiw	HL,2		; increase destinatin address
	dec	C
	brne	2b

	; execute page write
	subi	L,lo8(SPM_PAGESIZE) ; restore start address
	sbci	H,hi8(SPM_PAGESIZE)
	ldi	A,BIT(PGWRT) | BIT(SELFPRGEN)
; INPUT: A = command
; DESTROYS: F
	rcall	SpmCmd		; write page

	; re-enable RWW section, wait if RWW busy
4:	ldi	A,BIT(RWWSRE) | BIT(SELFPRGEN)
; INPUT: A = command
; DESTROYS: F
	rcall	SpmCmd

	in	A,_SFR_IO_ADDR(SPMCSR)
	sbrc	A,RWWSB
	rjmp	4b		; wait if RWW is busy

	; wait for last SPM instruction to complete
; DESTROYS: F
	rcall	SpmWait

	; shift destination pointer
	subi	L,lo8(-SPM_PAGESIZE)
	sbci	H,hi8(-SPM_PAGESIZE)

	; pop registers
	pop	C

	; enable interrupts
	sei
	ret

; ----------------------------------------------------------------------------
;                 Save program to internal Flash slot
; ----------------------------------------------------------------------------
; OUTPUT: NC = write error
; DESTROYS: AF, BC, DE, HL, PUSH2, PUSH3
; ----------------------------------------------------------------------------
; Enables interrupts.

.global SpmSave
SpmSave:
	; store old content
; OUTPUT: HL = program address - 4
;	  PUSH2 = old content of (Program-4)
;	  PUSH3 = old content of (Program-2)
; DESTROYS: - (saves flags)
; STACK: 2
	call	I2CStore2

	; prepare program size
	ldd	C,Y+DATA_VARSPTR
	ldd	B,Y+DATA_VARSPTR+1
	sub	C,L
	sbc	B,H
	std	MHL+0,C		; save program size
	std	MHL+1,B

	; prepare total size -> BC
	ldd	C,Y+DATA_EDITPTR
	ldd	B,Y+DATA_EDITPTR+1
	sub	C,L
	sbc	B,H
	std	MHL+2,C		; save total size
	std	MHL+3,B

	; prepare address
	movw	DE,HL		; DE <- source address
	ldi	L,lo8(SLOT_BEG)	; start of program slot
	ldi	H,hi8(SLOT_BEG)

	; write all pages
; INPUT: HL = destination address in Flash (must be aligned to 64 bytes = SPM_PAGESIZE)
;	 DE = source address, page data in SRAM (of size 64 bytes = SPM_PAGESIZE)
; OUTPUT: HL = next destination address
;	  DE = next source address
; DESTROYS: AF, R1, R0
2:	rcall	SpmWrite	; write 1 page
	subi	C,lo8(SPM_PAGESIZE) ; shift size counter
	sbci	B,hi8(SPM_PAGESIZE)
	brpl	2b

	; restore old content
; INPUT: PUSH2 = old content of (Program-4)
;	 PUSH3 = old content of (Program-2)
; OUTPUT: HL = program address - 4
; DESTROYS: -
; STACK: 2 (saves flags)
	jmp	I2CRestore

; ----------------------------------------------------------------------------
;                 Load program from internal Flash slot
; ----------------------------------------------------------------------------
; OUTPUT: NC = read error
; DESTROYS: AF, BC, DE, HL, PUSH2, PUSH3
; ----------------------------------------------------------------------------
; Enables interrupts.

.global SpmLoad
SpmLoad:
	; prepare slot addres
	ldi	L,lo8(SLOT_BEG)	; start of program slot
	ldi	H,hi8(SLOT_BEG)

	; load program size -> AF
	lpm	F,MHL+
	lpm	A,MHL+

	; check minimal program size (4 bytes)
	subi	F,4
	sbc	A,ZERO
	brcs	SpmLoadErr	; too small

	; check maximal program size (950 bytes)
	ldi	E,hi8(950)
	cpi	F,lo8(950)
	cpc	A,E
	brcc	SpmLoadErr	; too big

	; get total size -> BC
	lpm	C,MHL+
	lpm	B,MHL+
	sbiw	BC,4
	brcs	SpmLoadErr	; too small

	; check minimal total size
	cp	F,C
	cpc	A,B
	brcc	SpmLoadErr	; too small

	; destination address
	ldi	E,lo8(Program)
	ldi	D,hi8(Program)

	; set end of program
	add	F,E
	adc	A,D
	std	Y+DATA_VARSPTR,F
	std	Y+DATA_VARSPTR+1,A

	; check maximal size
	ldi	F,hi8(951)
	cpi	C,lo8(951)
	cpc	B,F
	brcc	SpmLoadErr	; too big

	; set end of variables
	movw	AF,BC
	add	F,E
	adc	A,D
	std	Y+DATA_EDITPTR,F
	std	Y+DATA_EDITPTR+1,A

	; copy program
2:	lpm	A,MHL+
	st	MDE+,A
	sbiw	BC,1
	brne	2b

	; OK
	sec		; OK flag
	ret

	; error
SpmLoadErr:
	clc		; error flag
	ret
