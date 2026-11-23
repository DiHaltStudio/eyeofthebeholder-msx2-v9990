; ============================================================================
; scene.asm - The 3D dungeon view, composed with V9990 commands
; Assembler: Sjasm 0.42c
;
; The view (176x120) is composed in VIEW_BUF, a hidden VRAM area, and then
; copied to the screen in one LMMM. Composition:
;   1. floor and ceiling background (normal or mirrored, as the original does
;      depending on the parity of the party position);
;   2. the wall pieces of the draw list (build/drawlist.inc), from the far
;      row to the near one, copied with transparency (colour 0);
;   3. block by block, far to near: decorations, items, doors, monsters.
; The pieces were rendered by tools/conv_level.py into the level store; the
; LEVELn.DAT tables give their VRAM coordinates.
;
; Visible blocks (ScummVM numbering, P = party):
;      00 01 02 03 04 05 06      row 3 ahead
;         07 08 09 10 11         row 2
;            12 13 14            row 1
;            15 (16) 17          row 0
; ============================================================================

; SCENE_DRAW - draws the view for (CUR_BLOCK, CUR_DIR); the LMMMs go
;   through the command queue (v9990.asm) meanwhile
SCENE_DRAW:
	ld a,1
	ld (Q_ON),a
	call .build
	call Q_FLUSH
	xor a
	ld (Q_ON),a
	ret
.build:	call DIM_FORGET
	; --- wall sides: facing us, right face, left face ---
	ld a,(CUR_DIR)
	ld e,a
	ld d,0
	ld hl,DSC_BLOCKMAP
	add hl,de
	ld a,(hl)
	ld (SIDE_D),a
	ld a,4
	add a,l
	ld l,a
	ld a,(hl)
	ld (SIDE_R),a
	ld a,4
	add a,l
	ld l,a
	ld a,(hl)
	ld (SIDE_L),a

	; --- the 18 visible blocks ---
	ld a,(CUR_DIR)
	add a,a			; *2
	ld e,a
	add a,a			; *4
	add a,a			; *8
	add a,a			; *16
	add a,e			; *18
	ld e,a
	ld d,0
	ld hl,DSC_BLOCKINDEX
	add hl,de
	ld de,VISBLK
	ld b,18
.vis:	ld a,(hl)
	push hl
	ld l,a
	rla			; sign extend into H
	sbc a,a
	ld h,a
	ld a,(CUR_BLOCK)
	add a,l
	ld l,a
	ld a,(CUR_BLOCK+1)
	adc a,h
	and 03h			; & 3FFh
	ld h,a
	ex de,hl
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ex de,hl
	pop hl
	inc hl
	djnz .vis

	; --- the wall facing the party of each visible block (used a lot) ---
	ld hl,VISWALL
	ld b,18
	xor a
.vw:	push bc
	push hl
	push af
	ld c,0
	call WALL_TYPE
	pop bc			; B = index (from AF)
	pop hl
	ld (hl),a
	inc hl
	ld a,b
	inc a
	pop bc
	djnz .vw

	; --- background: mirrored when (x + y + dir) is odd ---
	ld a,(CUR_BLOCK)
	ld e,a
	and 1Fh
	ld l,a
	ld a,(CUR_BLOCK+1)
	rr e			; bits 5-7 of the low byte + bit 8-9 of the high byte
	rra
	rr e
	rra
	rr e
	rra
	rr e
	rra
	rr e
	rra
	and 1Fh			; a = y
	add a,l
	ld hl,CUR_DIR
	add a,(hl)
	and 1
	ld (PROCFLAG),a
	add a,a
	add a,a			; *4
	ld e,a
	ld d,0
	ld hl,LEVELDAT+D_BG
	add hl,de
	ld de,CMD
	ldi
	ldi
	ldi
	ldi			; sx, sy
	ld hl,CMD_BGREST
	ld bc,8
	ldir			; dx, dy, nx, ny
	ld hl,CMD
	ld a,V9_LOG_COPY
	call V9_LMMM

	; --- wall pieces ---
	ld ix,DRAWLIST
.next:	ld a,(ix+0)
	cp 255
	jp z,.walls_done
	ld a,(ix+1)
	ld c,a
	ld a,(ix+0)
	call WALL_TYPE		; a = t
	ld b,a
	ld a,(ix+3)
	or a
	jr z,.c0
	dec a
	jr z,.c1
	dec a
	jr z,.c2
	dec a
	jr z,.c3
	; cond 4: t != 0 and t2 is a door -> draw t2
	ld a,b
	or a
	jp z,.skip
	call WALL_T2
	call IS_DOOR
	jp z,.skip
	ld b,a
	jp .draw
.c3:	; cond 3: hasWall(t) and t2 not a door
	ld a,b
	or a
	jp z,.skip
	call IS_DOOR
	jp nz,.skip
	call WALL_T2
	call IS_DOOR
	jp nz,.skip
	jp .draw
.c2:	; cond 2: not a door (a type 0 has no piece and is skipped below)
	ld a,b
	call IS_DOOR
	jp nz,.skip
	jp .draw
.c1:	; cond 1: hasWall
	ld a,b
	or a
	jp z,.skip
	call IS_DOOR
	jp nz,.skip
	jp .draw
.c0:	ld a,b
	or a
	jp z,.skip
.draw:	; B = wall type -> VMP set
	ld h,(LEVELDAT+D_WVMP)>>8
	ld l,b
	ld a,(hl)
	or a
	jp z,.skip
	dec a			; set-1
	ld e,a
	add a,a			; *2
	add a,a			; *4
	add a,a			; *8
	add a,a			; *16
	add a,e			; *17
	add a,e			; *18
	add a,(ix+4)		; + piece*2 + flip
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl		; *4 bytes per entry
	ld de,LEVELDAT+D_PIECES
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,d
	and e
	inc a
	jr z,.skip		; FFFFh: no piece stored
	ld a,(ix+5)
	add a,e
	ld (CMD),a
	ld a,0
	adc a,d
	ld (CMD+1),a		; sx = vx + source offset
	ld a,(hl)
	ld (CMD+2),a
	inc hl
	ld a,(hl)
	ld (CMD+3),a		; sy
	ld a,(ix+6)
	add a,VIEWBUF_X & 0FFh
	ld (CMD+4),a
	ld a,0
	adc a,VIEWBUF_X >> 8
	ld (CMD+5),a		; dx
	ld a,(ix+7)
	add a,VIEWBUF_Y & 0FFh
	ld (CMD+6),a
	ld a,0
	adc a,VIEWBUF_Y >> 8
	ld (CMD+7),a		; dy
	ld a,(ix+8)
	ld (CMD+8),a
	xor a
	ld (CMD+9),a		; nx
	ld a,(ix+9)
	ld (CMD+10),a
	xor a
	ld (CMD+11),a		; ny
	ld hl,CMD
	ld a,V9_LOG_TCOPY
	call V9_LMMM
.skip:	ld de,10
	add ix,de
	jp .next

.walls_done:
	; --- shapes: decorations, doors and monsters, block by block ---
	ld hl,DSC_TILEINDEX
	ld b,18
.shapes:
	call Q_PUMP
	push bc
	push hl
	ld a,(hl)
	ld (SHP_BLOCK),a
	call SHAPE_DIM
	jr z,.shp_next		; empty window
	ld a,(SHP_BLOCK)
	call DRAW_DECORATIONS
	ld a,(SHP_BLOCK)
	call DRAW_BLOCK_ITEMS
	ld a,(SHP_BLOCK)
	cp 15
	jr nc,.fly
	ld c,0
	call WALL_TYPE
	ld e,a
	call IS_DOOR
	jr z,.nodoor
	ld a,(SHP_BLOCK)
	call DRAW_DOOR
.nodoor:
	ld a,(SHP_BLOCK)
	call DRAW_MONSTERS
.fly:	ld a,(SHP_BLOCK)
	call DRAW_FLYING
	ld a,(SHP_BLOCK)
	call DRAW_TELEPORT	; (page 3)
.shp_next:
	pop hl
	pop bc
	inc hl
	djnz .shapes

	call XCALL
	dw FX_DRAW_CLOUD
	; --- to the screen ---
	call PTR_KEEP_ARROW
	ld hl,CMD_TOSCREEN
	ld a,V9_LOG_COPY
	call V9_LMMM
	jp DRAW_COMPASS

; WALL_TYPE - A = visible block, C = side selector (0 facing, 1 right, 2 left)
;   -> A = wall type. Preserves BC.
WALL_TYPE:
	push bc
	add a,a
	ld l,a
	ld h,0
	ld de,VISBLK
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)		; de = block
	ex de,hl
	add hl,hl
	add hl,hl		; *4
	ld de,LEVELDAT+D_MAZE
	add hl,de
	ex de,hl		; de = address of the block's four walls
	ld b,0
	ld hl,SIDE_D
	add hl,bc
	ld c,(hl)		; side 0..3
	ex de,hl
	add hl,bc
	ld a,(hl)
	pop bc
	ret

; WALL_T2 - the wall facing us of the second block of the entry -> A
WALL_T2:
	push bc
	ld a,(ix+2)
	ld c,0
	call WALL_TYPE
	pop bc
	ret

; IS_DOOR - A = wall type -> NZ if it is a door (flag 8). Preserves A, B.
IS_DOOR:
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	bit 3,(hl)
	ret

PROCFLAG: db 0
SHP_BLOCK: db 0
SIDE_D:	db 0
SIDE_R:	db 0
SIDE_L:	db 0
VISBLK:	ds 36
VISWALL: ds 18
CMD:	ds 12
CMD_BGREST:	dw VIEWBUF_X, VIEWBUF_Y, VIEW_W, VIEW_H
CMD_TOSCREEN:	dw VIEWBUF_X, VIEWBUF_Y, SCREEN_X, SCREEN_Y, VIEW_W, VIEW_H

; The finale composes only view columns 24..151, rows 8..102. Its
; scratch rectangle starts beside the sprite sheets' last two rows of
; shapes (the rightmost source there ends at x=351).
XD_VIEW_X:	equ 352
XD_VIEW_ROWS:	equ 95
XD_VIEW_INIT:
	ld de,176
	add hl,de
	ld (XD_VIEW_CLEAR_CMD+6),hl
	ld (XD_VIEW_SHOW_CMD+2),hl
XD_VIEW_CLEAR:
	ld hl,XD_VIEW_CLEAR_CMD
	ld a,V9_LOG_COPY
	jp V9_LMMM
XD_VIEW_SHOW:
	call V9_WAIT_CE
	call V9_WAIT_VBLANK
	ld hl,XD_VIEW_SHOW_CMD
	ld a,V9_LOG_COPY
	jp V9_LMMM
XD_VIEW_CLEAR_CMD:
	dw VIEWBUF_X+24, VIEWBUF_Y+8, XD_VIEW_X, 0, 128, XD_VIEW_ROWS
XD_VIEW_SHOW_CMD:
	dw XD_VIEW_X, 0, SCREEN_X+24, SCREEN_Y+8, 128, XD_VIEW_ROWS
