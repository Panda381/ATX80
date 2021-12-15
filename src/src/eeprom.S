; ****************************************************************************
;
;                                   EEPROM
;
; ****************************************************************************

#include "include.inc"

	.text

; ----------------------------------------------------------------------------
;                           Read EEPROM byte
; ----------------------------------------------------------------------------
; INPUT: BC = source address
; OUTPUT: A = data
; DESTROYS: nothing
; STACK: 2
; ----------------------------------------------------------------------------

; ----- set up address

.global EERead
EERead:
	out	_SFR_IO_ADDR(EEARH),B
	out	_SFR_IO_ADDR(EEARL),C

; ----- start read operation

	sbi	_SFR_IO_ADDR(EECR),EERE

; ----- read data

	in	A,_SFR_IO_ADDR(EEDR)
	ret

; ----------------------------------------------------------------------------
;                   Write EEPROM byte (enables interrupts)
; ----------------------------------------------------------------------------
; INPUT: BC = destination address
;	 F = data
; DESTROYS: nothing
; STACK: 5
; ----------------------------------------------------------------------------

; ----- check old content

.global EEWrite
EEWrite:
	push	A

; INPUT: BC = source address
; OUTPUT: A = data
; DESTROYS: nothing
; STACK: 2 bytes
	rcall	EERead		; read old byte -> A
	cp	A,F
	breq	EEWrite4	; data already set

; ----- set up address and data

	out	_SFR_IO_ADDR(EEARH),B
	out	_SFR_IO_ADDR(EEARL),C
	out	_SFR_IO_ADDR(EEDR),F

; ----- start write operation

	cli			; disable interrupts
#ifdef MCU8
	sbi	_SFR_IO_ADDR(EECR),EEMWE ; from now, 4 clock cycles to write EEWE
	sbi	_SFR_IO_ADDR(EECR),EEWE
#else
	sbi	_SFR_IO_ADDR(EECR),EEMPE ; from now, 4 clock cycles to write EEWE
	sbi	_SFR_IO_ADDR(EECR),EEPE
#endif
	sei			; enable interrupts

; ----- wait operation

2:
#ifdef MCU8
	sbic	_SFR_IO_ADDR(EECR),EEWE
#else
	sbic	_SFR_IO_ADDR(EECR),EEPE
#endif
	rjmp	2b

EEWrite4:
	pop	A
	ret

; ----------------------------------------------------------------------------
;                         Auto-save program to EEPROM
; ----------------------------------------------------------------------------
; DESTROYS: AF, BC, DE, HL
; STACK: 7
; ----------------------------------------------------------------------------

.global AutoSave
AutoSave:
	; write address -> BC
	clr	C
	clr	B

	; program address -> HL
	ldi	L,lo8(Program)		; start of program -> HL
	ldi	H,hi8(Program)

	; program size
	ldd	E,Y+DATA_VARSPTR	; end of program -> DE
	ldd	D,Y+DATA_VARSPTR+1
	sub	E,L			; length of program -> DE
	sbc	D,H
	breq	6f			; zero size

	; limit program size
	ldi	F,hi8(PROG_NUM)
	cpi	E,lo8(PROG_NUM)		; max. program size
	cpc	D,F
	brcs	2f			; size is OK
	ldi	E,lo8(PROG_NUM)		; limit size
	ldi	D,hi8(PROG_NUM)

	; write program
2:	ld	F,MHL+			; read byte
; INPUT: BC = destination address
;	 F = data
; DESTROYS: -
; STACK: 5
	rcall	EEWrite			; write byte to EEPROM

	; next byte
	adiw	BC,1			; increase destination address
	sbiw	DE,1			; decrease program size
	brne	2b

	; clear rest of EEPROM
6:	ldi	F,hi8(PROG_NUM)
	cpi	C,lo8(PROG_NUM)		; check destination address
	cpc	B,F
	brcc	8f			; end of EEPROM
	ldi	F,0xff			; clear byte
; INPUT: BC = destination address
;	 F = data
; DESTROYS: -
; STACK: 5
	rcall	EEWrite			; write byte to EEPROM

	; next byte
	adiw	BC,1			; increase destination address
	rjmp	6b

8:	ret

; ----------------------------------------------------------------------------
;                         Auto-load program from EEPROM
; ----------------------------------------------------------------------------
; OUTPUT: HL = end of program
; DESTROYS: AF, BC, DE
; STACK: 7
; ----------------------------------------------------------------------------

.global AutoLoad
AutoLoad:
	; read address -> BC
	clr	C
	clr	B

	; program address -> HL
	ldi	L,lo8(Program)		; start of program -> HL
	ldi	H,hi8(Program)

	; max. program size -> DE
	ldi	E,lo8(PROG_NUM)
	ldi	D,hi8(PROG_NUM)

	; read program from EEPROM
; INPUT: BC = source address
; OUTPUT: A = data
; DESTROYS: nothing
; STACK: 2 bytes
2:	rcall	EERead			; read byte
	st	MHL+,A
	adiw	BC,1			; increase source address
	sbiw	DE,1			; decrease program size
	brne	2b

	; find last NEWLINE of end of program
4:	ld	A,-MHL
	cpi	A,NEWLINE
	breq	6f
	ldi	D,hi8(Program)
	cpi	L,lo8(Program)
	cpc	H,D
	brne	4b
	sbiw	HL,1

6:	adiw	HL,1
	ret
