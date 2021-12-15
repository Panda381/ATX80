
; ****************************************************************************
;
;                        Delay loops (F_CPU = 24000000)
;
; ****************************************************************************
; Quartz 24 MHz, 1 clock = 0.0416667 us, 1 us = 24 clocks

#include "include.inc"

	.text

; ----------------------------------------------------------------------------
;                         Short delay 1 us (24 MHz)
; ----------------------------------------------------------------------------
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

; clocks = 3 + 8*2 + 1 + 4 = 24
.global wait1us
wait1us:
	; rcall	wait1us		; [3]
	nop2			; [2]
wait1us1:
	nop2			; [2]
wait1us2:
	nop2			; [2]
	nop2			; [2]
	nop2			; [2]
wait1us4:
	nop2			; [2]
	nop2			; [2]
	nop2			; [2]
	nop			; [1]
	ret			; [4]

; ----------------------------------------------------------------------------
;                    Short delay 2..65535 us
; ----------------------------------------------------------------------------
; INPUT: BC=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: BC
; STACK: 4
; ----------------------------------------------------------------------------

; base clocks (without loops) = 1+1+3+2+14+(-1)+4=24

	; ldi	C,lo8(delay)	; [1]
	; ldi	B,hi8(delay)	; [1]
	; rcall	waitus		; [3]

.global waitus
waitus:
	sbiw	BC,1		; [2] compensate base clocks
	rcall	wait1us4	; [3+3*2+1+4=14]

; ----- loop [24] clocks = 1 us

waitus2:
	rcall	wait1us2	; [3+6*2+1+4=20]
	sbiw	BC,1		; [2] decrement BC
	brne	waitus2		; [1,2] loop

	ret			; [4]

; ----------------------------------------------------------------------------
;                    Long delay 1..65536 ms (24 MHz)
; ----------------------------------------------------------------------------
; INPUT: BC=delay in [ms] (1..65535, 0=65536 ms)
; DESTROYS: DE, BC
; STACK: 6
; ----------------------------------------------------------------------------

; ----- delay BC -> DE

.global waitms
waitms:
	movw	DE,BC		; R27:R26 <- required delay

; ----- loop of 1 ms (24000 clocks)

waitms4:
	rcall	wait1us1	; [3+7*2+1+4=22]

	ldi	C,lo8(999)	; [1] delay low
	ldi	B,hi8(999)	; [1] delay high
; INPUT: BC=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: BC
; STACK: 4
	rcall	waitus		; [3+8*2+(delay-1)*24-1+4 = 23974]

	sbiw	DE,1		; [2] decrement DE
	brne	waitms4		; [1,2] loop

	ret
