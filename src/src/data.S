
; ****************************************************************************
;
;                                 Data
;
; ****************************************************************************

#include "include.inc"

	.data

; Data area pointed by Y register (max. 64 bytes)

.global DataStart
	.lcomm	DataStart,0

; ----- ATX80 sytem variables

; - keyboard
.global KeyShift		; 0: (u8) DATA_KEYSHIFT flag SHIFT is pressed if bit 7 = 0
	.lcomm KeyShift,1

.global KeyScan			; 1: (u8) DATA_KEYSCAN scanned key
	.lcomm KeyScan,1

.global KeyCnt			; 2: (u8) DATA_KEYCNT key press counter
	.lcomm KeyCnt,1

.global KeyPress		; 3: (u8) DATA_KEYPRESS currently pressed key, NOKEY = no key
	.lcomm KeyPress,1

.global KeyBuf			; 4: (u8) DATA_KEYBUF keyboard input buffer, NOKEY = no key
	.lcomm KeyBuf,1

; ----- ZX80 system variables (virtual address 0x4000)

.global DataZX80
	.lcomm DataZX80,0	; 5: begin of ZX80 system variables (ZX80: 0x4000, 16384)

.global	ErrCode
	.lcomm ErrCode,1	; 5: (u8) DATA_ERRCODE error code (ZX80: 16384 $4000 IY+$00 ERR_NR)

.global NulString
	.lcomm NulString,1	; 6: (u8) DATA_NULSTRING empty string - contains single character CH_QUOT (ZX80: 16385 $4001 IY+$01 FLAGS)

.global ExecLine
	.lcomm ExecLine,2	; 7: (u16) DATA_EXECLINE line number of current statement (ZX80: 16386 $4002 IY+$02 PPC)

.global CurPtr
	.lcomm CurPtr,2		; 9: (u16) DATA_CURPTR [K] or [L] cursor address (ZX80: 16388 $4004 IY+$04 P_PTR.)

.global EditLine
	.lcomm EditLine,2	; 11: (u16) DATA_EDITLINE number of current line with [>] cursor (ZX80: 16390 $4006 IY+$06 E_PPC)

; - begin ZX80 pointers (5 pointers)
.global PtrBeg			; start of pointers
	.lcomm PtrBeg,0

.global VarsPtr
	.lcomm VarsPtr,2	; 13: (u16) DATA_VARSPTR pointer to start of variables area (ZX80: 16392 $4008 IY+$08 VARS)
				;	variables follow program code

.global EditPtr
	.lcomm EditPtr,2	; 15: (u16) DATA_EDITPTR pointer to edit line (ZX80: 16394 $400A IY+$0A E_LINE)
				;	edit line follow program variables

.global DispPtr
	.lcomm DispPtr,2	; 17: (u16) DATA_DISPPTR pointer to start of display (ZX80: 16396 $400C IY+$0C D_FILE)
				;	display buffer follow edit line

.global Disp2Ptr
	.lcomm Disp2Ptr,2	; 19: (u16) DATA_DISP2PTR pointer to start of lower screen (ZX80: 16398 $400E IY+$0E DF_EA)

.global DispEnd
	.lcomm DispEnd,2	; 21: (u16) DATA_DISPEND pointer to end of display (ZX80: 16400 $4010 IY+$10 DF_END)

.global PtrEnd			; end of pointers
	.lcomm PtrEnd,0
; - end ZX80 pointers

.global Disp2Lines
	.lcomm Disp2Lines,1	; 23: (u8) DATA_DISP2LINES number of rows in lower screen (ZX80: 16402 $4012 IY+$12 DF_SZ)

.global DispTop
	.lcomm DispTop,2	; 24: (u16) DATA_DISPTOP number of first row on screen (ZX80: 16403 $4013 IY+$13 S_TOP.)

.global ErrPtr
	.lcomm ErrPtr,2		; 26: (u16) DATA_ERRPTR pointer to character preceding [S] marker, 0=no error (ZX80: 16405 $4015 IY+$15 X_PTR)

.global OldLine
	.lcomm OldLine,2	; 28: (u16) DATA_OLDLINE line number to which continue jumps (ZX80: 16407 $4017 IY+$17 OLDPPC)

.global FlagX
	.lcomm FlagX,1		; 30: (u8) DATA_FLAGX extended flags (ZX80: 16409 $4019 IY+$19 FLAGX.)
				;	bit 6: temporary 1=numeric result, 0=string result
				;	bit 7: 1=update K mode, 0=do not update K mode

.global NextTab
	.lcomm NextTab,2	; 31: (u16) DATA_NEXTTAB address of next item in syntax table (ZX80: 16410 $401A IY+$1A T_ADDR)

.global Seed
	.lcomm Seed,2		; 33: (u16) DATA_SEED seed of random generator (ZX80: 16412 $401C IY+$1C SEED)

.global Frames
	.lcomm Frames,2		; 35: (u16) DATA_FRAMES count of frames since start-up (ZX80: 16414 $401E IY+$1E FRAMES)

.global VarDest
	.lcomm VarDest,2	; 37: (u16) DATA_VARDEST address of variable in statement (ZX80: 16416 $4020 IY+$20 DEST)

.global Result
	.lcomm Result,2		; 39: (u16) DATA_RESULT value of last expression (ZX80: 16418 $4022 IY+$22 RESULT.)

.global PrintCols
	.lcomm PrintCols,1	; 41: (u8) DATA_PRINTCOLS remaining free columns to print (ZX80: 16420 $4024 IY+$24 S_POSN_X)

.global PrintRows
	.lcomm PrintRows,1	; 42: (u8) DATA_PRINTROWS remaining free rows to print (ZX80: 16421 $4025 IY+$25 S_POSN_Y)

.global CharPtr
	.lcomm CharPtr,2	; 43: (u16) DATA_CHARPTR address of character to be interpreted (ZX80: 16422 $4026 IY+$26 CH_ADD.)

; ----- allocable memory
; Memory blocks:
; - program code
; - system variables (from DataStart to Memory)
; - program variables (start at Memory)
;     + variables end-marker, byte 0x80
; - edit line, terminated with NEWLINE
; - display buffer, max. 24 rows, every row is terminated with NEWLINE
; - free space (up to StackMin)
; - system stack (minimal bottom at StackMin)

.global Program			; 45: start of program code (ZX80: 16424 $4028 IY+$28)
	.lcomm Program,0	; start of program code = start of allocable memory
