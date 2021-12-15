
; ****************************************************************************
;
;                                 Data
;
; ****************************************************************************

#include "include.inc"

	.data

; ----- start of FLASH program header
.global	SlotSize
	.lcomm SlotSize,2	; size of this slot (must be multiply of SPM_PAGESIZE), 0xffff = end-mark

.global	SlotInx
	.lcomm SlotInx,1	; slot index 0..

; ----- start of EEPROM program header
.global ProgSize
	.lcomm ProgSize,2	; program size

.global TotalSize
	.lcomm TotalSize,2	; total size (program + variables)

; ----- start of program data
.global ProgStart
	.lcomm ProgStart,0	; start of program

