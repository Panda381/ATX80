
; ****************************************************************************
;
;                                Render video
;
; ****************************************************************************
; Video timings
; -------------
;				VGA		PAL		NTSC
;   Original timings:
;
; horizontal frequency	[Hz]	31469		15625		15734
; vertical frequency [Hz]	59.94		50		59.94
; pixel clock [MHz]		25.175		13.859		12.162
;
; horizontal total [pixels]	800		887		772
; horizontal visible [pixels]	640		720		640
; horiz. front porch [pixels]	16		23		18
; horizontal sync [pixels]	96		65		57
; horiz. back porch [pixels]	48		79		57
;
; horizontal total [us]		31.77756	64		63.5
; horizontal visible [us]	25.42205	51.95		52.6
; horizontal front porch [us]	0.635551	1.65		1.5
; horizontal sync [us]		3.813307	4.7		4.7
; horizontal back porch [us]	1.906653	5.7		4.7
;
; vertical total [lines]	525		312.5		262.5
; vertical visible [lines]	480		288		243
; vertical front porch [lines]	10		2.5		3
; vertical sync [lines]		2		2.5		3
; vertical back porch [lines]	33		19.5		13.5
;
; horizontal visible [%]	80		81.2		82.8
; vertical visible [%]		91.4		92.2		92.6


;  Timings with quartz 24, resolution 256 x 192:
;
; horizontal frequency	[Hz]	31496		15625		15748
; vertical frequency [Hz]	59.84		50.35		59.96
; SPI divide factor SPIDIV	2		4		4
; pixel clock [MHz]		12		6		6
;                                                                      
; 1 character [cycles]		18		36		36	... = SPIDIV*9
; horizontal total [cycles]	762		1536		1524	... must be even number
; horizontal visible [cycles]	576		1152		1152	... = 32*9*SPIDIV
; horiz. front porch [cycles]	32		87		92
; horizontal sync [cycles]	91		112		112
; horiz. back porch [cycles]	63		185		168
; start visible from start of hsync [cycles] (= horiz. sync + horiz. back porch)
;				154		297		280
;
; horizontal total [us]		31.75		64		63.5
;                                                                      
; vertical total [lines]	525		312		262
; vertical visible [lines]	384		192		192
; vertical front porch [lines]	58		50		28
; vertical sync [lines]		2		3		3
; vertical back porch [lines]	81		67		39
;                                                                      
; horizontal visible [%]	75.6		75		75.6
; vertical visible [%]		73.1		61.5		73.3


#include "include.inc"

	.text

#define VMODEDESC_SIZE 5	// bytes per descriptor

; videomode descriptors (5 bytes per descriptor)
VideoMode_Desc:
	; VGA
	.byte	BIT(SPI2X)	; SPI2X register
	.word	762-1		; HTotal, horizontal total cycles - 1
	.word	91-1		; HSync, horizontal sync cycles - 1

	; NTSC
	.byte	0		; SPI2X register
	.word	1524-1		; HTotal, horizontal total cycles - 1
	.word	112-1		; HSync, horizontal sync cycles - 1

	; PAL
	.byte	0		; SPI2X register
	.word	1536-1		; HTotal, horizontal total cycles - 1
	.word	112-1		; HSync, horizontal sync cycles - 1

	.balign 2

; local registers
#define LINEOFF R22	// line offset of the tile, must be LOW to TILECNT
#define TILECNT R23	// character counter, must be HIGH to LINEOFF
#define TMP	R24	// temporary, must be LOW to TMP2
#define TMP2	R25	// temporary 2, character delay, must be HIGH to TMP
;  R27:R26 (XH:XL) pointer to frame buffer in RAM
;  R29:R28 (YH:YL) pointer to data section
;  R31:R30 (ZH:ZL) pointer to font in ROM, current video line

; Key code table
KeyTab:
	; without SHIFT
	;	ROW1	ROW4	ROW3	ROW2	ROW5	ROW6	ROW7	ROW8
	.byte	0xff,	CH_1,	CH_Q,	CH_A,	CH_0,	CH_P,	NEWLINE, CH_SPC		; COL1
	.byte	CH_Z,	CH_2,	CH_W,	CH_S,	CH_9,	CH_O,	CH_L,	CH_DOT		; COL2
	.byte	CH_X,	CH_3,	CH_E,	CH_D,	CH_8,	CH_I,	CH_K,	CH_M		; COL3
	.byte	CH_C,	CH_4,	CH_R,	CH_F,	CH_7,	CH_U,	CH_J,	CH_N		; COL4
	.byte	CH_V,	CH_5,	CH_T,	CH_G,	CH_6,	CH_Y,	CH_H,	CH_B		; COL5

	; with SHIFT
	;	ROW1		ROW4		ROW3		ROW2		ROW5		ROW6		ROW7		ROW8
	.byte	0xff,		TOKEN_NOT,	CH_1010,	CH_CHESS,	KEY_DELETE,	TOKEN_MUL,	KEY_EDIT,	CH_POUND	; COL1
	.byte	CH_COLON,	TOKEN_AND,	CH_0011,	CH_0110,	KEY_HOME,	TOKEN_RPAR,	TOKEN_EQU,	TOKEN_COMMA	; COL2
	.byte	TOKEN_SEMI,	TOKEN_THEN,	CH_1000,	CH_0010,	KEY_RIGHT,	TOKEN_LPAR,	TOKEN_ADD,	TOKEN_GR	; COL3
	.byte	CH_QUERY,	TOKEN_TO,	CH_0100,	CH_0001,	KEY_UP,		CH_DOLLAR,	TOKEN_SUB,	TOKEN_LT	; COL4
	.byte	TOKEN_DIV,	KEY_LEFT,	CH_CHESS1,	CH_CHESS2,	KEY_DOWN,	CH_QUOT,	TOKEN_PWR,	TOKEN_OR	; COL5

	.balign 2

; ----------------------------------------------------------------------------
;                        Scan keyboard column
; ----------------------------------------------------------------------------
; INPUT: ZL = keyboard column 1..5
; DESTROYS: TMP, ZH, ZL
; ----------------------------------------------------------------------------

ScanCol:
	; load keyboard state
	in	TMP,_SFR_IO_ADDR(PIND)

	; ignore SHIFT key
	dec	ZL		; keyboard column -> 0..4
	brne	2f		; not column 1
	ori	TMP,B7		; mask SHIFT key

	; check if some key is pressed
2:	cpi	TMP,0xff
	breq	9f		; no key

	; convert column (0..4) to key base index
	lsl	ZL
	lsl	ZL
	lsl	ZL		; column * 8

	; find pressed key
	dec	ZL
3:	inc	ZL
	lsl	TMP
	brcs	3b

	; shifted key
	ldd	TMP,Y+DATA_KEYSHIFT ; store key SHIFT state
	andi	TMP,B7		; check SHIFT state
	brne	4f		; SHIFT not pressed
	subi	ZL,-40		; key correction

	; convert to key code
4:	ldi	ZH,0
	subi	ZL,lo8(-(KeyTab))
	sbci	ZH,hi8(-(KeyTab))
	lpm	TMP,Z

	; store key code
	std	Y+DATA_KEYSCAN,TMP

9:	ret

; ----------------------------------------------------------------------------
;          Video rendering continue - render VSYNC and black lines
; ----------------------------------------------------------------------------

; ----- start VSYNC pulse

VRow2:	
	; prepare start of VSYNC
	;  VGA 384+59=443, NTSC 192+29=221, PAL 192+51=243
	ldi	TMP,lo8(443)		; VGA start of VSYNC
	ldi	TMP2,hi8(443)
	tst	DISPMODE		; check display mode
	brmi	2f			; old VGA
	breq	2f			; VGA
	ldi	TMP,lo8(221)		; NTSC start of VSYNC
	ldi	TMP2,hi8(221)
	sbrs	DISPMODE,0		; skip if bit 0 is set = NTSC
	ldi	TMP,lo8(243)		; PAL start of VSYNC

2:	cp	ZL,TMP
	cpc	ZH,TMP2
	brne	VRow3			; not starting VSYNC pulse

	tst	DISPMODE		; check display mode
	brpl	VRow22			; not old VGA

	cbi	_SFR_IO_ADDR(PORTB),2	; set VSYNC output to LOW state
	rjmp	VRow3

VRow22:	ldi	TMP,BIT(COM1A1) | BIT(WGM11)
#ifdef MCU8
	out	_SFR_IO_ADDR(TCCR1A),TMP ; start VSYNC pulse (invert SYNC signal)
#else
	sts	TCCR1A,TMP	; [2] start VSYNC pulse (invert SYNC signal)
#endif

; ----- stop VSYNC pulse

VRow3:
	; prepare end of VSYNC
	;  VGA 384+59+2=445, NTSC 192+29+3=224, PAL 192+51+3=246
	ldi	TMP,lo8(445)		; VGA end of VSYNC
	ldi	TMP2,hi8(445)
	tst	DISPMODE		; check display mode
	brmi	2f			; old VGA
	breq	2f			; VGA
	ldi	TMP,lo8(224)		; NTSC end of VSYNC
	ldi	TMP2,hi8(224)
	sbrs	DISPMODE,0		; skip if bit 0 is set = NTSC
	ldi	TMP,lo8(246)		; PAL end of VSYNC

2:	cp	ZL,TMP
	cpc	ZH,TMP2
	brne	VRow4			; not stopping VSYNC pulse

	tst	DISPMODE		; check display mode
	brpl	VRow32			; not old VGA

	sbi	_SFR_IO_ADDR(PORTB),2	; set VSYNC output to HIGH state
	rjmp	VRow4

VRow32:	ldi	TMP,BIT(COM1A1) | BIT(COM1A0) | BIT(WGM11)
#ifdef MCU8
	out	_SFR_IO_ADDR(TCCR1A),TMP ; stop VSYNC pulse (stop inverting SYNC signal)
#else
	sts	TCCR1A,TMP	; [2] stop VSYNC pulse (invert SYNC signal)
#endif

; ----- increment video line

VRow4:	adiw	ZL,1			; increment video line

; ----- end of frame

	; prepare number of video lines
	;  VGA 525, NTSC 262, PAL 312
	ldi	TMP,lo8(525)		; VGA video lines
	ldi	TMP2,hi8(525)
	tst	DISPMODE		; check display mode
	brmi	2f			; old VGA
	breq	2f			; VGA
	ldi	TMP,lo8(262)		; NTSC video lines
	ldi	TMP2,hi8(262)
	sbrs	DISPMODE,0		; [1,2] skip if bit 0 is set = NTSC
	ldi	TMP,lo8(312)		; PAL video lines

2:	cp	ZL,TMP
	cpc	ZH,TMP2
	brne	VRow5

	; restart current address of video line
	ldd	ZL,Y+DATA_DISPPTR	; start of display memory
	ldd	ZH,Y+DATA_DISPPTR+1
	adiw	ZL,1			; skip first NEWLINE
	movw	VADDR,ZL		; new address of current display row

	; reset current video line
	ldi	ZL,0			; reset video lines
	ldi	ZH,0

VRow5:	; store new video line
	movw	VLINE,ZL

; ----- scan keyboard

	sbiw	TMP,6			; 6 lines to check keyboard
	sub	ZL,TMP			; check keyboard scanline
	sbc	ZH,TMP2
	brcs	1f			; invalid scanline

	; ZL=0: prepare COL1
	brne	2f
	sbi	_SFR_IO_ADDR(DDRC),3	; set output to COL1
1:	rjmp	VRowStop

	; ZL=1: check COL1, prepare COL2
2:	cpi	ZL,1
	brne	3f

	; SHIFT state will not be updated while some key is pressed
	ldd	TMP,Y+DATA_KEYCNT	; key counter
	tst	TMP			; sumething pressed?
	brne	1f			; some key is in progress
	in	TMP,_SFR_IO_ADDR(PIND)	; read ROW of column1
	std	Y+DATA_KEYSHIFT,TMP	; store key SHIFT state

1:	ldi	TMP,0xff
	std	Y+DATA_KEYSCAN,TMP	; clear scanned key

; INPUT: ZL = keyboard column 1..5
; DESTROYS: TMP, ZH, ZL
	rcall	ScanCol			; scan keyboard
	cbi	_SFR_IO_ADDR(DDRC),3	; clear output to COL1
	sbi	_SFR_IO_ADDR(DDRC),2	; set output to COL2
	rjmp	VRowStop

	; ZL=2: check COL2, prepare COL3
3:	cpi	ZL,2
	brne	4f

; INPUT: ZL = keyboard column 1..5
; DESTROYS: TMP, ZH, ZL
	rcall	ScanCol			; scan keyboard
	cbi	_SFR_IO_ADDR(DDRC),2	; clear output to COL2
	sbi	_SFR_IO_ADDR(DDRC),1	; set output to COL3
	rjmp	VRowStop

	; ZL=3: check COL3, prepare COL4
4:	cpi	ZL,3
	brne	5f

; INPUT: ZL = keyboard column 1..5
; DESTROYS: TMP, ZH, ZL
	rcall	ScanCol			; scan keyboard
	cbi	_SFR_IO_ADDR(DDRC),1	; clear output to COL3
	sbi	_SFR_IO_ADDR(DDRC),0	; set output to COL4
	rjmp	VRowStop

	; ZL=4: check COL4, prepare COL5
5:	cpi	ZL,4
	brne	6f

; INPUT: ZL = keyboard column 1..5
; DESTROYS: TMP, ZH, ZL
	rcall	ScanCol			; scan keyboard
	cbi	_SFR_IO_ADDR(DDRC),0	; clear output to COL4
	sbi	_SFR_IO_ADDR(DDRB),0	; set output to COL5
	rjmp	VRowStop

	; ZL=5: check COL5
; INPUT: ZL = keyboard column 1..5
; DESTROYS: TMP, ZH, ZL
6:	rcall	ScanCol			; scan keyboard
	cbi	_SFR_IO_ADDR(DDRB),0	; clear output to COL5

; ----- key processing

	; get counter
	ldd	ZL,Y+DATA_KEYCNT	; current counter

	; something now pressed?
	ldd	TMP,Y+DATA_KEYSCAN	; scanned key
	cpi	TMP,0xff		; something pressed?
	breq	7f			; no key

	; check if key is changed - in such case reset counter
	ldd	TMP2,Y+DATA_KEYPRESS	; current key
	cp	TMP,TMP2		; another key?
	breq	1f			; key not changed
	clr	ZL			; reset counter
1:	std	Y+DATA_KEYPRESS,TMP	; store new key

	; first press
	tst	ZL
	brne	2f
	std	Y+DATA_KEYBUF,TMP	; output key

	; start counter
2:	cpi	ZL,4			; counter minimal value
	brcc	3f
	ldi	ZL,4			; set counter minimal value

	; repeat key
3:	inc	ZL			; increment counter
	cpi	ZL,30			; repeat value
	brcs	8f			; no repeat
	subi	ZL,6
	std	Y+DATA_KEYBUF,TMP	; output key
	rjmp	8f

	; check is counter is already 0 (nothing pressed)
7:	tst	ZL			; someting pressed?
	breq	8f			; nothing pressed

	; maximal countr
	cpi	ZL,5
	brcs	2f			; counter is OK
	ldi	ZL,5			; limit maximal counter to release

	; decrement counter, clear pressed key if reach zero
2:	dec	ZL			; decrement counter
	brne	8f			; not reached 0
	ldi	TMP,0xff
	std	Y+DATA_KEYPRESS,TMP	; no key pressed

	; save new counter
8:	std	Y+DATA_KEYCNT,ZL	; new counter

VRowStop:
	rjmp	RenderStop		; pop registers

; ----- continue from main render function
; here is Z flag = equal to first invisible line

VRow1:	brne	VRow12			; not first invisible line

	; increment number of frames
	ldd	TMP,Y+DATA_FRAMES
	ldd	TMP2,Y+DATA_FRAMES+1
	adiw	TMP,1
	std	Y+DATA_FRAMES,TMP
	std	Y+DATA_FRAMES+1,TMP2
VRow12:	rjmp	VRow2

; ----------------------------------------------------------------------------
;                           Video rendering
; ----------------------------------------------------------------------------
; Interrupt occurs at start of HSYNC pulse.

; Interrupt latency 6..10 cycles:
;  0..4 cycles for finishing currently executed instruction
;  4 cycles for pushing PC on stack and jump to interrupt vector table
;  2 cycles for the rjmp

; read TCNT1L: value will be 6..10 + 5 = 11..15 cycles

; STACK requirements: 12

#ifdef MCU8
#define PUSHCLK 11 	// clock synchronization (ATmega8)
#else
#define PUSHCLK 12 	// clock synchronization (ATmega88)
#endif

; Note: On input, Y points to data section (and it is never changed)

.global	TIMER1_OVF_vect
TIMER1_OVF_vect:

; Time: [6..10] (relative to start of HSYNC pulse)

	; [5] push registers 1
	push	TMP			; [2]
	in	TMP,_SFR_IO_ADDR(SREG)	; [1] status register
	push	TMP			; [2] push status register

; Time: [11..15]

	; [9..13] sync interrupt latency
#ifdef MCU8
	in	TMP,_SFR_IO_ADDR(TCNT1L); [1] get Timer1 counter, should be 11..15 (ATmega8)
#else
	lds	TMP,TCNT1L		; [2] get Timer1 counter
#endif
	cpi	TMP,PUSHCLK+1		; [1] 12 ?
	brcs	.			; [1,2] add delay 1 for 11
	cpi	TMP,PUSHCLK+2		; [1] 13 ?
	brcs	.			; [1,2] add delay 1 for 11,12
	cpi	TMP,PUSHCLK+3		; [1] 14 ?
	brcs	.			; [1,2] add delay 1 for 11,12,13
	cpi	TMP,PUSHCLK+4		; [1] 15 ?
	brcs	.			; [1,2] add delay 1 for 11,12,13,14

; Time: [24]

	; [6] push registers 2
	push	TMP2			; [2]
	push	ZL			; [2]
	push	ZH			; [2]

; Time: [30]

	; [1] load current video line -> Z
	movw	ZL,VLINE		; [1] current video line

; Time: [31]

	; [VGA 12,13, TV 11,12] check if this video line is visible image line
	ldi	TMP,HEIGHT*8		; [1] full display (24 rows = 192 lines)
	IF_FAST				; [1,2] fast video?
	ldi	TMP,8			; [1] short display (1 row = 8 video lines)
	ldi	TMP2,0			; [1]
	tst	DISPMODE		; [1] check VGA display mode
	brmi	3f			; [1,2] old VGA display mode
	brne	4f			; [1,2] TV display mode
3:	add	TMP,TMP			; [1] * 2 (16 video lines per row)
	adc	TMP2,TMP2		; [1]
4:	cp	ZL,TMP			; [1]
	cpc	ZH,TMP2			; [1]
	brcc	VRow1			; [1,2] jump if line is not visible (VSYNC)

; Time: [VGA 43, TV 42]

	; [8] push registers 3
	push	XL			; [2]
	push	XH			; [2]
	push	LINEOFF			; [2]
	push	TILECNT			; [2]

; Time: [VGA 51, TV 50]

	; [5] increment video line and save it (as next video line)
	adiw	ZL,1			; [2] increment video line
	movw	VLINE,ZL		; [1] save new line
	subi	ZL,1			; [1] return current line LOW
	mov	ZH,ZL			; [1] current line LOW -> ZH

; Time: [VGA 56, TV 55]

	; [VGA 8, TV 6] prepare delay periods and relative video line
	ldi	TMP2,7			; [1] delay of TV mode
	ldi	LINEOFF,7		; [1] line mask in TV mode
	tst	DISPMODE		; [1] TV mode?
	brmi	1f			; [1,2] OLD VGA
	brne	2f			; [1,2] TV mode
1:	lsr	ZH			; [1] video line LOW / 2
	ldi	TMP2,1			; [1] delay of VGA mode
	ldi	LINEOFF,0xf		; [1] line mask in VGA mode

; Time: [VGA 64, TV 61]

	; [1] get address of current row
2:	movw	XL,VADDR		; [1] address of current display row

; Time: [VGA 65, TV 62]

	; [4] push flag of last video line
	and	ZL,LINEOFF		; [1] mask video line (0..7 or 0..15)
	sub	ZL,LINEOFF		; [1] check last video line (if 0)
	push	ZL			; [2] save flag of last video line

; Time: [VGA 69, TV 66]

; start visible from start of hsync [cycles] (= horiz. sync + horiz. back porch)
;			VGA 154		PAL 297		NTSC 280
; VGA: 154 - 69 - 41 - 4 = 40, delay 13
; NTSC: 280 - 66 - 41 - 6 = 167, delay 56
; PAL: 297 - 66 - 41 - 6 = 184, delay 61

	; [3*DISPBP + (VGA 4, TV 6)] back porch delay
	ldi	TMP,13			; [1] VGA delay
	tst	DISPMODE		; [1] check display mode
	brmi	4f			; [1,2] old VGA
	breq	4f			; [1,2] VGA
	ldi	TMP,56			; [1] NTSC delay
	sbrs	DISPMODE,0		; [1,2] skip if bit 0 is set = NTSC
	ldi	TMP,61			; [1] PAL delay

4:	dec	TMP			; [1]
	brne	4b			; [1,2]

	; [8] prepare font address -> Z
	andi	ZH,7			; -41: [1] mask relative font line 0..7
	ldi	LINEOFF,0		; -40: [1] line offset = 0
	lsr	ZH			; -39: [1]
	ror	LINEOFF			; -38: [1]
	lsr	ZH			; -37: [1] ZH:LINEOFF = relative font line * 64
	ror	LINEOFF			; -36: [1]
	subi	LINEOFF,lo8(-(Font))	; -35: [1] add font base address
	sbci	ZH,hi8(-(Font))		; -34: [1]

	; [11] check end of display
	ldd	ZL,Y+DATA_DISPEND	; -33: [2] display end address
	ldd	TMP,Y+DATA_DISPEND+1	; -31: [2]
	cp	XL,ZL			; -29: [1] check end of display
	cpc	XH,TMP			; -28: [1]
	brcs	2f			; -27: [1,2] display address is OK

	mov	XL,ZL			; -26: [1] limit to end of display
	mov	XH,TMP			; -25: [1]
	sbiw	XL,1			; -24: [2] move to last NEWLINE
	rjmp	3f			; -22: [2]

2:	nop2				; -25: [2]
	nop2				; -23: [2]
	nop				; -21: [1]

; ===== Prepare first character

	; [1] prepare max. number of visible characters
3:	ldi	TILECNT,WIDTH-1		; -20: [1] max. width

	; [9] load first character
4:	ld	ZL,X+			; -19: [2] get first character from video RAM
	cpi	ZL,NEWLINE		; -17: [1] end of line
	brne	5f			; -16: [1,2] not new line
	ldi	ZL,CH_SPC		; -15: [1] substitute NEWLINE with space
	sbiw	XL,1			; -14: [2] return pointer to NEWLINE character
	rjmp	6f			; -12: [2]

5:	nop2				; -14: [2]
	nop2				; -12: [2]

	; [2] prepare first character
6:	bst	ZL,7			; -10: [1] T <- save bit 7 (inverze flag)
	andi	ZL,0x3f			; -9: [1] clear bit 7 (inverze flag) and bit 6

	; [4] load font pattern (font address must be aligned to 64 bytes)
	add	ZL,LINEOFF		; -8: [1] add font address LOW (+ videoline)
	lpm	ZL,Z			; -7: [3] load font pattern -> ZL

	; [2] inverze pattern
	brts	2f			; -4: [1,2] skip if T is set (= inverze flag is set)
	com	ZL			; -3: [1] complement font pattern (= inverze character)

	; [2] SPI enable
2:	ldi	TMP,SPIEN		; -2: [1]
	out	_SFR_IO_ADDR(SPCR),TMP	; -1: [1] SPI enabled

	; [1] output font pattern
	out	_SFR_IO_ADDR(SPDR),ZL	; 0: [1] output font pattern to SPI register

	; check TV or VGA mode
	cpi	TMP2,4			; 1: [1] VGA mode?
	brcs	VGARenderLoop		; 2: [1,2] jump to VGA mode
	nop				; 3: [1]

; ===== TV render loop - output visible characters

TVRenderLoop:	; TV 36 cycles per character

	; [4,5] load character from video buffer -> ZL, T
	ld	ZL,X+			; 4: [2] get character from video buffer
	cpi	ZL,NEWLINE		; 6: [1] end of line
	breq	RenderLoop4		; 7: [1,2] jmp if end of line (jump to time 9:)

	; [2] prepare character
	bst	ZL,7			; 8: [1] T <- save bit 7 (inverze flag)
	andi	ZL,0x3f			; 9: [1] clear bit 7 (inverze flag) and bit 6

	; [4] load font pattern (font address must be aligned to 64 bytes)
	add	ZL,LINEOFF		; 10: [1] add font address LOW (+ videoline)
	lpm	ZL,Z			; 11: [3] load font pattern -> ZL

	; [2] inverze pattern
	brts	2f			; 14: [1,2] skip if T is set (= inverze flag is set)
	com	ZL			; 15: [1] complement font pattern (= inverze character)

	; [TV 20] delay
2:	ldi	TMP,6			; 16: [1] time constant
3:	dec	TMP			; 17: [1] delay counter
	brne	3b			; 18: [1,2] delay
	nop2				; 34: [2]

	; [1] output font pattern
	out	_SFR_IO_ADDR(SPDR),ZL	; (36) 0: [1] output font pattern to SPI register

	; [3] next character
	dec	TILECNT			; 1: [1] character counter
	brne	TVRenderLoop		; 2: [1,2]
	nop2				; 3: [2]

	; full row - next character will be NEWLINE, skip it
RenderLoop4B:
	adiw	XL,1			; 5: [2] skip NEWLINE character
	nop2				; 7: [2]

; ===== wait for last character and display remaining spaces
; Without sending data, SPI outputs white character (stays HIGH), it means space character.

RenderLoop4:

	; character count correction
	inc	TILECNT			; 9: [1] including last character

	; [first pass: VGA 5, TV 23]
	mov	TMP,TMP2		; 10: [1] (VGA 1, TV 7)
	rjmp	3f			; 11: [2]

; Here is TILECNT = nunber of remaining spaces, TMP = 0

	; [next pass VGA 15, TV 33] delay to wait remaining characters, including last character
2:	nop2				; (18,36) 0: [2]
	mov	TMP,TMP2		; 2: [1] delay constant (VGA 1, TV 7)
	subi	TMP,-3			; 3: [1] additional delay + 3 (-> VGA 4, TV 10)

3:	dec	TMP			; 4: [1]
	brne	3b			; 5: [1,2] wait

	; [2,3] next remaining character
	dec	TILECNT			; 15,33: [1] tile counter
	brne	2b			; 16,34: [1,2] render next character

	; [2] SPI disable (set output to black)
	ldi	TMP,SPIDIS		; 17,35: [1]
	out	_SFR_IO_ADDR(SPCR),TMP	; (18,36) 0: [1] SPI disabled

; ===== Shift video RAM address on last relative font line

	; [5] save new address of display row
	pop	TMP			; [2] flag of last video line (if 0)
	tst	TMP			; [1] last video line?
	brne	4f			; [1,2] not last video line
	movw	VADDR,XL		; [1] save new address of display row

	; [8] pop registers 3
4:	pop	TILECNT			; [2]
	pop	LINEOFF			; [2]
	pop	XH			; [2]
	pop	XL			; [2]

; ----- pop registers

RenderStop:

	; [6] pop registers 2
	pop	ZH			; [2]
	pop	ZL			; [2]
	pop	TMP2			; [2]

	; [9] pop registers 1
	pop	TMP			; [2]
	out	_SFR_IO_ADDR(SREG),TMP	; [1]
	pop	TMP			; [2]

; - to check how many clock cycles remains before next interrupt
;	nop
;	nop2
;	nop2
	reti				; [4]


; ===== VGA render loop - output visible characters

VGARenderLoop:	; VGA 18 cycles per character

	; [4,5] load character from video buffer -> ZL, T
	ld	ZL,X+			; 4: [2] get character from video buffer
	cpi	ZL,NEWLINE		; 6: [1] end of line
	breq	RenderLoop4		; 7: [1,2] jump if end of line (jump to time 9:)

	; [2] prepare character
	bst	ZL,7			; 8: [1] T <- save bit 7 (inverze flag)
	andi	ZL,0x3f			; 9: [1] clear bit 7 (inverze flag) and bit 6

	; [4] load font pattern (font address must be aligned to 64 bytes)
	add	ZL,LINEOFF		; 10: [1] add font address LOW (+ videoline)
	lpm	ZL,Z			; 11: [3] load font pattern -> ZL

	; [2] inverze pattern
	brts	2f			; 14: [1,2] skip if T is set (= inverze flag is set)
	com	ZL			; 15: [1] complement font pattern (= inverze character)

	; [2] delay
2:	nop2				; 16: [2]

	; [1] output font pattern
	out	_SFR_IO_ADDR(SPDR),ZL	; (18) 0: [1] output font pattern to SPI register

	; [3] next character
	dec	TILECNT			; 1: [1] character counter
	brne	VGARenderLoop		; 2: [1,2]
	rjmp	RenderLoop4B		; 3: [2]

; ----------------------------------------------------------------------------
;                Initialize display mode (it enables interrupts)
; ----------------------------------------------------------------------------
; DESTROYS: R1, R0
; ----------------------------------------------------------------------------

.global DispInit
DispInit:

; ----- push registers

	push	r24
	push	r25
	push	ZL
	push	ZH

; ----- disable interrupts

	cli

; ----- connect OLDVGA with VGA
	
	mov	r24,DISPMODE
	cpi	r24,DISP_OLDVGA	; old VGA?
	brne	2f
	ldi	r24,DISP_VGA	; reduce old VGA mode

; ----- prepare address of videomode descriptor -> Z

2:	ldi	ZL,VMODEDESC_SIZE ; number of bytes per one descriptor
	mul	r24,ZL		; offset of descriptor
	ldi	ZL,lo8(VideoMode_Desc)
	ldi	ZH,hi8(VideoMode_Desc)
	add	ZL,r0
	adc	ZH,r1		; address of descriptor

; ----- load parameters

	; VSyncBeg
;	lpm	r24,Z+
;	lpm	r25,Z+
;	std	Y+DATA_VSYNCBEG,r24
;	std	Y+DATA_VSYNCBEG+1,r25
	
	; VSyncEnd
;	lpm	r24,Z+
;	lpm	r25,Z+
;	std	Y+DATA_VSYNCEND,r24
;	std	Y+DATA_VSYNCEND+1,r25

; ----- initialize SPI output

	; set SPI2X clock
	lpm	r24,Z+
	out	_SFR_IO_ADDR(SPSR),r24

	; enable SPI output (MSB first, master mode, SCK data on rising edge)
	ldi	r24,SPIEN		; SPI enable, speed clk/2
	out	_SFR_IO_ADDR(SPCR),r24

; ----- Initialize Timer1 (HSYNC output OC1A, period ICR1, reference OCR1A)

	; stop Timer1
#ifdef MCU8
	out	_SFR_IO_ADDR(TCCR1B),ZERO ; stop Timer1
	out	_SFR_IO_ADDR(TIMSK),ZERO ; disable all interrupts from Timer1
	out	_SFR_IO_ADDR(TCNT1H),ZERO
	out	_SFR_IO_ADDR(TCNT1L),ZERO ; reset Timer1 counter
#else
	sts	TCCR1B,ZERO	; stop Timer1
	sts	TIMSK1,ZERO	; disable all interrupts from Timer1
	sts	TCNT1H,ZERO
	sts	TCNT1L,ZERO	; reset Timer1 counter
#endif

	; set Timer1 period to horizontal cycles
	lpm	r24,Z+		; horizontal total cycles - 1 LOW
	lpm	r25,Z+		; horizontal total cycles - 1 HIGH
#ifdef MCU8
	out	_SFR_IO_ADDR(ICR1H),r25 ; set Timer1 period (= horizontal total cycles - 1)
	out	_SFR_IO_ADDR(ICR1L),r24
#else
	sts	ICR1H,r25
	sts	ICR1L,r24	; set Timer1 ICR1
#endif

	; set HSYNC width
	lpm	r24,Z+		; horizontal sync cycles - 1 LOW
	lpm	r25,Z+		; horizontal sync cycles - 1 HIGH
#ifdef MCU8
	out	_SFR_IO_ADDR(OCR1AH),r25
	out	_SFR_IO_ADDR(OCR1AL),r24 ; set Timer1 OCR1A
#else
	sts	OCR1AH,r25
	sts	OCR1AL,r24	; set Timer1 OCR1A
#endif

	; OC1A: start LOW pulse on TOP, stop HIGH pulse on match
	ldi	r24,BIT(COM1A1) | BIT(COM1A0) | BIT(WGM11)
#ifdef MCU8
	out	_SFR_IO_ADDR(TCCR1A),r24
#else
	sts	TCCR1A,r24
#endif

	; start Timer1 in fast PWM mode 14 (top=ICR1), no prescaler
	ldi	r24,BIT(WGM12) | BIT(WGM13) | BIT(CS10)
#ifdef MCU8
	out	_SFR_IO_ADDR(TCCR1B),r24
#else
	sts	TCCR1B,r24
#endif

	; enable interrupt on Timer1 overflow (interrupt on start of HSYNC)
	ldi	r24,BIT(TOIE1)
#ifdef MCU8
	out	_SFR_IO_ADDR(TIMSK),r24
#else
	sts	TIMSK1,r24
#endif

; ----- reset current video line

	mov	VLINE_L,ZERO
	mov	VLINE_H,ZERO

; ----- restart pointer to video memory

	ldd	r24,Y+DATA_DISPPTR
	ldd	r25,Y+DATA_DISPPTR+1
	adiw	r24,1			; skip first NEWLINE
	movw	VADDR,r24

; ----- enable interrupts

	sei

; ----- pop registers

	pop	ZH
	pop	ZL
	pop	r25
	pop	r24
	ret

; ----------------------------------------------------------------------------
;                            Get key from keyboard
; ----------------------------------------------------------------------------
; OUTPUT: A = key (NOKEY = no key)
;	  ZY = no key
; DESTROYS: F
; STACK: 2
; ----------------------------------------------------------------------------

.global GetKey
GetKey:
	; load key
	ldd	A,Y+DATA_KEYBUF		; get key
	cpi	A,NOKEY
	breq	8f			; no key
	ldi	F,0xff
	std	Y+DATA_KEYBUF,F		; delete key

	; convert to token if 'K' mode
	IF_LMODE			; if letter mode
	ret				; skip if not 'K' mode

	subi	A,-0xc0			; convert to token
	cpi	A,0xe6			; check 'LIST' minimal token
	brcc	6f			; token is OK
	subi	A,0xc0			; return previous character
6:	tst	A			; clear Z flag

8:	ret
