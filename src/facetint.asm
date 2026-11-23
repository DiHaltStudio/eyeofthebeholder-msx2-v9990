; ============================================================================
; facetint.asm - The face of a poisoned, stoned or invisible character
;                through the fading tables of the original (script overlay)
; Assembler: Sjasm 0.42c
; ============================================================================

; ----------------------------------------------------------------------------
; FACE_TINT - DE = x, C = y (game coordinates), A = 0 green (poisoned),
;   1 blue (stone), 2 dark (invisible): the 32 x 32 face just drawn there
;   goes through that table of FT_TABLES (the fading tables gui_drawFaceShape
;   draws the face with), row by row: LMCM to RAM, LMMC back.
; ----------------------------------------------------------------------------
FACE_TINT:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl		; * 64
	ld a,c
	ld bc,FT_TABLES
	add hl,bc
	ld c,a
	ld (FT_TAB),hl
	ld hl,SCREEN_X
	add hl,de
	ld (FT_X),hl
	ld a,c
	add a,SCREEN_Y
	ld (FT_Y),a
	call V9_WAIT_CE
	ld b,32
.row:	push bc
	ld e,30h		; LMCM: the row to the CPU
	call .cmd
	ld hl,FT_BUF
	ld b,32
.rd:	in a,(V9_STATUS)	; transfer ready (bit 7)
	rla
	jr nc,.rd
	in a,(V9_CMD)
	ld (hl),a
	inc hl
	djnz .rd
	ld e,10h		; LMMC: the row back through the table
	call .cmd
	ld hl,FT_BUF
	ld b,32
.wr:	ld a,(hl)
	and 3Fh
	push hl
	ld hl,(FT_TAB)
	add a,l
	ld l,a
	adc a,h
	sub l
	ld h,a
	ld c,(hl)
	pop hl
.tr:	in a,(V9_STATUS)
	rla
	jr nc,.tr
	ld a,c
	out (V9_CMD),a
	inc hl
	djnz .wr
	call V9_WAIT_CE
	ld hl,FT_Y
	inc (hl)
	pop bc
	djnz .row
	ret
; .cmd - E = opcode: 32 x 1 at (FT_X, FT_Y) as source and destination
.cmd:	ld a,V9R_CMD_SX
	out (V9_REGSEL),a
	ld hl,(FT_X)
	ld a,(FT_Y)
	ld c,V9_REGDAT
	out (c),l		; SX
	out (c),h
	out (c),a		; SY
	ld a,(PN_STAGE)
	ld d,a
	out (c),d
	ld a,(FT_Y)
	out (c),l		; DX
	out (c),h
	out (c),a		; DY
	out (c),d
	ld d,0
	ld a,32
	out (c),a		; NX
	out (c),d
	ld a,1
	out (c),a		; NY
	out (c),d
	out (c),d		; ARG
	ld a,V9_LOG_COPY
	out (c),a		; LOG
	ld a,0FFh
	out (c),a		; WM
	out (c),a
	ld a,V9R_CMD_OP
	out (V9_REGSEL),a
	out (c),e
	ret
FT_TAB:		dw 0
FT_X:		dw 0
FT_Y:		db 0
FT_BUF:		ds 32
	include "../build/facetint.inc"
