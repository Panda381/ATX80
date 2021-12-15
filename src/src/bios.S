
; ****************************************************************************
;
;                               ATX80 BIOS
;
; ****************************************************************************

; RAM Memory
; ----------
; - system variables, pointed by Y register, start address 'DataStart'
; - program code, start address 'Program'; every line starts with 2 bytes of line number
;	(higher byte first) and ends with NEWLINE; end of program is byte >= 0x40 (first byte of program variables)
; - program variables, start pointer 'VarsPtr', first byte of every entry contains flags in bits 5..7;
; - variables end-marker, byte 0x80
; - edit line, start pointer 'EditPtr', terminated with NEWLINE
; - display buffer, start poiner 'DispPtr', max. 24 rows, every row is terminated with NEWLINE
; - ...free space, start pointer 'DispEnd'
; - system stack, end address 'STACK', can use return program lines after GO SUB lines

; Format of vairables and program lines
; -------------------------------------
; 00xxxxxx xxxxxxxx code NEWLINE - program line, starting with 14-bit line number HIGH and then LOW (range 0..9999)
; 011xxxxx numL numH - short-named 16-bit integer variable, name is letter A..Z (0x26..0x3F)
; 010xxxxx 00xxxxxx..10xxxxxx numL numH - long-named 16-bit integer variable, name: 010x first / 00x next / 10x last
; 100xxxxx text 0x01 - text variable, name is letter A..Z (0x26..0x3F), terminated with " character (0x01)
; 101xxxxx size numL0 numH0 numL1 numH1.. - array of 16-bit integers, size = 1..255, name is letter A..Z (0x26..0x3F)
; 111xxxxx valueL valueH limitL limitH lineL lineH - control code of FOR loop (current value, last value, line number)
; 10000000 variables end-marker

#include "include.inc"

	.text

; ----------------------------------------------------------------------------
;                              Error
; ----------------------------------------------------------------------------
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; Note: Do not call this as function (as ZX80 does it), but jump here using rjmp.
; ZX80: L0008, RST 08H

.global Error
Error:
	; set error code only for the first time, set error flag
	IF_NOERROR		; if no error, save error code
.global ErrorSet
ErrorSet:
	std	Y+DATA_ERRCODE,L ; save error code (only if not error)
	SET_ERROR		; set error flag
GetCharRet:
	ret

; ----------------------------------------------------------------------------
;         Get current character from edit line with skipping spaces
; ----------------------------------------------------------------------------
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
; ----------------------------------------------------------------------------
; Function clears Z flag, it is required in ScanLoop function.
; ZX80: L001A

.global GetChar
GetChar:
	; get current address of the text -> HL
	ldd	L,Y+DATA_CHARPTR	; pointer to current character
	ldd	H,Y+DATA_CHARPTR+1

	; load character -> A
	ld	A,MHL

GetChar2:
	; check space character
	cpi	A,CH_SPC		; space character?
	brne	GetCharRet		; return if not a space

; NextChar must follow

; ----------------------------------------------------------------------------
;         Get next character from edit line with skipping spaces
; ----------------------------------------------------------------------------
; OUTPUT: A = next character (from next address, skips cursor and spaces)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0020, RST 20H
  
.global NextChar
NextChar:
	; Increment and load character from edit line
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAdd		; load character
	rjmp	GetChar2	; skip spaces

; ----------------------------------------------------------------------------
;                     Evaluate bracket expression
; ----------------------------------------------------------------------------
; DESTROYS:
; ----------------------------------------------------------------------------
; ZX80: L0049

.global Bracket
Bracket:
	; evaluate expression
; INPUT: HL = pointer to text
	rcall	EvalExp		; evaluate expression

	; check right bracket
	ld	A,MHL		; get next character
	cpi	A,TOKEN_RPAR	; check command ')'
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	breq	CharAdd		; right bracket is OK
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rjmp	InsErr		; not right bracket, insert error

; ----------------------------------------------------------------------------
;              Increment and load next character from edit line
; ----------------------------------------------------------------------------
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0052, L0018, RST 18H
  
.global CharAdd
CharAdd:
	; get current address of the text -> HL
	ldd	L,Y+DATA_CHARPTR	; pointer to current character
	ldd	H,Y+DATA_CHARPTR+1

; CharAddLP must follow

; ----------------------------------------------------------------------------
;          Increment address and load next character (skip cursor)
; ----------------------------------------------------------------------------
; INPUT: HL = current address of the text
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0055

.global CharAddLP
CharAddLP:
	; increment and save new pointer to the text
	adiw	HL,1			; increment pointer
	std	Y+DATA_CHARPTR,L	; save new pointer
	std	Y+DATA_CHARPTR+1,H

	; load character -> A
	ld	A,MHL

	; check 'K' cursor character
	cpi	A,CURSOR		; cursor character? (inverted 'K')
	brne	GetCharRet		; not cursor, end

	; save pointer to the cursor
	std	Y+DATA_CURPTR,L		; save pointer to the cursor
	std	Y+DATA_CURPTR+1,H

	; update K-mode flag
	ldd	A,Y+DATA_FLAGX		; load extended flags
	sbrc	A,7			; update K-mode flag? Skip if do not update K-mode
	SET_KMODE			; set K-mode flag
	rjmp	CharAddLP		; load next character

; ----------------------------------------------------------------------------
;                           Token table
; ----------------------------------------------------------------------------
; ZX80: L00BA

.global Tokens
Tokens:
	.byte	0xD4		; threshold character (= index of first token)
	.byte	CH_QUERY			+ 0x80	; '?' invalid code
	.byte	CH_QUOT				+ 0x80	; '"'		0xD4 212
	.byte	CH_T,CH_H,CH_E,CH_N		+ 0x80	; THEN		0xD5 213
	.byte	CH_T,CH_O			+ 0x80	; TO		0xD6 214
	.byte	CH_SEMI				+ 0x80	; ;		0xD7 215
	.byte	CH_COMMA			+ 0x80	; ,		0xD8 216
	.byte	CH_RPAR				+ 0x80	; )		0xD9 217
	.byte	CH_LPAR				+ 0x80	; (		0xDA 218
	.byte	CH_N,CH_O,CH_T			+ 0x80	; NOT		0xDB 219
	.byte	CH_MINUS			+ 0x80	; -		0xDC 220
	.byte	CH_PLUS				+ 0x80	; +		0xDD 221
	.byte	CH_ASTER			+ 0x80	; *		0xDE 222
	.byte	CH_SLASH			+ 0x80	; /		0xDF 223
	.byte	CH_A,CH_N,CH_D			+ 0x80	; AND		0xE0 224
	.byte	CH_O,CH_R			+ 0x80	; OR		0xE1 225
	.byte	CH_ASTER,CH_ASTER		+ 0x80	; **		0xE2 226
	.byte	CH_EQU				+ 0x80	; =		0xE3 227
	.byte	CH_GR				+ 0x80	; >		0xE4 228
	.byte	CH_LT				+ 0x80	; <		0xE5 229
	.byte	CH_L,CH_I,CH_S,CH_T		+ 0x80	; LIST		0xE6 230
	.byte	CH_R,CH_E,CH_T,CH_U,CH_R,CH_N 	+ 0x80	; RETURN	0xE7 231
	.byte	CH_C,CH_L,CH_S			+ 0x80	; CLS		0xE8 232
	.byte	CH_D,CH_I,CH_M			+ 0x80	; DIM		0xE9 233
	.byte	CH_S,CH_A,CH_V,CH_E		+ 0x80	; SAVE		0xEA 234
	.byte	CH_F,CH_O,CH_R			+ 0x80	; FOR		0xEB 235
	.byte	CH_G,CH_O,CH_SPC,CH_T,CH_O	+ 0x80	; GO TO		0xEC 236
	.byte	CH_P,CH_O,CH_K,CH_E		+ 0x80	; POKE		0xED 237
	.byte	CH_I,CH_N,CH_P,CH_U,CH_T	+ 0x80	; INPUT		0xEE 238
	.byte	CH_R,CH_A,CH_N,CH_D,CH_O
	.byte		CH_M,CH_I,CH_S,CH_E	+ 0x80	; RANDOMISE	0xEF 239
	.byte	CH_L,CH_E,CH_T			+ 0x80	; LET		0xF0 240
;	.byte	CH_QUERY			+ 0x80	; '?'		0xF1 241
	.byte	CH_F,CH_A,CH_S,CH_T		+ 0x80	; FAST		0xF1 241 ... ATX80 extension, set fast mode of display
;	.byte	CH_QUERY			+ 0x80	; '?'		0xF2 242
	.byte	CH_S,CH_L,CH_O,CH_W		+ 0x80	; SLOW		0xF2 242 ... ATX80 extension, set slow mode of display
	.byte	CH_N,CH_E,CH_X,CH_T		+ 0x80	; NEXT		0xF3 243
	.byte	CH_P,CH_R,CH_I,CH_N,CH_T	+ 0x80	; PRINT		0xF4 244
;	.byte	CH_QUERY			+ 0x80	; '?'		0xF5 245
	.byte	CH_M,CH_E,CH_M,CH_O,CH_R,CH_Y	+ 0x80	; MEMORY	0xF5 245 ... ATX80 extension, display memory info
	.byte	CH_N,CH_E,CH_W			+ 0x80	; NEW		0xF6 246
	.byte	CH_R,CH_U,CH_N			+ 0x80	; RUN		0xF7 247
	.byte	CH_S,CH_T,CH_O,CH_P		+ 0x80	; STOP		0xF8 248
	.byte	CH_C,CH_O,CH_N,CH_T,CH_I
	.byte		CH_N,CH_U,CH_E		+ 0x80	; CONTINUE	0xF9 249
	.byte	CH_I,CH_F			+ 0x80	; IF		0xFA 250
	.byte	CH_G,CH_O,CH_SPC,CH_S,CH_U,CH_B	+ 0x80	; GO SUB	0xFB 251
	.byte	CH_L,CH_O,CH_A,CH_D		+ 0x80	; LOAD		0xFC 252
	.byte	CH_C,CH_L,CH_E,CH_A,CH_R	+ 0x80	; CLEAR		0xFD 253
	.byte	CH_R,CH_E,CH_M			+ 0x80	; REM		0xFE 254
	.byte	CH_QUERY			+ 0x80	; '?'		0xFF 255

	.balign	2	; align to 2 bytes

; ----------------------------------------------------------------------------
;                           SAVE command
; ----------------------------------------------------------------------------
; INPUT: BC = slot index 0..64
; ----------------------------------------------------------------------------
; ZX80: L01B6

.global Save
Save:
	; quit if checking syntax
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
	rcall	Unstack

	; save program to internal Flash slot
	adiw	BC,0		; check zero index
	brne	2f		; save to external EEPROM
; OUTPUT: NC = write error
; DESTROYS: AF, BC, DE, HL, PUSH2, PUSH3
	jmp	SpmSave

	; save program
; INPUT: BC = slot number 0..64
; OUTPUT: NC = write error
; DESTROYS: AF, BC, DE, HL, PUSH1, PUSH2, PUSH3
2:	sbiw	BC,1		; slot number correction
	rjmp	I2CSave

; ----------------------------------------------------------------------------
;                      Initialize registers
; ----------------------------------------------------------------------------

InitReg:
	; initialize status register (it disables interrupts)
	out	_SFR_IO_ADDR(SREG),ZERO

	; clear flags
	out	_SFR_IO_ADDR(GPIOR0),ZERO ; clear flags
	std	Y+DATA_ERRCODE,ZERO	; error code
	std	Y+DATA_FLAGX,ZERO	; extra flags
	std	Y+DATA_EDITLINE,ZERO	; clear current line
	std	Y+DATA_EDITLINE+1,ZERO	; clear current line
	std	Y+DATA_DISPTOP,ZERO	; new top row
	std	Y+DATA_DISPTOP+1,ZERO

	; initialize stack
	ldi	L,lo8(STACK)	; end of stack (= last byte of RAM)
	ldi	H,hi8(STACK)
	ret

; ----------------------------------------------------------------------------
;                           LOAD command
; ----------------------------------------------------------------------------
; INPUT: BC = slot index 0..64
; ----------------------------------------------------------------------------
; ZX80: L0206

.global Load
Load:
	; quit if checking syntax
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
	rcall	Unstack

	; load program from internal Flash slot
	adiw	BC,0		; check zero index
	brne	3f		; load from external EEPROM
; OUTPUT: NC = read error
; DESTROYS: AF, BC, DE, HL, PUSH2, PUSH3
	call	SpmLoad
	rjmp	4f

; INPUT: BC = slot number 0...
; OUTPUT: NC = load error
3:	sbiw	BC,1		; slot number correction
	rcall	I2CLoad
4:	brcs	2f		; operation OK
	rjmp	CmdNew		; clear program

	; initialize registers
2:	rcall	InitReg
	out	_SFR_IO_ADDR(SPH),H
	out	_SFR_IO_ADDR(SPL),L

	rjmp	MainInit3

; ----------------------------------------------------------------------------
;                           LIST command
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line
;	 BC = last result
;	 Z = ZY if result is 0
; DESTROYS: 
; ----------------------------------------------------------------------------
; Note: Deletes return address and jumps to main routine to automatic listing.
; ZX80: L0256

.global CmdList
CmdList:
	; clear 2 invalid highest bits of the line number
	andi	B,0x3f			; mask valid bits

	; save new current line number
	std	Y+DATA_EDITLINE,C
	std	Y+DATA_EDITLINE+1,B

	; delete return address
	POP_BC

	; jump to automatic listing in main routine
	rjmp	MainExec

; ----------------------------------------------------------------------------
;                           System first start
; ----------------------------------------------------------------------------
; ZX80: RST 00H, L0000, L0261

.global MainInit
MainInit:
	; auto-load program
; OUTPUT: HL = end of program
; DESTROYS: AF, BC, DE
; STACK: 7
	rcall	AutoLoad
	rjmp	MainInit2

; ----------------------------------------------------------------------------
;                           NEW command
; ----------------------------------------------------------------------------
; STACK: initialize
; ----------------------------------------------------------------------------
; ZX80: RST 00H, L0000

.global CmdNew
CmdNew:
	; initialize registers
	rcall	InitReg
	out	_SFR_IO_ADDR(SPH),H
	out	_SFR_IO_ADDR(SPL),L

	; start of program variables (end of program)
	ldi	L,lo8(Program)		; start of allocable memory
	ldi	H,hi8(Program)

MainInit2:

	std	Y+DATA_VARSPTR,L	; set start of program variables
	std	Y+DATA_VARSPTR+1,H

	; end-mark of program variables
	ldi	F,0x80			; end-mark of program variables
	st	MHL+,F			; store end mark of program variables

	; start of edit line (working space)
	std	Y+DATA_EDITPTR,L	; set start of edit line
	std	Y+DATA_EDITPTR+1,H

MainInit3:

	; auto-save program to EEPROM
	;   Note: re-save during MainInit is OK, no writes are performed.
; DESTROYS: AF, BC, DE, HL
; STACK: 7
	rcall	AutoSave

	; push 0x3F00 into system stack = end-marker of GOSUB program stack
	push	ZERO
	ldi	A,0x3F
	push	A

	; enable interrupts
	sei

; MainExec must continue

; ----------------------------------------------------------------------------
;                      Start main execution loop
; ----------------------------------------------------------------------------
; ZX80: L0283

.global MainExec
MainExec:
	; insert [K] cursor to the start of edit line
; OUTPUT: HL = address of edit line DATA_EDITPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadEditPtr		; load pointer to edit line into HL
	ldi	F,CURSOR		; cursor, inverted 'K' character
	st	MHL+,F			; store [K] cursor

	; NEWLINE at end of edit line
	ldi	F,NEWLINE		; NEWLINE character at end of edit line
	st	MHL+,F			; store NEWLINE character

	; start of display file
	std	Y+DATA_DISPPTR,L	; start of display
	std	Y+DATA_DISPPTR+1,H

	; set number of lower screen to 2 rows
	ldi	F,2			; 2 rows
	std	Y+DATA_DISP2LINES,F	; set number of rows of lower screen

; ----- start of automatic listing
; ZX80: L0293
; 1) At first, continue listing from the current top row.
; 2) If current line was not reached, list is restarted with top line = previous line of current line

.global AutoList
AutoList:
	; clear screen
; OUTPUT: HL = current print address (= start of display + 1)
;	  C = remaining columns (= 33)
;	  B = remaining rows (= 23)
; DESTROYS: - (saves flags)
; STACK: 4
	rcall	DispCls			; clear screen
	movw	DE,HL			; DE <- end of the display

	; check if display is full
	mov	A,B			; remaining rows (= 23)
	ldd	r0,Y+DATA_DISP2LINES	; number of rows of lower screen
	sub	A,r0			; get number of free rows
	brcs	EdCopy			; display is full, go to copy edit line

	; new number of remaining rows -> B'
	inc	A			; reserve for 1 blank line
	mov	B,A			; set new remaining rows
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX			; exchange registers (print registers -> B', C', DE')

	; limit underflow of top row - use current row as top row if current row is above top row
	ldd	E,Y+DATA_EDITLINE	; get current line number with cursor '>' -> DE
	ldd	D,Y+DATA_EDITLINE+1

	ldd	L,Y+DATA_DISPTOP	; get top line number -> HL
	ldd	H,Y+DATA_DISPTOP+1

	sub	E,L			; distance of current line to top line -> DE, top line -> HL
	sbc	D,H
	brcc	2f			; no underflow

	add	L,E			; limit top line to current line -> HL
	adc	H,D
	std	Y+DATA_DISPTOP,L	; save new top row
	std	Y+DATA_DISPTOP+1,H

	; find address of first program line HL
; INPUT: HL = required line number
; OUTPUT: HL = address of program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = required line number
;	  ZY = required line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
2:	rcall	LineFind		; find address of program line

	; prepare flag: E=0 means current line was printed
	ldi	E,0

	; list all lines, up to program end or up to full upper screen
; INPUT: HL = pointer to program line
;	 E = flag, 0=current line was printed, 1=current line was not printed
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = error, display full or end of program reached
;	  E = updated flag
;	  HL = pointer to next program line
;	  B', C', DE' = updated
; DESTROYS: A, BC, D, HL', PUSH1, PUSH2, R1, R0
; STACK: 8
3:	rcall	OutLine		; print whole BASIC line
	brcs	3b		; if all OK, list next program line

	; check if current line has appeared
	dec	E		; check flag, 1=current line was not printed
	brne	ListDone	; current line was printed, all done

; current row is after last row -> use previous row or current row as top row

	; get address of previous line to current line
	movw	PUSH2,HL	; push address of next program line
; OUTPUT: HL = address of current program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = current line number
;	  ZY = current line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
	rcall	CurLineFind	; find address of previous program line -> DE
	movw	HL,PUSH2	; restore address of next program line

; Here is: HL = end address of LIST (not listed row on the bottom), DE = address of previous row before current row

	; distance - check if previous line lies above or below end of list
	sub	L,E
	sbc	H,D

	; if previous line lies above end of list, shift top row 1 row down, to next top row (shift screen 1 row up)
	ldi	L,lo8(DispTop)	; pointer to variable with top line number
	ldi	H,hi8(DispTop)
	brcc	LineFetch	; fetch next line to top line

	; if previous line lies below end of list, use previous line as new top row (shift screen 1 page up)
	ld	A,MDE+		; load previous program line HIGH
	ld	F,MDE		; load previous program line LOW
	st	MHL+,F		; save top program line LOW
	st	MHL,A		; save top program line HIGH
	rjmp	AutoList	; restart autolist from next page

; ----------------------------------------------------------------------------
;                     Cursor down editing
; ----------------------------------------------------------------------------
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L02D5

.global EdDown
EdDown:	ldi	L,lo8(EditLine)	; pointer to number of current line
	ldi	H,hi8(EditLine)

; LineFetch must follow
	
; ----------------------------------------------------------------------------
;                Line fetch - get next line number into variable
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to variable with line number
; OUTPUT: (HL) will be filled with next line number
; DESTROYS: A, BC, DE, PUSH1, PUSH2, R0, R1
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L02D8

.global LineFetch
LineFetch:
	; get line number from variable
	ldd	E,MHL+0		; line number LOW
	ldd	D,MHL+1		; line number HIGH

	; save pointer to the variable
	movw	PUSH2,HL

	; find next line
	movw	HL,DE		; DE <- line number
	adiw	HL,1		; increment to search next line
; INPUT: HL = required line number
; OUTPUT: HL = address of program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = required line number
;	  ZY = required line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
	rcall	LineFind	; find next line number

	; load number of next line
; INPUT: HL = pointer to current line
;	 DE = pointer to previous line
; OUTPUT: HL = pointer to current line + 1
;	  DE = line number (0 = line is invalid)
; DESTROYS: A
; STACK: 2
	rcall	LineNo		; load line number

	; restore pointer to the variable -> HL
	movw	HL,PUSH2

; LineStore must follow

; ----------------------------------------------------------------------------
;                         Store line number into variable
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to variable with line number
;	 DE = line number
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L02E5

.global LineStore
LineStore:
	; if inputting mode, jump to lower screen copying
	IF_INPUT		; if inputting mode
	rjmp	EdCopy		; if input, jump to lower screen copying

	; store line number into variable
	std	MHL+0,E		; store line number LOW
	std	MHL+1,D		; store line number HIGH

	; refresh auto-list
	rjmp	AutoList	; return to auto-list

; ----------------------------------------------------------------------------
;                              List done
; ----------------------------------------------------------------------------
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L02F0

.global ListDone
ListDone:
	; when listing is complete, clear rest of upper screen
; INPUT: B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: DE = new end address of the display
; DESTROYS: A, BC, R1, R0, registers are exchanged using EXX
; STACK: 4
	rcall	ClrEod		; clear rest of screen
	std	Y+DATA_DISP2PTR,E ; set address of lower screen
	std	Y+DATA_DISP2PTR+1,D

; EdCopy must follow

; ----------------------------------------------------------------------------
;                   Lower screen copying and execute key
; ----------------------------------------------------------------------------
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L02F7

.global EdCopy
EdCopy:
	; initialize flags: no leading space, L-mode, L-cursor, syntax on (input mode must be preserved)
;#define F_NOLEAD	0	// 1=no leading space, 0=leading space
;#define F_FAST		1	// 1=fast video mode, 0=slow video mode
;#define F_KMODE	2	// 1=K mode, 0=L mode
;#define F_KCURSOR	3	// 1=K cursor, 0=L cursor
;#define F_ERROR	4	// 1=error code is stored in ErrCode
;#define F_INPUT	5	// 1=inputting, 0=editing
;#define F_NUMRES	6	// 1=numeric result, 0=string result
;#define F_SYNTOFF	7	// 1=syntax off, 0=syntax on
	in	F,_SFR_IO_ADDR(GPIOR0)
	cbr	F,BIT(F_KMODE) | BIT(F_KCURSOR) | BIT(F_NUMRES) | BIT(F_SYNTOFF) ; clear bits
	sbr	F,BIT(F_NOLEAD)	; set bits
	out	_SFR_IO_ADDR(GPIOR0),F

	; check syntax of edit line
; OUTPUT: HL = address of edit line DATA_EDITPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadEditPtr	; get address of edit line -> HL
	rcall	MainGo		; check syntax

	; prepare printing to lower screen: address of lower screen -> DE
	ldd	E,Y+DATA_DISP2PTR
	ldd	D,Y+DATA_DISP2PTR+1

	; number of remaining rows (-> B) and columns (-> C)
	ldd	B,Y+DATA_DISP2LINES ; number of rows of lower screen
	ldi	C,1		; number of remaining columns (empty line)
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers

	; get start of edit line -> HL
; OUTPUT: HL = address of edit line DATA_EDITPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadEditPtr	; get address of edit line -> HL

	; print content of edit line (without line number - line number is now entered as text digits, not binary number)
; INPUT: HL = start of program code (after line number)
;	 E = flag, 0=current line was printed, 1=current line was not printed
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = error, display full or end of program reached
;	  HL = start of next program line
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, R1, R0
; STACK: 8
	rcall	OutLine2
	brcs	2f		; print is OK

	; else increase size of lower screen
	ldd	F,Y+DATA_DISP2LINES ; get number of lines of lower screen
	inc	F		; increase number of lines
	std	Y+DATA_DISP2LINES,F ; store new number of lines
	ldi	A,HEIGHT	; max. number of rows
	cp	A,F		; check maximum number of rows
	brcs	1f		; maximum rows already reached
	rjmp	AutoList	; restart auto-list with higher lower screen

1:	std	Y+DATA_DISP2LINES,A ; limit number or rows to maximum

	; clear rest of display
; INPUT: B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: DE = new end address of the display
; DESTROYS: A, BC, R1, R0, registers are exchanged using EXX
; STACK: 4
2:	rcall	ClrEod		; clear display

	; get key from keyboard
; OUTPUT: A = key (NOKEY = no key)
;	  ZY = no key
; DESTROYS: F
; STACK: 2
3:	call	GetKey	
	breq	3b		; wait for a key

	; check token codes
	cpi	A,0xc0		; sets overflow flag for editing keys 0x70..0x77
	brvs	EdKeys		; jump to editing keys 0x70..0x77

	; insert character at cursor position
; OUTPUT: HL = cursor address DATA_CURPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadCurPtr	; load cursor address -> HL
	ldi	C,1		; 1 byte required
	ldi	B,0
; INPUT: HL = current address (where new data should be inserted)
;	 BC = number of bytes to insert (must be >0)
; OUTPUT: HL = current address - 1
;	  DE = address of start of moved block - 1 (= last byte of new free space)
;	  BC = 0
; DESTROYS: R1, R0
; STACK: 4
	rcall	MakeRoom	; make room for 1 character
	st	MDE,A		; store character
	rjmp	EdCopy		; loop back

; ----------------------------------------------------------------------------
;                         Editing keys
; ----------------------------------------------------------------------------
; INPUT: A = key 0x70..0x77
; STACK: jump to key service, and then the service jumps back to main execution loop.
; ----------------------------------------------------------------------------
; ZX80: L035E

.global EdKeys
EdKeys:
	; address in the table
	ldi	L,lo8(EdKeyTab - 2*0x70)
	ldi	H,hi8(EdKeyTab - 2*0x70)
	add	L,A
	adc	H,ZERO
	add	L,A
	adc	H,ZERO		; table + 2*key_code

	; load jump address into the stack
	lpm	C,Z+		; load jump address LOW
	lpm	B,Z		; load jump address HIGH
	lsr	B
	ror	C		; convert address to word index
	PUSH_BC			; push jump address into stack

	; get cursor address -> HL, then jump to function
; OUTPUT: HL = cursor address DATA_CURPTR
; DESTROYS: -
; STACK: 2
	rjmp	LoadCurPtr	; load cursor address -> HL

; ----------------------------------------------------------------------------
;                    Delete one character from edit line
; ----------------------------------------------------------------------------
; INPUT: HL = address of the character
; OUTPUT: DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L036C

.global DelChar
DelChar:
	ldi	C,1		; delete 1 character
	ldi	B,0
; INPUT: HL = current address, start of deleted memory block
;	 BC = number of bytes of deleted memory block
; OUTPUT: DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 4
	rjmp	Reclaim		; reclaim memory

; ----------------------------------------------------------------------------
;                      Jump table of editing keys
; ----------------------------------------------------------------------------
; ZX80: L0372

.global EdKeyTab
EdKeyTab:
	.word	EdUp		; #define KEY_UP	0x70	// up
	.word	EdDown		; #define KEY_DOWN	0x71	// down
	.word	EdLeft		; #define KEY_LEFT	0x72	// left
	.word	EdRight		; #define KEY_RIGHT	0x73	// right
	.word	EdHome		; #define KEY_HOME	0x74	// home
	.word	EdEdit		; #define KEY_EDIT	0x75	// edit
	.word	EdEnter		; #define NEWLINE	0x76	// Newline = Z80 HALT instruction
	.word	EdDelete	; #define KEY_DELETE	0x77	// delete (rubout)

; ----------------------------------------------------------------------------
;                           Cursor left editing
; ----------------------------------------------------------------------------
; INPUT: HL = cursor address
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L0382

.global EdLeft
; DESTROYS: A, DE
; STACK: 2 (or -2 if returning to main routine)
EdLeft: rcall	EdEdge		; check cursor on start, exit if so
	sbiw	HL,2		; move cursor left by 2 positions

; EdRight must follow

; ----------------------------------------------------------------------------
;                           Cursor right editing
; ----------------------------------------------------------------------------
; INPUT: HL = cursor address
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L0387

.global EdRight
EdRight:adiw	HL,1		; move cursor right

	; check if cursor is at end of line
	ld	A,MHL		; get character on next position
	cpi	A,NEWLINE	; end of edit line?
	breq	EdRight2	; cursor is already on end of edit line, jump back

	; store cursor at new position
	ldi	F,CURSOR	; cursor character (= inverted 'K')
	st	MHL,F		; store cursor

	; store old character to old cursor position
; OUTPUT: HL = cursor address DATA_CURPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadCurPtr	; load cursor address -> HL
	st	MHL,A		; store character from new current position
EdRight2:
	rjmp	EdCopy		; jump back to main routine

; ----------------------------------------------------------------------------
;                          Delete editing
; ----------------------------------------------------------------------------
; INPUT: HL = cursor address
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L0395

.global EdDelete
EdDelete:
; DESTROYS: A, DE
; STACK: 2 (or -2 if returning to main routine)
	rcall	EdEdge		; check cursor on start, exit if so
	sbiw	HL,1		; move cursor left
; INPUT: HL = address of the character
; OUTPUT: DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 4
	rcall	DelChar		; delete 1 character
	rjmp	EdCopy		; jump back to main routine

; ----------------------------------------------------------------------------
;   Check if cursor is on start of edit line (if so, jumps to main routine)
; ----------------------------------------------------------------------------
; DESTROYS: A, DE
; STACK: 2 (or -2 if returning to main routine)
; ----------------------------------------------------------------------------
; ZX80: L039E

.global EdEdge
EdEdge:
	; get pointer to start of edit line -> DE
	ldd	E,Y+DATA_EDITPTR
	ldd	D,Y+DATA_EDITPTR+1

	; check if first character is [K] cursor (= edit line is empty)
	ld	A,MDE			; load first character
	cpi	A,CURSOR		; cursor? (= inverted 'K' character)
	breq	EdEdge2			; edit line is empty
	ret				; return to calling function, if line is not empty

	; line is empty, break function - drop return address and jump back to main routine
EdEdge2:
	POP_DE				; destroys return address
	rjmp	EdCopy			; jump back to main routine

; ----------------------------------------------------------------------------
;                     Cursor up editing
; ----------------------------------------------------------------------------
; INPUT: HL = cursor address
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L03A9

.global EdUp
EdUp:
	; find current program line
; OUTPUT: HL = address of current program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = current line number
;	  ZY = current line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
	rcall	CurLineFind	; find current line
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE and HL

	; get line number of previous line
; INPUT: HL = pointer to current line
;	 DE = pointer to previous line
; OUTPUT: HL = pointer to current line + 1
;	  DE = line number (0 = line is invalid)
; DESTROYS: A
; STACK: 2
	rcall	LineNo

	; start editing new program line
EdLine:	ldi	L,lo8(EditLine) ; current line
	ldi	H,hi8(EditLine)
; INPUT: HL = pointer to variable with line number
;	 DE = line number
	rjmp	LineStore	; store line number X into Z address

; ----------------------------------------------------------------------------
;                     Home editing, go to first line
; ----------------------------------------------------------------------------
; INPUT: HL = cursor address
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L03B9

.global EdHome
EdHome:	ldi	E,0		; use line number 0
	ldi	D,0
	rjmp	EdLine		; start editing line 0

; ----------------------------------------------------------------------------
;                   Collect line number from program line
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to current line
;	 DE = pointer to previous line
; OUTPUT: HL = pointer to current line + 1
;	  DE = line number (0 = line is invalid)
; DESTROYS: A
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L03C2 (begin at L03BE)

.global LineNo
LineNo:
	; check line number
	ld	A,MHL		; get high byte of line number
	andi	A,0xc0		; check if line number is valid
	breq	4f		; line number is OK
	
	; try to use previous line
	movw	HL,DE		; previous line
	ld	A,MHL		; get high byte of line number
	andi	A,0xc0		; check if line number is valid
	breq	4f		; line number is OK

	; use line 0
	clr	D
	clr	E
	ret

	; load line number
4:	ld	D,MHL+		; line number HIGH
	ld	E,MHL		; load line number LOW
	ret

; ----------------------------------------------------------------------------
;               Edit key (start editing current program line)
; ----------------------------------------------------------------------------
; INPUT: HL = cursor address
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L03CB

.global EdEdit
EdEdit:
	; restart print to start of edit line -> B', C', DE'
; Note: Original ZX80 does not initialize B register at this place. To work properly,
; value 2 or more is required. At ZX80, BC contains jump address to this routine,
; with B register = 3, so initialization is not necessary. Maybe it was an omission,
; but maybe it was a deliberate optimization.
	ldi	B,2	; set row counter
	ldi	C,0	; clear column counter, no free columns remain (to inhibit NEWLINE)
	ldd	E,Y+DATA_EDITPTR ; pointer to start of edit line -> DE
	ldd	D,Y+DATA_EDITPTR+1
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers

	; find current program line
; OUTPUT: HL = address of current program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = current line number
;	  ZY = current line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
	rcall	CurLineFind

	; load line number and check if line is valid
; INPUT: HL = pointer to current line
;	 DE = pointer to previous line
; OUTPUT: HL = pointer to current line + 1
;	  DE = line number (0 = line is invalid)
; DESTROYS: A
; STACK: 2
	rcall	LineNo
	adiw	DE,0		; check if line number = 0
	brne	2f		; line number is OK
	rjmp	MainExec	; invalid row, return to main loop

	; print line number
; INPUT: HL = pointer to program line
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  HL = pointer to program line + 1
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
2:	sbiw	HL,1		; shift to start of program line
	rcall	PrintLineNum	; print line number
	sbiw	HL,1		; shift to begin, again

	; shift to next program line - to get length of this program line
; INPUT: HL = pointer to current entry (current variable or program line)
; OUTPUT: DE = next entry (next variable or program line)
;	  BC = length of entry (length of variable or program line)
; DESTROYS: A, R1, R0
; STACK: 4
	rcall	NextOne
	adiw	HL,2		; shift pointer to first token (skip line number)
	sbiw	BC,2		; decrease length by 2 bytes of line number

	; get current print position -> DE
	movw	DE,DE_		; print pointer -> DE

	; store [K] cursor to print buffer
	ldi	A,CURSOR	; cursor, inverted 'K' character
	st	MDE+,A		; store cursor character

	; check memory overflow
	PUSH_HL			; push position with program
	ldi	L,34		; memory overhead 34 bytes
	ldi	H,0
	add	L,E		; add overhead to edit line address
	adc	H,D
	add	L,C		; add length of edit line
	adc	H,B
	in	r0,_SFR_IO_ADDR(SPL) ; load stack LOW
	sub	L,r0
	in	r0,_SFR_IO_ADDR(SPH) ; load stack HIGH
	sbc	H,r0
; warning - this instruction "POP HL" is missing in original ZX80 for case of error jump to EdCopy
	POP_HL 			; pop position within program
	brcs	4f		; memory is OK
	rjmp	EdCopy		; back

	; copy program to edit line
; OPERATION: (HL) -> (DE), DE++, HL++, BC--, repeat while BC != 0
; INPUT: HL = pointer to first byte of source address
;	 DE = pointer to first byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer after last byte of source address
;	  DE = pointer after last byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
4:	rcall	LDIR		; copy to edit line

	; update start of display
5:	std	Y+DATA_DISPPTR,E
	std	Y+DATA_DISPPTR+1,D
	rjmp	AutoList	; restart auto-list

; ----------------------------------------------------------------------------
;                         Enter key (parse edit line)
; ----------------------------------------------------------------------------
; INPUT: HL = cursor address
; STACK: jumps back to main execution loop
; ----------------------------------------------------------------------------
; ZX80: L0408

.global EdEnter
EdEnter:
	; check whether syntax error is active
	ldd	L,Y+DATA_ERRPTR		; get error pointer
	ldd	H,Y+DATA_ERRPTR+1
	or	H,L			; check error
	breq	2f			; no error
	rjmp	EdCopy			; cannot continue if syntax error

	; load pointer to cursor
; OUTPUT: HL = cursor address DATA_CURPTR
; DESTROYS: -
; STACK: 2
2:	rcall	LoadCurPtr	; load cursor address -> HL

	; delete cursor character
; INPUT: HL = address of the character
; OUTPUT: DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 4
	rcall	DelChar			; delete character at Z address

	; initialize pointer of next processed character
; OUTPUT: HL = address of edit line DATA_EDITPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadEditPtr		; load pointer to edit line -> HL
	std	Y+DATA_CHARPTR,L	; address of character
	std	Y+DATA_CHARPTR+1,H

	; load first character (skip spaces)
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
	rcall	GetChar

	; skip if input mode
	IF_INPUT			; if input mode	
	rjmp	4f			; skip if input mode

; ----- else edit line is to be run

	; load line number
; INPUT: HL = current address of the text
; OUTPUT: HL = new current address of the text
;	  HL' = number 0..32767
;	  CY = overflow
; DESTROYS: AF, D', R1, R0
; STACK: 4
	rcall	IntToHL			; load line number
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX			; exchange registers

	; check line number
	adiw	HL,0			; check if line number is 0
	breq	3f
	rjmp	MainAdd			; line number is valid, jump and add it to the program

	; line number is 0, preset executed line number to -2 (flag of direct execution)
3:	sbiw	HL,2			; HL <- -2
	std	Y+DATA_EXECLINE,L	; store current line number
	std	Y+DATA_EXECLINE+1,H

	; clear screen
; OUTPUT: HL = current print address (= start of display + 1)
;	  C = remaining columns (= 33)
;	  B = remaining rows (= 23)
; DESTROYS: - (saves flags)
; STACK: 4
	rcall	DispCls			; clear screen

	; check empty command - do listing
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX			; exchange registers
	ld	A,MHL			; load first character
	cpi	A,NEWLINE		; only empty row?
	brne	4f			; not empty row
	rjmp	MainExec		; do auto-list

; ----- check syntax

	; clear error
4:	std	Y+DATA_ERRCODE,ZERO	; clear error code
	CLR_ERROR			; clear error flag

	; initialize flags - syntax off, K cursor
;#define F_NOLEAD	0	// 1=no leading space, 0=leading space
;#define F_FAST		1	// 1=fast video mode, 0=slow video mode
;#define F_KMODE	2	// 1=K mode, 0=L mode
;#define F_KCURSOR	3	// 1=K cursor, 0=L cursor
;#define F_ERROR	4	// 1=error code is stored in ErrCode
;#define F_INPUT	5	// 1=inputting, 0=editing
;#define F_NUMRES	6	// 1=numeric result, 0=string result
;#define F_SYNTOFF	7	// 1=syntax off, 0=syntax on
	in	F,_SFR_IO_ADDR(GPIOR0)
	cbr	F,BIT(F_NOLEAD) | BIT(F_KMODE) | BIT(F_NUMRES)
	sbr	F,BIT(F_SYNTOFF) | BIT(F_KCURSOR)
	out	_SFR_IO_ADDR(GPIOR0),F

	; go and check syntax
3:	rcall	MainGo		; main go

	; reclaim whole edit line
; OUTPUT: HL = start of edit line
; 	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
5:	rcall	RecEdit

	; get current executed line number
	ldd	E,Y+DATA_EXECLINE
	ldd	D,Y+DATA_EXECLINE+1

	; if only INPUT (not editing), hide cursor
	IF_INPUT		; if inputting
	adiw	DE,1		; increment current line number, so cursor doesn't show
	SET_EDIT		; set editing mode

	; skip if error
	IF_ERROR
	rjmp	MainErr		; skip if error

	; get character address
	ldd	L,Y+DATA_CHARPTR ; get character pointer
	ldd	H,Y+DATA_CHARPTR+1
	adiw	HL,1		; shift to next character

	; skip if 'L' letter cursor ('K' cursor means 1st passage, row address is not initialized yet)
	IF_LCURSOR		; if L cursor
	rjmp	6f		; skip if L cursor, line is already prepared
	SET_LCURSOR		; set L cursor

	; current line -> HL, next character -> DE
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE and HL

	; check valid next line number (or direct command)
	mov	A,H		; A <- line number HIGH
	andi	A,0xc0		; check bit 6 and 7 (if direct command, line number will be -1 or -2)
	brne	MainErr		; invalid line number

	; find address of the line
; INPUT: HL = required line number
; OUTPUT: HL = address of program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = required line number
;	  ZY = required line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
	rcall	LineFind	; find line

	; check if next program line is valid
6:	ld	A,MHL		; get line number HIGH
	andi	A,0xc0		; check bits 6 and 7 (program end is > 0x3FFF)
	brne	MainErr		; invalid line number

	; get next line number
	ld	D,MHL+
	ld	E,MHL+
	std	Y+DATA_EXECLINE,E ; store new executed line number
	std	Y+DATA_EXECLINE+1,D

	; check BREAK key (space key is pressed)
	ldd	A,Y+DATA_KEYPRESS ; current pressed key
	cpi	A,CH_SPC	; space key?
	brne	3b		; not break, continue with ney line
; else break

; ----- break program
; ZX80: L0488

MainErr:
	; destroy return address
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
	rcall	Unstack

	; clear to end of display
; INPUT: B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: DE = new end address of the display
; DESTROYS: A, BC, R1, R0, registers are exchanged using EXX
; STACK: 4
	rcall	ClrEod

	; set remaining 1 row and 32 columns
	ldi	B,1		; 1 row remains
	ldi	C,WIDTH		; fill columns remain
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers

	; stop with no error
	ldd	A,Y+DATA_ERRCODE ; get error code
	ldd	C,Y+DATA_EXECLINE ; get last executed line number
	ldd	B,Y+DATA_EXECLINE+1
	IF_NOERROR		; if no error
	rjmp	8f		; skip if no error

	; break with STOP statement
	movw	r0,BC		; save current line number
	cpi	A,ERR_STOP	; STOP statement?
	brne	7f		; no STOP
	adiw	BC,1		; if STOP, continue with next program line

	; save line number to continue next
7:	std	Y+DATA_OLDLINE,C ; save old line number
	std	Y+DATA_OLDLINE+1,B
	movw	BC,r0		; restore line number

	; print error code
; INPUT: A = number 0..9
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: E = CH_0 character
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
8:	rcall	PrintDig1	; print number in A

	; print separator '/'
	ldi	A,CH_SLASH	; '/' character
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 (missing ZY flag of display overflow)
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh		; print character

	; print last program line number
; INPUT: BC = number to print
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
	rcall	PrintNum

	; clear rest of screen
; INPUT: B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: DE = new end address of the display
; DESTROYS: A, BC, R1, R0, registers are exchanged using EXX
; STACK: 4
	rcall	ClrEod

	; set SLOW display mode
	SET_SLOW

	; get key from keyboard
; OUTPUT: A = key (NOKEY = no key)
;	  ZY = no key
; DESTROYS: F
; STACK: 2
3:	call	GetKey	
	breq	3b		; wait for a key

	; go back to main loop
	rjmp	MainExec

; ----------------------------------------------------------------------------
;                   add BASIC line to the program
; ----------------------------------------------------------------------------
; INPUT: HL = edit line number
; ----------------------------------------------------------------------------
; ZX80: L04BA

.global MainAdd
MainAdd:
	; store new current edit line number
	std	Y+DATA_EDITLINE,L
	std	Y+DATA_EDITLINE+1,H

	; exchange registers
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX			; exchange alternative registers
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL			; exchange DE and HL

	; clear screen
; OUTPUT: HL = current print address (= start of display + 1)
;	  C = remaining columns (= 33)
;	  B = remaining rows (= 23)
; DESTROYS: - (saves flags)
; STACK: 4
	rcall	DispCls			; clear screen

	; prepare size of data to move
	sub	L,E			; length of program code
	sbc	H,D
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX			; exchange registers (HL <- current line number, HL' <- length of edit line)

	; search program line
; INPUT: HL = required line number
; OUTPUT: HL = address of program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = required line number
;	  ZY = required line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
	rcall	LineFind
	PUSH_HL				; save address of program line (this or next)
	brne	2f			; program line does not exist

	; shift to next program line - to get length of old program line
; INPUT: HL = pointer to current entry (current variable or program line)
; OUTPUT: DE = next entry (next variable or program line)
;	  BC = length of entry (length of variable or program line)
; DESTROYS: A, R1, R0
; STACK: 4
	rcall	NextOne			; get next program line

	; delete old program line
; INPUT: HL = current address, start of deleted memory block
;	 BC = number of bytes of deleted memory block
; OUTPUT: DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 4
	rcall	Reclaim			; delete old program line

	; check zero length of edit line
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
2:	rcall	EXX			; exchange registers
	adiw	HL,1			; length of edit line + 1
	movw	BC,HL			; BC <- legnth of edit line + 1
	mov	A,L			; A <- length LOW
	subi	A,3			; length without quotes and newline
	or	A,H			; check zero length
	breq	3f			; line is empty

	; check free space in RAM
; INPUT: BC = required number of bytes to allocate
; OUTPUT: NC = memory error
;	  DE = new end of data (new display end)
; DESTROYS: HL, R0
; STACK: 2
	rcall	CheckMem		; check free space

	; end if line is empty or memory error
3:	POP_HL				; HL <- address in program to insert new line
	brcc	8f			; line is empty or memory error, end routine, no line inserted

	; save length of edit line
	PUSH_BC
	sbiw	HL,1			; shift to start of edit line

	; make room in program area for inserting new line
; INPUT: HL = current address (where new data should be inserted)
;	 BC = number of bytes to insert (must be >0)
; OUTPUT: HL = current address - 1
;	  DE = address of start of moved block - 1 (= last byte of new free space)
;	  BC = 0
; DESTROYS: R1, R0
; STACK: 4
	rcall	MakeRoom
	adiw	DE,1		; shift to start of new free space

	; load pointer to start of display -> HL
; OUTPUT: HL = address of start of display DATA_DISPPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadDispPtr
	sbiw	HL,1		; decrease to point to end of edit line

	; restore length of edit line
	POP_BC
	sbiw	BC,1		; without end mark

	; copy line
; OPERATION: (HL) -> (DE), DE--, HL--, BC--, repeat while BC != 0
; INPUT: HL = pointer to last byte of source address
;	 DE = pointer to last byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer before first byte of source address
;	  DE = pointer before first byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	LDDR		; copy edit line into program area

	; store line number
	movw	HL,DE		; HL <- start of destination address
	ldd	E,Y+DATA_EDITLINE ; DE <- edit line
	ldd	D,Y+DATA_EDITLINE+1
	st	MHL+,D		; store edit line HIGH
	st	MHL,E		; store edit line LOW

	; auto-save program to EEPROM
; DESTROYS: AF, BC, DE, HL
; STACK: 7
8:	rcall	AutoSave

	; jump back to MainExec
	rjmp	MainExec

; ----------------------------------------------------------------------------
;                      Print whole BASIC line
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line
;	 E = flag, 0=current line was printed, 1=current line was not printed
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = error, display full or end of program reached
;	  E = updated flag
;	  HL = pointer to next program line
;	  B', C', DE' = updated
; DESTROYS: A, BC, D, HL', PUSH1, PUSH2, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L04F7

.global OutLine
OutLine:
	; get current line number with cursor -> BC
	ldd	C,Y+DATA_EDITLINE
	ldd	B,Y+DATA_EDITLINE+1

	; compare printed line number and current line number
; INPUT: HL = pointer to current program line
;	 BC = searched line number
; OUTPUT: ZY = line number is equal
;	  CY = current program line is less < than searched line number
; DESTROYS: A
; STACK: 2
	rcall	CmpLine			; compare line number
	ldi	D,CH_GR + CH_INV	; prepare inverted character '>'
	breq	2f			; printed line is current line

	; not current line, space will be printed
	ldi	D,CH_SPC		; space will be printed
	ldi	E,0
	adc	E,E			; get flag: 1=printed line precede current line (current line not printed yet)

	; check end of program
2:	ld	A,MHL			; load first byte = line number HIGH
	cpi	A,0x40			; check if program line is valid
	brcc	OutLine10		; end of program, program line is not valid

	; print line number (and skip line number 1st byte)
; INPUT: HL = pointer to program line
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  HL = pointer to program line + 1
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
	rcall	PrintLineNum		; print line number
	brcc	OutLine10		; memory error or display full
	adiw	HL,1			; skip line number 2nd byte

	; print space or cursor
	mov	A,D			; character to print
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 (missing ZY flag of display overflow)
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh			; print character
	brcc	OutLine10		; memory error or display full

; OutLine2 must follow

; ----------------------------------------------------------------------------
;                  Print BASIC line without line number
; ----------------------------------------------------------------------------
; INPUT: HL = start of program code (after line number)
;	 E = flag, 0=current line was printed, 1=current line was not printed
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = error, display full or end of program reached
;	  HL = start of next program line
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L0512

.global OutLine2
OutLine2:
	; disable leading spaces
	SET_NOLEAD			; set no leading flag

	; print error flag
3:	ldd	C,Y+DATA_ERRPTR		; load error address
	ldd	B,Y+DATA_ERRPTR+1
	cp	L,C			; compare program address
	cpc	H,B
	brne	4f			; not error address

	ldi	A,CH_S + CH_INV		; inverted 'S' character
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 (missing ZY flag of display overflow)
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh			; print error character
; Note: ZX80 at this place returns on flag ZY, which means that display is full (B' = 0)
	brcc	OutLine10		; end of display or memory error

	; load one character from program line
4:	ld	A,MHL+			; load one character

	; check cursor
	cpi	A,CURSOR		; cursor inverted 'K' character
	breq	8f			; print cursor

	; check character class
	cpi	A,0xc0			; compare with threshold 192
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	brvs	PrintChSpc		; jump if character is 64..127, it means NEWLINE character, print NEWLINE and exit routine
	brcs	6f			; jump if character is  0..63 or 128..191, print single character

	; print token 0xC0..0xFF
; INPUT: A = token index 0xD4..0xFF
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, R1, R0
; STACK: 6
	rcall	PrintToken		; print token
	rjmp	7f

	; print character (enable leading space)
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
6: 	rcall	PrintChSpc		; print character
7:	brcs	3b			; get next character
OutLine10:
	ret

	; print cursor
8:	IF_LMODE			; if L-mode
	inc	r23			; change to inverted 'L' character
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh			; print cursor character
	rjmp	7b

; ----------------------------------------------------------------------------
;                   Print one digit of the number
; ----------------------------------------------------------------------------
; INPUT: HL = number to print
;	 BC = negative increment (-10000, -1000, -100, -10)
;	 E = flags: 0xFF do not print spaces, CH_SPC print spaces, CH_0 print zeroes
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: HL = remainder of number to print
;	  E = modified flags
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L054C

.global PrintDig
PrintDig:
	ldi	A,0		; prepare character accumulator

	; count increments
2:	inc	A		; increment character accumulator
	add	L,C		; add negative increment
	adc	H,B
	brcs	2b		; next step

	; restore remainder
	sub	L,C		; subtract increment back
	sbc	H,B
	
	; check zero digit
	dec	A		; zero digit?
; INPUT: A = number 0..9
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: E = CH_0 character
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	brne	PrintDig1	; not zero digit

	; serve leading spaces
	mov	A,E		; load flags
	cpi	A,0xff		; disable printing leading spaces?
	brne	PrintChSpc2	; print zero od space character
	sec			; set carry flag to indicate no memory error
	ret			; exit if no leading spaces are printed

; ----------------------------------------------------------------------------
;                          Print one digit
; ----------------------------------------------------------------------------
; INPUT: A = number 0..9
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: E = CH_0 character
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0556

.global PrintDig1
PrintDig1:
	; other digits than zero - set flag to print zeroes next time
	ldi	E,CH_0		; zero digit will be printed next time
	add	A,E		; convert to digit character

; PrintChSpc must follow

; ----------------------------------------------------------------------------
;               Print character or space (enable leading space)
; ----------------------------------------------------------------------------
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; Enables leading spaces if other character than space is printed.
; ZX80: L0559

.global PrintChSpc
PrintChSpc:
	; space character does not allow leading spaces
	cpi	A,CH_SPC	; space character?
	breq	PrintCh		; skip if space character

PrintChSpc2:

	; allow leading spaces
	SET_LEAD		; allow leading spaces

; PrintCh must follow

; ----------------------------------------------------------------------------
;                     Print character to display
; ----------------------------------------------------------------------------
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 (missing ZY flag of display overflow)
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0560, RST 10H, L0010

.global PrintCh
PrintCh:
	; exchange alternative registers
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX

; Here si: DE = address in RAM, B = remaining rows, C = remaining columns, A = character to print

	; save printed character to H
	mov	H,A

	; get bit 6 of printed character -> carry in case of NEWLINE (0x76)
	rol	A
	rol	A

	; decrement number of remaining column (carry stays unchanged)
	dec	C		; decrement column number

	; in case of NEWLINE reset remaining columns to 0
	brcc	2f		; no carry, no NEWLINE
	ldi	C,0		; clear column counter, no free columns remain

	; check end of line
2:	brmi	4f		; column counter was already 0 (printing behind end of row), restart to new full row
	brcs	6f		; NEWLINE case
	brne	6f		; end of line not yet reached

	; automatic NEWLINE if end of row was reached (carry stays cleared)
	ldi	A,NEWLINE	; new line character
	st	MDE+,A		; store new line character -> (DE)++

  	; restart column counter in case of new line
4:	brcs	5f		; this was case of NEWLINE, columns will not be reset for now
	ldi	C,WIDTH		; restart column counter to full row

	; shift row counter
5:	subi	B,1		; decrement row counter
	breq	8f		; out of screen (carry will be clear = display overflow flag)

	; check free memory
6:	mov	L,B		; number of remaining rows
; INPUT: L = required reserve
;	 H = saved accumulator A
;	 DE = pointer, current end of display
; OUTPUT: NC = memory error
;	  A = restored accumulator from H
; DESTROYS: HL, R0
; STACK: 2
	rcall	CheckFree	; check free memory (returns NC on memory error)

	; store character
	st	MDE+,A		; store character A -> (DE)++

	; switch registers back (here is NC = display overflow)
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
8:	rjmp	EXX

; ----------------------------------------------------------------------------
;                  Print token (with leading space if needed)
; ----------------------------------------------------------------------------
; INPUT: A = token index 0xD4..0xFF
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L0584

.global PrintToken
PrintToken:
	; search token
; INPUT: A = token index 0xD4..0xFF
; OUTPUT: BC = pointer to token text in ROM (last character has bit 7 set)
;	  CY = first character is alphabet or digit (leading space will be needed)
;	  PUSH1 = saved pointer HL
; DESTROYS: A, R0
; STACK: 2
	rcall	TabSearch	; search token
	brcc	4f		; skip if first character is not alphanumeric

	; check if leading space is enabled
	IF_NOLEAD		; if no leading space
	rjmp	4f		; skip leading space

	; print leading space
	ldi	A,CH_SPC	; space character
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh		; print character
	brcc	9f		; memory error or display full

	; print one character
4:	movw	HL,BC		; HL <- pointer to token
5:	lpm	A,MHL		; load one character
	andi	A,0x3f		; mask valid bits (clear attributes)
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintChSpc	; print character or space (allow leading spaces)
	brcc	8f		; memory error

	; check end of token
	lpm	A,MHL+		; load character again
	add	A,A		; check bit 7
	brcc	5b		; bit 7 not set, print next character

	; print space character after alphanumeric character
	cpi	A,2*CH_0	; check alphanumeric character
	brcs	8f		; not alphanumeric character

	ldi	A,CH_SPC	; space character
	SET_NOLEAD		; disable leading space
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh		; print leading space

	; restore HL
8:	movw	HL,PUSH1	; restore HL
9:	ret

; ----------------------------------------------------------------------------
;                    Table search (search tokens)
; ----------------------------------------------------------------------------
; INPUT: A = token index 0xD4..0xFF
; OUTPUT: BC = pointer to token text in ROM (last character has bit 7 set)
;	  CY = first character is alphabet or digit (leading space will be needed)
;	  PUSH1 = saved pointer HL
; DESTROYS: A, R0
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L05A8

.global TabSearch
TabSearch:
	; save character pointer
	movw	PUSH1,HL

	; prepare address of search table -> HL
	ldi	L,lo8(Tokens)
	ldi	H,hi8(Tokens)

	; index relative (subtract threshold)
	lpm	r0,MHL+		; load threshold
	sub	A,r0		; subtract threshold
	brcs	8f		; invalid token (use "?" token)

	; find token
	inc	A		; correction, +1
2:	lpm	r0,MHL+		; load next character
	add	r0,r0		; check bit 7
	brcc	2b		; loop back if bit 7 is not set, find end of one token
	dec	A		; token counter
	brne	2b		; find token

	; check if first character is alphabet or digit
8:	lpm	A,MHL		; load first character
	andi	A,0x3f		; mask only valid bits
	ldi	C,-CH_0		; negative character '0' (= 0xE4)
	add	A,C		; check valid alphanumeric (CY = valid alphanumeric)

	; restore character pointer
	movw	BC,HL		; BC <- start of token
	movw	HL,PUSH1	; restore HL
	ret

; ----------------------------------------------------------------------------
;                      Clear to end of display
; ----------------------------------------------------------------------------
; INPUT: B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: DE = new end address of the display
; DESTROYS: A, BC, R1, R0, registers are exchanged using EXX
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L05C2

.global ClrEod
ClrEod:
	; exchange alternative registers
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX

	; check number of remaining rows
	cpi	B,0
	breq	8f		; no rows remain

	; check if current row is full (no NEWLINE will be inserted)
	cpi	C,0
	ldi	A,NEWLINE	; we will store NEWLINE character
	breq	4f		; no column left, NEWLINE will not be inserted

	; store empty rows
2:	st	MDE+,A		; store NEWLINE character
4:	dec	B		; decrement row counter
	brne	2b		; next row

	; save new end of display
8:	std	Y+DATA_DISPEND,E
	std	Y+DATA_DISPEND+1,D
	ret

; ----------------------------------------------------------------------------
;                         Make room in memory blocks
; ----------------------------------------------------------------------------
; INPUT: HL = current address (where new data should be inserted)
;	 BC = number of bytes to insert (must be >0)
; OUTPUT: HL = current address - 1
;	  DE = address of start of moved block - 1 (= last byte of new free space)
;	  BC = 0
; DESTROYS: R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L05D5

.global MakeRoom
MakeRoom:
	; shift pointers
; INPUT: BC = shift of pointers, >0 to insert, <0 to delete
;	 HL = current address, only higher pointers will be shifted
; OUTPUT: BC = block size to move + 1 (+ 1 because LDDR instruction begins after end of data)
; 	  DE = address of end of data to move (= old pointer of end of display)
; DESTROYS: R1, R0
; STACK: 2
	rcall	Pointers
	movw	HL,DE		; HL <- old end of data

	; prepare new end of data -> DE
	ldd	E,Y+DATA_DISPEND
	ldd	D,Y+DATA_DISPEND+1

; OPERATION: (HL) -> (DE), DE--, HL--, BC--, repeat while BC != 0
; INPUT: HL = pointer to last byte of source address
;	 DE = pointer to last byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer before first byte of source address
;	  DE = pointer before first byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rjmp	LDDR

; ----------------------------------------------------------------------------
;                             Shift pointers
; ----------------------------------------------------------------------------
; INPUT: BC = shift of pointers, >0 to insert, <0 to delete
;	 HL = current address, only higher pointers will be shifted
; OUTPUT: BC = block size to move + 1 (+ 1 because LDDR instruction begins after end of data)
; 	  DE = address of end of data to move (= old pointer of end of display)
; DESTROYS: R1, R0
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L05DF

.global Pointers
Pointers:
	; save current address -> DE
	movw	DE,HL			; current address -> DE

	; prepare start of pointers -> HL
	ldi	L,lo8(PtrBeg)		; address of first pointer
	ldi	H,hi8(PtrBeg)

	; load pointer -> r1:r0
2:	ldd	r0,MHL+0		; load pointer
	ldd	r1,MHL+1

	; compare current address with pointer
	cp	E,r0			; compare current address with pointer
	cpc	D,r1
	brcc	6f			; skip if current address does not lie below pointer (DE >= R1:R0)

	; shift and save new pointer, then restore old value of pointer for later usage
	add	r0,C			; shift pointer
	adc	r1,B
	std	MHL+0,r0		; save new pointer
	std	MHL+1,r1
	sub	r0,C			; restore old value of the pointer
	sbc	r1,B
	
	; next pointer
6:	adiw	HL,2			; shift address
	cpi	L,lo8(PtrEnd)		; end of pointers?
	brne	2b			; process next pointer

	; old end address of display = address of end of data to move
	movw	HL,DE			; restore current address -> HL
	movw	DE,r0			; old address of end of data -> DE (from last accessed pointer)

	; block size to move -> BC
	sub	r0,L
	sbc	r1,H
	movw	BC,r0
	adiw	BC,1			; 1 byte more due to LDDR instruction
	ret

; ----------------------------------------------------------------------------
;                    Find current program line
; ----------------------------------------------------------------------------
; OUTPUT: HL = address of current program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = current line number
;	  ZY = current line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------

.global CurLineFind
CurLineFind:
	; load current line number -> HL
	ldd	L,Y+DATA_EDITLINE
	ldd	H,Y+DATA_EDITLINE+1

; LineFind must follow

; ----------------------------------------------------------------------------
;                    Find program line by line number
; ----------------------------------------------------------------------------
; INPUT: HL = required line number
; OUTPUT: HL = address of program line (equal or higher)
; 	  DE = address of previous program line (can be equal to HL in case of first line)
;	  BC = required line number
;	  ZY = required line number has been found (or higher line or program end found otherwise)
; DESTROYS: A, PUSH1, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; First byte is >= 0x40 if end of program reached.
; ZX80: L060A

.global LineFind
LineFind:
	; save required line number
	movw	PUSH1,HL

	; start of program -> HL, DE
	ldi	L,lo8(Program)	; start of program code -> HL
	ldi	H,hi8(Program)
	movw	DE,HL		; DE <- current line

; here is DE = current line, HL = previous line

	; compare line number
2:	movw	BC,PUSH1	; required line number -> BC
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE and HL, HL <- current line, DE <- previous line
; INPUT: HL = pointer to current program line
;	 BC = searched line number
; OUTPUT: ZY = line number is equal
;	  CY = current program line is less < than searched line number
; DESTROYS: A
; STACK: 2
	rcall	CmpLine		; compare program line
	brcc	CmpLine4	; higher or same program line has been found
; Note: End of program will be successfully accepted as higher line number.

	; move to next program line
; INPUT: HL = pointer to current entry (current variable or program line)
; OUTPUT: DE = next entry (next variable or program line)
;	  BC = length of entry (length of variable or program line)
; DESTROYS: A, R1, R0
; STACK: 4
	rcall	NextOne		; move to next program line
	rjmp	2b

; ----------------------------------------------------------------------------
;                    Compare program line number
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to current program line
;	 BC = searched line number
; OUTPUT: ZY = line number is equal
;	  CY = current program line is less < than searched line number
; DESTROYS: A
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L061C

.global CmpLine
CmpLine:
	ldd	A,MHL+1		; program line LOW
	cp	A,C		; compare line numer LOW
	ldd	A,MHL+0		; program line HIGH
	cpc	A,B		; compare line number HIGH
CmpLine4:
	ret

; ----------------------------------------------------------------------------
;              Move to next entry (next variable or program line)
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to current entry (current variable or program line)
; OUTPUT: DE = next entry (next variable or program line)
;	  BC = length of entry (length of variable or program line)
; DESTROYS: A, R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0624

; Format of variables and program lines
; -------------------------------------
; 00xxxxxx xxxxxxxx code NEWLINE - program line, starting with 14-bit line number HIGH and then LOW (range 0..9999)
; 011xxxxx numL numH - short-named 16-bit integer variable, name is letter A..Z (CH_A..0x3F)
; 010xxxxx 00xxxxxx..10xxxxxx numL numH - long-named 16-bit integer variable, name: 010x first / 00x next / 10x last
; 100xxxxx text 0x01 - string variable, name is letter A..Z (CH_A..0x3F), terminated with " character (0x01)
; 101xxxxx size numL0 numH0 numL1 numH1.. - array of 16-bit integers, size = 1..255, name is letter A..Z (CH_A..0x3F)
; 111xxxxx valueL valueH limitL limitH lineL lineH - control code of FOR loop (current value, last value, line number)
; 10000000 variables end-marker

.global NextOne
NextOne:
	; save current pointer -> DE
	movw	DE,HL

	; load first byte, skip the byte
	ld	A,MHL+

	; check bit 7 and 6
	add	A,A		; get bit 7 -> C, get bit 6 -> N
	brmi	4f		; jump if bit 6 is set - short/long-named integer, loop control code
	brcs	7f		; jump if bit 7 is set - string variable or array

; --- Here is 00: program line
; 00xxxxxx xxxxxxxx code NEWLINE - program line, starting with 14-bit line number HIGH and then LOW (range 0..9999)

	; search end of entry (end of program line or end of text)
	adiw	HL,1		; skip low byte of line number
	ldi	A,NEWLINE	; search for newline
2:	ld	r0,MHL+		; load next byte
	cp	r0,A		; check byte
	brne	2b		; not equal, check next byte
; INPUT: DE = 1st number (smaller)
;	 HL = 2nd number (bigger)
; OUTPUT: BC = difference HL - DE
; 	  DE = 2nd number (bigger)
;	  HL = 1st number (smaller)
; DESTROYS: R1, R0
; STACK: 4
	rjmp	Differ		; end mark found, get entry length

; --- Here is x1x: short/long-named integer, loop control structure
; 011xxxxx numL numH - short-named 16-bit integer variable, name is letter A..Z (CH_A..0x3F)
; 010xxxxx 00xxxxxx..10xxxxxx numL numH - long-named 16-bit integer variable, name: 010x first / 00x next / 10x last
; 111xxxxx valueL valueH limitL limitH lineL lineH - control code of FOR loop (current value, last value, line number)

	; prepare number of entries to skip
4:	ldi	C,2		; if loop structure, skip 2 additional entries
	brcs	5f		; jump if bit 7 is set - loop control structure
	ldi	C,0		; if integer variable, no additional entries
5:	rol	A		; shift left, orifinal bit 5 is now on bit 7 position

	; search end of long name
6:	rol	A		; get bit 7 (or at first case get bit 5)
	ld	A,MHL+		; load next byte
	brcc	6b		; loop to find byte with bit 7 (or 5) set
	sbiw	HL,1		; return last byte
	rjmp	8f		; skip data

; --- Here is 10x: string variable or array
; 100xxxxx text 0x01 - string variable, name is letter A..Z (CH_A..0x3F), terminated with " character (0x01)
; 101xxxxx size numL0 numH0 numL1 numH1.. - array of 16-bit integers, size = 1..255, name is letter A..Z (CH_A..0x3F)

	; check bit 5
7:	andi	A,B6		; check bit 5 (now on position of bit 6)
	ldi	A,CH_QUOT	; will search end of text with separator "
	breq	2b		; jump if bit 5 is cleared - string variable

	; prepare for numeric array
	ld	C,MHL+		; load number of entries

	; skip additional entries
8:	ldi	B,0		; number of entries HIGH
	adiw	BC,1		; increment number of entries
	add	L,C		; add number of entries
	adc	H,B
	add	L,C
	adc	H,B

; Differ must follow

; ----------------------------------------------------------------------------
;                       Difference of numbers
; ----------------------------------------------------------------------------
; INPUT: DE = 1st number (smaller)
;	 HL = 2nd number (bigger)
; OUTPUT: BC = difference HL - DE
; 	  DE = 2nd number (bigger)
;	  HL = 1st number (smaller)
; DESTROYS: R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; Notes: HL and DE numbers will be exchanged.
; ZX80: L0653

.global Differ
Differ:
	movw	BC,HL		; BC <- 2nd number from HL
	sub	C,E		; get difference
	sbc	B,D
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rjmp	EXDEHL		; exchange registers DE and HL

; ----------------------------------------------------------------------------
;                            CLEAR variables
; ----------------------------------------------------------------------------
; OUTPUT: HL = address of begin of variables
;	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L065B

.global Clear
Clear:
	; get address of end of variables (edit line) -> HL
; OUTPUT: HL = address of edit line DATA_EDITPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadEditPtr		; load pointer to edit line into HL

	; decrement to point to 0x80 end-marker
	sbiw	HL,1

	; get address of begin of variables -> DE
	ldd	E,Y+DATA_VARSPTR
	ldd	D,Y+DATA_VARSPTR+1

; ReclaimDif must follow

; ----------------------------------------------------------------------------
;             Reclaim memory (delete memory block), using pointers
; ----------------------------------------------------------------------------
; INPUT: DE = current address, start of deleted memory block
;	 HL = end of deleted memory block
; OUTPUT: HL = current address, start of deleted memory block
; 	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L0663

.global ReclaimDif
ReclaimDif:
	; get length of memory block -> BC (HL and DE are exchanged)
; INPUT: DE = 1st number (smaller)
;	 HL = 2nd number (bigger)
; OUTPUT: BC = difference HL - DE
; 	  DE = 2nd number (bigger)
;	  HL = 1st number (smaller)
; DESTROYS: R1, R0
; STACK: 4
	rcall	Differ

; Reclaim must follow

; ----------------------------------------------------------------------------
;              Reclaim memory (delete memory block), using size
; ----------------------------------------------------------------------------
; INPUT: HL = current address, start of deleted memory block
;	 BC = number of bytes of deleted memory block
; OUTPUT: DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0666

.global Reclaim
Reclaim:
	; save size of deleted data
	movw	PUSH1,BC	; save size of deleted data

	; negate block size -> BC
	com	B		; one's complement of number HIGH
	neg	C		; negate number LOW, sets Carry if operand was not 0
	sbci	B,0xff		; borrow to HIGH

	; shift pointers
; INPUT: BC = shift of pointers, >0 to insert, <0 to delete
;	 HL = current address, only higher pointers will be shifted
; OUTPUT: BC = block size to move + 1 (+ 1 because LDDR instruction begins after end of data)
; 	  DE = address of end of data to move (= old pointer of end of display)
; DESTROYS: R1, R0
; STACK: 2
	rcall	Pointers	; shift pointers

	; prepare registers
	movw	DE,HL		; DE <- current address
	movw	HL,PUSH1	; HL <- size of deleted data
	add	L,E		; HL <- address after deleted data
	adc	H,D

	; move remaining data
	movw	PUSH1,DE	; save current address
; OPERATION: (HL) -> (DE), DE++, HL++, BC--, repeat while BC != 0
; INPUT: HL = pointer to first byte of source address
;	 DE = pointer to first byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer after last byte of source address
;	  DE = pointer after last byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	LDIR		; move data
	movw	HL,PUSH1	; restore current address
Reclaim9:
	ret

; ----------------------------------------------------------------------------
;                     Parse integer to alternate HL'
; ----------------------------------------------------------------------------
; INPUT: HL = current address of the text
; OUTPUT: HL = new current address of the text
;	  HL' = number 0..32767
;	  CY = overflow
; DESTROYS: AF, D', R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0679

.global IntToHL
IntToHL:
	; load first character -> A
	ld	A,MHL

	; switch registers, save HL pointer
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers BC, DE, HL with alternatives

	; clear accumulator -> HL
	clr	L
	clr	H

	; check valid digit
2:	subi	A,CH_0		; minimal '0' digit
	brcs	6f		; invalid character < '0'
	cpi	A,10		; maximal digit
	brcc	6f		; invalid character > '9'

	; preset accumulator HIGH to overflow (valid range is 0..32767)
	;	max. limited number: 0x0E00 = 3584, 3584*10 = 35840
	;	min. limited number: 0x0D00 = 3328, 3328*10 = 33280
	cpi	H,14		; can occur overflow?
	brcs	3f		; no overflow
	ldi	H,13		; limit overflow

	; multiply accumulator * 10
3:	ldi	F,10		; multiplier
	mov	D,H		; save accumulator HIGH -> D
	mul	L,F		; multiply accumulator LOW * 10
	movw	HL,r0		; HL <- multiplier LOW
	mul	D,F		; multiply accumulator HIGH
	add	H,r0		; add result

	; add next digit
	add	L,A
	adc	H,ZERO

	; load next character
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers BC, DE, HL with alternatives
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAdd		; increment and load next character
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers BC, DE, HL with alternatives
	rjmp	2b		; process next character

	; store integer result
; INPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
6:	rcall	SaveResult	; save last result DATA_RESULT from HL

	; check overflow
	mov	A,H		; get result HIGH
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers BC, DE, HL with alternatives
	LSL	A		; set carry if overflow
IntToHL8:
	ret

; ----------------------------------------------------------------------------
;                Print signed number (without leading spaces)
; ----------------------------------------------------------------------------
; INPUT: BC = number to print
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L06A1

.global PrintNum
PrintNum:
	; preserve registers
	movw	PUSH1,DE	; save registers DE
	movw	PUSH2,HL	; save registers HL

	; prepare number to print -> HL
	movw	HL,BC

	; check if number is negative
	tst	B		; negative number?
	brpl	4f		; number is not negative

	; print sign
	ldi	A,CH_MINUS	; minus character
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintChSpc	; print character '-'
	brcc	PrintNum8	; memory error

	; negate number
; INPUT: HL = number
; OUTPUT: HL = negative number
;	  CY = set if operand is not 0
;	  ZY = set if operand is 0
; DESTROYS: -
; STACK: 2
	rcall	NumNeg		; negate number HL

	; print digit 10000
4:	ldi	E,0xff		; flag - do not print leading spaces
	ldi	C,lo8(-10000)
	ldi	B,hi8(-10000)
; INPUT: HL = number to print
;	 BC = negative increment (-10000, -1000, -100, -10)
;	 E = flags: 0xFF do not print spaces, CH_SPC print spaces, CH_0 print zeroes
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: HL = remainder of number to print
;	  E = modified flags
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintDig	; print one digit
	brcc	PrintNum8	; memory error
	rjmp	PrintNum4

; ----------------------------------------------------------------------------
;              Print program line number (with leading spaces)
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  HL = pointer to program line + 1
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L06BF

.global PrintLineNum
PrintLineNum:
	; preserve registers and load program line number
	movw	PUSH1,DE	; save registers DE
	ld	D,MHL+		; load program line number HIGH
	ld	E,MHL		; load program line number LOW
	movw	PUSH2,HL	; save registers HL
	movw	HL,DE		; HL <- program line number

	; prepare flag
	ldi	E,CH_SPC	; flag - print leading spaces

PrintNum4:
	; print digit 1000
	ldi	C,lo8(-1000)
	ldi	B,hi8(-1000)
; INPUT: HL = number to print
;	 BC = negative increment (-10000, -1000, -100, -10)
;	 E = flags: 0xFF do not print spaces, CH_SPC print spaces, CH_0 print zeroes
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: HL = remainder of number to print
;	  E = modified flags
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintDig	; print one digit
	brcc	PrintNum8	; memory error

	; print digit 100
	ldi	C,lo8(-100)
	ldi	B,hi8(-100)
; INPUT: HL = number to print
;	 BC = negative increment (-10000, -1000, -100, -10)
;	 E = flags: 0xFF do not print spaces, CH_SPC print spaces, CH_0 print zeroes
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: HL = remainder of number to print
;	  E = modified flags
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintDig	; print one digit
	brcc	PrintNum8	; memory error

	; print digit 10
	ldi	C,lo8(-10)
; INPUT: HL = number to print
;	 BC = negative increment (-10000, -1000, -100, -10)
;	 E = flags: 0xFF do not print spaces, CH_SPC print spaces, CH_0 print zeroes
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: HL = remainder of number to print
;	  E = modified flags
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintDig	; print one digit
	brcc	PrintNum8	; memory error

	; print digit 1
	mov	A,L
; INPUT: A = number 0..9
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: E = CH_0 character
;	  NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintDig1	; print last digit

PrintNum8:
	; restore registers
	movw	HL,PUSH2	; restore registers HL
	movw	DE,PUSH1	; restore registers DE
	ret

; ----------------------------------------------------------------------------
;          Unstack (destroy return address or restore print position)
; ----------------------------------------------------------------------------
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
; ----------------------------------------------------------------------------
; ZX80: L06E0

.global Unstack
Unstack:
	; skip if only checking syntax
	IF_SYNTON		; if only checking syntax
	rjmp	Unstack2	; skip if only checking syntax

	; run-time, restore screen coordinates to lower screen
	ldd	E_,Y+DATA_DISP2PTR		; lower screen start address -> DE'
	ldd	D_,Y+DATA_DISP2PTR+1
	ldd	C_,Y+DATA_PRINTCOLS		; remaining columns
	ldd	B_,Y+DATA_PRINTROWS		; remaining rows
	ret

Unstack2:
	; only checking syntax, destroys return address
	POP_HL

; USR function not supported on ATX80
; ZX80: L06F0

.global Usr
Usr:
	ret		; return to main function

; ----------------------------------------------------------------------------
;                        Print item
; ----------------------------------------------------------------------------
; Updates print variables.
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
; STACK: 10
; ----------------------------------------------------------------------------
; ZX80: L06F1

.global PrItem
PrItem:
	; return if error has been encountered
	IF_ERROR
	ret

	; quit if checking syntax
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
	rcall	Unstack

	; load result -> HL
; OUTPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rcall	LoadResult	; load result -> HL

	; check type of result
	IF_STRRES		; string result?
; INPUT: HL = pointer to the string
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: A, HL', PUSH1, R1, R0
; STACK: 8
	rjmp	PrString	; print string

	; print numeric result
	movw	BC,HL		; BC <- numeric result
; INPUT: BC = number to print
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
	rcall	PrintNum	; print number

	; store print position or error
; INPUT: DE' = current print address
;	 C' = remaining columns
;	 B' = remaining rows
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: R1, R0 (saves flags)
; STACK: 4
	rjmp	PoCheck

; ----------------------------------------------------------------------------
;                        Print string
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to the string
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: A, HL', PUSH1, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L070C (begin L0709)

.global PrString
PrString:
	; check end of string
	ld	A,MHL+		; load next character
	cpi	A,CH_QUOT	; end of string?
; INPUT: DE' = current print address
;	 C' = remaining columns
;	 B' = remaining rows
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: R1, R0 (saves flags)
; STACK: 4
	breq	PoStore		; end of string, store print position

	; check control character or token
	sbrs	A,6		; check bit 6 - control character flag
	rjmp	PrString2	; bit 6 not set, print simple character

	; bit 6 is set, print token
; INPUT: A = token index 0xD4..0xFF
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, R1, R0
; STACK: 6
	rcall	PrintToken	; print token
	rjmp	PrString4

	; print simple character
PrString2:
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh		; print character
PrString4:
	brcs	PrString	; memory OK, go to next character
; DESTROYS: L (saves flags)
; STACK: 2
	rjmp	DispError	; error, out of screen

; ----------------------------------------------------------------------------
;                        Print Carriage return
; ----------------------------------------------------------------------------
; Updates print variables.
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L071B

.global PrintCR
PrintCR:
	; quit if checking syntax
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
	rcall	Unstack

	; print NEWLINE
	ldi	A,NEWLINE
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintChSpc	; print character or space, enables leading spaces

PoCheck:
; INPUT: DE' = current print address
;	 C' = remaining columns
;	 B' = remaining rows
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: R1, R0 (saves flags)
; STACK: 4
	brcs	PoStore		; store print position if no error

; DispError must follow

; ----------------------------------------------------------------------------
;                            Error - Screen is full
; ----------------------------------------------------------------------------
; DESTROYS: L (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0725

.global DispError
DispError:
	ldi	L,ERR_SCREEN
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error		; error

; ----------------------------------------------------------------------------
;                       Position fill, tabulator
; ----------------------------------------------------------------------------
; OUTPUT: HL = new current print address (used as end of display)
;	  C = new remaining columns
;	  B = new remaining rows
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: A, DE, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L0727

.global PoFill
PoFill:
	; quit if only checking syntax, else restore print position to lower screen
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
	rcall	Unstack

	; signal no leading space
	SET_NOLEAD

	; print space character
2:	ldi	A,CH_SPC
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh
; DESTROYS: L (saves flags)
; STACK: 2
	brcc	DispError		; error, display or memory is full

	; repeat until tabulated position 0..7
	mov	A,C_			; remaining columns
	dec	A
	andi	A,7
	brne	2b

; PoStore must follow

; ----------------------------------------------------------------------------
;                         Store print position
; ----------------------------------------------------------------------------
; INPUT: DE' = current print address
;	 C' = remaining columns
;	 B' = remaining rows
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: R1, R0 (saves flags)
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L073A

.global PoStore
PoStore:
	; get alternative registers
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange alternative registers
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE and HL

; ----- save pointers
; ZX80: L073C
PoStore2:
	; save remaining free columns and rows
	std	Y+DATA_PRINTCOLS,C
	std	Y+DATA_PRINTROWS,B

	; set address of lower screen
	std	Y+DATA_DISP2PTR,L
	std	Y+DATA_DISP2PTR+1,H

	; set address of display end
	std	Y+DATA_DISPEND,L
	std	Y+DATA_DISPEND+1,H
	ret

; ----------------------------------------------------------------------------
;                         CLS - Clear display
; ----------------------------------------------------------------------------
; OUTPUT: HL = current print address (= start of display + 1)
;	  C = remaining columns (= 33)
;	  B = remaining rows (= 23)
; DESTROYS: - (saves flags)
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0747

.global DispCls
DispCls:
	; get display start address -> HL
; OUTPUT: HL = address of start of display DATA_DISPPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadDispPtr		; get display start address -> HL

	; store NEWLINE before first display row
	ldi	C,NEWLINE		; newline character
	st	MHL+,C			; save NEWLINE character

	; remaining free columns and rows
	ldi	C,WIDTH+1
	ldi	B,HEIGHT-1

	; save pointers
	rjmp	PoStore2

; ----------------------------------------------------------------------------
;                       Z80 supporting functions
; ----------------------------------------------------------------------------
; This file is included in middle of the source, to enable using rjmp and
; rcall instructions in AVR with larger Flash memory than 8 KB.
#include "z80.S"

; ----------------------------------------------------------------------------
;                         Syntax table
; ----------------------------------------------------------------------------
; ZX80: L0752
; Difference of WinAVR compiler:
; 1) We cannot compile relocated labelled expression as a byte, it must be a word.
;    Therefore, we prefer to specify parameter offsets manually, as bytes.
; 2) Labels must start at an even address (word). Therefore, we will build
;    the table as one big table without labels.
; The easiest way is to use the values from the ZX80 table directly.

; Command function:
; INPUT: HL = pointer to program line
;	 BC = last result
;	 Z = ZY if result is 0

.global SyntTab
SyntTab:
	.byte	0x07A1 - 0x0752		; L0752: $4F offset to $07A1 P-LIST
	.byte	0x077F - 0x0753		; L0753: $2C offset to $077F P-RETURN
	.byte	0x07B8 - 0x0754		; L0754: $64 offset to $07B8 P-CLS
	.byte	0x0794 - 0x0755		; L0755: $3F offset to $0794 P-DIM
	.byte	0x07AF - 0x0756		; L0756: $59 offset to $07AF P-SAVE
	.byte	0x0782 - 0x0757		; L0757: $2B offset to $0782 P-FOR
	.byte	0x076F - 0x0758		; L0758: $17 offset to $076F P-GO-TO
	.byte	0x07A4 - 0x0759		; L0759: $4B offset to $07A4 P-POKE
	.byte	0x0790 - 0x075A		; L075A: $36 offset to $0790 P-INPUT
	.byte	0x07A9 - 0x075B		; L075B: $4E offset to $07A9 P-RANDOMISE
	.byte	0x076C - 0x075C		; L075C: $10 offset to $076C P-LET
;	.byte	0x07BB - 0x075D		; L075D: $5E offset to $07BB P-CH-END
	.byte	0x07C4 - 0x075D		; L075D:     offset to $07C4 P-FAST ... ATX80 extension, set fast mode of display
;	.byte	0x07BB - 0x075E		; L075E: $5D offset to $07BB P-CH-END
	.byte	0x07C7 - 0x075E		; L075E:     offset to $07C7 P-SLOW ... ATX80 extension, set slow mode of display
	.byte	0x0789 - 0x075F		; L075F: $2A offset to $0789 P-NEXT
	.byte	0x078D - 0x0760		; L0760: $2D offset to $078D P-PRINT
;	.byte	0x07BB - 0x0761		; L0761: $5A offset to $07BB P-CH-END
	.byte	0x07C1 - 0x0761		; L0761:     offset to $07C1 P-MEMORY ... ATX80 extension, display memory info
	.byte	0x07BE - 0x0762		; L0762: $5C offset to $07BE P-NEW
	.byte	0x079E - 0x0763		; L0763: $3B offset to $079E P-RUN
	.byte	0x077C - 0x0764		; L0764: $18 offset to $077C P-STOP
	.byte	0x07B2 - 0x0765		; L0765: $4D offset to $07B2 P-CONTINUE
	.byte	0x0773 - 0x0766		; L0766: $0D offset to $0773 P-IF
	.byte	0x0778 - 0x0767		; L0767: $11 offset to $0778 P-GOSUB
	.byte	0x07AC - 0x0768		; L0768: $44 offset to $07AC P-LOAD
	.byte	0x07B5 - 0x0769		; L0769: $4C offset to $07B5 P-CLEAR
	.byte	0x079B - 0x076A		; L076A: $31 offset to $079B P-REM
	.byte	0x07BB - 0x076B		; L076B: $50 offset to $07BB P-CH-END

; L076C: P-LET
	.byte	CLASS1		; class 1 - a variable is required
	.byte	TOKEN_EQU	; '=' token
	.byte	CLASS2		; class 2 - an expression of type integer or string must follow

; L076F: P-GO-TO (continue of P-LET)
	.byte	CLASS6		; class 6 - a numeric expression must follow
	.byte	CLASS0		; class 0 - no further operands
; INPUT: BC = new program line
; DESTROYS: -
; STACK: 2
	.word	Goto

; L0773: P-IF
	.byte	CLASS6		; class 6 - a numeric expression must follow
	.byte	TOKEN_THEN	; 'THEN' token
	.byte	CLASS5		; class 5 - variable syntax checked entirely by routine
	.word	CmdIf

; L0778: P-GOSUB
	.byte	CLASS6		; class 6 - a numeric expression must follow
	.byte	CLASS0		; class 0 - no further operands
; INPUT: BC = destination line number
; DESTROYS: HL, BC, DE, R1, R0
; STACK: 4 + 2 inserted return line number
	.word	Gosub

; L077C: P-STOP
	.byte	CLASS0		; class 0 - no further operands
; DESTROYS: L (saves flags)
; STACK: 2
	.word	Stop

; L077F: P-RETURN
	.byte	CLASS0		; class 0 - no further operands
; DESTROYS: HL, BC
; STACK: 2 - 2 returned line number
	.word	Return

; L0782: P-FOR
	.byte	CLASS4		; class 4 - a single-character variable must follow
	.byte	TOKEN_EQU	; '=' token
	.byte	CLASS6		; class 6 - a numeric expression must follow
	.byte	TOKEN_TO	; 'TO' token
	.byte	CLASS5		; class 5 - variable syntax checked entirely by routine
	.word	CmdFor

; L0789: P-NEXT
	.byte	CLASS4		; class 4 - a single-character variable must follow
	.byte	CLASS0		; class 0 - no further operands
	.word	CmdNext

; L078D: P-PRINT
	.byte	CLASS5		; class 5 - variable syntax checked entirely by routine
	.word	Print

; L0790: P-INPUT
	.byte	CLASS1		; class 1 - a variable is required
	.byte	CLASS0		; class 0 - no further operands
	.word	Input

; L0794: P-DIM
	.byte	CLASS4		; class 4 - a single-character variable must follow
	.byte	TOKEN_LPAR	; '(' token
	.byte	CLASS6		; class 6 - a numeric expression must follow
	.byte	TOKEN_RPAR	; ')' token
	.byte	CLASS0		; class 0 - no further operands
; INPUT: BC = number of entries (valid range 0..255)
; OUTPUT: HL = number of entries
; DESTROYS: AF, BC, DE, HL, PUSH3, PUSH2, PUSH1, R1, R0
; STACK: 8
	.word	CmdDim

; L079B: P-REM
	.byte	CLASS5		; class 5 - variable syntax checked entirely by routine
; INPUT: HL = pointer to program line
; OUTPUT: HL = new current address of the text
;	  A = next character
; DESTROYS: -
; STACK: 6
	.word	CmdRem

; L079E: P-RUN
	.byte	CLASS3		; class 3 - a numeric expression may follow, otherwise zero will be used
; INPUT: BC = new program line
; OUTPUT: HL = address of begin of variables
;	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
	.word	Run

; L07A1: P-LIST
	.byte	CLASS3		; class 3 - a numeric expression may follow, otherwise zero will be used
	.word	CmdList

; L07A4: P-POKE
	.byte	CLASS6		; class 6 - a numeric expression must follow
	.byte	TOKEN_COMMA	; ',' token
	.byte	CLASS5		; class 5 - variable syntax checked entirely by routine
	.word	CmdPoke

; L07A9: P-RANDOMISE
	.byte	CLASS3		; class 3 - a numeric expression may follow, otherwise zero will be used
; INPUT: BC = new seed value for random generator, 0 = use random value from FRAMES
;	 Z = ZY if result BC is 0
; DESTROYS: BC
	.word	Randomise

; L07AC: P-LOAD
;	.byte	CLASS0		; class 0 - no further operands
	.byte	CLASS3		; class 3 - a numeric expression may follow, otherwise zero will be used
	.word	Load

; L07AF: P-SAVE
;	.byte	CLASS0		; class 0 - no further operands
	.byte	CLASS3		; class 3 - a numeric expression may follow, otherwise zero will be used
	.word	Save

; L07B2: P-CONTINUE
	.byte	CLASS0		; class 0 - no further operands
; DESTROYS: BC
; STACK: 2
	.word	Continue

; L07B5: P-CLEAR
	.byte	CLASS0		; class 0 - no further operands
; OUTPUT: HL = address of begin of variables
;	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
	.word	Clear

; L07B8: P-CLS
	.byte	CLASS0		; class 0 - no further operands
; OUTPUT: HL = current print address (= start of display + 1)
;	  C = remaining columns (= 33)
;	  B = remaining rows (= 23)
; DESTROYS: - (saves flags)
; STACK: 4
	.word	DispCls

; L07BB: P-CH-END
	.byte	CLASS5		; class 5 - variable syntax checked entirely by routine
	.word	CheckEnd3

; (L07BE:) P-NEW
	.byte	CLASS0		; class 0 - no further operands
	.word	CmdNew

; (L07C1:) P-MEMORY ... ATX80 extension, display memory info
	.byte	CLASS0		; class 0 - no further operands
	.word	CmdMemory

; (L07C4:) P-FAST ... ATX80 extension, set fast mode of display
	.byte	CLASS0		; class 0 - no further operands
	.word	CmdFast

; (L07C7:) P-SLOW ... ATX80 extension, set slow mode of display
	.byte	CLASS0		; class 0 - no further operands
	.word	CmdSlow

	.balign	2	; align to 2 bytes

; ----------------------------------------------------------------------------
;                       Run program or check syntax
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line + 1
; ----------------------------------------------------------------------------
; ZX80: L07BE

.global MainGo
MainGo:
	; store program pointer
	sbiw	HL,1		; return to current character
	std	Y+DATA_CHARPTR,L
	std	Y+DATA_CHARPTR+1,H

	; clear error pointer
	std	Y+DATA_ERRPTR,ZERO
	std	Y+DATA_ERRPTR+1,ZERO

	; check if input mode
	ldd	B,Y+DATA_FLAGX	; get flags
	IF_EDIT			; if edit mode (not inputing)
	rjmp	2f		; jump to editing mode

; ----- run-time input

	; signal L-mode
	cbr	B,B7		; clear flag "update K mode"
	std	Y+DATA_FLAGX,B	; save flags

	; load next character and fetch value
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAdd		; load next character from program line
	rjmp	FetchVal	; fetch value

; ----- not input mode - run program or check syntax
; ZX80: L07D7

	; signal K-mode
2:	sbr	B,B7		; set flag "update K mode"
	std	Y+DATA_FLAGX,B	; save flags

	; load next character and skip spaces
; OUTPUT: A = next character (from next address, skips cursor and spaces)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 4
	rcall	NextChar	; load next character

	; parse line number to alternate HL'
; INPUT: HL = current address of the text
; OUTPUT: HL = new current address of the text
;	  HL' = number 0..32767
;	  CY = overflow
; DESTROYS: AF, D', R1, R0
; STACK: 4
	rcall	IntToHL		; parse line number
	brcs	MainGo4		; overflow error

	; check line max. value 9999
	movw	AF,HL_		; get loaded number
	subi	F,lo8(10000)	; check line overflow	
	sbci	A,hi8(10000)
	brcs	LineScan	; line number is OK

; ZX80: L07E5
MainGo4:
	; error, bad line number entered
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rcall	InsErr

; ----- Start line scanning
; ZX80: L07E8

.global LineScan
LineScan:
	; load next character
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
	rcall	GetChar

	; do not update K-mode anymore
	ldd	B,Y+DATA_FLAGX	; get flags
	cbr	B,B7		; clear flag "update K mode"
	std	Y+DATA_FLAGX,B	; save flags

	; clear result
	std	Y+DATA_RESULT,ZERO
	std	Y+DATA_RESULT+1,ZERO

	; NEWLINE - quit processing
	cpi	A,NEWLINE
	breq	9f		; if NEWLINE found, stop processing

	; get next character with skipping spaces
	mov	C,A		; save A character
; OUTPUT: A = next character (from next address, skips cursor and spaces)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 4
	rcall	NextChar	; get next character

	; check minimal command token 'LIST'
	subi	C,TOKEN_LIST	; check 'LIST' token
	brcs	MainGo4		; other tokens than commands are not allowed at this place

	; get address of parameters
	ldi	L,lo8(SyntTab)	; syntax table
	ldi	H,hi8(SyntTab)
	add	L,C		; add token index
	adc	H,ZERO
	lpm	C,MHL		; load offset of the parameters
	add	L,C		; add offset of parameters
	adc	H,ZERO
	rjmp	MainScanLoop2

9:	ret

; ----- Main scanning loop
; ZX80: L0809

ScanLoop:
	; restore pointer to syntax table
	ldd	L,Y+DATA_NEXTTAB	; get pointer to syntax table
	ldd	H,Y+DATA_NEXTTAB+1

MainScanLoop2:
	; get parameter from the syntax table
	lpm	A,MHL+			; load parameter byte
	std	Y+DATA_NEXTTAB,L	; store new address
	std	Y+DATA_NEXTTAB+1,H

	; store return address into the stack
	ldi	C,lo8(ScanLoop)
	ldi	B,hi8(ScanLoop)
	lsr	B			; convert to word index
	ror	C
	PUSH_BC				; store return address into the stack

	; check separator character
	mov	C,A			; save character
	lsl	A			; check bit 7
	brcs	ScanSep			; bit 7 is set, parse separator

	; load class address into the stack
	ldi	L,lo8(TabClass)		; class table
	ldi	H,hi8(TabClass)
	add	L,A			; add class * 2
	adc	H,ZERO
	lpm	F,MHL+			; load class address LOW
	lpm	A,MHL
	lsr	A			; convert to word index
	ror	F
	PUSH_AF				; push address

	; get next character and skip spaces, on return jumps to class function (zero flag is cleared NZ)
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
	rjmp	GetChar

; ----- check separator
; ZX80: L0826

ScanSep:
	; load next character
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
	rcall	GetChar

	; if token 'THEN', set back to K mode
	cpi	A,TOKEN_THEN	; 'THEN' token
	brne	2f

	; set K mode
	ldd	F,Y+DATA_FLAGX	; get flags
	sbr	F,B7		; set flag "update K mode"
	std	Y+DATA_FLAGX,F	; save flags

	; compare separator
2:	cp	A,C
	breq	3f
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rjmp	InsErr		; incorrect separator, go to InsErr

	; load next character with skipping spaces, then return back to ScanLoop
; OUTPUT: A = next character (from next address, skips cursor and spaces)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 4
3:	rjmp	NextChar

; ----------------------------------------------------------------------------
;                            Command class table
; ----------------------------------------------------------------------------
; ZX80: L0836

.global TabClass
TabClass:
	.word	Class0
	.word	Class1
	.word	Class2
	.word	Class3
	.word	Class4
	.word	Class5
	.word	Class6

; ----------------------------------------------------------------------------
;   Check end of command line (only if checking syntax, or only return if not)
; ----------------------------------------------------------------------------
; INPUT: HL = program pointer
; DESTROYS: A, BC, R0
; STACK: 2 (or 6 if checking syntax)
; ----------------------------------------------------------------------------
; ZX80: L083D

.global CheckEnd
CheckEnd:
	; check if running program
	IF_SYNTOFF		; if syntax is off
	ret			; return if running program

	; drop return address
	POP_BC

; ZX80: L0843
CheckEnd2:
	; check that NEWLINE must follow
	ld	A,MHL		; load current character

; ZX80: L0844
CheckEnd3:
	cpi	A,NEWLINE	; end of line?
; INPUT: HL = pointer to program line
; OUTPUT: HL = new current address of the text
;	  A = next character
; DESTROYS: -
; STACK: 6
	breq	CmdRem		; new line is OK

CheckEnd4:
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rcall	InsErr		; insert error

; CmdRem must follow

; ----------------------------------------------------------------------------
;                            REM command
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line
; OUTPUT: HL = new current address of the text
;	  A = next character
; DESTROYS: -
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L0849 (incorrectly L084A)
;
; Note: ZX80 code has error at this place. Class 5 pointer points to 2nd instruction
; of the function and therefore empty command 'REM' skips following program line.

.global CmdRem
CmdRem:
	; load current character
	ld	A,MHL

; ZX80: L084A, here is ZX80 original address of the function
CmdRem2:
	cpi	A,NEWLINE		; end of line?
	breq	JumpBCRet		; end

	; load next character with skipping spaces
; OUTPUT: A = next character (from next address, skips cursor and spaces)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 4
	rcall	NextChar
	rjmp	CmdRem2

; ----------------------------------------------------------------------------
;                            Command class 3
;      a numeric expression may follow, otherwise zero will be used
; ----------------------------------------------------------------------------
; INPUT: A = next character
;	 HL = new current address of the text
; ----------------------------------------------------------------------------
; ZX80: L0850

.global Class3
Class3:
	; check end of line
	cpi	A,NEWLINE		; end of line?
	breq	Class0			; end of line

	; if not end of line, load parameter
	rcall	Class6			; look for optional number

; Class0 must follow

; ----------------------------------------------------------------------------
;                   Command class 0 - no further operands
; ----------------------------------------------------------------------------
; INPUT: A = next character
;	 HL = new current address of the text
; ----------------------------------------------------------------------------
; ZX80: L0855

.global Class0
Class0:
	; set zero flag to use later (call CheckEnd function)
	cp	A,A

; Note: When entering Class5 from scanning loop, zero flag is cleared by GetChar function.

; ----------------------------------------------------------------------------
;       Command class 5 - variable syntax checked entirely by routine
; ----------------------------------------------------------------------------
; INPUT: A = next character
;	 HL = new current address of the text
;	 ZY = call CheckEnd function (entered from Class0), NZ = do not call CheckEnd (enterd from ScanLoop)
; STACK: 2 -2, execute function and jump back to scan loop
; ----------------------------------------------------------------------------
; ZX80: L0856

.global Class5
Class5:
	; drop looping address, class 5 is last in sequence
	POP_BC

	; if zero flag is set then check end of program line
	brne	2f
; INPUT: HL = program pointer
; DESTROYS: A, BC, R0
; STACK: 2 (or 6 if checking syntax)
	rcall	CheckEnd	; check end of program line (or only return if not checking syntax)

	; load jump address to the command
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
2:	rcall	EXDEHL		; exchange DE and HL registers
	ldd	L,Y+DATA_NEXTTAB ; get pointer into syntax table
	ldd	H,Y+DATA_NEXTTAB+1
	lpm	C,MHL+		; load jump address
	lpm	B,MHL
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE and HL registers

; ----- run BC routine
; ZX80: L0862
JumpBC:
	; stor jump address into the stack
	lsr	B			; convert to word index
	ror	C
	PUSH_BC				; push address

	; load last result -> BC
	ldd	C,Y+DATA_RESULT
	ldd	B,Y+DATA_RESULT+1

	; check zero result
	mov	A,B
	or	A,C
JumpBCRet:
	ret				; jump to command routine

; ----------------------------------------------------------------------------
;               Command class 1 - a variable is required
; ----------------------------------------------------------------------------
; INPUT: A = next character
;	 HL = new current address of the text
; ----------------------------------------------------------------------------
; ZX80: L086A

.global Class1
Class1:
	; check first alphabetic character
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
	rcall	Alpha
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	brcc	InsErr		; error, invalid character

	; if checking syntax, go to look vars
	IF_SYNTON		; if check syntax
	rjmp	LookVars	; search variable

	; continue run-time, save variable name
	std	Y+DATA_VARDEST,L ; save variable address
	std	Y+DATA_VARDEST+1,H

	; look for variable (temporary switch ON syntax checking)
	SET_SYNTON		; enable syntax checking
; INPUT: HL = pointer to name of the variable
	rcall	LookVars	; search variable
	SET_SYNTOFF		; disable syntax checking
	ret

; ----------------------------------------------------------------------------
;                          Command class 2
;          an expression, of type integer or string, must follow
; ----------------------------------------------------------------------------
; INPUT: A = next character
;	 HL = new current address of the text
; ----------------------------------------------------------------------------
; ZX80: L0885

.global Class2
Class2:
	; drop looping address, class 2 is last in sequence
	POP_BC

	in	B,_SFR_IO_ADDR(GPIOR0) ; load flags

; Runtime uses FLAGX instead of FLAGS

; ----------------------------------------------------------------------------
;                                Fetch value
; ----------------------------------------------------------------------------
; INPUT: B = flags (Flag or FlagX)
; ----------------------------------------------------------------------------
; ZX80: L0889

.global FetchVal
FetchVal:
	; evaluate expression
	push	B		; save flags
	rcall	ScanCalc	; evaluate expression
	pop	D		; restore flags

	; prepare return address to LET routine
	ldi	C,lo8(CmdLet)
	ldi	B,hi8(CmdLet)

	; check if check syntax
	in	A,_SFR_IO_ADDR(GPIOR0) ; load flags
	IF_SYNTOFF		; if not checking syntax
	rjmp	JumpBC		; run next routine

	; if checking syntax, compare result type
	eor	A,D		; compare flags

	; error if result types (bit 6) are not the same
	sbrc	A,6		; skip if bit 6 of flags are identical
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rcall	InsErr		; insert error

	rjmp	CheckEnd2	; check end of expression

; ----------------------------------------------------------------------------
;               Class 4 - a single-character variable must follow
; ----------------------------------------------------------------------------
; INPUT: A = next character
;	 HL = new current address of the text
; ----------------------------------------------------------------------------
; ZX80: L089E

.global Class4
Class4:
	; store pointer to variable
	std	Y+DATA_VARDEST,L
	std	Y+DATA_VARDEST+1,H

	; check alpha character
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
	rcall	Alpha		; check alphabetic character
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	brcc	InsErr		; invalid variable name

	; load next character and skip spaces
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rjmp	CharAdd

; ----------------------------------------------------------------------------
;                 Class 6 - a numeric expression must follow
; ----------------------------------------------------------------------------
; INPUT: A = next character
;	 HL = new current address of the text
; ----------------------------------------------------------------------------
; ZX80: L08A8

.global Class6
Class6:
	; evaluate expression
	rcall	ScanCalc	; evaluate expression

	; check numeric expression
	IF_NUMRES		; if numeric result
	ret			; OK

; InsErr must follow

; ----------------------------------------------------------------------------
;                               Insert error
; ----------------------------------------------------------------------------
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L08AE

.global InsErr
InsErr:
	; check if error pointer is already set (not 0)
	ldd	A,Y+DATA_ERRPTR		; load error pointer
	ldd	r0,Y+DATA_ERRPTR+1
	or	A,r0			; is error pointer 0 ?
	brne	2f			; error pointer is already set

	; store new error address
	std	Y+DATA_ERRPTR,L
	std	Y+DATA_ERRPTR+1,H
2:	ret

; ----------------------------------------------------------------------------
;                            MEMORY command
; ----------------------------------------------------------------------------
; ... ATX80 extension, display memory info

.global CmdMemory
CmdMemory:
	; quit if checking syntax
; OUTPUT: DE' = new print address (start of lower screen)
;	  C' = new remaining columns
;	  B' = new remaining rows
; DESTROYS: R1, R0, destroys return address if only checking syntax
; STACK: 2, or -2 if checking syntax
	rcall	Unstack

	; get program size
	ldd	C,Y+DATA_VARSPTR	; start of variables
	ldd	B,Y+DATA_VARSPTR+1
	subi	C,lo8(Program)		; get program size
	sbci	B,hi8(Program)	

	; display program size
; INPUT: BC = number to print
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
	rcall	PrintNum	; print number

	; print separator '/'
	ldi	A,CH_SLASH	; '/' character
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 (missing ZY flag of display overflow)
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh		; print character

	; get variables size
	ldd	C,Y+DATA_EDITPTR	; start of edit line
	ldd	B,Y+DATA_EDITPTR+1
	ldd	E,Y+DATA_VARSPTR	; start of variables
	ldd	D,Y+DATA_VARSPTR+1
	sub	C,E			; get variables size
	sbc	B,D

	; display variables size
; INPUT: BC = number to print
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
	rcall	PrintNum	; print number

	; print separator '/'
	ldi	A,CH_SLASH	; '/' character
; INPUT: A = character to print (bit 7 = inverted, bit 6 = newline)
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	 (missing ZY flag of display overflow)
;	 B', C', DE' = updated
; DESTROYS: A, HL', R1, R0
; STACK: 4
	rcall	PrintCh		; print character

	; get free memory
	in	C,_SFR_IO_ADDR(SPL)	; load stack LOW
	in	B,_SFR_IO_ADDR(SPH)	; load stack HIGH
	ldd	E,Y+DATA_DISPEND	; display end
	ldd	D,Y+DATA_DISPEND+1
	subi	C,FREE_RES+10		; subtract some reserve
	sbc	B,ZERO
	sub	C,E			; subtract display end
	sbc	B,D
	brpl	2f
	ldi	C,0
	ldi	B,0

	; display free memory
; INPUT: BC = number to print
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
2:	rcall	PrintNum	; print number

	; store print position or error
; INPUT: DE' = current print address
;	 C' = remaining columns
;	 B' = remaining rows
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: R1, R0 (saves flags)
; STACK: 4
	rcall	PoCheck

	; check end of command
; INPUT: HL = program pointer
; DESTROYS: A, BC, R0
; STACK: 2 (or 6 if checking syntax)
	rcall	CheckEnd	; check end (or only return if not checking syntax)

	; display NEWLINE
	rjmp	PrintCR		; jump to print NEWLINE

; ----------------------------------------------------------------------------
;                            FAST command
; ----------------------------------------------------------------------------
; ... ATX80 extension, set fast mode of display

.global CmdFast
CmdFast:
	; check if running program
	IF_SYNTON		; if syntax is on
	ret			; return if not running program

	; set fast mode
	SET_FAST
	ret

; ----------------------------------------------------------------------------
;                            SLOW command
; ----------------------------------------------------------------------------
; ... ATX80 extension, set slow mode of display

.global CmdSlow
CmdSlow:
	; check if running program
	IF_SYNTON		; if syntax is on
	ret			; return if not running program

	; set slow mode
	SET_SLOW
	ret

; ----------------------------------------------------------------------------
;                            IF command
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line
;	 BC = last result
;	 Z = ZY if result BC is 0
; ----------------------------------------------------------------------------
; ZX80: L08B9

.global CmdIf
CmdIf:
	; skip if result is TRUE, then execute following code
	brne	2f		; go to TRUE

	; if run-time, skip rest of the line
	IF_SYNTOFF		; syntax is OFF?
; INPUT: HL = pointer to program line
; OUTPUT: HL = new current address of the text
;	  A = next character
; DESTROYS: -
; STACK: 6
	rjmp	CmdRem		; skip rest of line

	; continue execution (or check syntax)
2:	rjmp	LineScan	; continue line scanning

; ----------------------------------------------------------------------------
;                            FOR command
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line
;	 BC = last result
;	 Z = ZY if result BC is 0
; ----------------------------------------------------------------------------
; ZX80: L08C4

.global CmdFor
CmdFor:
	; save start value BC
	PUSH_BC			; save start value

	; load LIMIT
	rcall	Class6		; evaluate limit value

	; restore start value BC
	POP_BC			; restore start value

	; check end of command
; INPUT: HL = program pointer
; DESTROYS: A, BC, R0
; STACK: 2 (or 6 if checking syntax)
	rcall	CheckEnd	; check end of command (or only return if not checking syntax)

	; get LIMIT value from result -> HL
; OUTPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rcall	LoadResult	; load result DATA_RESULT to HL

	; save LIMIT into stack
	PUSH_HL			; save limit

	; store start value into variable
	rcall	CmdLet		; run LET command - store init value into variable

	; restore limit
	POP_BC			; restore limit

	; return if error has been encountered (variable does not exist)
	IF_ERROR
	ret

	; push limit
	PUSH_BC

	; check if variable is already initialized (change simple variable to loop variable)
; 011xxxxx numL numH - short-named 16-bit integer variable, name is letter A..Z (0x26..0x3F)
; 111xxxxx valueL valueH limitL limitH lineL lineH - control code of FOR loop (current value, last value, line number)
	sbiw	HL,1		; shift pointer to name of variable
	ld	F,MHL		; load variable name -> F
	mov	A,F		; save character -> A
	ori	A,B7		; set bit 7 (change to loop type of variable)
	st	MHL,A		; store name with bit 7 set
	adiw	HL,2		; shift pointer to last byte of value
	andi	F,B7		; check if variable is already initialized
	brne	4f		; variable is already initialized to loop mode

	; extend simple variable to loop type of the variable
	adiw	HL,1		; shift pointer to end of variable
	ldi	C,4		; else extra 4 bytes needed
	ldi	B,0
; INPUT: HL = current address (where new data should be inserted)
;	 BC = number of bytes to insert (must be >0)
; OUTPUT: HL = current address - 1
;	  DE = address of start of moved block - 1 (= last byte of new free space)
;	  BC = 0
; DESTROYS: R1, R0
; STACK: 4
	rcall	MakeRoom	; make room

	; shift pointer to the limit
4:	adiw	HL,1		; shit pointer to the limit

	; store limit value
	POP_DE			; restore limit value
	st	MHL+,E		; store limit
	st	MHL+,D

	; load current line
	ldd	E,Y+DATA_EXECLINE ; load current line
	ldd	D,Y+DATA_EXECLINE+1
	adiw	DE,1		; increment to point to next program line

	; store loop destination line
	st	MHL+,E		; store current line
	st	MHL,D
CmdFor9:
	ret

; ----------------------------------------------------------------------------
;                              NEXT command
; ----------------------------------------------------------------------------
; ZX80: L08F9

.global CmdNext
CmdNext:
	; fetch address of variable -> HL
; OUTPUT: HL = address of variable name DATA_VARDEST
; DESTROYS: -
; STACK: 2
	rcall	LoadVarDest	; get address of variable

	; find variable
; INPUT: HL = pointer to first letter of name of variable
	rcall	LVFind		; find variable

	; return if error is set (variable was not found)
	IF_ERROR		; if error
	ret

; Here is: HL = value, DE = pointer to high byte of value location
; variable 111xxxxx valueL valueH limitL limitH lineL lineH - control code of FOR loop (current value, last value, line number)

	; shift pointer to start of variable
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE and HL, DE <- value, HL <- address
	sbiw	HL,2		; shift pointer to letter of the variable

	; check if variable is initialized with FOR
	ld	F,MHL+		; load letter
	andi	F,B7		; check bit 7
; DESTROYS: L (saves flags)
; STACK: 2
	breq	NextError	; error - variable is not initialized by FOR

	; increment value of the variable
	adiw	DE,1		; increment loop value
	st	MHL+,E		; store new value
	st	MHL+,D

	; load limit of the loop -> BC
	ld	C,MHL+
	ld	B,MHL+

	; save pointer to variable
	movw	r0,HL

	; compare limit HL with value DE
	movw	HL,BC		; HL <- limit
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = 0xFFFF (true) if HL<DE, 0 (false) if HL>=DE
; DESTROYS: -
; STACK: 2
	rcall	NumLes		; compare HL < DE
	adiw	HL,0		; check result

	; restore pointer to variable
	movw	HL,r0

	; return if end of loop (if limit HL < value DE, result is 0xFFFF)
	brne	CmdFor9		; end of loop

	; load line number and jump to it
	ld	C,MHL+		; load line number
	ld	B,MHL
; INPUT: BC = new program line
; DESTROYS: -
; STACK: 2
	rjmp	Goto		; go to program line

; ----------------------------------------------------------------------------
;                       NEXT error - NEXT without FOR
; ----------------------------------------------------------------------------
; DESTROYS: L (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0921

.global NextError
NextError:
	; NEXT error
	ldi	L,ERR_NEXTFOR	 	; NEXT error
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error

; ----------------------------------------------------------------------------
;                             RANDOMISE
; ----------------------------------------------------------------------------
; INPUT: BC = new seed value for random generator, 0 = use random value from FRAMES
;	 Z = ZY if result BC is 0
; DESTROYS: BC
; ----------------------------------------------------------------------------
; ZX80: L0923

.global Randomise
Randomise:
	; check if seed is zero
	brne	2f		; seed is not zero

	; get seed from frame counter
	ldd	C,Y+DATA_FRAMES
	ldd	B,Y+DATA_FRAMES+1

	; save new seed value
2:	std	Y+DATA_SEED,C	; save new seed value
	std	Y+DATA_SEED+1,B
	ret

; ----------------------------------------------------------------------------
;                             STOP program
; ----------------------------------------------------------------------------
; DESTROYS: L (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L092E

.global Stop
Stop:
	ldi	L,ERR_STOP		; STOP command
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error			; error

; ----------------------------------------------------------------------------
;                             CONTINUE program
; ----------------------------------------------------------------------------
; DESTROYS: BC
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0930

.global Continue
Continue:
	; restore old program line
	ldd	C,Y+DATA_OLDLINE	; get old line to continue
	ldd	B,Y+DATA_OLDLINE+1

; Goto must continue

; ----------------------------------------------------------------------------
;                             GO TO program line
; ----------------------------------------------------------------------------
; INPUT: BC = new program line
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0934

.global Goto
Goto:
	; store new program line
	std	Y+DATA_EXECLINE,C	; set new program line
	std	Y+DATA_EXECLINE+1,B

	; set [K] cursor
	SET_KCURSOR
Goto9:	ret

; ----------------------------------------------------------------------------
;                             RUN program
; ----------------------------------------------------------------------------
; INPUT: BC = new program line
; OUTPUT: HL = address of begin of variables
;	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L093D

.global Run
Run:
	; set new program line
; INPUT: BC = new program line
; DESTROYS: -
; STACK: 2
	rcall	Goto		; set new program line
; OUTPUT: HL = address of begin of variables
;	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
	rjmp	Clear		; clear variables

; ----------------------------------------------------------------------------
;                             GOSUB command
; ----------------------------------------------------------------------------
; INPUT: BC = destination line number
; DESTROYS: HL, BC, DE, R1, R0
; STACK: 4 + 2 inserted return line number
; ----------------------------------------------------------------------------
; ZX80: L0943

.global Gosub
Gosub:
	; load current executed line number -> HL
	ldd	L,Y+DATA_EXECLINE	; current line number
	ldd	H,Y+DATA_EXECLINE+1

	; drop return address -> R1:R0
	pop	r1
	pop	r0

	; place next line number to the stack
	adiw	HL,1			; increment current line number
	PUSH_HL				; store next line number into stack

	; restore return address into stack
	push	r0
	push	r1

	; jump to destination using GOTO
; INPUT: BC = new program line
; DESTROYS: -
; STACK: 2
	rcall	Goto			; set new program line

	; exit by a six-byte memory check
	ldi	B,0
	ldi	C,6

; CheckMem must follow

; ----------------------------------------------------------------------------
;                          Check free memory
; ----------------------------------------------------------------------------
; INPUT: BC = required number of bytes to allocate
; OUTPUT: NC = memory error
;	  DE = new end of data (new display end)
; DESTROYS: HL, R0
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L094F

.global CheckMem
CheckMem:
	; get end address of the display -> DE
	ldd	E,Y+DATA_DISPEND	; display end
	ldd	D,Y+DATA_DISPEND+1

	; get new end address -> DE
	add	E,C			; add block size
	adc	D,B

	; remaining number of bytes = number of remaining rows
	ldd	L,Y+DATA_PRINTROWS	; remaining rows -> L

	; save A register into H
	mov	H,A

; CheckFree must follow

; ----------------------------------------------------------------------------
;                      Check free memory after pointer
; ----------------------------------------------------------------------------
; INPUT: L = required reserve
;	 H = saved accumulator A
;	 DE = pointer, current end of display
; OUTPUT: NC = memory error
;	  A = restored accumulator from H
; DESTROYS: HL, R0
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0958

.global CheckFree
CheckFree:
	; restore accumulator from H
	mov	A,H

	; add some reserve
	clr	H
	subi	L,-FREE_RES		; some reserve for a few NEWLINEs, error text 0/9999 and video interrupt

	; new pointer -> HL
	add	L,E
	adc	H,D

	; check reserve
	in	r0,_SFR_IO_ADDR(SPL)	; load stack LOW
	sub	L,r0
	in	r0,_SFR_IO_ADDR(SPH)	; load stack HIGH
	sbc	H,r0
	brcs	Goto9			; free space is OK

; MemError must follow

; ----------------------------------------------------------------------------
;                              Memory error
; ----------------------------------------------------------------------------
; DESTROYS: L, saves flags
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0963

.global MemError
MemError:
	; memory error
	ldi	L,ERR_MEMORY	 	; memory error
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error

; ----------------------------------------------------------------------------
;                             RETURN command
; ----------------------------------------------------------------------------
; DESTROYS: HL, BC
; STACK: 2 - 2 returned line number
; ----------------------------------------------------------------------------
; System stack contains line number following GOSUB command.
; ZX80: L0965

.global Return
Return:
	; load line number of return address, saved in the stack
	POP_HL			; get return address
	POP_BC			; get line number

	; check if line number is valid
	cpi	B,0x3f		; check end-marker 0x3F00?
	breq	9f		; end-marker has been found, return address is invalid

	; line number is valid, jump to return line
	PUSH_HL			; restore return address
; INPUT: BC = new program line
; DESTROYS: -
; STACK: 2
	rjmp	Goto		; jump to return line
	
	; invalid return line number, restore return address
9:	PUSH_BC			; store end-marker back to the stack
	PUSH_HL			; restore return address

; ReturnError must follow

; ----------------------------------------------------------------------------
;                   RETURN error - no GOSUB
; ----------------------------------------------------------------------------
; DESTROYS: L, saves flags
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0970

.global ReturnError
ReturnError:
	; RETURN error
	ldi	L,ERR_RETURN	 	; RETURN error
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error

; ----------------------------------------------------------------------------
;                             PRINT command
; ----------------------------------------------------------------------------
; ZX80: L0972

.global Print
Print:
	; check empty row
	ld	A,MHL		; fetch the character
	cpi	A,NEWLINE	; NEWLINE? (empty row)
	brne	2f		; no
; Updates print variables.
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
; STACK: 6
	rjmp	PrintCR		; jump to print NEWLINE

	; check separator ','
2:	subi	A,TOKEN_COMMA	; check tokens ',' and ';' (',' gives 0, ';' gives -1 and carry)
	adc	A,ZERO		; check separator (both ';'  and ',' results 0)
	breq	4f		; character is separator ',' or ';'

	; evaluate expression
	rcall	ScanCalc	; scanning calculator expression

	; print item
; Updates print variables.
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
; STACK: 10
	rcall	PrItem

	; get next character
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
	rcall	GetChar

	; check separator ','
	subi	A,TOKEN_COMMA	; check tokens ',' and ';' (',' gives 0, ';' gives -1 and carry)
	adc	A,ZERO		; check separator (both ';'  and ',' results 0, CY=';')
	breq	4f		; character is separator ',' or ';'

	; check end of command
; INPUT: HL = program pointer
; DESTROYS: A, BC, R0
; STACK: 2 (or 6 if checking syntax)
	rcall	CheckEnd	; check end (or only return if not checking syntax)
; Updates print variables.
; OUTPUT: HL = current print address
;	  C = remaining columns
;	  B = remaining rows
;	  DE = original HL
; STACK: 6
	rjmp	PrintCR		; jump to print NEWLINE

	; shift to tabulator position if comma ','
4:	brcs	6f		; skip if ';'
; OUTPUT: HL = new current print address (used as end of display)
;	  C = new remaining columns
;	  B = new remaining rows
;	  Registers are exchanged using EXX and EXDEHL.
; DESTROYS: A, DE, R1, R0
; STACK: 6
	rcall	PoFill		; position fill

	; get next character
; OUTPUT: A = next character (from next address, skips cursor and spaces)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 4
6:	rcall	NextChar
	cpi	A,NEWLINE	; end of row?
	brne	2b		; process next item
	ret

; ----------------------------------------------------------------------------
;                             INPUT command
; ----------------------------------------------------------------------------
; ZX80: L099A

.global Input
Input:
	; check direct statement - line number HIGH will be -2
	ldd	F,Y+DATA_EXECLINE+1 ; get line number of current statement HIGH
	tst	F		; check line number HIGH
	brmi	InputError	; direct statement, error

	; discard return address
	POP_HL

	; signal input mode
	SET_INPUT		; set input mode

	; get extended flags and clear result type
	ldd	F,Y+DATA_FLAGX	; load extended flags
	cbr	F,B6		; clear bit 6 (result type)

	; get current result type
	in	A,_SFR_IO_ADDR(GPIOR0) ; get flags
	andi	A,B6		; isolate bit 6 - result type

	; prepare required space for input
	ldi	B,0
	ldi	C,2		; allocate 2 bytes for numeric
	brne	2f		; required numeric result
	ldi	C,4		; allocate 2 extra bytes for quotes

	; store new extra flags
2:	or	A,F
	std	Y+DATA_FLAGX,A	; store new extra flags

	; allocate free space at end of edit line
; INPUT: BC = required free space
; OUTPUT: DE = address of start of new free space in edit line + 1 (after old NEWLINE)
;	  HL = address after free space (pointer to new NEWLINE or end-mark 0x80)
;	  NC = memory error
; DESTROYS: PUSH2, PUSH1, R1, R0
; STACK: 6
	rcall	Reserve
	brcc	CmdPoke9	; memory error

	; mark end of line
	ldi	F,NEWLINE
	st	MHL,F		; store NEWLINE after end of allocate space

	; check numeric result
	cpi	C,2		; numeric result?
	breq	3f		; skip if numeric result

	; insert initial and closing quote
	ldi	A,CH_QUOT	; quote character
	st	MDE,A		; store initial quote
	st	-MHL,A		; store closing quote

	; insert cursor
3:	ldi	A,CURSOR	; cursor - inverted 'K' character
	st	-MHL,A		; store cursor character

	; decrease number of remaining rows
	ldd	A,Y+DATA_PRINTROWS ; number of remaining free rows to print
	inc	A		; reserve for blank line
	std	Y+DATA_DISP2LINES,A ; set number of rows of lower screen

	; jump back to EdCopy
	rjmp	EdCopy

; ----------------------------------------------------------------------------
;                 INPUT error - can only be used in a program
; ----------------------------------------------------------------------------
; DESTROYS: L (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L09CF

.global InputError
InputError:
	; INPUT error
	ldi	L,ERR_INPUT	 	; INPUT error
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error

; ----------------------------------------------------------------------------
;                            POKE command
; ----------------------------------------------------------------------------
; ZX80: L09D1

.global CmdPoke
CmdPoke:
	; push previous result - destination address
	PUSH_BC

	; evaluate expression after comma (value)
	rcall	ScanCalc	; scanning calculator expression

	; restore destination adedress
	POP_DE

	; check end (or only return if not checking syntax)
; INPUT: HL = program pointer
; DESTROYS: A, BC, R0
; STACK: 2 (or 6 if checking syntax)
	rcall	CheckEnd

	; value to store
	ldd	A,Y+DATA_RESULT	; last value

	; return if error
	IF_ERROR
	ret

	; conversion from ZX80 address to ATX80 address
	subi	E,lo8(-ZX80_SHIFT)
	sbci	D,hi8(-ZX80_SHIFT)

	; save value
	st	MDE,A		; store value into RAM
CmdPoke9:
	ret

; ----------------------------------------------------------------------------
;                     Evaluate expression
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to text
; ----------------------------------------------------------------------------
; ZX80: L0025

.global EvalExp
EvalExp:
	; get current character with skipping spaces
; INPUT: HL = current address of the text
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAddLP		; get current character

; ScanCalc must follow

; ----------------------------------------------------------------------------
;                      Scanning calculator expression
; ----------------------------------------------------------------------------
; DESTROYS: 
; ----------------------------------------------------------------------------
; ZX80: L0028, RST 28H, L09E1

.global ScanCalc
ScanCalc:

; ----- reset priority level and start scanning

	; get current character from edit line with skipping spaces
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
	rcall	GetChar			; get current character

	; reset priority level, reset operation
	ldi	B,0
	ldi	C,0

	; save current priority on machine stack - flag to terminate scanning
	PUSH_BC

; ----- first character - check unary operator
; ZX80: L09E3

ScanLoop1:
	; check alphanumeric character '0'..'9' or 'A'..'Z'
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
	rcall	AlphaNum		; check alphanumeric character
	brcs	ScanVarNum		; valid alphanumeric character, this is variable or digit

	; consider negate '-' and perform "0 - value"
	ldi	B,9			; prepare priority 9
	ldi	C,0			; operation 'subtract'
	ldi	E,0			; set DE value to 0
	ldi	D,0
	subi	A,TOKEN_SUB		; check token '-'
	breq	ScanPushPo		; unary minus

	; consider 'not' and perform "0xFFFF - value"
	sbiw	DE,1			; set DE to 0xFFFF
	ldi	B,4			; prepare priority 4, operation stays 'subtract'
	inc	A			; check token 'NOT'
	breq	ScanPushPo		; unary NOT

	; consider opening bracket
	inc	A			; check token '('
	breq	ScanBracket		; bracket

; ----- evaluate string

	; consider quote "
	cpi	A,CH_QUOT-TOKEN_SUB+1+1	; check character "
	brne	ScanAbort		; no valid case

	; store string pointer
	SET_STRRES			; set string result
	adiw	HL,1			; skip " character
; INPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rcall	SaveResult		; save last result DATA_RESULT from HL
					; - store string pointer in the result

	; find end of string
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
3:	rcall	CharAdd		; increment and load character
	dec	A		; check character " 0x01, end of string
	breq	ScanCont	; end of string

	cpi	A,NEWLINE-1	; check NEWLINE character
	brne	3b		; not NEWLINE, loop next character

; ----- error, abort processing of this level
; ZX80: L0A0E

ScanAbort:
	; abort, something unexpected appeared
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rcall	InsErr		; insert error
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers
	ldi	B,0		; reset priority level
	ldi	C,0
	rjmp	ScanLoop3

; ----- process unary operator (push into stack)
; ZX80: L0A17

ScanPushPo:
	; push value and operator into stack
	PUSH_DE			; push value
	PUSH_BC			; push operation and priority level

; ZX80: L0A19
ScanLoop2:
	; get next character and continue parse next operator
; OUTPUT: A = next character (from next address, skips cursor and spaces)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 4
	rcall	NextChar	; get next character
	rjmp	ScanLoop1	; parse next operator

; ----- bracket '(', evaluate bracket expression
; ZX80: L0A1C

ScanBracket:
	; evaluate bracket expression and scan next operator
	rcall	Bracket		; evaluate bracket expression
	rjmp	ScanOpertr	; scan operator

; ----- end of string, continue scanning

ScanCont:
	; get next character
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAdd		; get next character	
	rjmp	ScanOpertr	; scan operator

; ----- here is variable or digit
; ZX80: L0A24

ScanVarNum:
	cpi	A,CH_A		; check whether letter or digit
	brcs	ScanDigit	; scan digit

	; character is alpha - use variable
; INPUT: HL = pointer to name of the variable
	rcall	LookVars	; find variable
	rjmp	ScanOpertr	; scan operator

; ----- digit

ScanDigit:
	; load number
; INPUT: HL = current address of the text
; OUTPUT: HL = new current address of the text
;	  HL' = number 0..32767
;	  CY = overflow
; DESTROYS: AF, D', R1, R0
; STACK: 4
	rcall	IntToHL		; load number
	brcc	2f		; no overflow
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rcall	InsErr		; set error
2:	SET_NUMRES		; set numeric result

; ----- scan operator
; ZX80: L0A37

ScanOpertr:
	; get current character - get operator
; OUTPUT: A = current character (from current address, skips cursor and spaces)
;	  HL = new current address of the text
;	  NZ = clear zero flag (required by ScanLoop function)
; DESTROYS: -
; STACK: 4
	rcall	GetChar		; get current character
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers

	; check operator
	ldi	B,0		; reset priority if no operator
	ldi	C,0
	subi	A,TOKEN_SUB	; minimal operator '-'
	brcs	ScanLoop3	; invalid operator
	cpi	A,10		; check operator -, +, *, /, AND, OR, **, =, >, <
	brcc	ScanLoop3	; invalid operator

	; get operator priority
	mov	C,A		; C <- operator
	ldi	L,lo8(PriorTab) ; table od priority
	ldi	H,hi8(PriorTab)
	add	L,A		; add operator
	adc	H,ZERO
	lpm	B,MHL		; load priority -> B

; ----- compare with previous priority
; ZX80: L0A4C

ScanLoop3:
	; compare new priority
	POP_DE			; pop old priority
	cp	D,B		; compare old priority with current priority
	brcs	ScanTighter	; forward if current priority is higher

; ----- current priority is not higher, perform this operation

	; check zero priority, end of expression
	tst	D		; check zero priority = no operation
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers
	breq	8f		; return on zero priority, HL contains result
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers

	; skip if only checking syntax
	IF_SYNTON		; checking syntax?
	rjmp	ScanSynTest	; check syntax

	; get address of the operator
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: AF, DE, PUSH1, PUSH2, PUSH3, R1, R0
; STACK: 8
	ldi	L,lo8(TabOps)	; table of arithmetic operators
	ldi	H,hi8(TabOps)
	add	L,E		; add operator * 2
	adc	H,ZERO
	add	L,E
	adc	H,ZERO
	lpm	E,MHL+		; load address LOW
	lpm	D,MHL		; address HIGH

	; pop value -> HL and push return address
	pop	r1		; pop value
	pop	r0
	ldi	L,lo8(ScanInsVal) ; return address
	ldi	H,hi8(ScanInsVal)
	lsr	H
	ror	L		; convert address to word index
	PUSH_HL			; push return address
	movw	HL,r0		; HL <- value

	; push address of the routine and jump to it
	lsr	D
	ror	E		; convert address to word index
	PUSH_DE
	ldd	E,Y+DATA_RESULT	; get current result
	ldd	D,Y+DATA_RESULT+1
8:	ret			; jump to routine

; Routines of TabOps:
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: AF, DE, PUSH1, PUSH2, R1, R0
; STACK: 8

; ----- only checking syntax, not calculating expression
; ZX80: L0A6F

ScanSynTest:
	; compare operands, if are the same type
	mov	A,E		; get last operation code
	cpi	A,10		; check operation code - sets carry if numeric
	ror	A		; carry to bit 7
	lsr	A		; carry to bit 6
	in	r0,_SFR_IO_ADDR(GPIOR0) ; get flags
	eor	A,r0		; XOR flags
	andi	A,B6		; isolate bit 6
	breq	2f		; operands are the same type

	; error, incorrect operand type
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rcall	InsErr		; insert error
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers

	; get last value from the stack
2:	POP_HL

; ----- return from arithmetic function
; ZX80: L0A7F

ScanInsVal:
	; store result
; INPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rcall	SaveResult	; save last result DATA_RESULT from HL
	SET_NUMRES		; set numeric result
	rjmp	ScanLoop3	; process next operand

; ----- current priority is higher - go deeper
; ZX80: L0A88

ScanTighter:
	; push lower priority
	PUSH_DE			; push lower priority

	; skip if numeric result
	mov	A,C		; get operator
	IF_NUMRES		; if numeric result
	rjmp	ScanNext	; skip if numeric

	; text result - prepare operators
	subi	A,-3		; shift operator
	mov	C,A

	cpi	A,10		; check operator
	brcc	ScanNext	; operator is OK

	; error, incorrect text operand type
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rcall	InsErr		; insert error
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers

; ----- push result and go to deeper scanning

ScanNext:
; OUTPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rcall	LoadResult	; load result DATA_RESULT to HL
	PUSH_HL			; push result
	PUSH_BC			; push priority and operator
	
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX		; exchange registers
	rjmp	ScanLoop2	; continue scanning

; ----------------------------------------------------------------------------
;                        Table of priorities
; ----------------------------------------------------------------------------
; ZX80: L0AA3

.global PriorTab
PriorTab:
	.byte	6	; 0 '-'
	.byte	6	; 1 '+'
	.byte	8	; 2 '*'
	.byte	7	; 3 '/'
	.byte	3	; 4 AND
	.byte	2	; 5 OR
	.byte	10	; 6 ** power
	.byte	5	; 7 =
	.byte	5	; 8 >
	.byte	5	; 9 <

	.balign	2	; align to 2 bytes

; ----------------------------------------------------------------------------
;                           Look variable
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to name of the variable
; ----------------------------------------------------------------------------
; ZX80: L0AAD

.global LookVars
LookVars:
	; save pointer to first letter of name of the variable
	PUSH_HL

	; presume numeric result
	SET_NUMRES

	; load second character of the name
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAdd			; get next character

	; check string variable
	cpi	A,CH_DOLLAR		; check '$' character
	brne	1f
	rjmp	LVString		; string variable

	; check array
1:	cpi	A,TOKEN_LPAR		; check '(' token
	brne	2f
	rjmp	LVArray			; array variable

; here stay integer and functions

	; check alphanumeric character (to find end of name)
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
2:	rcall	AlphaNum
	brcc	3f			; not alphanumeric

	; get next character
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAdd			; get next character
	rjmp	2b			; check next character

	; check numeric function
3:	cpi	A,TOKEN_LPAR		; check '(' token
	breq	4f			; check function

	; check string type
	cpi	A,CH_DOLLAR		; check '$' character
	breq	5f
	rjmp	LVSyn			; not function

	; check string function
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
5:	rcall	CharAdd			; get next character
	cpi	A,TOKEN_LPAR		; check '(' token
	breq	4f
	rjmp	LVFuncErr		; not function

	; search function table
4:	ldi	E,lo8(TabFunc-1)	; integer function table
	ldi	D,hi8(TabFunc-1)

; ZX80: L0AD9
LVFuncLoop:
	; restore pointer to start of function name
	POP_HL
	PUSH_HL

	; load character and shift to next character
6:	ld	C,MHL			; load character
; INPUT: HL = current address of the text
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAddLP		; shift pointer

	; load character from the table
	adiw	DE,1			; shift pointer
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL			; exchange pointers
	lpm	A,MHL			; load character
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL			; exchange pointers

	; compare characters
	cp	A,C			; compare characters
	breq	6b			; characters are OK

	; compare last character, without flag bits
	andi	A,0x3f			; clear flag bits
	cp	A,C			; compare again
	brne	7f			; not equal, go to next function

	; last character is OK, check if next character is token '('
	ld	C,MHL			; load next character
	cpi	C,TOKEN_LPAR		; check token '('
	breq	FuncMatch		; function name found OK

; find next function in table

	; load next character and check end of table
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
7:	rcall	EXDEHL			; exchange pointers
	lpm	A,MHL+			; load character
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL			; exchange pointers

	; check end of table
	tst	A			; end of table?
	breq	LVFuncErr		; end of table

	; check end of token
	lsl	A			; shift left, check bit 7
	brcc	7b			; search end of token

	adiw	DE,1			; skip 1st byte of the address
	rjmp	LVFuncLoop		; try next function

; function match
; ZX80: L0AF9
FuncMatch:
	; evaluate bracket expression
	PUSH_DE				; save pointer to the table
	rcall	Bracket			; evaluate bracket expression
	POP_DE				; restore pointer to the table

	; discard text pointer and push result to stack
	pop	r0
	pop	r0			; discard pointer
	PUSH_HL				; push result to stack

	; check type of function argument
	in	F,_SFR_IO_ADDR(GPIOR0)	; load flags
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL			; exchange pointers
	lpm	A,MHL+			; load last character with flags
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL			; exchange pointers
	eor	F,A			; XOR flags
	andi	F,B6			; check result type
	brne	LVFuncErr		; incompatible argument type

	; detect result type
	SET_NUMRES			; set numeric result
	andi	A,0x3f			; clear indicator bits
	cpi	A,CH_DOLLAR		; string function?
	brne	2f			; not string function
	SET_STRRES			; set string result

	; return if only checking syntax
2:	POP_HL				; restore result of expression in brackets
	IF_SYNTON			; if checking syntax
	ret				; return if only checking syntax

	; prepare return address from function
	ldi	L,lo8(InsRslt)		; return to insert result routine
	ldi	H,hi8(InsRslt)
	lsr	H			; convert to word index
	ror	L
	PUSH_HL				; push return address

	; load function address
	movw	HL,DE			; HL <- pointer into table
	lpm	E,MHL+			; load address
	lpm	D,MHL
	lsr	D			; convert to word index
	ror	E
	PUSH_DE				; push routine address

	; load result argument and jump to function
; OUTPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rjmp	LoadResult		; load result DATA_RESULT to HL
					; and jump to function, returns to InsRslt routine

; ----- function error
; ZX80: L0B27

LVFuncErr:
	POP_HL				; restore pointer to program line
; INPUT: HL = program pointer
; DESTROYS: A, R0
; STACK: 2
	rjmp	InsErr

; ----- array
; ZX80: L0B2B

LVArray:
	rcall	Bracket			; evaluate bracket expression
	rjmp	LVSyn

; ----- string variable
; ZX80: L0B30

LVString:
	SET_STRRES	; set string result
; OUTPUT: A = character (from next address, skips cursor)
;	  HL = new current address of the text
; DESTROYS: -
; STACK: 2
	rcall	CharAdd	; load next character

; ----- process variable
; ZX80: L0B35

LVSyn:
	POP_HL				; restore pointer to program line
	IF_SYNTON	; if check syntax is on
	ret		; return if syntax is on

; LVFind must follow

; ----------------------------------------------------------------------------
;                  Find variable and load its value
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to first letter of name of variable
; ----------------------------------------------------------------------------
; ZX80: L0B3B

.global LVFind
LVFind:
	; load 2 first characters of name of variable
	ld	C,MHL+		; load 1st character -> C
	ld	A,MHL		; load 2nd character -> A

	; save pointer to name of variable + 1
	PUSH_HL

	; check if 2nd character is '(' = array
	cpi	A,TOKEN_LPAR	; check token '('
	brne	2f		; simple numeric variables

; ----- array

	; save BC
	PUSH_BC

	; save current text address
	ldd	C,Y+DATA_CHARPTR
	ldd	B,Y+DATA_CHARPTR+1
	PUSH_BC

	; evaluate expression (index of array entry)
; INPUT: HL = pointer to text
	rcall	EvalExp

	; restore original text address
	POP_HL
	std	Y+DATA_CHARPTR+1,H
	std	Y+DATA_CHARPTR,L

	; restore BC
	POP_BC

	; check error
	IF_NOERROR		; if no error
	rjmp	VRun		; no error

	; set subscript error
	ldi	L,ERR_SUBSCRIPT ; subscript error
	rcall	ErrorSet	; set error

	; error, restore pointer to name of variable nad return
	POP_HL			; return pointer
	ret

; ----- encode simple variable

	; check string variable
2:	cbr	C,B5		; reset bit 5, presume string type
	cpi	A,CH_DOLLAR	; is 2nd character '$' ?
	breq	VRun		; string variable

	; presume long-named numeric
	sbr	C,B6		; set bit 6, presume long-named numeric

	; check alphanumeric second character
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
	rcall	AlphaNum
	brcs	VRun		; invalid character
	sbr	C,B5		; else mark as simple numeric or for/next variable

; ----- search variable
; ZX80: L0B6B

VRun:
	; point HL to first variable from VARS
	ldd	L,Y+DATA_VARSPTR
	ldd	H,Y+DATA_VARSPTR+1

; ZX80: L0B6E
VEach:
	; get first byte of variable
	ld	A,MHL
	andi	A,0x7f		; reset bit 7 to allow simple numeric variable to march against loop variable
	brne	2f

	; end-mark 0x80, error - variable not found
	rjmp	VarNotFound

	; compare to first letter
2:	cp	A,C
	brne	VNext		; not equal, go to next variable

	; check bits 5 and 6
	add	A,A
	add	A,A
	brmi	StkVar		; bit 5 is set - single letter numeric variable or loop or array
	brcc	StrRslt		; bit 5 is clear and bit 6 is clear - string

; ----- long-named variable 010...

	POP_DE			; DE <- restore pointer to variable name in program line
	PUSH_DE
	PUSH_HL			; save pointer to variable

	; compare long-named variable name
4:	adiw	HL,1		; shift pointer of variable
	ld	A,MDE+		; character from program line
	ld	F,MHL		; character from variable
	cp	A,F		; compare character
	breq	4b		; equal, check another character

	; compare with cleared flag bits
	ori	A,B7		; set bit 7
	cp	A,F		; compare last character
	brne	VGetPtr		; names are not equal

	; check end of variable name
	ld	A,MDE		; get character from program line
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
	rcall	AlphaNum	; check alphanumeric character
	brcc	VFound		; invalid charactr - name is OK, variable has been found

; ----- incorrect variable, check next variable
; ZX80: L0B92

VGetPtr:
	; restore pinter to variable
	POP_HL			; restore pointer to variable

; ----- next variable
; ZX80: L0B93

VNext:
	; save BC with 1st character
	PUSH_BC

	; shift to next variable
; INPUT: HL = pointer to current entry (current variable or program line)
; OUTPUT: DE = next entry (next variable or program line)
;	  BC = length of entry (length of variable or program line)
; DESTROYS: A, R1, R0
; STACK: 4
	rcall	NextOne
	movw	HL,DE		; HL <- next entry
	POP_BC
	rjmp	VEach		; check another variable

; ----- variable has been found
; ZX80: L0B9B

VFound:
	; drop pointer to variables
	POP_DE

; ZX80: L0B9C
VFound2:
	; drop pointer to name of the variable
	POP_DE

; ZX80: L0B9D
VFound3:
	; load value of the variable
	adiw	HL,1		; shift pointer
	ld	E,MHL+		; load LOW byte of value
	ld	D,MHL		; load HIGH byte of value
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; DE <- pointer, HL <- value
	rjmp	InsRslt

; ----- simple variable, array of loop
; ZX80: L0BA4

StkVar:
	brcs	VFound2		; bit 5 is set and bit 6 is set - short named variable and loop, variable found OK

; ----- array

	; discard pointer to program line
	pop	r0
	pop	r0

	; pointer to variable -> DE
	movw	DE,HL

	; check index size
; OUTPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rcall	LoadResult	; load result DATA_RESULT to HL (= index of array entry)
	tst	H		; check high byte
	brne	SubsError	; entry index is > 255, subscript error

	; check array size
	adiw	DE,1		; shift pointer to array dimension
	ld	A,MDE		; get array size
	cp	A,L		; compare index
	brcs	SubsError	; subscript error

	; prepare entry address
	add	L,L		; entry index * 2
	adc	H,H
	add	L,E		; add address of the variable
	adc	H,D
	rjmp	VFound3		; load value of the entry

; ----- string
; ZX80: L0BB8

StrRslt:
	POP_DE			; drop pointer to variable
	adiw	HL,1		; shift pointer to text of the string

; ----- store result
; ZX80: L0BBA

.global InsRslt
InsRslt:
; INPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rjmp	SaveResult	; save last result DATA_RESULT from HL

; ----------------------------------------------------------------------------
;                            Subscript error
; ----------------------------------------------------------------------------
; DESTROYS: L (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0BBE

.global SubsError
SubsError:
	ldi	L,ERR_SUBSCRIPT
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error		; error

; ----------------------------------------------------------------------------
;                      Integral functions table
; ----------------------------------------------------------------------------
; ZX80: L0BC0
;   bit 7: 1=end of function name
;   bit 6: 1=numeric argument, 0=string argument

.global TabFunc
TabFunc:
	.byte	CH_P,CH_E,CH_E,CH_K 		+ 0xC0	; PEEK
; INPUT: HL = pointer to address (string or memory)
; OUTPUT: HL = number
; DESTROYS: -
; STACK: 2
	.word	Peek

	.byte	CH_C,CH_H,CH_R,CH_DOLLAR	+ 0xC0	; CHR$
; INPUT: HL = character code
; OUTPUT: HL = pointer to string
; DESTROYS: AF, BC, DE, PUSH2, PUSH1, R1, R0
; STACK: 8
	.word	Chr

	.byte	CH_C,CH_O,CH_D,CH_E		+ 0x80	; CODE
; INPUT: HL = pointer to address (string or memory)
; OUTPUT: HL = number
; DESTROYS: -
; STACK: 2
	.word	Code

	.byte	CH_R,CH_N,CH_D			+ 0xC0	; RND
; INPUT: HL = range, max. value (number 1..HL will be generated)
; OUTPUT: HL = random number in range 1..HL
; DESTROYS: BC, DE, PUSH1, PUSH2, R1, R0
; STACK: 4
	.word	Rnd

	.byte	CH_T,CH_L,CH_DOLLAR		+ 0x80	; TL$
; INPUT: HL = pointer to string
; OUTPUT: HL = pointer to string + 1 (string tail, without 1st character)
; DESTROYS: -
; STACK: 2
	.word	StrTl

	.byte	CH_U,CH_S,CH_R			+ 0xC0	; USR (not supported on AVR)
	.word	Usr

	.byte	CH_S,CH_T,CH_R,CH_DOLLAR	+ 0xC0	; STR$
; INPUT: HL = integer number
; OUTPUT: HL = pointer to string (at edit line + 1)
; DESTROYS: A, BC, DE, BC', DE', HL', PUSH1, PUSH2, PUSH3, R1, R0
; STACK: 8
	.word	Str

	.byte	CH_A,CH_B,CH_S			+ 0xC0	; ABS
; INPUT: HL = number
;	 A = sign accumulator
; OUTPUT: HL = absolute value of number
;	  A will be incremented if number was negative
; DESTROYS: -
; STACK: 2
	.word	NumAbs

	.byte	0					; end-marker

	.balign	2	; align to 2 bytes

; ----------------------------------------------------------------------------
;                   RND function - random number generator
; ----------------------------------------------------------------------------
; INPUT: HL = range, max. value (number 1..HL will be generated)
; OUTPUT: HL = random number in range 1..HL
; DESTROYS: BC, DE, PUSH1, PUSH2, R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0BED

.global Rnd
Rnd:
	; save required range
	movw	PUSH2,HL

	; get seed -> HL
	ldd	L,Y+DATA_SEED
	ldd	H,Y+DATA_SEED+1

	; multiplier 77 -> DE
	ldi	E,lo8(77)
	ldi	D,hi8(77)

	; zero seed is not allowed
	adiw	HL,0		; check zero seed
	breq	2f		; zero seed is not allowed

	; multiply seed by value 77
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: BC:HL = result
;	 NZ = overflow, ZY = result is OK
;	 NC carry is cleared
; DESTROYS: PUSH1, R1, R0
; STACK: 2
	rcall	Mul16		; multiply

	; subtract overflow HL - BC -> HL
	sub	L,C
	sbc	H,B
	brcc	3f		; continue if no carry

	adiw	HL,1		; increment if carry
	rjmp	3f

	; substitute zero seed with value -77 (0xFFB3)
2:	ldi	L,lo8(-77)
	ldi	H,hi8(-77)

	; save new SEED
3:	std	Y+DATA_SEED,L
	std	Y+DATA_SEED+1,H

	; restore required range -> DE
	movw	DE,PUSH2

	; multiply seed by range
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: BC:HL = result
;	 NZ = overflow, ZY = result is OK
;	 NC carry is cleared
; DESTROYS: PUSH1, R1, R0
; STACK: 2
	rcall	Mul16		; multiply

	; get result
	movw	HL,BC		; result value
	adiw	HL,1		; increment to ensure range 1..Z
	ret

; ----------------------------------------------------------------------------
;                   CODE and PEEK functions
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to address (string or memory)
; OUTPUT: HL = number
; DESTROYS: F
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0C24

.global Peek
Peek:
	; access to ROM font (original address 0x0E00..0x0FFF)
	ldi	F,hi8(0x0E00)
	cpi	L,lo8(0x0E00)
	cpc	H,F
	brcs	3f

	ldi	F,hi8(0x1000)
	cpi	L,lo8(0x1000)
	cpc	H,F
	brcc	3f

	; Original ZX80 font is organised to 1 column of characters:
	;	B0..B2 = letter line 0..7
	;	B3..B8 = letter index 0..63
	; ATX80 font is organised by lines:
	;	B0..B5 = letter index 0..63
	;	B6..B8 = letter line 0..7
	subi	L,lo8(0x0E00)		; get byte offset -> HL (0x0000..0x01FF)
	sbci	H,hi8(0x0E00)
	mov	F,L

	lsr	H			; shift leter index to B2 base
	ror	L
	lsr	L			; shift leter index to B1 base
	lsr	L			; shift leter index to B0 base

	andi	F,0x07			; mask letter line 0..7
	swap	F			; shift lette line to B4 base
	lsl	F			; shift letter line to B5 base
	lsl	F			; shift letter line to B6 base
	adc	H,H			; shift B8 to H
	or	L,F			; compose new offset

	; get font byte
	subi	L,lo8(-(Font))		; add Font offset
	sbci	H,hi8(-(Font))
	lpm	L,MHL			; load font byte
	rjmp	8f

	; conversion from ZX80 address to ATX80 address
3:	subi	L,lo8(-ZX80_SHIFT)
	sbci	H,hi8(-ZX80_SHIFT)

	; check if pointers are accessed
	ldi	F,hi8(PtrBeg)		; check start of pointers
	cpi	L,lo8(PtrBeg)
	cpc	H,F
	brcs	Code			; not pointers

	ldi	F,hi8(PtrEnd)		; check end of pointers
	cpi	L,lo8(PtrEnd)
	cpc	H,F
	brcc	Code			; not pointers

	; check odd address
	mov	F,L			; address LOW
	subi	F,lo8(PtrBeg)		; address offset
	lsr	F			; check bit 0
	brcs	2f			; odd address

	; load parameter and correct LOW part of the address
	rcall	Code			; load L from (HL)
	subi	L,lo8(ZX80_SHIFT)	; pointer LOW correction
	ret

	; load full address
2:	sbiw	HL,1			; shift address down
	ld	F,MHL			; load pointer LOW
	ldd	H,MHL+1			; load pointer HIGH
	subi	F,lo8(ZX80_SHIFT)	; pointer full correction
	sbci	H,hi8(ZX80_SHIFT)

	; return parameter
	mov	L,H
	rjmp	8f

.global Code
Code:
	; load parameter (1st character of string or byte from address)
	ld	L,MHL
8:	ldi	H,0
	ret

; ----------------------------------------------------------------------------
;        STR$ function - convert number to string (at edit line + 1)
; ----------------------------------------------------------------------------
; INPUT: HL = integer number
; OUTPUT: HL = pointer to string (at edit line + 1)
; DESTROYS: A, BC, DE, BC', DE', HL', PUSH1, PUSH2, PUSH3, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L0C10

.global Str
Str:
	; exchange alternative registers
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX

	; reserve 7 character space (max. number is "-32768" + 0x01)
	ldi	C,7
	ldi	B,0
; INPUT: BC = required free space
; OUTPUT: DE = address of start of new free space in edit line + 1 (after old NEWLINE)
;	  HL = address after free space (pointer to new NEWLINE or end-mark 0x80)
;	  NC = memory error
; DESTROYS: PUSH2, PUSH1, R1, R0
; STACK: 6
	rcall	Reserve		; reserve free space in edit line
; OUTPUT: HL = pointer to empty string
; DESTROYS: - (saves flags)
; STACK: 2
	brcc	NulStr		; memory error, return nul string

	; save start of new space + 1
	movw	PUSH3,DE	; save pointer

	; exchange alternative registers
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX

	; print number to edit line
	movw	BC,HL		; BC <- number to print
; INPUT: BC = number to print
;	 B' = remaining rows
;	 C' = remaining columns
;	 DE' = address in RAM
; OUTPUT: NC = memory error or display overflow
;	  B', C', DE' = updated
; DESTROYS: A, BC, HL', PUSH1, PUSH2, R1, R0
; STACK: 6
	rcall	PrintNum	; print number into X buffer

	; exchange alternative registers (saves flags)
; OPERATION: BC <-> BC', DE <-> DE', HL <-> HL'
; INPUT/OUTPUT: HL,DE,BC,HL',DE',BC' registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXX

	; save terminating " (saves flags)
	ldi	A,CH_QUOT	; end-mark "
	st	MDE,A		; save end-mark

	; restore pointer to start of string (saves flags)
	movw	HL,PUSH3
	ret

; ZX80: L0C22
CmdLetRet:
	POP_HL			; restore pointer
	ret

; ----------------------------------------------------------------------------
;       CHR$ function - convert character code to 1-character string
; ----------------------------------------------------------------------------
; INPUT: HL = character code
; OUTPUT: HL = pointer to string
; DESTROYS: AF, BC, DE, PUSH2, PUSH1, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L0C28

.global Chr
Chr:
	; reserve 2 character space
	ldi	C,2
	ldi	B,0

	; required character
	mov	A,L

	; reserve space for 1 character
; INPUT: BC = required free space
; OUTPUT: DE = address of start of new free space in edit line + 1 (after old NEWLINE)
;	  HL = address after free space (pointer to new NEWLINE or end-mark 0x80)
;	  NC = memory error
; DESTROYS: PUSH2, PUSH1, R1, R0
; STACK: 6
	rcall	Reserve		; reserve free space in edit line
; OUTPUT: HL = pointer to empty string
; DESTROYS: - (saves flags)
; STACK: 2
	brcc	NulStr		; memory error

	; store string
	ldi	F,CH_QUOT	; terminator "
	st	MHL,F		; store end-mark "
	st	-MHL,A		; store character
	ret

; ----------------------------------------------------------------------------
;                   Returns pointer to empty string
; ----------------------------------------------------------------------------
; OUTPUT: HL = pointer to empty string
; DESTROYS: - (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0C34

.global NulStr
NulStr:
	; pointer to empty string (contains character CH_QUOT)
	ldi	L,lo8(NulString)
	ldi	H,hi8(NulString)
	ret

; ----------------------------------------------------------------------------
;        TL$ function - returns tail of string, without 1st character
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to string
; OUTPUT: HL = pointer to string + 1 (string tail, without 1st character)
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0C38

.global StrTl
StrTl:
	ld	A,MHL		; load 1st character
	cpi	A,CH_QUOT	; empty string?
	breq	2f		; empty string
	adiw	HL,1		; shift to next character
2:	ret

; ----------------------------------------------------------------------------
;                           LET command
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to program line
;	 BC = last result
;	 Z = ZY if result is 0
; ----------------------------------------------------------------------------
; ZX80: L0C3D

.global CmdLet
CmdLet:
	; return if error has been encountered
	IF_ERROR
	ret

	; save start value
	PUSH_BC

	; get pointer to name of the variable -> HL
; OUTPUT: HL = address of variable name DATA_VARDEST
; DESTROYS: -
; STACK: 2
	rcall	LoadVarDest	; load DATA_VARDEST -> HL

	; find variable
	rcall	LVFind		; find variable

	; return on subrscript errror
	ldd	A,Y+DATA_ERRCODE
	cpi	A,ERR_SUBSCRIPT	; subscript error?
	breq	CmdLetRet	; return on subscript error

; continue with variable not found or OK

	; no error - variable has been found OK
	IF_NOERROR		; no error?
	rjmp	LExists		; variable already exists

	; variable not found, clear the error
	std	Y+DATA_ERRCODE,ZERO ; clear error code
	CLR_ERROR		; clear error flag
	
	; check string variable
	IF_STRRES		; if string result
	rjmp	LString		; go to string result

	; continue with numeric variable
; OUTPUT: HL = address of variable name DATA_VARDEST
; DESTROYS: -
; STACK: 2
	rcall	LoadVarDest	; load DATA_VARDEST -> HL
	ldi	C,2		; minimal space = 3
	ldi	B,0

	; search end of variable name
2:	adiw	BC,1		; increment character count
	adiw	HL,1		; increment character pointer
	ld	A,MHL		; load character
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
	rcall	AlphaNum	; check alphanumeric
	brcs	2b		; search end of name

	; check array '('
	cpi	A,TOKEN_LPAR	; check '('
	brne	3f
	rjmp	VarNotFound	; error, array not declared yet

	; create free space for the variable
; INPUT: BC = required free space
; OUTPUT: DE = address of start of new free space in edit line + 1 (after old NEWLINE)
;	  HL = address after free space (pointer to new NEWLINE or end-mark 0x80)
;	  NC = memory error
; DESTROYS: PUSH2, PUSH1, R1, R0
; STACK: 6
3:	rcall	Reserve
	brcc	CmdLetRet	; memory error

	; prepare pointers to start of name of variable
	PUSH_DE			; save first new location + 1
; OUTPUT: HL = address of variable name DATA_VARDEST
; DESTROYS: -
; STACK: 2
	rcall	LoadVarDest	; load DATA_VARDEST -> HL
	sbiw	DE,1		; shift pointer to start of free space

	; prepare simple numeric type
	ldi	A,0x40		; prepare mask 010... (bit 5 is inverted, result will be 011...)
	sbiw	BC,3		; reduce count by 3 bytes (ZY = simple numeric)
	breq	2f		; simple numeric

	; copy name of the variable, without last character
; OPERATION: (HL) -> (DE), DE++, HL++, BC--, repeat while BC != 0
; INPUT: HL = pointer to first byte of source address
;	 DE = pointer to first byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer after last byte of source address
;	  DE = pointer after last byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	LDIR

	; copy last character, it will have bit 7 set = flag of end of name
	ld	A,MHL		; get last character
	ori	A,B7		; set bit 7 (end mark)
	st	MDE,A		; store last character

	; prepare long numeric type
	ldi	A,0x60		; prepare mask 011... (bit 5 is inverted, result will be 010...)

; integer variable
2:	POP_HL			; restore pointer to start of free space + 1

; INPUT: A = flags with inverted bit 5
;	 HL = pointer to destination variable + 1
; DESTROYS: AF, HL, DE, BC, PUSH1, R1, R0
; STACK: 8
	rcall	LMask		; insert masked letter

; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE HL
	sbiw	DE,1

; store content
; ZX80: L0C8D

LNumeric:
	POP_HL			; restore variable value
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE HL
	st	MHL,D		; store D
	st	-MHL,E		; store E
	ret			; HL points to variable value

; ----- variable already exists
; ZX80: L0C93

LExists:
	IF_NUMRES		; if numeric result
	rjmp	LNumeric	; store numeric result

	; store new string
	POP_HL			; restore string
	rcall	LLength		; store new string

	; prepare pointer to old string variable
; OUTPUT: HL = last result DATA_RESULT
; DESTROYS: -
; STACK: 2
	rcall	LoadResult	; load result DATA_RESULT to HL (get pointer to old string)
	sbiw	HL,1		; point to letter

	; shift to next variable - to get old length
; INPUT: HL = pointer to current entry (current variable or program line)
; OUTPUT: DE = next entry (next variable or program line)
;	  BC = length of entry (length of variable or program line)
; DESTROYS: A, R1, R0
; STACK: 4
	rcall	NextOne		; shift to next variable

; INPUT: HL = current address, start of deleted memory block
;	 BC = number of bytes of deleted memory block
; OUTPUT: DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 4
	rjmp	Reclaim		; delete old variable

; ----- string variable - store new string
; ZX80: L0CA3

LString:
	POP_HL			; restore pointers

; LLength must follow

; ----------------------------------------------------------------------------
;                      Store string variable
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to the string (immediately after first quote ")
; DESTROYS: AF, HL, DE, BC, PUSH1, PUSH2, PUSH3, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; 100xxxxx text 0x01 - text variable, name is letter A..Z (0x26..0x3F), terminated with " character (0x01)
; ZX80: L0CA4

.global LLength
LLength:
	; prepare to find string length	
	ldi	C,1		; length (including quote character and name character)
	ldi	B,0

	; get string length (minimal BC=2)
2:	adiw	BC,1		; increase length
	ld	A,MHL+		; load character
	cpi	A,CH_QUOT	; end of string?
	brne	2b

	; HL now points to end of string (after terminating quote character)
	movw	PUSH3,HL	; save pointer to end of string

	; create space for the string
; INPUT: BC = required free space
; OUTPUT: DE = address of start of new free space in edit line + 1 (after old NEWLINE)
;	  HL = address after free space (pointer to new NEWLINE or end-mark 0x80)
;	  NC = memory error
; DESTROYS: PUSH2, PUSH1, R1, R0
; STACK: 6
	rcall	Reserve		; create space for the string
	movw	DE,HL		; DE <- end of new variable
	movw	HL,PUSH3	; restore pointer to end of string
	brcc	LMaskRet	; memory error

	; copy string (it will overwrite end-mark 0x80, but it will be corrected later)
; OPERATION: (HL) -> (DE), DE--, HL--, BC--, repeat while BC != 0
; INPUT: HL = pointer to last byte of source address
;	 DE = pointer to last byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer before first byte of source address
;	  DE = pointer before first byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	LDDR		; copy string down
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange DE and HL
	adiw	HL,1		; shift to start of string, 2nd byte of the variable
	ldi	A,0xA0		; mask 101xxx, changes latero into 100xxx (bit 5 will be inverted)

; LMask must follow - stores first byte of the variable

; ----------------------------------------------------------------------------
;                        Store first letter of variable
; ----------------------------------------------------------------------------
; INPUT: A = flags with inverted bit 5
;	 HL = pointer to destination variable + 1
; DESTROYS: AF, BC, DE, HL, PUSH1, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L0CB9

.global LMask
LMask:
	; destination variable + 1 -> DE
	movw	DE,HL		; DE <- pointer to variable + 1

	; prepare first byte
; OUTPUT: HL = address of variable name DATA_VARDEST
; DESTROYS: -
; STACK: 2
	rcall	LoadVarDest	; load DATA_VARDEST -> HL
	ld	F,MHL		; load letter (bit 5 of letter is set)
	eor	A,F		; set flags (bit 5 of flags will be inverted)

	; destination variable + 1 -> HL
	movw	HL,DE

; Now HL points to 2nd byte of variable - next byte after single-named name of variable.
; This 1st byte will be deleted and new 1st byte (with name of variable) will be
; stored into place of previous end-mark 0x80.

	; delete 1st byte of the variable (from start of edit line = address after end-mark 0x80)
; INPUT: HL = end of data from edit line to delete .... = destination variable + 1
; OUTPUT: HL = start of edit line
; 	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
	rcall	RecEditTo	; delete 1st byte of variable

	; store first letter of the variable - to the place of previous end-mark 0x80
	sbiw	HL,1		; shift pointer one letter down
	st	MHL,A		; insert masked letter (store 1st byte of the variable)

	; set new address of edit line immediately after new variable
; OUTPUT: HL = address of start of display DATA_DISPPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadDispPtr	; get display start address -> HL
	std	Y+DATA_EDITPTR,L ; it will be new edit line
	std	Y+DATA_EDITPTR+1,H

	; store new end-marker
	sbiw	HL,1		; pointer to last byte of variables
	ldi	F,0x80		; end mark
	st	MHL,F		; mark end of variables
LMaskRet:
	ret

; ----------------------------------------------------------------------------
;                         Error - variable not found
; ----------------------------------------------------------------------------
; DESTROYS: L (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0CD0

.global VarNotFound
VarNotFound:
	POP_HL			; destroy HL pointer in the stack

.global VarNotFound2
VarNotFound2:
	ldi	L,ERR_VARNFND
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error

; ----------------------------------------------------------------------------
;                    DIM command - create integer array
; ----------------------------------------------------------------------------
; INPUT: BC = number of entries (valid range 0..255)
; OUTPUT: HL = number of entries
; DESTROYS: AF, BC, DE, HL, PUSH3, PUSH2, PUSH1, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; 101xxxxx size numL0 numH0 numL1 numH1.. - array of 16-bit integers, size = 1..255, name is letter A..Z (0x26..0x3F)
; ZX80: L0CD3

.global CmdDim
CmdDim:
	; check range, max. 255 entries allowed
	tst	B		; check number of entries HIGH
	breq	2f		; number of entries is OK < 256
	rjmp	SubsError	; subscript error

	; save number of entries
2:	movw	PUSH3,BC

	; prepare memory size
	adiw	BC,2		; +1 to increase size to range 1..256 (including element 0)
				; +1 including name and subscript byte
	add	C,C		; * 2, allocate 2 bytes per integer
	adc	B,B

	; create free space
; INPUT: BC = required free space
; OUTPUT: DE = address of start of new free space in edit line + 1 (after old NEWLINE)
;	  HL = address after free space (pointer to new NEWLINE or end-mark 0x80)
;	  NC = memory error
; DESTROYS: PUSH1, PUSH2, R1, R0
; STACK: 6
	rcall	Reserve		; reserve free space
	brcc	9f		; memory error

	; memory fill with zero values
	sbiw	HL,1		; shift HL pointer to last byte of the free space
	movw	DE,HL		; DE <- pointer to last byte
	sbiw	DE,1		; shift DE pointer (destination) one less than HL (source)
	sbiw	BC,2		; without 2 bytes - HL should stop on 'size' entry
	st	MHL,ZERO	; clear last byte
; OPERATION: (HL) -> (DE), DE--, HL--, BC--, repeat while BC != 0
; INPUT: HL = pointer to last byte of source address
;	 DE = pointer to last byte of destination address
;	 BC = number of bytes (0 means 64K)
; OUTPUT: HL = pointer before first byte of source address
;	  DE = pointer before first byte of destination address
;	  BC = 0
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	LDDR		; block fill locations with zero

	; save number of entries
	movw	BC,PUSH3	; restore number of entries
	st	MHL,C		; save number of entries

	; prepare mask 101xxxxx (with bit 5 inverted)
	ldi	A,0x80		; bit 5 must be inverted
; INPUT: A = flags with inverted bit 5
;	 HL = pointer to destination variable + 1
; DESTROYS: AF, BC, DE, HL, PUSH1, R1, R0
; STACK: 8
	rjmp	LMask		; store first character of name with flags

	; memory error, pop number of entries -> HL
9:	movw	HL,PUSH3
	ret

; ----------------------------------------------------------------------------
;              Reserve free space in end of edit line (working space)
; ----------------------------------------------------------------------------
; INPUT: BC = required free space
; OUTPUT: DE = address of start of new free space in edit line + 1 (after old NEWLINE)
;	  HL = address after free space (pointer to new NEWLINE or end-mark 0x80)
;	  NC = memory error
; DESTROYS: PUSH1, PUSH2, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; Note: If edit line is empty, function is used to reserve space of variables,
;       last byte after free space is end-mark of variables 0x80.
; ZX80: RST 30H, L0030, L0CF3

.global Reserve
Reserve:
	; check free memory
; INPUT: BC = required number of bytes to allocate
; OUTPUT: NC = memory error
;	  DE = new end of data (new display end)
; DESTROYS: HL, R0
; STACK: 2
	rcall	CheckMem		; check free memory
	brcc	9f			; memory error

	; save number of bytes -> PUSH1
	movw	PUSH1,BC

	; save pointer to edit line -> PUSH2 (pointer can be modified by the Pointers function)
; OUTPUT: HL = address of edit line DATA_EDITPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadEditPtr		; load pointer to edit line into HL
	movw	PUSH2,HL

	; prepare end of edit line -> HL
; OUTPUT: HL = address of start of display DATA_DISPPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadDispPtr		; get display start address -> HL (= end of edit line)
	sbiw	HL,1			; shift pointer to last NEWLINE character or end-mark 0x80

	; create free space in end of edit line (before terminating NEWLINE/0x80)
; INPUT: HL = current address (where new data should be inserted)
;	 BC = number of bytes to insert (must be >0)
; OUTPUT: HL = current address - 1
;	  DE = address of start of moved block - 1 (= last byte of new free space)
;	  BC = 0
; DESTROYS: R1, R0
; STACK: 4
	rcall	MakeRoom		; reserve free space
	adiw	HL,2			; restore current address and shift to start of free space + 1

	; restore pointer to edit line
; Note: This pointer can be modified in case when edit line is
;       totally empty (does not contain NEWLINE on its end)
	std	Y+DATA_EDITPTR,PUSH2_L
	std	Y+DATA_EDITPTR+1,PUSH2_H

	; restore number of bytes -> BC
	movw	BC,PUSH1

	; exchange pointers, after end of line (NEWLINE) -> HL, start of free space + 1 -> DE
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange HL and DE
	adiw	HL,1		; shift to end of free space (points to new NEWLINE)
	sec			; set carry = no error
9:	ret

; ----------------------------------------------------------------------------
;                           Reclaim whole edit line
; ----------------------------------------------------------------------------
; OUTPUT: HL = start of edit line
; 	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L0D0A

.global RecEdit
RecEdit:
	; end of edit line -> HL
; OUTPUT: HL = address of start of display DATA_DISPPTR
; DESTROYS: -
; STACK: 2
	rcall	LoadDispPtr		; get display start address -> HL (= end of edit line)

; RecEditTo must follow

; ----------------------------------------------------------------------------
;                  Reclaim edit line up to given address
; ----------------------------------------------------------------------------
; INPUT: HL = end of data from edit line to delete
; OUTPUT: HL = start of edit line
; 	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L0D0D

.global RecEditTo
RecEditTo:
	; start of edit line -> DE
	ldd	E,Y+DATA_EDITPTR	; start of edit line
	ldd	D,Y+DATA_EDITPTR+1

	; reclaim edit line (delete data between X and Z pointers)
; INPUT: DE = current address, start of deleted memory block
;	 HL = end of deleted memory block
; OUTPUT: HL = current address, start of deleted memory block
; 	  DE = new end address of data + 1
;	  BC = 0
; DESTROYS: R1, R0, PUSH1
; STACK: 6
	rjmp	ReclaimDif

; ----------------------------------------------------------------------------
;                      Check alphabetic character 'A'..'Z'
; ----------------------------------------------------------------------------
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0D14

.global Alpha
Alpha:
	cpi	A,CH_A		; check minimal character 'A'
	rjmp	AlphaNum2

; ----------------------------------------------------------------------------
;              Check alphanumeric character '0'..'9' or 'A'..'Z'
; ----------------------------------------------------------------------------
; INPUT: A = character
; OUTPUT: NC = invalid character
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0D18

.global AlphaNum
AlphaNum:
	cpi	A,CH_0		; check minimal character '0'
AlphaNum2:
	brcs	AlphaNum4	; invalid character < '0'
	cpi	A,CH_Z+1	; check maximal character 'Z'
	ret			; CY = character is OK

AlphaNum4:
	clc			; clear carry = error flag
	ret

; ----------------------------------------------------------------------------
;                   Table of arithmetic operators
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: AF, DE, PUSH1, PUSH2, PUSH3, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L0D1F

.global TabOps
TabOps:
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result HL - DE
; DESTROYS: -
; STACK: 2
	.word	NumSub		; 0: 0xDC 220 - Subtraction
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result HL + DE
; DESTROYS: -
; STACK: 2
	.word	NumAdd		; 1: 0xDD 221 + Addition
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: A, DE, PUSH1, PUSH2, R1, R0
; STACK: 8
	.word	NumMul		; 2: 0xDE 222 * Multiplication
; INPUT: HL = 1st number (dividend)
;	 DE = 2nd number (divisor)
; OTPUT: HL = result
; DESTROYS: AF, DE, R1, R0
; STACK: 8
	.word	NumDiv		; 3: 0xDF 223 / Division
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: -
; STACK: 2
	.word	BitAND		; 4: 0xE0 224 AND
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: -
; STACK: 2
	.word	BitOR		; 5: 0xE1 225 OR
; INPUT: HL = 1st number, base
;	 DE = 2nd number, exponent
; OTPUT: HL = result
; DESTROYS: A, DE, PUSH1, PUSH2, PUSH3, R1, R0
; STACK: 4
	.word	NumPwr		; 6: 0xE2 226 ** Power
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = 0xFFFF (true) if HL=DE, 0 (false) if HL<>DE
; DESTROYS: -
; STACK: 2
	.word	NumEqu		; 7: 0xE3 227 = Compare numbers for equality HL=DE
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = 0xFFFF (true) if HL>DE, 0 (false) if HL<=DE
; DESTROYS: DE, R1, R0
; STACK: 4
	.word	NumGrt		; 8: 0xE4 228 > Compare numbers for greater than HL>DE
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = 0xFFFF (true) if HL<DE, 0 (false) if HL>=DE
; DESTROYS: -
; STACK: 2
	.word	NumLes		; 9: 0xE5 229 < Compare numbers for less than HL<DE
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: HL = 0xFFFF (true) if HL=DE, 0 (false) if HL<>DE
; DESTROYS: DE, A, R0
; STACK: 4
	.word	StrEqu		; 10: 0xE3 227 = Compare strings for equality HL=DE
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: HL = 0xFFFF (true) if HL>DE, 0 (false) if HL<=DE
; DESTROYS: DE, A, R0
; STACK: 4
	.word	StrGrt		; 11: 0xE4 228 > Compare strings for greater than HL>DE
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: HL = 0xFFFF (true) if HL<DE, 0 (false) if HL>=DE
; DESTROYS: DE, A, R1, R0
; STACK: 6
	.word	StrLes		; 12: 0xE5 229 < Compare strings for less than HL<DE

; ----------------------------------------------------------------------------
;                                 Subtraction
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result HL - DE
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0D39

.global NumSub
NumSub:
	sub	L,E
	sbc	H,D
	rjmp	NumAdd2		; check overflow

; ----------------------------------------------------------------------------
;                                 Addition
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result HL + DE
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0D3E

.global NumAdd
NumAdd:	add	L,E
	adc	H,D
NumAdd2:
	brvc	Mul168		; no overflow, only return

; Overflow must continue

; ----------------------------------------------------------------------------
;                              Overflow error
; ----------------------------------------------------------------------------
; DESTROYS: L (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0D42

.global Overflow
Overflow:
	ldi	L,ERR_OVERFLOW ; overflow error
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error

; ----------------------------------------------------------------------------
;                             Multiplication
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: A, DE, PUSH1, PUSH2, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L0D44

.global NumMul
NumMul:
	; prepare to multiplication
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: HL = absolute value of 1st number
;	  DE = absolute value of 2nd number
;	  A = count of negative signs 0..2 (0=both positive,.. 2=both negative)
; DESTROYS: R1, R0
; STACK: 6
	rcall	PrepMul		; prepare to multiplication (absolute values)

	; save BC (contains priority/operation)
	movw	PUSH2,BC	; save BC

	; unsigned multiplicaton
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: BC:HL = result
;	 NZ = overflow, ZY = result is OK
;	 NC carry is cleared
; DESTROYS: PUSH1, R1, R0
; STACK: 2
	rcall	Mul16		; multiply

	; restore BC
	movw	BC,PUSH2	; restore BC

	; check overflow
; DESTROYS: L (saves flags)
; STACK: 2
	brne	Overflow	; overflow

	; restore sign
NumMul3:lsr	A		; check sign (bit 0)
	brcc	Mul168		; result is positive, only return
; INPUT: HL = number
; OUTPUT: HL = negative number
;	  CY = set if operand is not 0
;	  ZY = set if operand is 0
; DESTROYS: -
; STACK: 2
	rjmp	NumNeg		; negate result if sign is set

; ----------------------------------------------------------------------------
;                         Unsigned multiplication
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: BC:HL = result
;	 NZ = overflow, ZY = result is OK
;	 NC carry is cleared
; DESTROYS: PUSH1, R1, R0
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0D55

.global Mul16
Mul16:
	; L * E -> PUSH1
	mul	L,E
	movw	PUSH1,r0

	; H * D -> BC
	mul	H,D
	movw	BC,r0

	; L * D -> add to B:C:PUSH1_H
	mul	L,D
	add	PUSH1_H,r0
	adc	C,r1 
	adc	B,ZERO

	; H * E -> add to B:C:PUSH1_H
	mul	H,E
	add	PUSH1_H,r0
	adc	C,r1 
	adc	B,ZERO

	; result LOW -> HL
	movw	HL,PUSH1

	; check overflow -> sets NZ in case of overflow
	add	PUSH1_H,PUSH1_H	; check bit 15 of result
	sbc	r0,r0		; 0xff if carry, 0 if OK
	or	r0,B
	or	r0,C
Mul168:	ret

; ----------------------------------------------------------------------------
;                                 Power
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number, base
;	 DE = 2nd number, exponent
; OTPUT: HL = result
; DESTROYS: A, DE, PUSH3, PUSH2, PUSH1, R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0D70

.global NumPwr
NumPwr:
	; exponent cannot be negative
	sbrc	D,7		; check sign bit, skip if number is positive (skip if bit 7 is clear)
; DESTROYS: L (saves flags)
; STACK: 2
	rjmp	Overflow	; overflow error, exponent cannot be negative

	; absolute value of base Z and prepare result sign -> R23
	clr	A		; clear sign accumulator
; INPUT: HL = number
;	 A = sign accumulator
; OUTPUT: HL = absolute value of number
;	  A will be incremented if number was negative
; DESTROYS: -
; STACK: 2
	rcall	NumAbs		; absolute value and set A sign flag	
	and	A,E		; result will be positive if exponent is even

	; save BC (contains priority/operation)
	movw	PUSH2,BC	; save BC

	; prepare registers
	movw	BC,DE		; exponent -> BC
	movw	DE,HL		; base -> DE
	ldi	L,1		; HL <- result accumulator 1
	ldi	H,0

	; decrement exponent and check underflow
2:	sbiw	BC,1		; decrement exponent
	brmi	4f		; exit and correct sign

	; multiply
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: BC:HL = result
;	 NZ = overflow, ZY = result is OK
;	 NC carry is cleared
; DESTROYS: PUSH1, R1, R0
; STACK: 2
	movw	PUSH3,BC
	rcall	Mul16
	movw	BC,PUSH3
	breq	2b		; next step if no overflow

	movw	BC,PUSH2	; restore BC
; DESTROYS: L (saves flags)
; STACK: 2
	rjmp	Overflow	; overflow error

	; restore BC
4:	movw	BC,PUSH2	; restore BC
	rjmp	NumMul3

; ----------------------------------------------------------------------------
;                                 Division
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number (dividend)
;	 DE = 2nd number (divisor)
; OTPUT: HL = result
; DESTROYS: AF, DE, R1, R0
; STACK: 8
; ----------------------------------------------------------------------------
; ZX80: L0D90

.global NumDiv
NumDiv:
	; check if divisor is 0
	mov	A,D		; divisor HIGH
	or	A,E		; divisor LOW
; DESTROYS: L (saves flags)
; STACK: 2
	breq	Overflow	; overflow (divide by zero)

	; prepare to division
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: HL = absolute value of 1st number
;	  DE = absolute value of 2nd number
;	  A = count of negative signs 0..2 (0=both positive,.. 2=both negative)
; DESTROYS: R1, R0
; STACK: 6
	rcall	PrepMul		; prepare to division (absolute values)

	; save BC (contains priority/operation)
	movw	r0,BC		; save BC

	; prepare operation
	add	L,L		; shift dividend left
	adc	H,H
	ldi	C,0		; clear remainder BC
	ldi	B,0
	ldi	F,16		; number of bits

; At start, here is carry cleared = highest bit from dividend, which in fact was 0

	; shift remainder and add bit from dividend
2:	rol	C		; shift accumulator and add carry from dividen
	rol	B
	
	; try subtract divisor
	sub	C,E
	sbc	B,D
	brcc	4f		; no borrow

	; add divisor back (carry will be set)
	add	C,E
	adc	B,D

	; add carry to accumulator and get next bit from dividend
4:	rol	L		; shift dividend left
	rol	H

	; loop counter
	dec	F		; loop counter
	brne	2b		; next step

	; complement result
	com	L
	com	H

	; restore BC
	movw	BC,r0		; restore BC

	; correct sign
	rjmp	NumMul3		; negate result

; ----------------------------------------------------------------------------
;                                 Bitwise AND
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0DB5

.global BitAND
BitAND:
	and	L,E
	and	H,D
	ret

; ----------------------------------------------------------------------------
;                                 Bitwise OR
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = result
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0DBC

.global BitOR
BitOR:
	or	L,E
	or	H,D
	ret

; ----------------------------------------------------------------------------
;                   Compare numbers for equality HL=DE
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = 0xFFFF (true) if HL=DE, 0 (false) if HL<>DE
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0DC3

.global NumEqu
NumEqu:	
	cp	L,E		; compare numbers
	cpc	H,D
NumEqu2:
; OTPUT: HL = 0 = false
; DESTROYS: -
; STACK: 2
	brne	NumFalse	; set result to false if HL<>DE

; NumTrue must follow

; ----------------------------------------------------------------------------
;                      Set result to -1 (true)
; ----------------------------------------------------------------------------
; OTPUT: HL = -1 = 0xFFFF = true
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global NumTrue
NumTrue:
	ldi	L,0xff
NumTrue2:
	mov	H,L
	ret

; ----------------------------------------------------------------------------
;                 Compare numbers for greater than HL>DE
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = 0xFFFF (true) if HL>DE, 0 (false) if HL<=DE
; DESTROYS: DE, R1, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0DCC

.global NumGrt
NumGrt:	
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange numbers DE and HL

; NumLes must follow

; ----------------------------------------------------------------------------
;                   Compare numbers for less than HL<DE
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OTPUT: HL = 0xFFFF (true) if HL<DE, 0 (false) if HL>=DE
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0DCD

.global NumLes
NumLes:
	cp	L,E		; compare numbers
	cpc	H,D
; OTPUT: HL = -1 = 0xFFFF = true
; DESTROYS: -
; STACK: 2
	brlt	NumTrue		; set result to true if HL<DE

; NumFalse must follow

; ----------------------------------------------------------------------------
;                      Set result to 0 (false)
; ----------------------------------------------------------------------------
; OTPUT: HL = 0 = false
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

.global NumFalse
NumFalse:
	ldi	L,0
	rjmp	NumTrue2

; ----------------------------------------------------------------------------
;                      Compare strings for equality HL=DE
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: HL = 0xFFFF (true) if HL=DE, 0 (false) if HL<>DE
; DESTROYS: DE, A, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0DD9

.global StrEqu
StrEqu:
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: ZY = strings are equal
;	 CY = 1st string (HL) > 2nd string (DE)
; DESTROYS: HL, DE, A, R0
; STACK: 2
	rcall	StrCmp		; string comparison
	rjmp	NumEqu2		; check result

; ----------------------------------------------------------------------------
;                  Compare strings for less than HL<DE
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: HL = 0xFFFF (true) if HL<DE, 0 (false) if HL>=DE
; DESTROYS: DE, A, R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; ZX80: L0DDE

.global StrLes
StrLes:
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
	rcall	EXDEHL		; exchange strings DE and HL

; StrGrt must follow

; ----------------------------------------------------------------------------
;                 Compare strings for greater than HL>DE
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: HL = 0xFFFF (true) if HL>DE, 0 (false) if HL<=DE
; DESTROYS: DE, A, R0
; STACK: 4
; ----------------------------------------------------------------------------
; ZX80: L0DDF

.global StrGrt
StrGrt:
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: ZY = strings are equal
;	 CY = 1st string (HL) > 2nd string (DE)
; DESTROYS: HL, DE, A, R0
; STACK: 2
	rcall	StrCmp		; string comparison
; OTPUT: HL = -1 = 0xFFFF = true
; DESTROYS: -
; STACK: 2
	brcs	NumTrue		; set result to true if HL>DE
; OTPUT: HL = 0 = false
; DESTROYS: -
; STACK: 2
	rjmp	NumFalse	; set result to false if HL<=DE

; ----------------------------------------------------------------------------
;                        String comparison DE cmp HL
; ----------------------------------------------------------------------------
; INPUT: HL = pointer to 1st string (terminated by 0x01 " character)
;	 DE = pointer to 2nd string (terminated by 0x01 " character)
; OTPUT: ZY = strings are equal
;	 CY = 1st string (HL) > 2nd string (DE)
; DESTROYS: HL, DE, A, R0
; STACK: 2
; ----------------------------------------------------------------------------
; ZX80: L0DE4

.global StrCmp
StrCmp:
	; compare one character
	ld	A,MDE+		; load character from 2nd string
	ld	r0,MHL+		; load character from 1st string
	cp	A,r0		; compare characters, "2nd cmp 1nd"
	brne	8f		; string are not equal

	; characters are equal, check end of string
	cpi	A,CH_QUOT	; check terminating character 0x01 "
	brne	StrCmp		; not terminated, check next character
8:	ret

; ----------------------------------------------------------------------------
;                    Prepare to multiply or divide
; ----------------------------------------------------------------------------
; INPUT: HL = 1st number
;	 DE = 2nd number
; OUTPUT: HL = absolute value of 1st number
;	  DE = absolute value of 2nd number
;	  A = count of negative signs 0..2 (0=both positive,.. 2=both negative)
; DESTROYS: R1, R0
; STACK: 6
; ----------------------------------------------------------------------------
; Note: Number -32768 stays unchanged.
; ZX80: L0DED

.global PrepMul
PrepMul:
	clr	A		; clear sign accumulator
	rcall	2f		; exchange numbers and do absolute value
; OPERATION: DE <-> HL
; INPUT/OUTPUT: HL,DE registers
; DESTROYS: R1, R0 (saves flags)
; STACK: 2
2:	rcall	EXDEHL		; exchange numbers

; NumAbs must follow

; ----------------------------------------------------------------------------
;                            Absolute value ABS
; ----------------------------------------------------------------------------
; INPUT: HL = number
;	 A = sign accumulator
; OUTPUT: HL = absolute value of number
;	  A will be incremented if number was negative
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; Note: Number -32768 stays unchanged.
; ZX80: L0DF2

.global NumAbs
NumAbs:
	tst	H		; check if number is negative
	brpl	NumNeg9		; number is not negative
	inc	A		; increment sign accumulator

; NumNeg must follow

; ----------------------------------------------------------------------------
;                           Negate (two's complement)
; ----------------------------------------------------------------------------
; INPUT: HL = number
; OUTPUT: HL = negative number
;	  CY = set if operand is not 0
;	  ZY = set if operand is 0
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------
; Note: Number -32768 stays unchanged.
; ZX80: L0DF6

.global NumNeg
NumNeg:
	com	H		; one's complement of number HIGH
	neg	L		; negate number LOW, sets C if operand was not 0
	sbci	H,0xff		; borrow to HIGH
NumNeg9:ret

; ----------------------------------------------------------------------------
;                                Font
; ----------------------------------------------------------------------------
; Original ZX80 font is arranged as 1 column of 64 charactes.
; Unlike ZX80, font here is not arranged to column, but to one row.

; You can save it (and edit) as portable bitmap PBM 512x8 pixels/1-bit.
; PBM header: 0x50, 0x34, 0x0A, 0x35, 0x31, 0x32, 0x0A, 0x38, 0x0A
; Text form of PBM header: "P4\n512\n8\n"

	.align 6	; align to 64 bytes (must be aligned to 64 bytes!)

; ZX80: L0E00
.global Font
Font:

; line 0
	.byte	0x00, 0x00, 0xf0, 0x00, 0xf0, 0x0f, 0x00, 0x00, 0x0f, 0xaa, 0x00, 0xaa, 0x00, 0x00, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

; line 1
	.byte	0x00, 0x14, 0xf0, 0x00, 0xf0, 0x0f, 0x00, 0x00, 0x0f, 0x55, 0x00, 0x55, 0x1e, 0x08, 0x00, 0x3e
	.byte	0x04, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1c, 0x0c, 0x3e, 0x3e
	.byte	0x0c, 0x7f, 0x3e, 0x7f, 0x3e, 0x3e, 0x3e, 0x7e, 0x1e, 0x7c, 0x7f, 0x7f, 0x1e, 0x41, 0x3e, 0x02
	.byte	0x42, 0x40, 0x41, 0x61, 0x3e, 0x7e, 0x3e, 0x7e, 0x3e, 0x7f, 0x41, 0x41, 0x41, 0x21, 0x41, 0x7f

; line 2
	.byte	0x00, 0x14, 0xf0, 0x00, 0xf0, 0x0f, 0x00, 0x00, 0x0f, 0xaa, 0x00, 0xaa, 0x21, 0x3e, 0x00, 0x41
	.byte	0x08, 0x08, 0x00, 0x08, 0x2a, 0x02, 0x00, 0x10, 0x04, 0x08, 0x00, 0x00, 0x22, 0x14, 0x41, 0x41
	.byte	0x14, 0x40, 0x40, 0x01, 0x41, 0x41, 0x41, 0x41, 0x21, 0x42, 0x40, 0x40, 0x21, 0x41, 0x08, 0x02
	.byte	0x44, 0x40, 0x63, 0x51, 0x41, 0x41, 0x41, 0x41, 0x40, 0x08, 0x41, 0x41, 0x41, 0x12, 0x22, 0x02

; line 3
	.byte	0x00, 0x00, 0xf0, 0x00, 0xf0, 0x0f, 0x00, 0x00, 0x0f, 0x55, 0x00, 0x55, 0x78, 0x48, 0x08, 0x06
	.byte	0x08, 0x08, 0x00, 0x08, 0x1c, 0x04, 0x3e, 0x08, 0x08, 0x00, 0x00, 0x00, 0x41, 0x04, 0x01, 0x06
	.byte	0x24, 0x7e, 0x7e, 0x02, 0x3e, 0x41, 0x41, 0x7e, 0x40, 0x41, 0x7c, 0x7c, 0x40, 0x7f, 0x08, 0x02
	.byte	0x78, 0x40, 0x55, 0x49, 0x41, 0x41, 0x41, 0x41, 0x3e, 0x08, 0x41, 0x41, 0x41, 0x0c, 0x1c, 0x04

; line 4
	.byte	0x00, 0x00, 0xf0, 0xff, 0x00, 0x00, 0xf0, 0x0f, 0xf0, 0xaa, 0xaa, 0x00, 0x20, 0x3e, 0x00, 0x08
	.byte	0x08, 0x08, 0x3e, 0x3e, 0x08, 0x08, 0x00, 0x04, 0x10, 0x00, 0x00, 0x00, 0x41, 0x04, 0x3e, 0x01
	.byte	0x44, 0x01, 0x41, 0x04, 0x41, 0x3f, 0x7f, 0x41, 0x40, 0x41, 0x40, 0x40, 0x47, 0x41, 0x08, 0x42
	.byte	0x44, 0x40, 0x49, 0x45, 0x41, 0x7e, 0x49, 0x7e, 0x01, 0x08, 0x41, 0x22, 0x49, 0x0c, 0x08, 0x08

; line 5
	.byte	0x00, 0x00, 0xf0, 0xff, 0x00, 0x00, 0xf0, 0x0f, 0xf0, 0x55, 0x55, 0x00, 0x20, 0x09, 0x00, 0x00
	.byte	0x08, 0x08, 0x00, 0x08, 0x1c, 0x10, 0x3e, 0x08, 0x08, 0x08, 0x08, 0x0c, 0x22, 0x04, 0x40, 0x41
	.byte	0x7f, 0x41, 0x41, 0x08, 0x41, 0x01, 0x41, 0x41, 0x21, 0x42, 0x40, 0x40, 0x21, 0x41, 0x08, 0x22
	.byte	0x42, 0x40, 0x41, 0x43, 0x41, 0x40, 0x45, 0x44, 0x41, 0x08, 0x41, 0x14, 0x55, 0x12, 0x08, 0x10

; line 6
	.byte	0x00, 0x00, 0xf0, 0xff, 0x00, 0x00, 0xf0, 0x0f, 0xf0, 0xaa, 0xaa, 0x00, 0x7f, 0x3e, 0x08, 0x08
	.byte	0x04, 0x10, 0x00, 0x08, 0x2a, 0x20, 0x00, 0x10, 0x04, 0x08, 0x08, 0x0c, 0x1c, 0x1e, 0x7f, 0x3e
	.byte	0x04, 0x3e, 0x3e, 0x08, 0x3e, 0x3e, 0x41, 0x7e, 0x1e, 0x7c, 0x7f, 0x40, 0x1e, 0x41, 0x3e, 0x1c
	.byte	0x41, 0x7f, 0x41, 0x41, 0x3e, 0x40, 0x3e, 0x42, 0x3e, 0x08, 0x3e, 0x08, 0x22, 0x21, 0x08, 0x7f

; line 7
	.byte	0x00, 0x00, 0xf0, 0xff, 0x00, 0x00, 0xf0, 0x0f, 0xf0, 0x55, 0x55, 0x00, 0x00, 0x08, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
	.byte	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00

	.balign	2	; align to 2 bytes
