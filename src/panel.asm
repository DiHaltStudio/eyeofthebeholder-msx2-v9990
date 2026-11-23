; Complete party portraits off screen; publish at VBlank before their scanout.
; Lives in the auxiliary/automap segment; its exploration data is untouched.
; PANELBUF is exclusively an inventory backup while CONTROL_MODE != 0.
; PANEL_DRAW routes that case to INV_DRAW, so the closed-inventory path may
; reuse its first 64x52 pixels. All generic GUI primitives honour PN_STAGE;
; the portrait tint must read AND write the same off-screen rows.
; No queued scene commands are active here. Drain before staging, before
; publishing and before returning/reusing the scratch rectangle.
PN_RENDER:
	ld a,(TXT_FONT)		; (the camp menus print with FONT8)
	push af
	call TEXT_FONT6
	call .prepare
	pop af
	or a
	ret z
	jp TEXT_FONT8
.prepare:	ld a,(PN_INDEX)
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	ret z
	; box position
	ld a,(PN_INDEX)
	ld hl,184
	bit 0,a
	jr z,.left
	ld hl,256
.left:	ld (PN_X),hl
	srl a
	ld (PN_ROW),a
	ld e,a
	ld d,0
	ld hl,PANEL_BOXY
	add hl,de
	ld a,(hl)
	ld (PN_Y),a
	; Keep caller-visible coordinates (SWAP_BLINK uses them after drawing).
	ld hl,(PN_X)
	push hl
	ld a,(PN_Y)
	push af
	call PTR_KEEP_ARROW
	call V9_WAIT_CE
	; The damage splat protrudes one row below the 50-row box. Preserve
	; both gap rows, exactly as direct drawing did, then compose over them.
	ld hl,(PN_X)
	ld de,SCREEN_X
	add hl,de
	ld (PN_SEED),hl
	ld a,(PN_Y)
	add a,SCREEN_Y
	ld l,a
	ld h,0
	ld (PN_SEED+2),hl
	ld hl,PN_SEED
	ld a,V9_LOG_COPY
	call V9_LMMM
	call V9_WAIT_CE
	ld hl,PANELBUF_X-SCREEN_X
	ld (PN_X),hl
	ld a,PANELBUF_Y-256-SCREEN_Y
	ld (PN_Y),a
	ld a,1
	ld (PN_STAGE),a
	call .paint
	call V9_WAIT_CE
	xor a
	ld (PN_STAGE),a
	pop af
	ld (PN_Y),a
	add a,SCREEN_Y
	ld l,a
	ld h,0
	ld (PN_COPY+6),hl
	pop hl
	ld (PN_X),hl
	ld de,SCREEN_X
	add hl,de
	ld (PN_COPY+4),hl
	; Wait for a fresh blank with the completed panel and the engine idle.
	; Start immediately: V9_WAIT_VBLANK also runs audio before returning.
	; B2 overscan blank is ~1.4 ms; this 64x52 copy takes ~2.2 ms on Z80.
	; It finishes before the TOP panel at display row 22 (~2.8 ms deadline),
	; so no scanline reads a partially copied portrait. Keep audio AFTER it.
	ld a,1
	out (V9_INTFLAG),a
.wait:	in a,(V9_INTFLAG)
	rrca
	jr nc,.wait
	ld hl,PN_COPY
	ld e,V9_LOG_COPY
	call V9_ISSUE
.copy_wait:
	in a,(V9_STATUS)
	rrca
	jr c,.copy_wait		; keep audio outside this publication deadline
.published:
	jp SFX_POLL		; consume this frame once, after the finished copy
.paint:	ld a,(PN_Y)
	; box background (two parts of INVENT.CPS)
	ld hl,SHP_BOX0
	ld de,(PN_X)
	ld c,a
	ld a,V9_LOG_COPY
	call BLIT_SCREEN
	ld hl,SHP_BOX1
	ld de,(PN_X)
	ld a,(PN_Y)
	add a,24
	ld c,a
	ld a,V9_LOG_COPY
	call BLIT_SCREEN
	; name (poisoned or paralysed: dark red)
	push iy
	pop hl
	inc hl			; P_NAME
	ld de,(PN_X)
	inc de
	inc de
	ld a,(PN_Y)
	add a,2
	ld c,a
	ld a,(iy+P_FLAGS)
	and 6
	ld a,C_BLACK
	jr z,.nm
	ld a,C_DARKRED
.nm:	ld b,C_FILL
	call TEXT_PRINT
	; face (dead: skull; unconscious: grid over it; stone, poisoned,
	; invisible: through a fading table, gui_drawFaceShape)
	ld a,(iy+P_FACE)
	ld l,a
	ld h,0
	ld de,SHP_FACE0
	add hl,de
	ld a,(iy+P_HP)
	cp -10
	jr nz,.face
	ld hl,SHP_DEADCHAR
.face:	push af
	ld de,(PN_X)
	ld a,(PN_Y)
	add a,9
	ld c,a
	ld a,V9_LOG_COPY
	call BLIT_SCREEN
	pop af
	jr z,.slots
	ld a,1
	bit 3,(iy+P_FLAGS)	; stone: blue
	jr nz,.tint
	dec a
	bit 1,(iy+P_FLAGS)	; poisoned: green
	jr nz,.tint
	ld a,(iy+P_EFFECT)	; invisible (140h): dark
	and 40h
	ld b,a
	ld a,(iy+P_EFFECT+1)
	and 1
	or b
	jr z,.grid
	ld a,2
.tint:	ld de,(PN_X)
	ld b,a
	ld a,(PN_Y)
	add a,9
	ld c,a
	ld a,b
	call SCALL
	dw FACE_TINT
.grid:	ld a,(iy+P_HP)
	dec a
	jp p,.slots
	ld hl,SHP_DISABLEDGRID
	ld de,(PN_X)
	ld a,(PN_Y)
	add a,9
	ld c,a
	ld a,V9_LOG_TCOPY
	call BLIT_SCREEN
.slots:	; weapon slots
	xor a
	call PANEL_SLOT
	ld a,1
	call PANEL_SLOT
	; hit points
	call PANEL_HP
	; damage just taken: red splat with the number
	ld a,(iy+P_DAMAGE)
	or a
	ret z
	ld hl,(PN_X)
	ld de,13
	add hl,de
	ex de,hl
	ld a,(PN_Y)
	add a,30
	ld c,a
	ld hl,SHP_REDSPLAT
	ld a,V9_LOG_TCOPY
	call BLIT_SCREEN
	ld a,(iy+P_DAMAGE)
	call NUM_STR		; HL = text, B = length
	ld a,b
	add a,a
	add a,b			; len * 3
	ld e,a
	ld a,34
	sub e
	ld e,a
	ld d,0
	push hl
	ld hl,(PN_X)
	add hl,de
	ex de,hl
	pop hl
	ld a,(PN_Y)
	add a,42
	ld c,a
	ld a,C_WHITE
	ld b,0
	jp TEXT_PRINT

PN_COPY: dw PANELBUF_X, PANELBUF_Y, 0, 0, 64, 52
PN_SEED: dw 0, 0, PANELBUF_X, PANELBUF_Y, 64, 52

; Build the book, including its disabled grid, before showing any of it.
BOOK_STAGE_BEGIN:
	call WCALL
	dw BOOK_STAGE_COORDS
	ld (BOOK_STAGE_COPY),hl
	ld (BOOK_STAGE_COPY+2),de
	ld bc,BOOK_X
	or a
	sbc hl,bc
	ld (GUI_BASE_X),hl
	ex de,hl
	ld bc,BOOK_Y
	or a
	sbc hl,bc
	ld (GUI_BASE_Y),hl
	ret
BOOK_STAGE_SHOW:
	ld hl,SCREEN_Y
	ld (GUI_BASE_Y),hl
	ld hl,SCREEN_X
	ld (GUI_BASE_X),hl
	call V9_WAIT_CE
	call V9_WAIT_VBLANK
	ld hl,BOOK_STAGE_COPY
	ld a,V9_LOG_COPY
	jp V9_LMMM
BOOK_STAGE_COPY:
	dw 0, 0, SCREEN_X+BOOK_X, SCREEN_Y+BOOK_Y, BOOK_W, BOOK_H
