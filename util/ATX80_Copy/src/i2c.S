
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
; DESTROYS: R22
; ----------------------------------------------------------------------------
; Note: SDA and SCL pins are already initialized to use internal pull-ups.
; Internal pull-ups are about 36 kOhm and it supports only low speed interface.

I2CInit:
	; set status register (set prescaler to value 4^1=4)
	ldi	R22,1
#ifdef MCU8
	out	_SFR_IO_ADDR(TWSR),R22
#else
	sts	TWSR,R22
#endif

	; set bit rate register, freq = F_CPU/(16 + 2*TWBR*4^TWPS)
	;   freq = 24000000/(16 + 2*98*4^1) = 30000 Hz
	ldi	R22,98
#ifdef MCU8
	out	_SFR_IO_ADDR(TWBR),R22
#else
	sts	TWBR,R22
#endif

	; set control register (enable TWI)
	ldi	R22,BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),R22
#else
	sts	TWCR,R22
#endif
	ret

; ----------------------------------------------------------------------------
;               Terminate I2C interface after transmission
; ----------------------------------------------------------------------------
; DESTROYS: -
; ----------------------------------------------------------------------------

.global I2CTerm
I2CTerm:
	; short delay to stop operations
; INPUT: R25:R24=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: R25, R24
	push	r24
	push	r25
	ldi	r24,lo8(1000)
	ldi	r25,hi8(1000)
	rcall	waitus
	pop	r25
	pop	r24

	; disable TWI interface
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),ZERO
#else
	sts	TWCR,ZERO
#endif
	ret

; ----------------------------------------------------------------------------
;                        Send START condition
; ----------------------------------------------------------------------------
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
; ----------------------------------------------------------------------------

I2CStart:
	; reset TWINT flag, send START condition, enable TWI interface
	ldi	R22,BIT(TWINT) | BIT(TWSTA) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),R22
#else
	sts	TWCR,R22
#endif

; I2CWait must follow

; ----------------------------------------------------------------------------
;                   Wait to complete current operation
; ----------------------------------------------------------------------------
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
; ----------------------------------------------------------------------------

I2CWait:
	; wait while TWINT flag is clear
#ifdef MCU8
	in	R22,_SFR_IO_ADDR(TWCR)
#else
	lds	R22,TWCR
#endif
	sbrs	R22,TWINT
	rjmp	I2CWait

; I2CStatus must follow

; ----------------------------------------------------------------------------
;                Load status register (without prescaler bits)
; ----------------------------------------------------------------------------
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
; ----------------------------------------------------------------------------

I2CStatus:
#ifdef MCU8
	in	R22,_SFR_IO_ADDR(TWSR)
#else
	lds	R22,TWSR
#endif
	andi	R22,0xf8

	; we don't need to distinguish between first START and repeated START
	cpi	R22,I2C_START2	; repeated START
	brne	2f
	ldi	R22,I2C_START	; return first START

	; when receiving, no difference between ACK and NACK
2:	cpi	R22,I2C_RDATA_NACK
	brne	4f
	ldi	R22,I2C_RDATA_ACK
4:	ret

; ----------------------------------------------------------------------------
;                        Send STOP condition
; ----------------------------------------------------------------------------
; DESTROYS: R22
; ----------------------------------------------------------------------------

I2CStop:
	; reset TWINT flag, send STOP condition, enable TWI interface
	ldi	R22,BIT(TWINT) | BIT(TWSTO) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),R22
#else
	sts	TWCR,R22
#endif
	ret

; ----------------------------------------------------------------------------
;                         Receive byte
; ----------------------------------------------------------------------------
; INPUT: R23 = flag BIT(TWEA) (= not last byte) or 0 (= last byte)
; OUTPUT: R23 = received byte
;	  R22 = status register bits 3..7
; DESTROYS: -
; ----------------------------------------------------------------------------

I2CRecv:
	; reset TWINT flag, enable TWI interface
	ori	R23,BIT(TWINT) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),R23
#else
	sts	TWCR,R23
#endif

	; wait to complete operation
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rcall	I2CWait

	; receive data byte
#ifdef MCU8
	in	R23,_SFR_IO_ADDR(TWDR)
#else
	lds	R23,TWDR
#endif
	ret

; ----------------------------------------------------------------------------
;                         Send byte (address or data)
; ----------------------------------------------------------------------------
; INPUT: R23 = data byte to send
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
; ----------------------------------------------------------------------------

I2CSend:
	; send data byte
#ifdef MCU8
	out	_SFR_IO_ADDR(TWDR),R23
#else
	sts	TWDR,R23
#endif

	; reset TWINT flag, enable TWI interface
	ldi	R22,BIT(TWINT) | BIT(TWEN)
#ifdef MCU8
	out	_SFR_IO_ADDR(TWCR),R22
#else
	sts	TWCR,R22
#endif

	; wait
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rjmp	I2CWait

; ----------------------------------------------------------------------------
;                          Prepare slot index
; ----------------------------------------------------------------------------
; INPUT: R24 = slot index 0..
; OUTPUT: R25:R24 = slot offset 0..65535
;	  R0 = 0 do not wait NACK (first run)
; DESTROYS: -
; ----------------------------------------------------------------------------

I2CSlot:
	; prepare slot offset -> R25:R24
	sts	SlotInx,r24	; store slot index
	mov	r25,r24		; slot * 256
	clr	r24
	add	r25,r25		; slot * 512
	add	r25,r25		; slot * 1024
	clr	r0		; flag - do not wait at first pass
	ret

; ----------------------------------------------------------------------------
;                          Send address
; ----------------------------------------------------------------------------
; INPUT: R25:R24 = byte offset (0..65535)
;	 R0 = flag: 1=wait if NACK (wait previous operation), 0=do not wait NACK (first run)
; OUTPUT: R22 = status register bits 3..7
;	  ZY = status is OK, NZ = operation error
; DESTROYS: -
; ----------------------------------------------------------------------------

I2CAddr:
	; save R23
	push	R23

	; send START condition
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
2:	rcall	I2CStart
	cpi	R22,I2C_START
	brne	8f

	; send command (write operation)
	ldi	R23,I2C_W
; INPUT: R23 = data byte to send
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rcall	I2CSend
	cpi	R22,I2C_WADDR_NACK
	sbrc	r0,0			; skip waiting if R0=0
	breq	2b			; wait (only if R0=1)
	cpi	R22,I2C_WADDR_ACK
	brne	8f

	; send start address HIGH
	mov	R23,R25
; INPUT: R23 = data byte to send
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rcall	I2CSend
	cpi	R22,I2C_WDATA_ACK
	brne	8f

	; send start address LOW
	mov	R23,R24
; INPUT: R23 = data byte to send
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rcall	I2CSend
	cpi	R22,I2C_WDATA_ACK

	; restore R23
8:	pop	R23
	ret

; ----------------------------------------------------------------------------
;                 Save program to external EEPROM
; ----------------------------------------------------------------------------
; INPUT: R24 = slot index 0..63
;	 R27:R26 = data size
;	 R31:R30 = data in ROM
; ----------------------------------------------------------------------------

.global I2CSave
I2CSave:
	; initialize I2C interface
; DESTROYS: R22
	rcall	I2CInit

	; prepare slot index
; INPUT: R24 = slot index 0..63
; OUTPUT: R25:R24 = slot offset 0..65535
;	  R0 = 0 do not wait NACK (first run)
; DESTROYS: -
	rcall	I2CSlot

	; send address
; INPUT: R25:R24 = byte offset (0..65535)
;	 R0 = flag: 1=wait if NACK (wait previous operation), 0=do not wait NACK (first run)
; OUTPUT: R22 = status register bits 3..7
;	  ZY = status is OK, NZ = operation error
; DESTROYS: -
2:	rcall	I2CAddr
	brne	I2CError2

	; send one page of data
4:	lpm	R23,Z+
; INPUT: R23 = data byte to send
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rcall	I2CSend
	cpi	R22,I2C_WDATA_ACK
	brne	I2CError2

	; next byte at this page
	adiw	R24,1		; increment destination offset
	sbiw	R26,1		; decrement size counter
	breq	6f		; end of data

	mov	R23,R24		; destination offset LOW
	andi	R23,I2C_PAGEMASK ; check page align
	brne	4b		; next byte at this page

	; send STOP condition
; DESTROYS: R22
	rcall	I2CStop

	; delay (required to start write operation)
	; - Requires min. 50 us if checking NACK, to start write operation
	; - Requires min. 4 ms if not checking NACK, to complete write operation
	push	r24
	push	r25
	ldi	R24,lo8(I2C_DELAY)
	ldi	R25,hi8(I2C_DELAY)
; INPUT: R25:R24=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: R25:R24
	rcall	waitus
	pop	r25
	pop	r24

	; prepare for next pass
	clr	r0
	inc	r0		; flag - wait
	rjmp	2b

	; send last STOP condition
; DESTROYS: R22
6:	rcall	I2CStop

	; wait to complete write operation
	ldi	R24,lo8(I2C_WAIT)
	ldi	R25,hi8(I2C_WAIT)
; INPUT: R25:R24=delay in [us] (2..65535, 0=65536 us, 1=65537 us)
; DESTROYS: R25:R24
; STACK: 4
	rcall	waitus

	; set operation OK
	sec		; set operation OK

	; terminate I2C interface
; DESTROYS: -
	rjmp	I2CTerm

I2CError2:
	rjmp	I2CError

; ----------------------------------------------------------------------------
;                 Load program from external EEPROM
; ----------------------------------------------------------------------------
; INPUT: R24 = slot index 0..63
; OUTPUT: NC = read error
; DESTROYS: R31, R30, R25, R24, R23, R22, R1, R0
; ----------------------------------------------------------------------------

.global I2CLoad
I2CLoad:

; ----- initialize I2C interface
; DESTROYS: R22
	rcall	I2CInit

; ----- start loading

	; prepare slot index
; INPUT: R24 = slot index 0..63
; OUTPUT: R25:R24 = slot offset 0..65535
;	  R0 = 0 do not wait NACK (first run)
; DESTROYS: -
	rcall	I2CSlot

	; send address
; INPUT: R25:R24 = byte offset (0..65535)
;	 R0 = flag: 1=wait if NACK (wait previous operation), 0=do not wait NACK (first run)
; OUTPUT: R22 = status register bits 3..7
;	  ZY = status is OK, NZ = operation error
; DESTROYS: -
	rcall	I2CAddr
	brne	I2CError2

	; send START condition again
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rcall	I2CStart
	cpi	R22,I2C_START
	brne	I2CError2

	; send read command
	ldi	R23,I2C_R
; INPUT: R23 = data byte to send
; OUTPUT: R22 = status register bits 3..7
; DESTROYS: -
	rcall	I2CSend
	cpi	R22,I2C_RADDR_ACK
	brne	I2CError2

; ----- load header

	; prepare to load header
	ldi	r24,4
	ldi	r30,lo8(ProgSize)
	ldi	r31,hi8(ProgSize)

	; receive byte
; INPUT: R23 = flag BIT(TWEA) (= not last byte) or 0 (= last byte)
; OUTPUT: R23 = received byte
;	  R22 = status register bits 3..7
; DESTROYS: -
2:	ldi	R23,BIT(TWEA)
	rcall	I2CRecv			; receive byte
	cpi	R22,I2C_RDATA_ACK	; both ACK and NACK are OK
	brne	I2CError2
	st	Z+,R23			; store received byte

	; next byte
	dec	r24
	brne	2b

; ----- process header

	sbiw	r30,4		; shift to start of header

	; load program size -> R23:R22
	ld	R22,Z+
	ld	R23,Z+

	; check minimal program size (4 bytes)
	cpi	R22,4
	cpc	R23,ZERO
	brcs	I2CError	; too small

	; check maximal program size (1000 bytes)
	ldi	R24,hi8(1000)
	cpi	R22,lo8(1000)
	cpc	R23,R24
	brcc	I2CError	; too big

	; get total size -> R25:R24
	ld	R24,Z+
	ld	R25,Z+

	; check minimal total size
	cp	R22,R24
	cpc	R23,R25
	brcc	I2CError	; too small

	; check maximal size
	ldi	R22,hi8(1001)
	cpi	R24,lo8(1001)
	cpc	R25,R22
	brcc	I2CError	; too big
	sbiw	r24,4		; total size without header -> R25:R24

	; prepare slot size -> R23:R22
	movw	r22,r24
	subi	r22,lo8(-(4+3+SPM_PAGESIZE-1)) ; add header and round up to page size
	sbci	r23,hi8(-(4+3+SPM_PAGESIZE-1))
	andi	r22,~(SPM_PAGESIZE-1) ; round down to page size
	sts	SlotSize,r22	; store slot size
	sts	SlotSize+1,r23

; ----- load program

	; prepare acknowledge flag
2:	sbiw	r24,1
	ldi	R23,BIT(TWEA)
	brne	3f
	ldi	R23,0
3:	adiw	r24,1

	; receive byte
; INPUT: R23 = flag BIT(TWEA) (= not last byte) or 0 (= last byte)
; OUTPUT: R23 = received byte
;	  R22 = status register bits 3..7
; DESTROYS: -
	ldi	R23,BIT(TWEA)
	rcall	I2CRecv			; receive byte
	cpi	R22,I2C_RDATA_ACK	; both ACK and NACK are OK
	brne	I2CError
	st	Z+,R23			; store received byte

	; next byte
	sbiw	r24,1		; R25:R24 size counter
	brne	2b

; ----- stop loading

	rcall	I2CError	; stop operations

	; clear rest of slot
	lds	r24,SlotSize
	lds	r25,SlotSize+1
	subi	r24,lo8(-(SlotSize))
	sbci	r25,hi8(-(SlotSize))
	sub	r24,r30
	sbc	r25,r31
	ldi	r23,0xff
	rjmp	6f

4:	st	Z+,r23
6:	sbiw	r24,1
	brpl	4b

	; operation OK
	sec		; set operation OK
	ret

I2CError:

	; send STOP condition
; DESTROYS: R22
	rcall	I2CStop

	; terminate I2C interface
	; - needed to terminate last STOP condition
; DESTROYS: -
	rcall	I2CTerm

	; operation error
	clc		; error, clear carry
	ret
