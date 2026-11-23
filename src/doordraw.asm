; ============================================================================
; doordraw.asm - The doors of the view (drawDoor, EoBEngine::drawDoorIntern),
;                in page 3 (PAGE3.DAT; their tables, doortab.inc, are in the
;                resident part): every group of levels has its own kind of door
;   levels 1-3, 12   one shape that rises (level 12: other heights)
;   levels 4-6       two halves that slide apart, the right one mirrored,
;                    in the window of the door frame
;   levels 7-9       a frame (the second door shape) and a gate that rises
;   levels 10-11     two parts that open up and down
; Assembler: Sjasm 0.42c
; ============================================================================

; DRAW_DOOR - A = visible block index, E = wall type (a door). Called from
;   the shape pass with the window of the block set (SHAPE_DIM).
DRAW_DOOR:
	ld (DOOR_INDEX),a
	ld a,e
	cp 32
	ret nc
	ld (DOOR_WALL),a
	ld l,a
	ld h,0
	ld de,DSC_DOORSHPINDEX
	add hl,de
	ld a,(hl)		; type
	ld hl,DOOR_INDEX
	ld e,(hl)
	ld d,0
	ld hl,DSC_DIMMAP
	add hl,de
	ld c,(hl)		; d = distance class
	add a,2
	sub c			; shape index: type + 2 - d
	ld (DOOR_D),bc		; (low byte: d)
	ld (DOOR_SI),a
	call DOOR_ENTRY
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (DOOR_SHP),de
	ld a,d
	and e
	inc a
	ret z			; no shape
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (DOOR_SW),de
	ld a,(hl)
	ld (DOOR_SWX),a
	inc hl
	ld a,(hl)
	ld (DOOR_SWY),a
	; w = DSC_SHAPECOORDS[(index * 5 + 4) * 2], x = 88 + w
	ld a,(DOOR_INDEX)
	ld e,a
	add a,a
	add a,a
	add a,e
	add a,4
	add a,a
	ld e,a
	ld d,0
	ld hl,DSC_SHAPECOORDS
	add hl,de
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (DOOR_W),de
	ld hl,88
	add hl,de
	ld (DOOR_X),hl
	; vertical window: the door frame (setDoorShapeDim)
	ld hl,DSC_DOORFRAMEIDX1
	call .frame
	ld hl,DSC_DOORFRAMEY1
	call .frame2
	ld (CLIP_Y1),a
	ld hl,DSC_DOORFRAMEIDX2
	call .frame
	ld hl,DSC_DOORFRAMEY2
	call .frame2
	ld (CLIP_Y2),a
	; the kind of door of the level
	ld a,(CUR_LEVEL)
	cp 4
	jr c,.std
	cp 7
	jp c,.split
	cp 10
	jp c,.gate
	cp 12
	jp c,.lift
.std:	; y = DoorY1[d] (DoorY6 on level 12) - h - the opening
	ld hl,DSC_DOORY1
	cp 12
	jr nz,.y1
	ld hl,DSC_DOORY6
.y1:	call DOOR_DY
	push af
	ld hl,(DOOR_SHP)
	call SHAPE_ENTRY
	pop af
	sub (ix+5)
	push af
	ld hl,DSC_DOORMULT1
	ld de,DSC_DOORMULT2
	call DOOR_OPENING
	ld b,a
	pop af
	sub b
	ld c,a
	call DOOR_XC
	ld hl,(DOOR_SHP)
	ld b,0
	call DRAW_SHAPE
	ld de,0
	jp .switch

.split:	; the window of the halves: the block window cut to DSC_DOOREXT
	ld a,(CLIP_X1)
	ld (DOOR_CX1),a
	ld a,(CLIP_X2)
	ld (DOOR_CX2),a
	ld a,(DOOR_INDEX)
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld hl,DSC_DOOREXT
	add hl,de
	ld e,(hl)
	inc hl
	ld a,(hl)		; x1 high
	inc hl
	or a
	jr nz,.x1		; negative (or beyond the view): the block's
	ld a,(CLIP_X1)
	cp e
	jr nc,.x1
	ld a,e
	ld (CLIP_X1),a
.x1:	ld e,(hl)
	inc hl
	ld a,(hl)		; x2 high
	or a
	jr nz,.x2
	ld a,(CLIP_X2)
	cp e
	jr c,.x2
	ld a,e
	ld (CLIP_X2),a
.x2:	ld hl,DSC_DOORY7
	call DOOR_DY
	push af
	ld hl,(DOOR_SHP)
	call SHAPE_ENTRY
	pop af
	sub (ix+5)
	ld c,a			; y = DoorY7[d] - h
	ld a,(ix+4)
	ld (DOOR_HW),a		; the width of a half
	push bc
	ld hl,DSC_DOORMULT3
	ld de,DSC_DOORMULT4
	call DOOR_OPENING
	ld (DOOR_V),a		; how far each half went
	pop bc
	; the left half at x - (v + w)
	ld hl,DOOR_HW
	add a,(hl)
	ld e,a
	ld a,0
	adc a,a
	ld d,a
	ld hl,(DOOR_X)
	or a
	sbc hl,de
	ex de,hl
	push bc
	ld hl,(DOOR_SHP)
	ld b,0
	call DRAW_SHAPE
	pop bc
	; the right one, mirrored, at x + v
	ld a,(DOOR_V)
	ld e,a
	ld d,0
	ld hl,(DOOR_X)
	add hl,de
	ex de,hl
	ld hl,(DOOR_SHP)
	ld b,1
	call DRAW_SHAPE
	ld a,(DOOR_CX1)
	ld (CLIP_X1),a
	ld a,(DOOR_CX2)
	ld (CLIP_X2),a
	ld a,(DOOR_V)		; the switch moves with the right half
	ld e,a
	ld d,0
	jp .switch

.gate:	; the frame (shape index + 3) at y = DoorY3[d] - its h
	call DOOR_SHP2
	jr z,.nofr
	push hl
	call SHAPE_ENTRY
	ld hl,DSC_DOORY3
	call DOOR_DY
	sub (ix+5)
	ld c,a
	call DOOR_XC
	pop hl
	ld b,0
	call DRAW_SHAPE
.nofr:	; the gate at y = DoorY3[d] - the opening
	ld hl,DSC_DOORMULT1
	ld de,DSC_DOORMULT2
	call DOOR_OPENING
	push af
	ld hl,DSC_DOORY3
	call DOOR_DY
	pop bc
	sub b
	ld c,a
	push bc
	ld hl,(DOOR_SHP)
	call SHAPE_ENTRY
	call DOOR_XC
	pop bc
	ld hl,(DOOR_SHP)
	ld b,0
	call DRAW_SHAPE
	ld de,0
	jr .switch

.lift:	; v = - opening: the upper part at y = DoorY4[d] + 2v, the lower one
	; (shape index + 3) at y = DoorY5[d] - ((v >> 3) + (v >> 2))
	ld hl,DSC_DOORMULT5
	ld de,DSC_DOORMULT6
	call DOOR_OPENING
	ld (DOOR_V),a
	ld hl,(DOOR_SHP)
	call SHAPE_ENTRY
	call DOOR_XC
	ld (DOOR_XL),de
	ld hl,DSC_DOORY4
	call DOOR_DY
	ld hl,DOOR_V
	sub (hl)
	sub (hl)
	ld c,a
	ld hl,(DOOR_SHP)
	ld b,0
	call DRAW_SHAPE
	ld a,(DOOR_V)
	neg			; v
	ld b,a
	sra a
	sra a
	ld c,a			; v >> 2
	ld a,b
	sra a
	sra a
	sra a			; v >> 3
	add a,c
	ld b,a
	ld hl,DSC_DOORY5
	call DOOR_DY
	sub b
	ld c,a
	call DOOR_SHP2
	jr z,.l0
	ld de,(DOOR_XL)
	ld b,0
	call DRAW_SHAPE
.l0:	ld de,0
	; (falls into .switch)

.switch:
	; DE = its shift: the switch, when the wall kept its preset decoration
	; slot (-1), at (switch x + w + DE, switch y)
	ld a,(DOOR_WALL)
	ld h,(LEVELDAT+D_WSHAPE)>>8
	ld l,a
	ld a,(hl)
	cp 0FFh
	jr nz,.end
	ld a,(DOOR_SWX)
	ld l,a
	ld h,0
	add hl,de
	ld de,(DOOR_W)
	add hl,de
	ex de,hl
	ld a,(DOOR_SWY)
	ld c,a
	ld hl,(DOOR_SW)
	ld b,0
	call DRAW_SHAPE
.end:	xor a
	ld (CLIP_Y1),a
	ld a,VIEW_H
	ld (CLIP_Y2),a
	ret
; .frame - HL = DSC_DOORFRAMEIDXn -> A = its entry of CUR_LEVEL + d
.frame:	ld a,(CUR_LEVEL)
	dec a
	add a,l
	ld l,a
	adc a,h
	sub l
	ld h,a
	ld a,(DOOR_D)
	add a,(hl)
	ret
; .frame2 - HL = DSC_DOORFRAMEYn, A = index -> A = its value
.frame2:
	add a,l
	ld l,a
	adc a,h
	sub l
	ld h,a
	ld a,(hl)
	ret

; DOOR_ENTRY - A = door shape index -> HL = its entry in D_DOORS
DOOR_ENTRY:
	ld l,a
	ld h,0
	ld e,a
	ld d,h
	add hl,hl
	add hl,de		; * 3
	add hl,hl		; * 6
	ld de,LEVELDAT+D_DOORS
	add hl,de
	ret

; DOOR_SHP2 -> HL = the shape of door shape index + 3; Z: none
DOOR_SHP2:
	ld a,(DOOR_SI)
	add a,3
	call DOOR_ENTRY
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	ld a,h
	and l
	inc a
	ret

; DOOR_DY - HL = a table per distance class -> A = its entry for d
DOOR_DY:
	ld a,(DOOR_D)
	add a,l
	ld l,a
	adc a,h
	sub l
	ld h,a
	ld a,(hl)
	ret

; DOOR_XC - IX = shape entry -> DE = DOOR_X - w / 2
DOOR_XC:
	ld a,(ix+4)
	srl a
	ld e,a
	ld d,0
	ld hl,(DOOR_X)
	or a
	sbc hl,de
	ex de,hl
	ret

; DOOR_OPENING - HL = multipliers, DE = values for the walls >= 30 (per
;   distance class) -> A = how far the door is open:
;   (wall - DSC_DOORSCALEOFFS[wall]) * mult[d], or value[d]
DOOR_OPENING:
	ld a,(DOOR_WALL)
	cp 30
	jr c,.s
	ex de,hl
	jr DOOR_DY
.s:	call DOOR_DY
	ld b,a
	ld a,(DOOR_WALL)
	ld l,a
	ld h,0
	ld de,DSC_DOORSCALEOFFS
	add hl,de
	ld a,(DOOR_WALL)
	sub (hl)		; opening step
	ld c,a
	xor a
	inc c
.m:	dec c
	ret z
	add a,b
	jr .m

DOOR_INDEX:	db 0
DOOR_WALL:	db 0
DOOR_D:		dw 0
DOOR_SI:	db 0
DOOR_SHP:	dw 0
DOOR_SW:	dw 0
DOOR_SWX:	db 0
DOOR_SWY:	db 0
DOOR_W:		dw 0
DOOR_X:		dw 0
DOOR_XL:	dw 0
DOOR_V:		db 0
DOOR_HW:	db 0
DOOR_CX1:	db 0
DOOR_CX2:	db 0
