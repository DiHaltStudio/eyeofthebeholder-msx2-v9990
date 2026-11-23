; ============================================================================
; teleport.asm - The sparkles of the teleporters (drawTeleporter,
;                timerUpdateTeleporters), in page 3 (PAGE3.DAT)
; Assembler: Sjasm 0.42c
; ============================================================================

TELE_WALL:	equ 52		; _teleporterWallId (EOB1)

; DRAW_TELEPORT - A = visible block: a teleporter on the wall facing the
;   party gets its sparkles, two shapes at 13 places each (the pulse picks
;   which shape is where). Called from the shape pass (window of the block).
DRAW_TELEPORT:
	ld e,a
	ld d,0
	ld hl,VISWALL
	add hl,de
	ld a,(hl)
	cp TELE_WALL
	ret nz
	ld hl,DSC_DIMMAP
	add hl,de
	ld a,2
	sub (hl)
	ret c			; (the party's row: none)
	ld (TP_T),a
	ld a,1
	ld (TP_SEEN),a
	; x1 = DSC_ITEMSHPX[index] - TP_X[t], y1 = TP_Y[t]
	ld hl,DSC_ITEMSHPX
	add hl,de
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,(TP_T)
	ld c,a
	ld b,0
	ld hl,TP_X
	add hl,bc
	ld a,e
	sub (hl)
	ld e,a
	jr nc,.n
	dec d
.n:	ld (TP_X1),de
	ld hl,TP_Y
	add hl,bc
	ld a,(hl)
	ld (TP_Y1),a
	xor a
.i:	ld (TP_I),a
	ld a,(TP_T)
	add a,a
	ld hl,TP_I
	add a,(hl)
	ld (TP_D),a		; d = t * 2 + i
	ld c,0			; the first (t = 0, i = 0) 4 pixels up left
	or a
	jr nz,.o
	ld c,-4
.o:	ld a,c
	ld (TP_O),a
	ld a,(TP_D)
	ld hl,TP_PULSE
	xor (hl)
	ld (TP_SH),a		; shape d ^ pulse
	ld a,(TP_D)		; TELE_COORDS + d * 26
	ld l,a
	ld h,0
	add hl,hl
	ld e,l
	ld d,h			; * 2
	add hl,hl
	add hl,hl
	ld c,l
	ld b,h			; * 8
	add hl,hl		; * 16
	add hl,bc
	add hl,de		; * 26
	ld de,TELE_COORDS
	add hl,de
	ld b,13
.p:	push bc
	push hl
	ld a,(TP_O)
	add a,(hl)		; (coordinates < 128)
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld hl,(TP_X1)
	add hl,de
	ex de,hl		; x
	pop hl
	push hl
	inc hl
	ld a,(TP_Y1)
	add a,(hl)
	ld hl,TP_O
	add a,(hl)
	ld c,a			; y
	ld a,(TP_SH)
	ld hl,SHP_TELE0
	add a,l
	ld l,a
	adc a,h
	sub l
	ld h,a
	ld b,0
	call DRAW_SHAPE
	pop hl
	inc hl
	inc hl
	pop bc
	djnz .p
	ld a,(TP_I)
	inc a
	cp 2
	jr c,.i
	ret

; TELE_TICK - per tick: every 10 ticks the pulse changes and, if a
;   teleporter was drawn, the scene is drawn again
TELE_TICK:
	ld hl,TP_CNT
	dec (hl)
	ret nz
	ld (hl),10
	ld a,(TP_PULSE)
	xor 1
	ld (TP_PULSE),a
	ld a,(TP_SEEN)
	or a
	ret z
	xor a
	ld (TP_SEEN),a
	inc a
	ld (SCENE_DIRTY),a
	ret

TP_X:		db 28h, 1Ch, 12h
TP_Y:		db 0Dh, 15h, 1Ah
TP_CNT:		db 10
TP_PULSE:	db 0
TP_SEEN:	db 0
TP_T:		db 0
TP_I:		db 0
TP_D:		db 0
TP_O:		db 0
TP_SH:		db 0
TP_Y1:		db 0
TP_X1:		dw 0

	include "../build/teletab.inc"
