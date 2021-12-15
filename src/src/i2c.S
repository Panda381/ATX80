
; ****************************************************************************
;
;                         I2C interface to external EEPROM
;
; ****************************************************************************
; Supported EEPROMs:
;  Microchip 24LC32 ... 32 Kbit, 4 KB, 4 slots, page size 32 bytes, write cycle 5 ms
;  Microchip 24LC64 ... 64 Kbit, 8 KB, 8 slots, page size 32 bytes, write cycle 2 ms
;  Microchip 24LC128 ... 128 Kbit, 16 KB, 16 slots, page size 64 bytes, write cycle 5 ms
;  Microchip 24LC256 ... 256 Kbit, 32 KB, 32 slots, page size 64 bytes, write cycle 5 ms ... recommended
;  Microchip 24LC512 ... 512 Kbit, 64 KB, 64 slots, page size 128 bytes, write cycle 5 ms

#include "include.inc"

; 24LC256P, EEPROM 256 kbit, 32 KB * 8 bits
; -----------------------------------------
; Slave address:
;  1 0 1 0 A2 A1 A0 R/W
; where A2,A1,A0 of main EEPROM is set to 0.

; Bits are transfered in order from MSB to LSB.

; Write data:
; 1) START condition
; 2) control byte I2C_W (address + select write operation)
; 3) address high byte, bits A14..A8 (A15 is 0)
; 4) address low byte, bits A7..A0
; 5) 1..64 bytes (up to page size)
; 6) STOP condition (device starts write cycle)
;
; Write cycles takes 5 ms max. During write cycle device does not acknowledge commands.
; After write byte, internal address counter will point to following location.
; Page write operation cannot write across physical page boundary (64 bytes).
;
; Polling write cycle:
; 1) START condition
; 2) control byte I2C_W (address + select write operation)
; 3) If device did not acknowledge (ACK = 0) repeta to 2.
; 4) STOP condition
;
; Read data:
; 1) START condition
; 2) control byte I2C_W (address + select write operation)
; 3) address high byte, bits A14..A8 (A15 is 0)
; 4) address low byte, bits A7..A0
; 5) START condition
; 6) control byte I2C_R (address + select read operation)
; 5) read bytes, acknowledge all bytes except last byte
; 6) STOP condition

#define I2C_W	0xa0	// I2C write address
#define I2C_R	0xa1	// I2C read address

; status
#define	I2C_START	0x08	// START transmitted
#define I2C_START2	0x10	// repeated START transmitted
#define I2C_WADDR_ACK	0x18	// write address transmitted, ACK received
#define I2C_WADDR_NACK	0x20	// write address transmitted, NOT ACK received
#define I2C_WDATA_ACK	0x28	// data byte transmitted, ACK received
#define I2C_WDATA_NACK	0x30	// data byte transmitted, NOT ACK received
#define I2C_LOST	0x38	// arbitration lost
#define I2C_RADDR_ACK	0x40	// read address transmitted, ACK received
#define I2C_RADDR_NACK	0x48	// read address transmitted, NOT ACK received
#define I2C_RDATA_ACK	0x50	// data byte received, ACK transmitted
#define I2C_RDATA_NACK	0x58	// data byte received, NOT ACK transmitted

#define I2C_PAGE	32	// max. page size (smallest page which can hold in write buffer)
#define I2C_PAGEMASK	(I2C_PAGE-1) // page mask

#define I2C_WAIT	6000	// max. page write time at [us] (time to end write operation)
#define I2C_DELAY	2000	// min. page write time at [us] (time to start write operation)

	.text

; ----------------------------------------------------------------------------
;               Initialize I2C interface before transmission
; ----------------------------------------------------------------------------
; OUTPUT: PUSH1_L = old bit rate register
; DESTROYS: F
; STACK: 2
; ----------------------------------------------------------------------------
; Note: SDA and SCL pins are already initialized to use internal pull-ups.
; Internal pull-ups are about 36 kOhm and it supports only low speed interface.

I2CInit:
	; save current bit rate register (application can use it as flag register)
#ifdef MCU8
	in	PUSH1_L,_SFR_IO_ADDR(TWBR)
#else
	lds	PUSH1_L,TWBR
#endif

	; set status register (set prescaler to value 4^1=4)
	ldi	F,1
#ifdef MCU8
	out	_SFR_IO_ADDR(TWSR),F
#else
	sts	TWSR,F
#endif

	; set bit rate register, freq = F_CPU/(16 + 2*TWBR*4^TWPS)
	;   freq = 24000000/(16 + 2*98*4^1) = 30000 Hz
	ldi	F,98
#ifdef MCU8
	out	_SFR_IO_ADDR(TWBR),F
#else
	sts	TWBR,F
#endif

	; set control register (enable TWI)
	ldi	F,BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),F
#else
	sts	TWCR,F
#endif
	ret

; ----------------------------------------------------------------------------
;               Terminate I2C interface after transmission
; ----------------------------------------------------------------------------
; INPUT: PUSH1_L = old bit rate register
; DESTROYS: -
; STACK: 2 (saves flags)
; ----------------------------------------------------------------------------

I2CTerm:
	; disable TWI interface
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),ZERO
#else
	sts	TWCR,ZERO
#endif

	; return bit rate register
#ifdef MCU8
	out	_SFR_IO_ADDR(TWBR),PUSH1_L
#else
	sts	TWBR,PUSH1_L
#endif
	ret

; ----------------------------------------------------------------------------
;                        Send START condition
; ----------------------------------------------------------------------------
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

I2CStart:
	; reset TWINT flag, send START condition, enable TWI interface
	ldi	F,BIT(TWINT) | BIT(TWSTA) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),F
#else
	sts	TWCR,F
#endif

; I2CWait must follow

; ----------------------------------------------------------------------------
;                   Wait to complete current operation
; ----------------------------------------------------------------------------
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

I2CWait:
	; wait while TWINT flag is clear
#ifdef MCU8
	in	F,_SFR_IO_ADDR(TWCR)
#else
	lds	F,TWCR
#endif
	sbrs	F,TWINT
	rjmp	I2CWait

; I2CStatus must follow

; ----------------------------------------------------------------------------
;                Load status register (without prescaler bits)
; ----------------------------------------------------------------------------
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

I2CStatus:
#ifdef MCU8
	in	F,_SFR_IO_ADDR(TWSR)
#else
	lds	F,TWSR
#endif
	andi	F,0xf8

	; we don't need to distinguish between first START and repeated START
	cpi	F,I2C_START2	; repeated START
	brne	2f
	ldi	F,I2C_START	; return first START
2:	ret

; ----------------------------------------------------------------------------
;                        Send STOP condition
; ----------------------------------------------------------------------------
; DESTROYS: F
; STACK: 2 (saves flags)
; ----------------------------------------------------------------------------

I2CStop:
	; reset TWINT flag, send STOP condition, enable TWI interface
	ldi	F,BIT(TWINT) | BIT(TWSTO) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),F
#else
	sts	TWCR,F
#endif
	ret

; ----------------------------------------------------------------------------
;                         Receive byte
; ----------------------------------------------------------------------------
; INPUT: A = flag BIT(TWEA) (= not last byte) or 0 (= last byte)
; OUTPUT: A = received byte
;	  F = status register bits 3..7
; DESTROYS: -
; STACK: 4
; ----------------------------------------------------------------------------

I2CRecv:
	; reset TWINT flag, enable TWI interface
	ori	A,BIT(TWINT) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),A
#else
	sts	TWCR,A
#endif

	; wait to complete operation
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
	rcall	I2CWait

	; receive data byte
#ifdef MCU8
	in	A,_SFR_IO_ADDR(TWDR)
#else
	lds	A,TWDR
#endif
	ret

; ----------------------------------------------------------------------------
;                         Send byte (address or data)
; ----------------------------------------------------------------------------
; INPUT: A = data byte to send
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

I2CSend:
	; send data byte
#ifdef MCU8
	out	_SFR_IO_ADDR(TWDR),A
#else
	sts	TWDR,A
#endif

	; reset TWINT flag, enable TWI interface
	ldi	F,BIT(TWINT) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),F
#else
	sts	TWCR,F
#endif

	; wait
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
	rjmp	I2CWait

; ----------------------------------------------------------------------------
;                          Write address
; ----------------------------------------------------------------------------
; INPUT: BC = byte offset (0..32767)
;	 R0 = flag: 1=wait if NACK (wait previous operation), 0=do not wait NACK (first run)
; OUTPUT: F = status register bits 3..7
;	  ZY = status is OK, NZ = operation error
; DESTROYS: -
; STACK: 4
; ----------------------------------------------------------------------------

I2CAddr:
	; save A
	push	A

	; send START condition
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
2:	rcall	I2CStart
	cpi	F,I2C_START
	brne	8f

	; send command (write operation)
	ldi	A,I2C_W
; INPUT: A = data byte to send
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
	rcall	I2CSend
	cpi	F,I2C_WADDR_NACK
	sbrc	r0,0			; skip waiting if R0=0
	breq	2b			; wait (only if R0=1)
	cpi	F,I2C_WADDR_ACK
	brne	8f

	; send start address HIGH
	mov	A,B
; INPUT: A = data byte to send
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
	rcall	I2CSend
	cpi	F,I2C_WDATA_ACK
	brne	8f

	; send start address LOW
	mov	A,C
; INPUT: A = data byte to send
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
	rcall	I2CSend
	cpi	F,I2C_WDATA_ACK

	; restore A
8:	pop	A

I2CAddr4:
	ret

; ----------------------------------------------------------------------------
;                  Store old content and prepare slot address
; ----------------------------------------------------------------------------
; INPUT: BC = slot index 0..63
; OUTPUT: BC = byte offset (0..65535)
;	  HL = program address - 4
;	  PUSH2 = old content of (Program-4)
;	  PUSH3 = old content of (Program-2)
;	  CY = error
; DESTROYS: -
; STACK: 2
; ----------------------------------------------------------------------------

I2CStore:
	; check range 0..63
	tst	B		; check slot index HIGH
	sec			; set CY flag
	brne	I2CStore8	; invalid slot index

	; convert slot number to byte offset (one slot is 1024 bytes)
	mov	B,C		; slot * 256
	clr	C
	add	B,B		; slot * 512
	brcs	I2CStore8	; overflow
	add	B,B		; slot * 1024

; I2CStore2 must follow

; ----------------------------------------------------------------------------
;                           Store old content
; ----------------------------------------------------------------------------
; OUTPUT: HL = program address - 4
;	  PUSH2 = old content of (Program-4)
;	  PUSH3 = old content of (Program-2)
; DESTROYS: - (saves flags)
; STACK: 2
; ----------------------------------------------------------------------------

.global I2CStore2
I2CStore2:
	; prepare save start address -> HL
	ldi	L,lo8(Program-4)
	ldi	H,hi8(Program-4)

	; save old content of CharPtr, PrintCols and PrintRows -> PUSH2, PUSH3
	ldd	PUSH2_L,MHL+0
	ldd	PUSH2_H,MHL+1
	ldd	PUSH3_L,MHL+2
	ldd	PUSH3_H,MHL+3
I2CStore8:
	ret

; ----------------------------------------------------------------------------
;                       Restore old content
; ----------------------------------------------------------------------------
; INPUT: PUSH2 = old content of (Program-4)
;	 PUSH3 = old content of (Program-2)
; OUTPUT: HL = program address - 4
; DESTROYS: -
; STACK: 2 (saves flags)
; ----------------------------------------------------------------------------

.global I2CRestore
I2CRestore:
	; prepare save start address -> HL
	ldi	L,lo8(Program-4)
	ldi	H,hi8(Program-4)

	; restore old content of CharPtr, PrintCols and PrintRows
	std	MHL+0,PUSH2_L
	std	MHL+1,PUSH2_H
	std	MHL+2,PUSH3_L
	std	MHL+3,PUSH3_H
	ret

; ----------------------------------------------------------------------------
;                 Save program to external EEPROM
; ----------------------------------------------------------------------------
; INPUT: BC = slot number 0..63
; OUTPUT: NC = write error
; DESTROYS: AF, BC, DE, HL, PUSH1, PUSH2, PUSH3, R0
; ----------------------------------------------------------------------------

.global I2CSave
I2CSave:
	; store old content
; INPUT: BC = slot index 0..63
; OUTPUT: BC = byte offset (0..65535)
;	  HL = program address - 4
;	  PUSH2 = old content of (Program-4)
;	  PUSH3 = old content of (Program-2)
;	  CY = error
; DESTROYS: -
; STACK: 2
	rcall	I2CStore
	brcs	I2CError

	; prepare program size
	ldd	E,Y+DATA_VARSPTR
	ldd	D,Y+DATA_VARSPTR+1
	sub	E,L
	sbc	D,H
	std	MHL+0,E		; save program size
	std	MHL+1,D

	; prepare total size -> DE
	ldd	E,Y+DATA_EDITPTR
	ldd	D,Y+DATA_EDITPTR+1
	sub	E,L
	sbc	D,H
	std	MHL+2,E		; save total size
	std	MHL+3,D

	; initialize I2C interface
; OUTPUT: PUSH1_L = old bit rate register
; DESTROYS: F
; STACK: 2
	rcall	I2CInit

	; send address
; INPUT: BC = byte offset (0..32767)
;	 R0 = flag, 1=wait if NACK (wait previous operation), 0=do not wait NACK (first run)
; OUTPUT: F = status register bits 3..7
;	  ZY = status is OK, NZ = operation error
; DESTROYS: -
; STACK: 4
	clr	r0		; flag - do not wait at first pass
2:	rcall	I2CAddr
	brne	I2CError

	; send one page of data
4:	ld	A,MHL+
; INPUT: A = data byte to send
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
	rcall	I2CSend
	cpi	F,I2C_WDATA_ACK
	brne	I2CError

	; next byte at this page
	adiw	BC,1		; increment destination offset
	sbiw	DE,1		; decrement size counter
	breq	6f		; end of data
	mov	A,C		; destination offset LOW
	andi	A,I2C_PAGEMASK	; check page align
	brne	4b		; next byte at this page

	; send STOP condition
; DESTROYS: F
; STACK: 2 (saves flags)
	rcall	I2CStop

	; delay (required to start write operation)
	; - Requires min. 50 us if checking NACK, to start write operation
	; - Requires min. 4 ms if not checking NACK, to complete write operation
	PUSH_BC
	ldi	C,lo8(I2C_DELAY)
	ldi	B,hi8(I2C_DELAY)
; INPUT: BC=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: BC
; STACK: 4
	rcall	waitus
	POP_BC

	; prepare for next pass
	clr	r0
	inc	r0		; flag - wait
	rjmp	2b

	; send last STOP condition
; DESTROYS: F
; STACK: 2 (saves flags)
6:	rcall	I2CStop

	; wait to complete write operation
	PUSH_BC
	ldi	C,lo8(I2C_WAIT)
	ldi	B,hi8(I2C_WAIT)
; INPUT: BC=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: BC
; STACK: 4
	rcall	waitus
	POP_BC

	; restore old content
; INPUT: PUSH2 = old content of (Program-4)
;	 PUSH3 = old content of (Program-2)
; OUTPUT: HL = program address - 4
; DESTROYS: -
; STACK: 2 (saves flags)
	rcall	I2CRestore

	; set operation OK
	sec		; set operation OK

	; terminate I2C interface
; INPUT: PUSH1_L = old bit rate register
; DESTROYS: -
; STACK: 2 (saves flags)
	rjmp	I2CTerm

; ----------------------------------------------------------------------------
;                       External EEPROM error
; ----------------------------------------------------------------------------

.global I2CError
I2CError:
	; send STOP condition
; DESTROYS: F
; STACK: 2 (saves flags)
	rcall	I2CStop

	; restore old content
; INPUT: PUSH2 = old content of (Program-4)
;	 PUSH3 = old content of (Program-2)
; OUTPUT: HL = program address - 4
; DESTROYS: -
; STACK: 2 (saves flags)
	rcall	I2CRestore

	; terminate I2C interface
; INPUT: PUSH1_L = old bit rate register
; DESTROYS: -
; STACK: 2 (saves flags)
	rcall	I2CTerm

	; set error flag
	clc

	; write error
	ldi	L,ERR_EEPROM
; INPUT: L = error code ERR_* (only first error is set into ErrCode variable)
; DESTROYS: - (saves flags)
; STACK: 2
	rjmp	Error

; ----------------------------------------------------------------------------
;                 Load program from external EEPROM
; ----------------------------------------------------------------------------
; INPUT: BC = slot number 0...
; OUTPUT: NC = read error
; DESTROYS: AF, BC, DE, HL, PUSH1, PUSH2, PUSH3, R0
; ----------------------------------------------------------------------------

.global I2CLoad
I2CLoad:
	; store old content
; INPUT: BC = slot index 0..63
; OUTPUT: BC = byte offset (0..65535)
;	  HL = program address - 4
;	  PUSH2 = old content of (Program-4)
;	  PUSH3 = old content of (Program-2)
;	  CY = error
; DESTROYS: -
; STACK: 2
	rcall	I2CStore
	brcs	I2CError

	; preset size to read info header
	ldi	E,10
	ldi	D,0

	; initialize I2C interface
; OUTPUT: PUSH1_L = old bit rate register
; DESTROYS: F
; STACK: 2
	rcall	I2CInit

	; send address
; INPUT: BC = byte offset (0..32767)
; OUTPUT: F = status register bits 3..7
;	  ZY = status is OK, NZ = operation error
; DESTROYS: -
; STACK: 4
	clr	r0		; do not wait
	rcall	I2CAddr
	brne	I2CError

	; send START condition again
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2 (saves flags)
	rcall	I2CStart
	cpi	F,I2C_START
	brne	I2CError

	; send read command
	ldi	A,I2C_R
; INPUT: A = data byte to send
; OUTPUT: F = status register bits 3..7
; DESTROYS: -
; STACK: 2
	rcall	I2CSend
	cpi	F,I2C_RADDR_ACK
	brne	I2CError

	; prepare acknowledge flag
2:	sbiw	DE,1
	ldi	A,BIT(TWEA)
	brne	3f
	ldi	A,0
3:	adiw	DE,1

	; receive byte
; INPUT: A = flag BIT(TWEA) or 0
; OUTPUT: A = received byte
;	  F = status register bits 3..7
; DESTROYS: -
; STACK: 4
3:	rcall	I2CRecv
	cpi	F,I2C_RDATA_ACK		; both ACK and NACK are OK
	breq	4f
	cpi	F,I2C_RDATA_NACK
	brne	I2CError
4:	st	MHL+,A			; store received byte

	; check if header has been received
	ldi	A,hi8(Program)
	cpi	L,lo8(Program)
	cpc	H,A
	brne	6f

; ----- process program size

	sbiw	HL,4		; shift to variables

	; load program size -> AF
	ldd	F,MHL+0
	ldd	A,MHL+1

	; check minimal program size (4 bytes)
	cpi	F,4
	cpc	A,ZERO
	brcs	I2CError	; too small

	; check maximal program size (1000 bytes)
	ldi	E,hi8(1000)
	cpi	F,lo8(1000)
	cpc	A,E
	brcc	I2CError	; too big

	; get total size
	ldd	E,MHL+2
	ldd	D,MHL+3

	; check minimal total size
	cp	F,E
	cpc	A,D
	brcc	I2CError	; too small

	; set end of program
	add	F,L
	adc	A,H
	std	Y+DATA_VARSPTR,F
	std	Y+DATA_VARSPTR+1,A

	; check maximal size
	ldi	F,hi8(1001)
	cpi	E,lo8(1001)
	cpc	D,F
	brcc	I2CError	; too big

	; set end of variables
	movw	AF,DE
	add	F,L
	adc	A,H
	std	Y+DATA_EDITPTR,F
	std	Y+DATA_EDITPTR+1,A

	adiw	HL,4		; shift pointer back

	; check end of data
6:	sbiw	DE,1
	brne	2b

	; send STOP condition
; DESTROYS: F
; STACK: 2 (saves flags)
	rcall	I2CStop

	; restore old content
; INPUT: PUSH2 = old content of (Program-4)
;	 PUSH3 = old content of (Program-2)
; OUTPUT: HL = program address - 4
; DESTROYS: -
; STACK: 2 (saves flags)
	rcall	I2CRestore

	; set operation OK
	sec		; set operation OK

	; terminate I2C interface
; INPUT: PUSH1_L = old bit rate register
; DESTROYS: -
; STACK: 2 (saves flags)
	rjmp	I2CTerm
