
; ****************************************************************************
;
;                   ATX80 BIOS - simulate Z80 instructions
;
; ****************************************************************************

; ----------------------------------------------------------------------------
;      Exchange registers DE and HL (simulate Z80 EX DE,HL instruction)
; ----------------------------------------------------------------------------
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------

.global EXDEHL
EXDEHL:
	movw	r0,DE
	movw	DE,HL
	movw	HL,r0
	ret

; ----------------------------------------------------------------------------
;   Exchange registers with alternate registers (simulate EXX instruction)
; ----------------------------------------------------------------------------
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------

.global EXX
EXX:
	; exchange BC <-> BC_
	movw	r0,BC
	movw	BC,BC_
	movw	BC_,r0

	; exchange DE <-> DE_
	movw	r0,DE
	movw	DE,DE_
	movw	DE_,r0

	; exchange HL <-> HL_
	movw	r0,HL
	movw	HL,HL_
	movw	HL_,r0
	ret

; ----------------------------------------------------------------------------
;              Copy with increment (simulate Z80 LDIR instruction)
; ----------------------------------------------------------------------------
; OPERATION: (HL) -> (DE), DE++, HL++, BC--, repeat while BC != 0
; INPUT: HL = pointer to first byte of source address
;	 DE = pointer to first byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer after last byte of source address
;	  DE = pointer after last byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------

.global LDIR
LDIR:
	in	r1,_SFR_IO_ADDR(SREG) ; save status register
2:	ld	r0,MHL+		; load source byte and increment HL
	st	MDE+,r0		; save destination byte and increment DE
	sbiw	BC,1		; decrement counter
	brne	2b		; repeat while BC != 0
	out	_SFR_IO_ADDR(SREG),r1 ; restore status register
	ret

; ----------------------------------------------------------------------------
;              Copy with decrement (simulate Z80 LDDR instruction)
; ----------------------------------------------------------------------------
; OPERATION: (HL) -> (DE), DE--, HL--, BC--, repeat while BC != 0
; INPUT: HL = pointer to last byte of source address
;	 DE = pointer to last byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer before first byte of source address
;	  DE = pointer before first byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------

.global LDDR
LDDR:
	in	r1,_SFR_IO_ADDR(SREG) ; save status register
2:	ld	r0,MHL		; load source byte
	st	MDE,r0		; save destination byte
	sbiw	HL,1		; decrement HL
	sbiw	DE,1		; decrement DE
	sbiw	BC,1		; decrement counter
	brne	2b		; repeat while BC != 0
	out	_SFR_IO_ADDR(SREG),r1 ; restore status register
	ret

; ----------------------------------------------------------------------------
;               Load cursor address DATA_CURPTR into HL
; ----------------------------------------------------------------------------
; OUTPUT: HL = cursor address DATA_CURPTR
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global LoadCurPtr
LoadCurPtr:
	ldd	L,Y+DATA_CURPTR
	ldd	H,Y+DATA_CURPTR+1
	ret

; ----------------------------------------------------------------------------
;            Load pointer to edit line DATA_EDITPTR into HL
; ----------------------------------------------------------------------------
; OUTPUT: HL = address of edit line DATA_EDITPTR
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global LoadEditPtr
LoadEditPtr:
	ldd	L,Y+DATA_EDITPTR
	ldd	H,Y+DATA_EDITPTR+1
	ret

; ----------------------------------------------------------------------------
;            Load pointer to start of display DATA_DISPPTR into HL
; ----------------------------------------------------------------------------
; OUTPUT: HL = address of start of display DATA_DISPPTR
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global LoadDispPtr
LoadDispPtr:
	ldd	L,Y+DATA_DISPPTR
	ldd	H,Y+DATA_DISPPTR+1
	ret

; ----------------------------------------------------------------------------
;               Load address of variable DATA_VARDEST into HL
; ----------------------------------------------------------------------------
; OUTPUT: HL = address of variable name DATA_VARDEST
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global LoadVarDest
LoadVarDest:
	ldd	L,Y+DATA_VARDEST
	ldd	H,Y+DATA_VARDEST+1
	ret

; ----------------------------------------------------------------------------
;                   Load last result DATA_RESULT into HL
; ----------------------------------------------------------------------------
; OUTPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global LoadResult
LoadResult:
	ldd	L,Y+DATA_RESULT
	ldd	H,Y+DATA_RESULT+1
	ret

; ----------------------------------------------------------------------------
;                   Save last result DATA_RESULT from HL
; ----------------------------------------------------------------------------
; INPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global SaveResult
SaveResult:
	std	Y+DATA_RESULT,L
	std	Y+DATA_RESULT+1,H
	ret
