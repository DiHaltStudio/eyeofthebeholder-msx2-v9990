; Hardware arrow and software item cursor. In the effects overlay.
FX_PTR_HIDE:
	push af
	ld a,(PTR_ON)
	or a
	jr nz,.hide
	pop af
	ret
.hide:	push bc
	push de
	push hl
	push ix
	xor a
	ld (PTR_ON),a
	ld a,(PTR_HARD)
	or a
	jr z,.soft
	xor a
	ld (PTR_HARD),a
	call FX_PTR_ARROW_OFF
	jr .done
.soft:	ld hl,PTR_SAVE_X
	ld (PTR_CMD),hl
	ld hl,PTR_SAVE_Y
	ld (PTR_CMD+2),hl
	ld hl,(PTR_X)
	ld de,SCREEN_X
	add hl,de
	ld (PTR_CMD+4),hl
	ld hl,(PTR_Y)
	ld de,SCREEN_Y
	add hl,de
	ld (PTR_CMD+6),hl
	ld hl,PTR_CMD
	ld a,V9_LOG_COPY
	call V9_LMMM
.done:	pop ix
	pop hl
	pop de
	pop bc
	pop af
	ret

; ----------------------------------------------------------------------------
; PTR_SHOW - draws the pointer at the mouse position (if not already there)
; ----------------------------------------------------------------------------
FX_PTR_SHOW:
	; shape: the icon of the item in hand; hot spot 8, 8 with an item
	ld hl,(HAND)
	ld a,h
	or l
	ld c,0
	jr z,.hot
	ld c,8
.hot:	call FX_ITEM_ICON
	ld (PTR_NID),hl
	ld b,0
	ld hl,(MOUSE_X)
	or a
	sbc hl,bc
	ld (PTR_NX),hl
	ld a,(MOUSE_Y)
	ld l,a
	ld h,0
	sbc hl,bc
	ld (PTR_NY),hl
	; unchanged?
	ld a,(PTR_ON)
	or a
	jr z,.draw
	ld hl,(PTR_X)
	ld de,(PTR_NX)
	or a
	sbc hl,de
	jr nz,.move
	ld hl,(PTR_Y)
	ld de,(PTR_NY)
	sbc hl,de
	jr nz,.move
	ld hl,(PTR_ID)
	ld de,(PTR_NID)
	sbc hl,de
	ret z
.move:	ld a,(PTR_HARD)
	or a
	jr z,.erase
	ld hl,(PTR_NID)
	ld de,SHP_ICON0
	or a
	sbc hl,de
	jr z,.draw		; move the hardware cursor without hiding it
.erase:	call FX_PTR_HIDE
.draw:	ld hl,(PTR_NX)
	ld (PTR_X),hl
	ld hl,(PTR_NY)
	ld (PTR_Y),hl
	ld hl,(PTR_NID)
	ld (PTR_ID),hl
	ld de,SHP_ICON0
	or a
	sbc hl,de
	jr nz,.icon
	call FX_PTR_ARROW
	jr .shown
.icon:	; save what is below
	ld hl,(PTR_X)
	ld de,SCREEN_X
	add hl,de
	ld (PTR_CMD),hl
	ld hl,(PTR_Y)
	ld de,SCREEN_Y
	add hl,de
	ld (PTR_CMD+2),hl
	ld hl,PTR_SAVE_X
	ld (PTR_CMD+4),hl
	ld hl,PTR_SAVE_Y
	ld (PTR_CMD+6),hl
	ld hl,PTR_CMD
	ld a,V9_LOG_COPY
	call V9_LMMM
	; the icon (a RAM shape: through the cache)
	ld hl,(PTR_ID)
	ld (SHP_ID),hl
	call SHAPE_ENTRY
	ret c
	ld b,0
	call MCACHE_GET
	ld l,(ix+0)
	ld h,(ix+1)
	ld (PTR_CMD),hl
	ld l,(ix+2)
	ld h,(ix+3)
	ld (PTR_CMD+2),hl
	ld hl,(PTR_X)
	ld de,SCREEN_X
	add hl,de
	ld (PTR_CMD+4),hl
	ld hl,(PTR_Y)
	ld de,SCREEN_Y
	add hl,de
	ld (PTR_CMD+6),hl
	ld hl,PTR_CMD
	ld a,V9_LOG_TCOPY
	call V9_LMMM
.shown:	ld a,1
	ld (PTR_ON),a
	ret


; The monochrome hardware masks are generated from the existing arrow:
; bright interior and dark outline. The item cursor keeps its full palette.
; B2 NTSC includes 14 overscan lines above the 212-line origin of cursor
; coordinates. The first cursor line is displayed one further line down.
B2_CURSOR_Y_BIAS: equ 14+1
FX_PTR_ARROW:
	ld a,1
	ld (PTR_HARD),a
	ld hl,PTR_MASK_READY
	bit 0,(hl)
	jr nz,.coords
	set 0,(hl)
	ld a,V9R_CSPO
	ld e,C_WHITE >> 2
	call V9_SETREG
	ld c,7
	ld hl,0FF00h
	call V9_SETWADDR
	ld hl,PTR_ARROW_MASKS
	ld bc,V9_VRAM		; B = 0: 256 bytes
	otir
.coords:
	ld c,7
	ld hl,0FE00h
	call V9_SETWADDR
	ld hl,(PTR_Y)
	ld de,SCREEN_Y-B2_CURSOR_Y_BIAS
	add hl,de
	ex de,hl		; DE = cursor Y
	ld hl,(PTR_X)
	ld bc,SCREEN_X
	add hl,bc		; HL = cursor X
	ld b,(C_WHITE & 3) << 6
	call .attr
	set 5,b			; complement this colour for the outline
.attr:
	ld a,e
	out (V9_VRAM),a
	xor a
	out (V9_VRAM),a
	ld a,d
	out (V9_VRAM),a
	xor a
	out (V9_VRAM),a
	ld a,l
	out (V9_VRAM),a
	xor a
	out (V9_VRAM),a
	ld a,h
	or b
	out (V9_VRAM),a
	xor a
	out (V9_VRAM),a
	ret

FX_PTR_ARROW_OFF:
	ld c,7
	ld hl,0FE00h
	call V9_SETWADDR
	ld b,16
.clear:
	ld a,10h
	out (V9_VRAM),a
	djnz .clear
	ret
PTR_MASK_READY: db 0

	include "../build/cursor.inc"
