
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

; ===== Display

#define WIDTH	32	// number of characters per row
#define HEIGHT	24	// number of rows

; selected display mode
#define DISP_OLDVGA	-1	// old VGA
#define DISP_VGA	0	// VGA
#define DISP_NTSC	1	// NTSC
#define DISP_PAL	2	// PAL

#define DISP_TV		1	// TV mode (NTSC or PAL)
#define DISP_DEF	DISP_VGA // default display type

; SPI enable/disable (value of SPCR register)
#define SPIEN	(BIT(SPE) | BIT(MSTR) | 0)
#define SPIDIS	(BIT(MSTR) | 0)

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
; SPM_PAGESIZE		64	// size of one SPM flash memory page (64 for ATmega8x, 128 for ATmega328)
#define SLOT_PAGES	(SLOT_SIZE/SPM_PAGESIZE) // number of SPM pages per Flash program slot

#define FREE_RES	26 // memory reserve for CheckFree function (ZX80: 19) (video interrupt requires 12)

; ==== EEPROM

#define PROG_NUM	(EEPROM_SIZE-2)	// number of max. program size

#define CFG_DISP	(EEPROM_END-1) // selected display mode

; ===== Offsets in data area Y

; Data area pointed by Y registers (DataStart, size max. 64 bytes)
; ----- ATX80 system variables
#define DATA_KEYSHIFT	0	// (u8) flag SHIFT is pressed if bit 7 = 0
#define DATA_KEYSCAN	1	// (u8) scanned key
#define DATA_KEYCNT	2	// (u8) key press counter
#define DATA_KEYPRESS	3	// (u8) currently pressed key, NOKEY = no key
#define DATA_KEYBUF	4	// (u8) keyboard input buffer, NOKEY = no key
; ----- ZX80 system variables
#define DATA_ERRCODE	5	// (u8) error code - 1 (ZX80: ERR_NR)
#define DATA_NULSTRING	6	// (u8) empty string - contains single character CH_QUOT
#define DATA_EXECLINE	7	// (u16) line number of current statement (ZX80: PPC)
#define DATA_CURPTR	9	// (u16) [K] or [L] cursor address (ZX80: P_PTR.)
#define DATA_EDITLINE	11	// (u16) number of current line with [>] cursor (ZX80: E_PPC)
; ----- begin pointers (5 pointers)
#define DATA_VARSPTR	13	// (u16) pointer to start of variables area (ZX80: VARS)
#define DATA_EDITPTR	15	// (u16) pointer to edit line (ZX80: E_LINE)
#define DATA_DISPPTR	17	// (u16) pointer to start of display (ZX80: D_FILE)
#define DATA_DISP2PTR	19	// (u16) pointer to start of lower screen (ZX80: DF_EA)
#define DATA_DISPEND	21	// (u16) pointer to end of display (ZX80: DF_END)
; ----- end pointers
#define DATA_DISP2LINES	23	// (u8) number of lines in lower screen (ZX80: DF_SZ)
#define DATA_DISPTOP	24	// (u16) number of first line on screen (ZX80: S_TOP.)
#define DATA_ERRPTR	26	// (u16) pointer to character preceding [S] marker, 0=no error (ZX80: X_PTR)
#define DATA_OLDLINE	28	// (u16) line number to which continue jumps (ZX80: OLDPPC)
#define DATA_FLAGX	30	// (u8) DATA_FLAGX extended flags
				//	bit 6: temporary 1=numeric result, 0=string result
				//	bit 7: 1=update K mode, 0=do not update K mode
#define DATA_NEXTTAB	31	// (u16) address of next item in syntax table (ZX80: T_ADDR)
#define DATA_SEED	33	// (u16) seed of random generator (ZX80: SEED)
#define DATA_FRAMES	35	// (u16) count of frames since start-up (ZX80: FRAMES)
#define DATA_VARDEST	37	// (u16) address of variable in statement (ZX80: DEST)
#define DATA_RESULT	39	// (u16) value of last expression (ZX80: RESULT.)
#define DATA_PRINTCOLS	41	// (u8) remaining free columns to print (ZX80: S_POSN_X)
#define DATA_PRINTROWS	42	// (u8) remaining free rows to print (ZX80: S_POSN_Y)
#define DATA_CHARPTR	43	// (u16) address of character to be interpreted (ZX80: CH_ADD.)

#define ZX80_SHIFT	(DataZX80 - 0x4000) // conversion from ZX80 address to ATX80 address

; ===== Characters
;   Mosaic pixels 1234:
;	1 2
;	3 4

; Base characters
#define CH_SPC		0x00	// space
#define CH_QUOT		0x01	// " (string separator)
#define CH_1010		0x02	// mosaic
#define CH_0011		0x03	// mosaic
#define CH_1000		0x04	// mosaic
#define CH_0100		0x05	// mosaic
#define CH_0010		0x06	// mosaic
#define CH_0001		0x07	// mosaic
#define CH_0110		0x08	// mosaic
#define CH_CHESS	0x09	// chess pattern
#define CH_CHESS1	0x0A	// mosaic
#define CH_CHESS2	0x0B	// mosaic
#define CH_POUND	0x0C	// pound
#define CH_DOLLAR	0x0D	// dollar $
#define CH_COLON	0x0E	// : colon
#define CH_QUERY	0x0F	// ? query
#define CH_LPAR		0x10	// ( left parenthesis
#define CH_RPAR		0x11	// ) right parenthesis
#define CH_MINUS	0x12	// - minus
#define CH_PLUS		0x13	// + plus
#define CH_ASTER	0x14	// * asterisk
#define CH_SLASH	0x15	// / slash
#define CH_EQU		0x16	// = equal
#define CH_GR		0x17	// > greater
#define CH_LT		0x18	// < less
#define CH_SEMI		0x19	// ; semicolon
#define CH_COMMA	0x1A	// , comma
#define CH_DOT		0x1B	// . dot
#define CH_0		0x1C	// 0 (number 0)
#define CH_1		0x1D	// 1 (number 1)
#define CH_2		0x1E	// 2 (number 2)
#define CH_3		0x1F	// 3 (number 3)
#define CH_4		0x20	// 4 (number 4)
#define CH_5		0x21	// 5 (number 5)
#define CH_6		0x22	// 6 (number 6)
#define CH_7		0x23	// 7 (number 7)
#define CH_8		0x24	// 8 (number 8)
#define CH_9		0x25	// 9 (number 9)
#define CH_A		0x26	// A (38)
#define CH_B		0x27	// B (39)
#define CH_C		0x28	// C (40)
#define CH_D		0x29	// D (41)
#define CH_E		0x2A	// E (42)
#define CH_F		0x2B	// F (43)
#define CH_G		0x2C	// G (44)
#define CH_H		0x2D	// H (45)
#define CH_I		0x2E	// I (46)
#define CH_J		0x2F	// J (47)
#define CH_K		0x30	// K (48)
#define CH_L		0x31	// L (49)
#define CH_M		0x32	// M (50)
#define CH_N		0x33	// N (51)
#define CH_O		0x34	// O (52)
#define CH_P		0x35	// P (53)
#define CH_Q		0x36	// Q (54)
#define CH_R		0x37	// R (55)
#define CH_S		0x38	// S (56)
#define CH_T		0x39	// T (57)
#define CH_U		0x3A	// U (58)
#define CH_V		0x3B	// V (59)
#define CH_W		0x3C	// W (60)
#define CH_X		0x3D	// X (61)
#define CH_Y		0x3E	// Y (62)
#define CH_Z		0x3F	// Z (63)

; Keys
#define KEY_UP		0x70	// up
#define KEY_DOWN	0x71	// down
#define KEY_LEFT	0x72	// left
#define KEY_RIGHT	0x73	// right
#define KEY_HOME	0x74	// home
#define KEY_EDIT	0x75	// edit
#define NEWLINE		0x76	// Newline = Z80 HALT instruction
#define KEY_DELETE	0x77	// delete (rubout)

; Tokens
#define TOKEN_QUOT	0xD4 	// 212 "
#define TOKEN_THEN	0xD5	// 213 THEN
#define TOKEN_TO	0xD6	// 214 TO
#define TOKEN_SEMI	0xD7	// 215 ;
#define TOKEN_COMMA	0xD8	// 216 ,
#define TOKEN_RPAR	0xD9	// 217 )
#define TOKEN_LPAR	0xDA	// 218 (
#define TOKEN_NOT	0xDB	// 219 NOT
#define TOKEN_SUB	0xDC	// 220 -
#define TOKEN_ADD	0xDD	// 221 +
#define TOKEN_MUL	0xDE	// 222 *
#define TOKEN_DIV	0xDF	// 223 /
#define TOKEN_AND	0xE0	// 224 AND
#define TOKEN_OR	0xE1	// 225 OR
#define TOKEN_PWR	0xE2	// 226 ** power
#define TOKEN_EQU	0xE3	// 227 =
#define TOKEN_GR	0xE4	// 228 >
#define TOKEN_LT	0xE5	// 229 <
#define TOKEN_LIST	0xE6	// 230 LIST
#define TOKEN_RETURN	0xE7	// 231 RETURN
#define TOKEN_CLS	0xE8	// 232 CLS
#define TOKEN_DIM	0xE9	// 233 DIM
#define TOKEN_SAVE	0xEA	// 234 SAVE
#define TOKEN_FOR	0xEB	// 235 FOR
#define TOKEN_GOTO	0xEC	// 236 GO TO
#define TOKEN_POKE	0xED	// 237 POKE
#define TOKEN_INPUT	0xEE	// 238 INPUT
#define TOKEN_RANDOM	0xEF	// 239 RANDOMISE
#define TOKEN_LET	0xF0	// 240 LET
;0xF1 241 ?
#define TOKEN_FAST	0xF1	// 241 FAST ... ATX80 extension, set fast mode of display
;0xF2 242 ?
#define TOKEN_SLOW	0xF2	// 242 SLOW ... ATX80 extension, set slow mode of display
#define TOKEN_NEXT	0xF3	// 243 NEXT
#define TOKEN_PRINT	0xF4	// 244 PRINT
     ;0xF5 245 ?
#define TOKEN_MEMORY	0xF5	// 245 MEMORY ... ATX80 extension, display memory info
#define TOKEN_NEW	0xF6	// 246 NEW
#define TOKEN_RUN	0xF7	// 247 RUN
#define TOKEN_STOP	0xF8	// 248 STOP
#define TOKEN_CONT	0xF9	// 249 CONTINUE
#define TOKEN_IF	0xFA	// 250 IF
#define TOKEN_GOSUB	0xFB	// 251 GO SUB
#define TOKEN_LOAD	0xFC	// 252 LOAD
#define TOKEN_CLEAR	0xFD	// 253 CLEAR
#define TOKEN_REM	0xFE	// 254 REM
;0xFF 255 ?

#define CH_INV		0x80	// inversion flag

#define NOKEY		0xff	// no key

#define CURSOR		(CH_K + CH_INV) // cursor character, inverted 'K'

; ==== Syntax class

#define CLASS0		0	// no further operands
#define CLASS1		1	// a variable is required
#define CLASS2		2	// an expression, of type integer or string, must follow
#define CLASS3		3	// a numeric expression may follow, otherwise zero will be used
#define CLASS4		4	// a single-character variable must follow
#define CLASS5		5	// variable syntax checked entirely by routine
#define CLASS6		6	// a numeric expression must follow

; ===== Flags in GPIO global register

; alternative General Purpose I/O register
#ifndef GPIOR0
#define GPIOR0	TWBR	// use TWI Bit Rate Registers
#endif

#define F_NOLEAD	0	// 1=no leading space, 0=leading space
#define F_FAST		1	// 1=fast video mode, 0=slow video mode
#define F_KMODE		2	// 1=K mode, 0=L mode
#define F_KCURSOR	3	// 1=K cursor, 0=L cursor
#define F_ERROR		4	// 1=error code is stored in ErrCode
#define F_INPUT		5	// 1=inputting, 0=editing
#define F_NUMRES	6	// 1=numeric result, 0=string result
#define F_SYNTOFF	7	// 1=syntax off, 0=syntax on

; set flag
#define SET_NOLEAD	sbi _SFR_IO_ADDR(GPIOR0),F_NOLEAD	// set 'no leading space' flag
#define SET_FAST	sbi _SFR_IO_ADDR(GPIOR0),F_FAST		// set 'fast video mode' flag
#define SET_KMODE	sbi _SFR_IO_ADDR(GPIOR0),F_KMODE	// set 'K mode' flag
#define SET_KCURSOR	sbi _SFR_IO_ADDR(GPIOR0),F_KCURSOR	// set 'K cursor' flag
#define SET_ERROR	sbi _SFR_IO_ADDR(GPIOR0),F_ERROR	// set 'error' flag
#define SET_INPUT	sbi _SFR_IO_ADDR(GPIOR0),F_INPUT	// set 'inputting' flag
#define SET_NUMRES	sbi _SFR_IO_ADDR(GPIOR0),F_NUMRES	// set 'numeric result' flag
#define SET_SYNTOFF	sbi _SFR_IO_ADDR(GPIOR0),F_SYNTOFF	// set 'syntax off' flag

; clear flag
#define SET_LEAD	cbi _SFR_IO_ADDR(GPIOR0),F_NOLEAD	// set 'leading space' flag
#define SET_SLOW	cbi _SFR_IO_ADDR(GPIOR0),F_FAST		// set 'slow video mode' flag
#define SET_LMODE	cbi _SFR_IO_ADDR(GPIOR0),F_KMODE	// set 'L mode' flag
#define SET_LCURSOR	cbi _SFR_IO_ADDR(GPIOR0),F_KCURSOR	// set 'L cursor' flag
#define CLR_ERROR	cbi _SFR_IO_ADDR(GPIOR0),F_ERROR	// clear 'error' flag
#define SET_EDIT	cbi _SFR_IO_ADDR(GPIOR0),F_INPUT	// set 'editing' flag
#define SET_STRRES	cbi _SFR_IO_ADDR(GPIOR0),F_NUMRES	// set 'string result' flag
#define SET_SYNTON	cbi _SFR_IO_ADDR(GPIOR0),F_SYNTOFF	// set 'syntax on' flag

; IF = execute following instruction if flag is set (skip if clear)
#define IF_NOLEAD	sbic _SFR_IO_ADDR(GPIOR0),F_NOLEAD	// execute if 'no leading space' flag
#define IF_FAST		sbic _SFR_IO_ADDR(GPIOR0),F_FAST	// execute if 'fast vide mode' flag
#define IF_KMODE	sbic _SFR_IO_ADDR(GPIOR0),F_KMODE	// execute if 'K mode' flag
#define IF_KCURSOR	sbic _SFR_IO_ADDR(GPIOR0),F_KCURSOR	// execute if 'K cursor' flag
#define IF_ERROR	sbic _SFR_IO_ADDR(GPIOR0),F_ERROR	// execute if 'error' flag
#define IF_INPUT	sbic _SFR_IO_ADDR(GPIOR0),F_INPUT	// execute if 'inputting' flag
#define IF_NUMRES	sbic _SFR_IO_ADDR(GPIOR0),F_NUMRES	// execute if 'numeric result' flag
#define IF_SYNTOFF	sbic _SFR_IO_ADDR(GPIOR0),F_SYNTOFF	// execute if 'syntax off' flag

; IFN = execute following instruction if flag is not set (skip if is set)
#define IF_LEAD		sbis _SFR_IO_ADDR(GPIOR0),F_NOLEAD	// execute if 'leading space' flag
#define IF_SLOW		sbis _SFR_IO_ADDR(GPIOR0),F_FAST	// execute if 'slow video mode' flag
#define IF_LMODE	sbis _SFR_IO_ADDR(GPIOR0),F_KMODE	// execute if 'L mode' flag
#define IF_LCURSOR	sbis _SFR_IO_ADDR(GPIOR0),F_KCURSOR	// execute if 'L cursor' flag
#define IF_NOERROR	sbis _SFR_IO_ADDR(GPIOR0),F_ERROR	// execute if not 'error' flag
#define IF_EDIT		sbis _SFR_IO_ADDR(GPIOR0),F_INPUT	// execute if 'editing' flag
#define IF_STRRES	sbis _SFR_IO_ADDR(GPIOR0),F_NUMRES	// execute if 'string result' flag
#define IF_SYNTON	sbis _SFR_IO_ADDR(GPIOR0),F_SYNTOFF	// execute if 'syntax on' flag

; ===== Error codes

#define ERR_OK		0	// OK
#define ERR_NEXTFOR	1	// NEXT without FOR
#define ERR_VARNFND	2	// Variable not found
#define ERR_SUBSCRIPT	3	// subscript error (invalid range od DIM)
#define ERR_MEMORY	4	// memory error
#define ERR_SCREEN	5	// screen is full
#define ERR_OVERFLOW	6	// overflow
#define ERR_RETURN	7	// RETURN error, no GOSUB
#define ERR_INPUT	8	// INPUT can only be used in a program
#define ERR_STOP	9	// STOP command
#define ERR_EEPROM	10	// external EEPROM error

; ===== Registers
; R1 and R0 = temporary, result of multiplication, can be destroyed

#define ZERO	R2	// zero register, contains 0
#define DISPMODE R3	// display mode (contains DISP_*)

#define F_	R4	// alternative to Z80 F' register
#define A_	R5	// alternative to Z80 A' register
#define AF_	F_	// alternative to Z80 AF' registers

#define	C_	R6	// alternative to Z80 C' register
#define B_	R7	// alternative to Z80 B' register
#define BC_	C_	// alternative to Z80 BC' registers

#define E_	R8	// alternative to Z80 E' register
#define D_	R9	// alternative to Z80 D' register
#define DE_	E_	// alternative to Z80 DE' registers

#define L_	R10	// alternative to Z80 L' register
#define H_	R11	// alternative to Z80 H' register
#define HL_	L_	// alternative to Z80 HL' registers

#define VADDR	R12	// R13:R12 address of current video row
#define VADDR_L	R12
#define VADDR_H	R13

#define VLINE	R14	// R15:R14 current video line
#define VLINE_L	R14
#define VLINE_H	R15

; following registers R16..R30 can use immediate operands (ANDI, CBR, CPI, LDI, ORI, SBCI, SBR, SUBI)
#define PUSH1	R16	// R17:R16 push double registers 1
#define PUSH1_L	R16
#define PUSH1_H R17

#define PUSH2	R18	// R19:R18 push double registers 2
#define PUSH2_L	R18
#define PUSH2_H R19

#define PUSH3	R20	// R21:R20 push double registers 3
#define PUSH3_L	R20
#define PUSH3_H R21

#define F	R22	// temporary register (it is not used as Z80 flags)
#define A	R23	// alternative to Z80 A register
#define AF	F	// register pair AF

; following registers R24..R31 can use ADIW and SBIW instruction
#define	C	R24	// alternative to Z80 C register
#define B	R25	// alternative to Z80 B register
#define BC	C	// alternative to Z80 BC registers

; register R27:R26 can use LD/ST X, X+, -X, but not displacement (offset)
#define E	R26	// alternative to Z80 E register
#define D	R27	// alternative to Z80 D register
#define DE	E	// alternative to Z80 DE registers
#define MDE	X	// alternative to Z80 memory (DE) registers

; register R31:R30 can use LD/ST Z, Z+, -Z, displacement Z+q, Flash read LPM, ICALL, IJMP
#define L	R30	// alternative to Z80 L register
#define H	R31	// alternative to Z80 H register
#define HL	L	// alternative to Z80 HL registers
#define MHL	Z	// alternative to Z80 memory (HL) registers

; ===== Program control, macros

#define	nop2		rjmp	.+0	; [2] shorter form of "nop nop"

#if ROM_SIZE <= 0x2000 // Flash ROM size is max. 8 KB
#define call	rcall
#define jmp	rjmp
#endif
	
.macro PUSH_AF
	push	F
	push	A
.endm

.macro PUSH_BC
	push	C
	push	B
.endm

.macro PUSH_DE
	push	E
	push	D
.endm

.macro PUSH_HL
	push	L
	push	H
.endm
	
.macro POP_AF
	pop	A
	pop	F
.endm

.macro POP_BC
	pop	B
	pop	C
.endm

.macro POP_DE
	pop	D
	pop	E
.endm

.macro POP_HL
	pop	H
	pop	L
.endm
