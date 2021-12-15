
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

; ----- initialize status register (not needed, initialized in boot code)

	out	_SFR_IO_ADDR(SREG),ZERO

; ----- initialize stack (not needed, initialized in boot code)

	ldi	r24,lo8(STACK)	; end of stack (= last byte of RAM)
	ldi	r25,hi8(STACK)
	out	_SFR_IO_ADDR(SPH),r25
	out	_SFR_IO_ADDR(SPL),r24

; ----- initialize port B
; PB2: VSYNC, output HIGH

	ldi	r24,B2			; outputs: VSYNC
	out	_SFR_IO_ADDR(PORTB),r24	; set level of port B
	out	_SFR_IO_ADDR(DDRB),r24	; set direction of port B

; ----- initialize port C
; PC0: COL4, input pull-up (key 4)
; PC1: COL3, input pull-up (key 3)
; PC2: COL2, input pull-up (key 2)
; PC3: COL1, input pull-up (key 1)
; PC4: SDA, input pull-up
; PC5: SCL, input pull-up

	ldi	r24,B0+B1+B2+B3+B4+B5	; pull-ups: SDA, SCL
	out	_SFR_IO_ADDR(PORTC),r24	; set pull-ups of port C
	out	_SFR_IO_ADDR(DDRC),ZERO ; set direction of port C

; ----- initialize port D - set ROW4 to output LOW

	sbi	_SFR_IO_ADDR(DDRD),6
	cbi	_SFR_IO_ADDR(PORTD),6

; ----- signalize waiting

Loop:	ldi	r24,lo8(125)
	ldi	r25,hi8(125)
	rcall	waitms			; short delay

	cbi	_SFR_IO_ADDR(PORTB),2	; VSYNC LED OFF

	ldi	r24,lo8(125)
	ldi	r25,hi8(125)
	rcall	waitms			; short delay

	sbi	_SFR_IO_ADDR(PORTB),2	; VSYNC LED ON

; ----- check keyboard

	ldi	r24,0			; LOAD: first slot of group A
	ldi	r25,11
	sbis	_SFR_IO_ADDR(PINC),3 ; 1
	rjmp	Load

	ldi	r24,11			; LOAD: first slot of group B
	ldi	r25,22
	sbis	_SFR_IO_ADDR(PINC),2 ; 2
	rjmp	Load

	ldi	r24,22			; LOAD: first slot of group C
	ldi	r25,32
	sbis	_SFR_IO_ADDR(PINC),1 ; 3
	rjmp	Load

	sbis	_SFR_IO_ADDR(PINC),0 ; 4
	rjmp	Save

	rjmp	Loop

; ----- load

Load:
	; delay to set LED ON
	push	r24
	push	r25
	ldi	r24,lo8(1000)
	ldi	r25,hi8(1000)
	rcall	waitms			; short delay
	pop	r25
	pop	r24

; ----- prepare destination address and slot index

	ldi	r30,lo8(FlashStart)	; destination address
	ldi	r31,hi8(FlashStart)

; ----- push registers

2:	push	r25
	push	r24
	push	r30
	push	r31

; ----- load one program

; INPUT: R24 = slot index 0..
; OUTPUT: NC = read error
; DESTROYS: R31, R30, R25, R24, R23, R22, R0
	rcall	I2CLoad

; ----- pop registers

	pop	r31
	pop	r30
	pop	r24
	pop	r25
	brcc	8f		; error, skip this slot

; ----- write program

	push	r25
	push	r24

	; check memory overflow
	lds	r24,SlotSize	; get slot size
	lds	r25,SlotSize+1
	add	r24,r30		; end of program
	adc	r25,r31
	subi	r24,lo8(FlashEnd-SPM_PAGESIZE-1) ; check max. address
	sbci	r25,hi8(FlashEnd-SPM_PAGESIZE-1)
	brcc	5f		; memory overflow	

	lds	r24,SlotSize	; get slot size
	lds	r25,SlotSize+1
	ldi	r26,lo8(SlotSize)
	ldi	r27,hi8(SlotSize)
; INPUT: R31:R30 (Z) = destination address in Flash (must be aligned to 64 bytes = SPM_PAGESIZE)
;	 R27:R26 (X) = source address, page data in SRAM (of size 64 bytes = SPM_PAGESIZE)
; OUTPUT: R31:R30 (Z) = next destination address
;	  R27:R26 (X) = next source address
; DESTROYS: R23, R22, R1, R0
4:	call	SpmWrite		; write one SPM page

	subi	r24,lo8(SPM_PAGESIZE)
	sbci	r25,hi8(SPM_PAGESIZE)
	breq	5f
	brpl	4b		; next page

5:	pop	r24
	pop	r25

; ----- next slot

8:	inc	r24			; increment slot index
	cp	r24,r25			; check last index of max. slot
	brne	2b			; get next slot

; ----- write end-mark

	ldi	r24,0xff
	sts	SlotSize,r24
	sts	SlotSize+1,r24
	sts	SlotInx,r24

	ldi	r26,lo8(SlotSize)
	ldi	r27,hi8(SlotSize)
; INPUT: R31:R30 (Z) = destination address in Flash (must be aligned to 64 bytes = SPM_PAGESIZE)
;	 R27:R26 (X) = source address, page data in SRAM (of size 64 bytes = SPM_PAGESIZE)
; OUTPUT: R31:R30 (Z) = next destination address
;	  R27:R26 (X) = next source address
; DESTROYS: R23, R22, R1, R0
	call	SpmWrite		; write one SPM page

	rjmp	Loop

; ----- save

Save:
	; delay to set LED ON
	push	r24
	ldi	r24,lo8(500)
	ldi	r25,hi8(500)
	rcall	waitms			; short delay
	pop	r24

	; prepare start of first slot -> R31:R30
	ldi	r30,lo8(FlashEnd+2)
	ldi	r31,hi8(FlashEnd+2)
	lpm	r0,Z+
	lpm	r31,Z
	mov	r30,r0

	; get slot size -> R27:R26
2:	lpm	r26,Z+			; slot size
	lpm	r27,Z+
	cpi	r27,hi8(1024+256)
	brcc	9f			; invalid slot size
	cpi	r26,8
	cpc	r27,ZERO
	brcs	9f

	movw	r24,r26
	add	r24,r30
	adc	r25,r31
	subi	r24,lo8(FlashEnd)
	sbci	r25,hi8(FlashEnd)
	brcc	9f			; overflow memory end

	; get slot index -> R24
	lpm	r24,Z+			; slot index
	cpi	r24,64
	brcc	9f			; invalid slot index

	; push registers
	push	r26
	push	r27
	push	r30
	push	r31

	; get program size
	lpm	r26,Z+
	lpm	r27,Z+
	ldi	r25,hi8(1000)
	cpi	r26,lo8(1000)
	cpc	r27,r25
	brcc	8f			; invalid program size

	; get total size
	lpm	r26,Z+
	lpm	r27,Z+
	cpi	r26,lo8(1000)
	cpc	r27,r25
	brcc	8f			; invalid total size
	sbiw	r30,4

	; write slot
; INPUT: R24 = slot index 0..63
;	 R27:R26 = data size
;	 R31:R30 = data in ROM
	rcall	I2CSave

	; pop registers
8:	pop	r31
	pop	r30
	pop	r27
	pop	r26

	; shift to next slot
	sbiw	r30,3
	add	r30,r26
	adc	r31,r27
	rjmp	2b

9:	rjmp	Loop
