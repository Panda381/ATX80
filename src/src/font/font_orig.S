
; ****************************************************************************
;
;                                Character set
;
; ****************************************************************************

#include "include.inc"

	.text

	.align 8	; align to 256 bytes

;   Mosaic pixels 1234:
;	1 2
;	3 4

; Original ZX80 font is arranged as 1 column of 64 charactes.
; You can save it (and edit) as portable bitmap PBM 8x512 pixels/1-bit.

; PBM header: 0x50, 0x34, 0x0A, 0x38, 0x0A, 0x35, 0x31, 0x32, 0x0A
; Text form of PBM header: "P4\n8\n512\n"

; ZX81: L0E00
.global Font
Font:
	; 0x00 ' '
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000

	; 0x01 '"'
        .byte	0b00000000
        .byte	0b00010100
        .byte	0b00010100
        .byte	0b00000000
        .byte	0b00000000
        .byte	0b00000000
        .byte	0b00000000
        .byte	0b00000000
	
	; 0x02 mosaic 1010
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000

	; 0x03 mosaic 0011
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b11111111
	.byte	0b11111111
	.byte	0b11111111
	.byte	0b11111111

	; 0x04 mosaic 1000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000

	; 0x05 mosaic 0100
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000

	; 0x06 mosaic 0010
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000

	; 0x07 mosaic 0001
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b00001111

	; 0x08 mosaic 0110
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b00001111
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000
	.byte	0b11110000

	; 0x09 chess patte
	.byte	0b10101010
	.byte	0b01010101
	.byte	0b10101010
	.byte	0b01010101
	.byte	0b10101010
	.byte	0b01010101
	.byte	0b10101010
	.byte	0b01010101

	; 0x0A mosaic 0011
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b10101010
	.byte	0b01010101
	.byte	0b10101010
	.byte	0b01010101

	; 0x0B mosaic 1100
	.byte	0b10101010
	.byte	0b01010101
	.byte	0b10101010
	.byte	0b01010101
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000

	; 0x0C uk pound
	.byte	0b00000000
	.byte	0b00011110
	.byte	0b00100001
	.byte	0b01111000
	.byte	0b00100000
	.byte	0b00100000
	.byte	0b01111111
	.byte	0b00000000

	; 0x0D '$' dollar
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00111110
	.byte	0b01001000
	.byte	0b00111110	
	.byte	0b00001001
	.byte	0b00111110
	.byte	0b00001000

	; 0x0E ':' colon
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00000000

	; 0x0F '?'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b00000110
	.byte	0b00001000
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00000000

	; 0x10 '('
	.byte	0b00000000
	.byte	0b00000100
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00000100
	.byte	0b00000000

	; 0x11 ')'
	.byte	0b00000000
	.byte	0b00010000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00010000
	.byte	0b00000000

	; 0x12 '-'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000

	; 0x13 '+'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00111110
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00000000

	; 0x14 '*'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00101010
	.byte	0b00011100
	.byte	0b00001000
	.byte	0b00011100
	.byte	0b00101010
	.byte	0b00000000

	; 0x15 '/'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000010
	.byte	0b00000100
	.byte	0b00001000
	.byte	0b00010000
	.byte	0b00100000
	.byte	0b00000000

	; 0x16 '='
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b00000000
	.byte	0b00000000

	; 0x17 '>'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00010000
	.byte	0b00001000
	.byte	0b00000100
	.byte	0b00001000
	.byte	0b00010000
	.byte	0b00000000

	; 0x18 '<'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000100
	.byte	0b00001000
	.byte	0b00010000
	.byte	0b00001000
	.byte	0b00000100
	.byte	0b00000000

	; 0x19 ';'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00010000

	; 0x1A ','
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00010000

	; 0x1B '.'
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00000000
	.byte	0b00001100
	.byte	0b00001100
	.byte	0b00000000

	; 0x1C '0'
	.byte	0b00000000
	.byte	0b00011100
	.byte	0b00100010
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00100010
	.byte	0b00011100
	.byte	0b00000000

	; 0x1D '1'
	.byte	0b00000000
	.byte	0b00001100
	.byte	0b00010100
	.byte	0b00000100
	.byte	0b00000100
	.byte	0b00000100
	.byte	0b00011110
	.byte	0b00000000

	; 0x1E '2'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b00000001
	.byte	0b00111110
	.byte	0b01000000
	.byte	0b01111111
	.byte	0b00000000

	; 0x1F '3'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b00000110
	.byte	0b00000001
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x20 '4'
	.byte	0b00000000
	.byte	0b00001100
	.byte	0b00010100
	.byte	0b00100100
	.byte	0b01000100
	.byte	0b01111111
	.byte	0b00000100
	.byte	0b00000000

	; 0x21 '5'
	.byte	0b00000000
	.byte	0b01111111
	.byte	0b01000000
	.byte	0b01111110
	.byte	0b00000001
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x22 '6'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000000
	.byte	0b01111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x23 '7'
	.byte	0b00000000
	.byte	0b01111111
	.byte	0b00000001
	.byte	0b00000010
	.byte	0b00000100
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00000000

	; 0x24 '8'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x25 '9'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00111111
	.byte	0b00000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x26 'A'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01111111
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00000000

	; 0x27 'B'
	.byte	0b00000000
	.byte	0b01111110
	.byte	0b01000001
	.byte	0b01111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01111110
	.byte	0b00000000

	; 0x28 'C'
	.byte	0b00000000
	.byte	0b00011110
	.byte	0b00100001
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b00100001
	.byte	0b00011110
	.byte	0b00000000

	; 0x29 'D'
	.byte	0b00000000
	.byte	0b01111100
	.byte	0b01000010
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000010
	.byte	0b01111100
	.byte	0b00000000

	; 0x2A 'E'
	.byte	0b00000000
	.byte	0b01111111
	.byte	0b01000000
	.byte	0b01111100
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b01111111
	.byte	0b00000000

	; 0x2B 'F'
	.byte	0b00000000
	.byte	0b01111111
	.byte	0b01000000
	.byte	0b01111100
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b00000000

	; 0x2C 'G'
	.byte	0b00000000
	.byte	0b00011110
	.byte	0b00100001
	.byte	0b01000000
	.byte	0b01000111
	.byte	0b00100001
	.byte	0b00011110
	.byte	0b00000000

	; 0x2D 'H'
	.byte	0b00000000
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01111111
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00000000

	; 0x2E 'I'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00111110
	.byte	0b00000000

	; 0x2F 'J'
	.byte	0b00000000
	.byte	0b00000010
	.byte	0b00000010
	.byte	0b00000010
	.byte	0b01000010
	.byte	0b00100010
	.byte	0b00011100
	.byte	0b00000000

	; 0x30 'K'
	.byte	0b00000000
	.byte	0b01000010
	.byte	0b01000100
	.byte	0b01111000
	.byte	0b01000100
	.byte	0b01000010
	.byte	0b01000001
	.byte	0b00000000

	; 0x31 'L'
	.byte	0b00000000
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b01111111
	.byte	0b00000000

	; 0x32 'M'
	.byte	0b00000000
	.byte	0b01000001
	.byte	0b01100011
	.byte	0b01010101
	.byte	0b01001001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00000000

	; 0x33 'N'
	.byte	0b00000000
	.byte	0b01100001
	.byte	0b01010001
	.byte	0b01001001
	.byte	0b01000101
	.byte	0b01000011
	.byte	0b01000001
	.byte	0b00000000

	; 0x34 'O'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x35 'P'
	.byte	0b00000000
	.byte	0b01111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01111110
	.byte	0b01000000
	.byte	0b01000000
	.byte	0b00000000

	; 0x36 'Q'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01001001
	.byte	0b01000101
	.byte	0b00111110
	.byte	0b00000000

	; 0x37 'R'
	.byte	0b00000000
	.byte	0b01111110
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01111110
	.byte	0b01000100
	.byte	0b01000010
	.byte	0b00000000

	; 0x38 'S'
	.byte	0b00000000
	.byte	0b00111110
	.byte	0b01000000
	.byte	0b00111110
	.byte	0b00000001
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x39 'T'
	.byte	0b00000000
	.byte	0b01111111
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00000000

	; 0x3A 'U'
	.byte	0b00000000
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00111110
	.byte	0b00000000

	; 0x3B 'V'
	.byte	0b00000000
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b00100010
	.byte	0b00010100
	.byte	0b00001000
	.byte	0b00000000

	; 0x3C 'W'
	.byte	0b00000000
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01000001
	.byte	0b01001001
	.byte	0b01010101
	.byte	0b00100010
	.byte	0b00000000

	; 0x3D 'X'
	.byte	0b00000000
	.byte	0b00100001
	.byte	0b00010010
	.byte	0b00001100
	.byte	0b00001100
	.byte	0b00010010
	.byte	0b00100001
	.byte	0b00000000

	; 0x3E 'Y'
	.byte	0b00000000
	.byte	0b01000001
	.byte	0b00100010
	.byte	0b00011100
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00001000
	.byte	0b00000000

	; 0x3F 'Z'
	.byte	0b00000000
	.byte	0b01111111
	.byte	0b00000010
	.byte	0b00000100
	.byte	0b00001000
	.byte	0b00010000
	.byte	0b01111111
	.byte	0b00000000

	.balign	2	; align to 2 bytes
