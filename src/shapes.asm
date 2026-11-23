; ============================================================================
; shapes.asm - Shapes over the 3D view: decorations, doors, compass
; Assembler: Sjasm 0.42c
;
; A shape is a rectangle stored in VRAM with colour 0 = transparent; the
; LEVELn.DAT shape table (D_SHAPES, 8 bytes each) gives vx, vy, w, h and the
; id of its mirrored twin (FFFFh = none). Shapes with vy = FFFEh live in RAM
; (decorations, monsters): vx is their address in page 2 and byte 6 their
; segment index; cache.asm uploads them to VRAM on demand.
;
; Everything is copied into VIEW_BUF with LMMM + transparency, clipped to
; the window CLIP_X1..CLIP_X2 / CLIP_Y1..CLIP_Y2 (pixels of the 176x120 view),
; which SHAPE_DIM computes per visible block like setLevelShapesDim does.
; ============================================================================

SHAPE_NONE:	equ 0FFFFh

; ----------------------------------------------------------------------------
; SHAPE_DIM - A = visible block index -> CLIP_X1 / CLIP_X2 (pixels)
;   NZ if the window is not empty
; ----------------------------------------------------------------------------
SHAPE_DIM:
	; once per scene and block: the windows are kept in DIM_MEMO
	ld e,a
	ld d,0
	ld hl,DIM_MEMO
	add hl,de
	add hl,de
	ld e,a
	ld a,(hl)
	inc a
	jr z,.calc
	dec a
	ld (CLIP_X1),a
	inc hl
	ld a,(hl)
	ld (CLIP_X2),a
	jp DIM_RESULT
.calc:	push hl
	ld a,e
	call SHAPE_DIM_CALC
	pop hl
	ld a,(CLIP_X1)
	ld (hl),a
	inc hl
	ld a,(CLIP_X2)
	ld (hl),a
	jp DIM_RESULT

; DIM_FORGET - a new scene: the windows of SHAPE_DIM are computed again
DIM_FORGET:
	ld hl,DIM_MEMO
	ld b,18*2
.f:	ld (hl),0FFh
	inc hl
	djnz .f
	ret

; SHAPE_DIM_CALC - A = visible block: the window from the blocks in front
;   of it (DSC_DIMLIST: only the pairs of setLevelShapesDim that clip)
SHAPE_DIM_CALC:
	ld l,a
	ld h,0
	add hl,hl
	ld de,DSC_DIMLIST
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a			; HL = its list: (i, t, door x1, door x2)
	ld bc,22*256+0		; B = x2, C = x1 (blocks)
.loop:	ld a,(hl)
	cp 0FFh
	jr z,.end
	push hl
	ld e,a
	ld d,0
	ld hl,VISWALL
	add hl,de
	ld l,(hl)		; the wall facing us of visible block i
	ld h,(LEVELDAT+D_WFLAGS)>>8
	bit 3,(hl)
	jr nz,.door
	ld h,(LEVELDAT+D_WVMP)>>8
	ld a,(hl)
	pop hl
	inc hl
	or a
	jr z,.next		; no wall piece: no clipping
	ld a,(hl)		; t (signed)
	cp -40
	jr z,.next
	cp -41
	jr z,.empty
	or a
	jp m,.neg
	cp b			; t > 0: x2 = min(x2, t)
	jr nc,.check
	ld b,a
	jr .check
.neg:	neg			; t < 0: x1 = max(x1, -t)
	cp c
	jr c,.check
	ld c,a
.check:	ld a,b
	cp c
	jr c,.end		; x2 < x1: stop
.next:	inc hl
	inc hl
	inc hl
	jr .loop
.door:	pop hl			; door: the pair (x1, x2)
	inc hl
	inc hl
	ld a,(hl)
	cp c
	jr c,.d2
	ld c,a
.d2:	inc hl
	ld a,(hl)
	cp b
	jr nc,.d3
	ld b,a
.d3:	inc hl
	ld a,b
	cp c
	jr nc,.loop
	jr .end
.empty:	ld bc,0*256+22
.end:	ld a,c
	add a,a
	add a,a
	add a,a
	ld (CLIP_X1),a
	ld a,b
	add a,a
	add a,a
	add a,a
	ld (CLIP_X2),a
DIM_RESULT:
	ld a,(CLIP_X2)
	ld hl,CLIP_X1
	cp (hl)			; NZ when x2 > x1
	ret nc
	xor a			; x2 < x1: empty too
	ret

; ----------------------------------------------------------------------------
; DRAW_SHAPE - HL = shape id, DE = x (signed), C = y (signed), B = 1 mirrored
;   Copies the shape clipped to CLIP_X1..CLIP_X2 / CLIP_Y1..CLIP_Y2.
; ----------------------------------------------------------------------------
DRAW_SHAPE:
	res 0,e			; x &= ~1 (EOB1)
	ld (SHP_X),de
	ld a,c
	ld (SHP_Y),a
	rla
	sbc a,a
	ld (SHP_Y+1),a
	ld (SHP_ID),hl
	call SHAPE_ENTRY	; IX = entry
	ret c
	ld a,(ix+3)
	inc a			; vy = FFFEh: RAM shape
	jr nz,.vram
	call MCACHE_GET		; RAM shape: IX = its cached copy
	jr .noflip
.vram:	ld a,b
	or a
	jr z,.noflip
	ld l,(ix+6)
	ld h,(ix+7)		; the mirrored twin
	ld a,h
	and l
	inc a
	ret z			; no twin
	call SHAPE_ENTRY
	ret c
.noflip:
	; --- horizontal clip ---
	ld hl,(SHP_X)
	ld a,(CLIP_X1)
	ld e,a
	ld d,0
	or a
	sbc hl,de		; x - x1
	jp p,.xok		; x >= x1: no left clip
	; left clip: x0 = x1, source offset = x1 - x
	ld a,l
	cpl
	inc a
	ld (SHP_SRCX),a		; -(x - x1)
	ld hl,0
	jr .xr
.xok:	xor a
	ld (SHP_SRCX),a
	; hl = x - x1 (>= 0)
.xr:	add hl,de		; hl = x0 (absolute)
	ld (SHP_X0),hl
	ld a,(ix+4)		; w
	ld e,a
	ld d,0
	ld hl,(SHP_X)
	add hl,de		; x + w
	ld a,(CLIP_X2)
	ld e,a
	or a
	sbc hl,de		; (x + w) - x2
	jr z,.x2ok
	jp m,.x2ok
	ld de,(CLIP_X2)
	ld d,0
	ld hl,0
	add hl,de		; x1 = x2
	jr .width
.x2ok:	ld hl,(SHP_X)
	ld e,(ix+4)
	ld d,0
	add hl,de
.width:	ld de,(SHP_X0)
	or a
	sbc hl,de		; nx = x1 - x0
	ret z
	ret m
	ld a,h
	or a
	ret nz
	ld a,l
	ld (SHP_NX),a
	; --- vertical clip ---
	ld hl,(SHP_Y)
	ld a,(CLIP_Y1)
	ld e,a
	ld d,0
	or a
	sbc hl,de
	jp p,.yok
	ld a,l
	cpl
	inc a
	ld (SHP_SRCY),a
	ld hl,0
	jr .yr
.yok:	xor a
	ld (SHP_SRCY),a
.yr:	add hl,de
	ld (SHP_Y0),hl
	ld e,(ix+5)
	ld hl,(SHP_Y)
	add hl,de		; y + h
	ld a,(CLIP_Y2)
	ld e,a
	or a
	sbc hl,de
	jr z,.y2ok
	jp m,.y2ok
	ld hl,0
	add hl,de
	jr .height
.y2ok:	ld hl,(SHP_Y)
	ld e,(ix+5)
	add hl,de
.height: ld de,(SHP_Y0)
	or a
	sbc hl,de
	ret z
	ret m
	ld a,l
	ld (SHP_NY),a
	; --- command ---
	ld a,(SHP_SRCX)
	ld e,a
	ld d,0
	ld l,(ix+0)
	ld h,(ix+1)
	add hl,de
	ld (CMD),hl		; sx
	ld a,(SHP_SRCY)
	ld e,a
	ld l,(ix+2)
	ld h,(ix+3)
	add hl,de
	ld (CMD+2),hl		; sy
	ld hl,(SHP_X0)
	ld de,VIEWBUF_X
	add hl,de
	ld (CMD+4),hl		; dx
	ld hl,(SHP_Y0)
	ld de,VIEWBUF_Y
	add hl,de
	ld (CMD+6),hl		; dy
	ld a,(SHP_NX)
	ld l,a
	ld h,0
	ld (CMD+8),hl
	ld a,(SHP_NY)
	ld l,a
	ld (CMD+10),hl
	ld hl,CMD
	ld a,V9_LOG_TCOPY
	jp V9_LMMM

; SHAPE_ENTRY - HL = shape id -> IX = entry; C set if none/not stored
;   ids below GLOBAL_ID: level shapes (LEVELDAT+D_SHAPES); from GLOBAL_ID on:
;   interface shapes (GLOBALDAT)
SHAPE_ENTRY:
	ld a,h
	and l
	inc a
	scf
	ret z
	ld de,SHP_BLUEICON0
	or a
	sbc hl,de
	jr c,.regular
	call XCALL
	dw FX_BLUE_ENTRY
	ret
.regular:
	add hl,de
	ld a,h
	cp GLOBAL_ID>>8
	jr c,.level
	sub GLOBAL_ID>>8
	ld h,a
	ld de,GLOBALDAT+2
	jr .ent
.level:	ld de,LEVELDAT+D_SHAPES
.ent:	add hl,hl
	add hl,hl
	add hl,hl
	add hl,de
	push hl
	pop ix
	ld a,(ix+0)
	and (ix+1)
	inc a
	scf
	ret z			; vx = FFFFh: dropped shape
	or a
	ret

; SHAPE_W - HL = shape id -> A = width (0 if none)
SHAPE_W:
	call SHAPE_ENTRY
	ld a,0
	ret c
	ld a,(ix+4)
	ret

; ----------------------------------------------------------------------------
; DRAW_DECORATIONS - A = visible block index (drawDecorations)
; ----------------------------------------------------------------------------
DRAW_DECORATIONS:
	ld (DEC_INDEX),a
	ld a,1
.pass:	ld (DEC_PASS),a		; i = 1 then 0
	ld a,(DEC_INDEX)
	add a,a
	ld hl,DEC_PASS
	add a,(hl)
	ld (DEC_S),a		; s = index*2 + i
	ld e,a
	ld d,0
	ld hl,DSC_WALLMAPPING
	add hl,de
	ld a,(hl)
	or a
	jp z,.nextpass
	dec a
	ld c,a
	ld a,(DEC_INDEX)
	call WALL_TYPE
	ld h,(LEVELDAT+D_WSHAPE)>>8
	ld l,a
	ld a,(hl)
	cp 0FFh
	jp z,.nextpass
.chain:	or a
	jp z,.nextpass
	dec a
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl		; *64
	ld de,LEVELDAT+D_DECOS
	add hl,de
	push hl
	pop iy			; IY = decoration entry
	ld a,(DEC_S)
	ld e,a
	ld d,0
	ld hl,DSC_SHAPEINDEX
	add hl,de
	ld a,(hl)		; ix (signed, 1-based slot)
	ld b,a
	ld a,(DEC_PASS)
	or a
	jr nz,.noneg
	ld a,(iy+0)		; flags
	bit 0,a
	jr nz,.neg
	bit 1,a
	jr z,.noneg
	ld a,(PROCFLAG)
	or a
	jr z,.noneg
.neg:	ld a,b
	neg
	ld b,a
.noneg:	ld a,b
	ld (DEC_IX),a
	or a
	jp p,.pos
	neg
.pos:	dec a			; shpIx
	ld l,a
	ld h,0
	ld e,a
	add hl,hl
	add hl,de		; *3
	add hl,hl		; *6
	push iy
	pop de
	add hl,de
	ld de,4
	add hl,de		; slot: shape, x, y
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,d
	and e
	inc a
	jp z,.follow		; no shape in this slot
	push de			; shape id
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (DEC_SX),de
	ld a,(hl)
	ld (DEC_SY),a
	; x = 0 or, in the facing pass, the block's x offset
	ld hl,0
	ld a,(DEC_PASS)
	or a
	jr nz,.xdone
	ld a,(DEC_INDEX)
	bit 2,(iy+0)
	jr z,.dscx
	add a,a
	add a,a
	ld e,a
	ld a,(DEC_INDEX)
	add a,e			; *5
	add a,4
	add a,a			; (index*5+4)*2
	ld e,a
	ld d,0
	ld hl,DSC_SHAPECOORDS
	add hl,de
	add hl,de		; words
	jr .ldx
.dscx:	add a,a
	ld e,a
	ld d,0
	ld hl,DSC_X
	add hl,de
.ldx:	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
.xdone:	pop de			; DE = shape id
	ld a,(DEC_IX)
	or a
	jp m,.mirror
	ld bc,(DEC_SX)
	add hl,bc		; x += shapeX
	ex de,hl		; HL = shape id, DE = x
	ld a,(DEC_SY)
	ld c,a
	ld b,0
	push iy
	call DRAW_SHAPE
	pop iy
	jr .follow
.mirror:
	push hl
	ex de,hl
	push hl
	call SHAPE_W		; A = w
	pop hl			; shape id
	pop de			; x
	ex de,hl		; HL = x, DE = shape id
	ld bc,176
	add hl,bc
	ld bc,(DEC_SX)
	or a
	sbc hl,bc		; + 176 - shapeX
	ld c,a
	ld b,0
	or a
	sbc hl,bc		; - w
	ex de,hl		; HL = id, DE = x
	ld a,(DEC_SY)
	ld c,a
	ld b,1
	push iy
	call DRAW_SHAPE
	pop iy
.follow:
	ld a,(iy+1)		; next
	jp .chain
.nextpass:
	ld a,(DEC_PASS)
	or a
	ret z
	xor a
	jp .pass

; DRAW_DOOR: in page 3 (doordraw.asm)

; ----------------------------------------------------------------------------
; DRAW_COMPASS - the three needles of the current facing, on the screen
;   (reads LEVELDAT: from an overlay, through WCALL)
; ----------------------------------------------------------------------------
DRAW_COMPASS:
	ld a,(BOOK_ON)		; the spellbook covers it
	or a
	ret nz
	call PTR_KEEP_ARROW
	ld b,3
	ld c,0
.lp:	push bc
	ld a,c
	add a,a
	add a,a
	ld hl,CUR_DIR
	add a,(hl)
	ld l,a
	ld h,0
	call SHAPE_ENTRY
	pop bc
	jr c,.next
	ld l,(ix+0)
	ld h,(ix+1)
	ld (CMD),hl
	ld l,(ix+2)
	ld h,(ix+3)
	ld (CMD+2),hl
	ld hl,COMPASS_X
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	add a,SCREEN_X
	ld l,a
	ld h,0
	ld (CMD+4),hl
	ld hl,COMPASS_Y
	add hl,de
	ld a,(hl)
	add a,SCREEN_Y
	ld l,a
	ld h,0
	ld (CMD+6),hl
	ld l,(ix+4)
	ld h,0
	ld (CMD+8),hl
	ld l,(ix+5)
	ld (CMD+10),hl
	push bc
	ld hl,CMD
	ld a,V9_LOG_TCOPY
	call V9_LMMM
	pop bc
.next:	inc c
	djnz .lp
	ret

CLIP_X1:	db 0
CLIP_X2:	db VIEW_W
CLIP_Y1:	db 0
CLIP_Y2:	db VIEW_H
DIM_MEMO:	ds 18*2
SHP_X:		dw 0
SHP_Y:		dw 0
SHP_X0:		dw 0
SHP_Y0:		dw 0
SHP_SRCX:	db 0
SHP_SRCY:	db 0
SHP_NX:		db 0
SHP_NY:		db 0
DEC_INDEX:	db 0
DEC_PASS:	db 0
DEC_S:		db 0
DEC_IX:		db 0
DEC_SX:		dw 0
DEC_SY:		db 0
