
; ****************************************************************************
;
;                               Main function
;
; ****************************************************************************

#include "include.inc"

	.text

; ----------------------------------------------------------------------------
;                    System reset, start main function
; ----------------------------------------------------------------------------

; Reset
.global main
main:

; ----- initialize global registers

	eor	ZERO,ZERO	; register 0
	ldi	YL,lo8(DataStart) ; data area LOW
	ldi	YH,hi8(DataStart) ; data area HIGH

; ----- initialize status register (not needed, initialized in boot code)

;	out	_SFR_IO_ADDR(SREG),ZERO

; ----- clear flags

	out	_SFR_IO_ADDR(GPIOR0),ZERO

; ----- clear whole RAM memory (initialize to 0)

	ldi	ZL,lo8(RAM_BEG)
	ldi	ZH,hi8(RAM_BEG)
	ldi	r25,hi8(RAM_END)
1:	st	Z+,ZERO
	cpi	r30,lo8(RAM_END)
	cpc	r31,r25
	brne	1b

; ----- initialize stack (not needed, initialized in boot code)

;	ldi	r24,lo8(STACK)	; end of stack (= last byte of RAM)
;	ldi	r25,hi8(STACK)
;	out	_SFR_IO_ADDR(SPH),r25
;	out	_SFR_IO_ADDR(SPL),r24

; ----- prepare display mode

	; load display mode from EEPROM
; INPUT: BC = source address
; OUTPUT: A = data
; DESTROYS: nothing
; STACK: 2
	ldi	C,lo8(CFG_DISP)
	ldi	B,hi8(CFG_DISP)
	rcall	EERead		; read EEPROM
	cpi	A,DISP_OLDVGA	; old VGA
	breq	2f		; videomode is OK
	cpi	A,3		; max. value + 1
	brcs	2f		; videomode is OK
	ldi	A,DISP_OLDVGA	; limit videomode

	; set ROW4 to output LOW
2:	sbi	_SFR_IO_ADDR(DDRD),6
	cbi	_SFR_IO_ADDR(PORTD),6

	; set COL1..COL4 to input pull-up
	ldi	F,B0+B1+B2+B3+B4+B5
	out	_SFR_IO_ADDR(PORTC),F
	
	; wait a while to stabilise signals
; INPUT: BC=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: BC
; STACK: 4
	ldi	C,lo8(1000)
	ldi	B,hi8(1000)
	rcall	waitus		; delay 1 ms

	; get buttons 1..4 and change display mode
	sbis	_SFR_IO_ADDR(PINC),3 ; 1
	ldi	A,DISP_OLDVGA
	sbis	_SFR_IO_ADDR(PINC),2 ; 2
	ldi	A,DISP_VGA
	sbis	_SFR_IO_ADDR(PINC),1 ; 3
	ldi	A,DISP_NTSC
	sbis	_SFR_IO_ADDR(PINC),0 ; 4
	ldi	A,DISP_PAL
	mov	DISPMODE,A

	; write video mode to EEPROM
; INPUT: BC = destination address
;	 F = data
; DESTROYS: nothing
; STACK: 5
	mov	F,A
	ldi	C,lo8(CFG_DISP)
	ldi	B,hi8(CFG_DISP)
	rcall	EEWrite

; ----- initialize port B
; PB0: COL5, input
; PB1: SYNC display synchronization, output LOW
; PB2: VSYNC, output LOW
; PB3: MOSI, output LOW
; PB4: MISO, input
; PB5: SCK, output LOW

	out	_SFR_IO_ADDR(PORTB),ZERO ; set pull-ups of port B
	ldi	r24,B1+B2+B3+B5		; outputs: SYN, VSYNC, MOSI, SCK
	out	_SFR_IO_ADDR(DDRB),r24	; set direction of port B

; ----- initialize port C
; PC0: COL4, input
; PC1: COL3, input
; PC2: COL2, input
; PC3: COL1, input
; PC4: SDA, input pull-up
; PC5: SCL, input pull-up

	ldi	r24,B4+B5		; pull-ups: SDA, SCL
	out	_SFR_IO_ADDR(PORTC),r24	; set pull-ups of port C
	out	_SFR_IO_ADDR(DDRC),ZERO ; set direction of port C

; ----- initialize port D
; PD0: ROW8, input pull-up
; PD1: ROW7, input pull-up
; PD2: ROW6, input pull-up
; PD3: ROW5, input pull-up
; PD4: ROW2, input pull-up
; PD5: ROW3, input pull-up
; PD6: ROW4, input pull-up
; PD7: ROW1, input pull-up

	ldi	r25,0xff
	out	_SFR_IO_ADDR(PORTD),r25 ; set pull-ups of port D
	out	_SFR_IO_ADDR(DDRD),ZERO	; set direction of port D

; ----- Initialize empty string

	ldi	r24,CH_QUOT
	std	Y+DATA_NULSTRING,r24

; ----- initialize keyboard scanner

	std	Y+DATA_KEYPRESS,r25	; no key pressed
	std	Y+DATA_KEYBUF,r25	; no key in buffer

; ----- initialize display driver

	rcall	DispInit	; initialize display (it enables interrupts)

; ----- start BIOS code

	jmp	MainInit		; start BIOS code
