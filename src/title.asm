; ============================================================================
; title.asm - the title screen and its menu (part of the MAGIC overlay):
;   EoBEngine::mainMenu / mainMenuLoop. A level is loaded already (the
;   pointer uses its shape cache); its palette is in PALBUF.
; ============================================================================

; TITLE_MENU - -> A = 0 load the last game, 1 start, 2 back to DOS
TITLE_MENU:
	xor a
	call TT_DISPLAY		; hide before changing palette, pixels or menu
	call PTR_HIDE
	ld de,F_TITLEPAL	; the palette in ROWBUF: PALBUF keeps the level's
	ld hl,ROWBUF
	ld bc,192
	call LOAD_RAM
	ld hl,ROWBUF
	di			; DOS returned with IRQs on; BIOS must not interrupt OTIR
	call TT_VBLANK
	xor a
	ld b,192
	call V9_SETPAL
	ei
	ld de,F_TITLEV9
	call LOAD_V9_KEEP
	; the two boxes of the menu
	ld hl,TT_BOXES
	ld b,2
.box:	push bc
	ld e,(hl)
	inc hl
	ld d,0
	ld (BOX_X),de
	ld de,BOX_Y
	ld bc,6
	ldir
	push hl
	call GUI_BOX
	pop hl
	pop bc
	djnz .box
	call TEXT_FONT8
	xor a
	ld (TT_SEL),a
	ld a,0FFh
	ld (TT_KEY),a
	ld hl,(MOUSE_X)
	ld (TT_MX),hl
	ld a,(MOUSE_Y)
	ld (TT_MY),a		; a stationary pointer must leave the initial selection alone
.draw:	; the items, the one under the pointer in red
	ld b,0
.it:	push bc
	ld a,b
	add a,a
	ld e,a
	ld d,0
	ld hl,TT_ITEMS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	ld a,b
	add a,a
	add a,a
	add a,a
	add a,168
	ld c,a
	ld a,(TT_SEL)
	cp b
	ld a,C_WHITE
	jr nz,.c
	ld a,C_LIGHTRED
.c:	ld de,80
	call SHADED_T8
	pop bc
	inc b
	ld a,b
	cp 3
	jr c,.it
	ld a,V9R_CTRL | 0C0h	; only publish on the initial, hidden draw
	out (V9_REGSEL),a
	in a,(V9_REGDAT)
	bit 7,a
	jr nz,.wait
	call PTR_SHOW
	ld a,80h		; publish the complete title and menu together
	call TT_DISPLAY
.wait:	call V9_WAIT_VBLANK
	call MOUSE_UPDATE
	call PTR_SHOW
	; keys: cursors up / down, space or return
	ld a,7
	call KEY_ROW
	bit 7,a
	ld a,KEY_USE
	jr z,.k
	call KEYS_READ
.k:	ld hl,TT_KEY
	cp (hl)
	ld (hl),a
	jr z,.mouse
	cp KEY_USE
	jr z,.go
	ld hl,TT_SEL
	cp KEY_FWD
	jr nz,.dn
	ld a,(hl)
	dec a
	jp p,.set
	ld a,2
	jr .set
.dn:	cp KEY_BACK
	jr nz,.mouse
	ld a,(hl)
	inc a
	cp 3
	jr c,.set
	xor a
.set:	ld (hl),a
	jp .draw
.mouse:	; the pointer moved: the item under it
	ld hl,(MOUSE_X)
	ld de,(TT_MX)
	ld (TT_MX),hl
	or a
	sbc hl,de
	jr nz,.hov
	ld a,(MOUSE_Y)
	ld hl,TT_MY
	cp (hl)
	jr z,.same
.hov:	ld a,(MOUSE_Y)
	ld (TT_MY),a
	call TT_ITEM		; A = item under the pointer, FFh none
	ld hl,TT_SEL
	cp (hl)
	jr z,.same
	ld (hl),a
	jp .draw
.same:	ld a,(CLICK)
	or a
	jr z,.wait
	xor a
	ld (CLICK),a
	call TT_ITEM
	cp 3
	jr nc,.wait
	ld (TT_SEL),a
.go:	ld a,(TT_SEL)
	cp 3
	jp nc,.wait
	push af
	call PTR_HIDE
	cp 1			; start: the party is made now
	jr nz,.pal
	ld a,(CG_DEFAULT)
	or a
	call z,START_CHARGEN
.pal:	xor a
	call TT_DISPLAY		; INIT_DONE also draws before its call to LOAD_GAME
	call TEXT_FONT6
	ld hl,PALBUF		; the level palette again
	call TT_VBLANK
	xor a
	ld b,192
	call V9_SETPAL
	pop af
	ret

; START_CHARGEN - the character generation (CHARGEN.OVL, run once in a
;   segment of its own); then the new party has no spells ready and no
;   timed effects
START_CHARGEN:
	ld hl,TEXTBUF+20
	ld b,1
	call MAP_ALLOC
	ld hl,F_CHARGEN
	ld de,TEXTBUF
	ld bc,16
	ldir
	ld a,(TEXTBUF+20)
	ld de,TEXTBUF
	call SEG_RUN
	ld hl,CH_SPELLS
	ld de,CH_SPELLS+1
	ld bc,600-1
	ld (hl),0
	ldir
	ld hl,CH_EVENTS
	ld de,CH_EVENTS+1
	ld bc,6*12-1
	ld (hl),0
	ldir
	xor a
	ld (MAGIC_ACTIVE),a
	ld l,a
	ld h,a
	ld (PARTY_EFFECTS),hl
	ret
F_CHARGEN:	db LANG_C1,LANG_C2,5Ch,"CHARGEN.OVL",0
CG_DEFAULT:	db 0		; 1: the party of the start file (the tests)

; TT_ITEM - -> A = menu item under the pointer (0..2) or FFh
TT_ITEM:
	ld hl,(MOUSE_X)
	ld de,80
	or a
	sbc hl,de
	jr c,.no
	ld de,168
	sbc hl,de
	jr nc,.no
	ld a,(MOUSE_Y)
	sub 168
	jr c,.no
	cp 24
	jr nc,.no
	rrca
	rrca
	rrca
	and 1Fh
	ret
.no:	ld a,0FFh
	ret

; SHADED_T8 - HL = text, DE = x, C = y, A = colour, with a black shadow
SHADED_T8:
	push af
	push hl
	push de
	push bc
	inc de
	inc c
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	pop bc
	pop de
	pop hl
	pop af
	ld b,0
	jp TEXT_PRINT

TT_BOXES:	; x, y, w, h, frame 1, frame 2, fill (0 none)
	db 77, 165, 173, 29, TITLE_C14, TITLE_C13, TITLE_C12
	db 76, 164, 175, 31, TITLE_C14, TITLE_C13, 0
TT_ITEMS:	dw STR_TITLE0, STR_TITLE1, STR_TITLE2
TT_SEL:		db 0
TT_KEY:		db 0
TT_MX:		dw 0
TT_MY:		db 0
F_TITLEPAL:	db "TITLE.PAL",0
F_TITLEV9:	db "TITLE.V9",0
