; ============================================================================
; chargen.asm - CHARGEN.OVL: the character generation (CharacterGenerator,
;   chargen.cpp, the DOS version of EOB1). Four characters are made in the
;   boxes of the screen of the original: race, class, alignment, the rolled
;   statistics (reroll, modify), a portrait and a name; PLAY gives them the
;   equipment of their class and the game starts with them.
;
; Run once from the title menu (TITLE_MENU, START_CHARGEN) through SEG_RUN,
; in a segment of its own at CG_BASE, with level 1 loaded: the shape cache
; lends it its first CG_ROWS rows (tools/conv_chargen.py puts there the
; clean panel, the button bodies and the sparkles) and goes on below them;
; the portraits come from the global shapes as in the game.
; Coordinates are those of the 320x200 screen of the original.
; ============================================================================

	output "../build/CHARGEN.OVL"
	org CG_BASE

CG_FACEX:	equ 208		; the portrait in the panel
CG_FACEY:	equ 66

CG_MAIN:
	call PTR_HIDE
	ld a,42h		; the screen off while the picture loads
	call V9_DISPLAY
	ld hl,(CACHE_Y0)	; the cache gives its first rows
	ld (CG_SAVEY0),hl
	ld hl,CG_Y+CG_ROWS
	ld (CACHE_Y0),hl
	call CACHE_RESET
	ld de,CG_F_V9
	call LOAD_V9_KEEP
	ld de,CG_F_PAL
	ld hl,ROWBUF
	ld bc,192
	call LOAD_RAM
	ld hl,ROWBUF
	xor a
	ld b,192
	call V9_SETPAL
	ld a,082h
	call V9_DISPLAY
	call TEXT_FONT8
	ld hl,CG_F_SND		; its music and the click (CGSND.DAT)
	call CG_SNDSET
	ld a,1
	ld (CG_MUSIC),a
	call CG_CLEAR_PARTY
	ld a,0FFh
	ld (CG_HLB),a
	ld hl,CG_PORT
	ld b,4
.np:	ld (hl),a
	inc hl
	djnz .np
	xor a
	ld (CG_BOX),a
	ld (CG_SPARKON),a
	ld (CG_KLAST),a
	ld a,3
	ld (CG_TICKF),a
	call CG_COMPLETE
	; ---- the boxes: choose one (createCustomParty) ----
.loop:	ld a,(CG_BOX)
	add a,6
	call CG_HL_SET
	call CG_POLL
	ld a,(CG_K)
	ld hl,CG_BOX
	cp KEY_TLEFT
	jr z,.x
	cp KEY_TRIGHT
	jr nz,.ny
.x:	ld a,(hl)
	xor 1
	ld (hl),a
	jr .loop
.ny:	cp KEY_FWD
	jr z,.y
	cp KEY_BACK
	jr nz,.nk
.y:	ld a,(hl)
	xor 2
	ld (hl),a
	jr .loop
.nk:	cp KEY_USE
	jr z,.sel
	ld a,4			; P: PLAY (the text of the original says so)
	call KEY_ROW
	bit 5,a
	jp z,.play
	ld a,(CG_C)
	or a
	jr z,.loop
	ld hl,CG_L_BOXES
	ld b,5
	call CG_HIT
	cp 4
	jr z,.play
	jr nc,.loop
	ld (CG_BOX),a
.sel:	ld a,0FFh
	call CG_HL_SET
	ld a,(CG_BOX)
	call CG_HASNAME
	jr z,.new
	ld a,(CG_BOX)
	ld (CG_B0),a
	call CG_VIEW
	or a
	jr nz,.play
	ld a,(CG_B0)		; another box, an empty one: it is made now
	ld hl,CG_BOX
	cp (hl)
	jr z,.done
	ld a,(hl)
	call CG_HASNAME
	jr nz,.done
.new:	call CG_CREATE
.done:	call CG_COMPLETE
	jp .loop
.play:	; PLAY: only with four characters
	ld b,4
.chk:	ld a,b
	dec a
	push bc
	call CG_HASNAME
	pop bc
	jp z,.loop
	djnz .chk
	ld a,15
	call CG_PRESS
	call CG_FINISH
	; back to the game: the cache, the sounds, the font
	call PTR_HIDE
	ld hl,(CG_SAVEY0)
	ld (CACHE_Y0),hl
	call CACHE_RESET
	xor a
	ld (CG_MUSIC),a
	ld hl,F_SFX
	call CG_SNDSET
	jp TEXT_FONT6

; CG_SNDSET - HL = name in this overlay: that set of sounds (SFX_LOADSET
;   wants the name out of page 2)
CG_SNDSET:
	ld de,TEXTBUF
	ld bc,16
	ldir
	ld de,TEXTBUF
	jp SFX_LOADSET

; CG_CLEAR_PARTY - the party of the start file goes: its items are free
;   again, its records empty
CG_CLEAR_PARTY:
	xor a
.ch:	push af
	call CHAR_PTR
	push iy
	pop hl
	ld de,P_INV
	add hl,de
	ld b,27
.it:	push bc
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ld a,d
	or e
	jr z,.ni
	ex de,hl
	call ITEM_IX
	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
.ni:	pop hl
	pop bc
	djnz .it
	push iy
	pop hl
	ld e,l
	ld d,h
	inc de
	ld (hl),0
	ld bc,P_SIZE-1
	ldir
	pop af
	inc a
	cp 6
	jr c,.ch
	ret

; CG_HASNAME - A = box -> NZ if it has a character (a name)
CG_HASNAME:
	call CHAR_PTR
	ld a,(iy+P_NAME)
	or a
	ret

; ----------------------------------------------------------------------------
; The panel at the right: its texts (checkForCompleteParty)
; ----------------------------------------------------------------------------
CG_COMPLETE:
	call CG_PANEL
	ld hl,CG_S1_8		; "Select the box ..."
	ld de,152
	ld c,80
	ld a,C_WHITE
	call CG_TEXT
	ld b,4
.n:	ld a,b
	dec a
	push bc
	call CG_HASNAME
	pop bc
	jr z,.inc
	djnz .n
	ld hl,CG_S1_0		; "Your party is complete ..."
	ld de,152
	ld c,125
	ld a,C_WHITE
	call CG_TEXT
	ld a,15			; PLAY
	jr .b
.inc:	ld a,14			; the empty bar
.b:	ld c,0
	jp CG_BUTTON

; CG_PANEL - the clean panel (144, 64)-(303, 191)
CG_PANEL:
	ld de,144
	ld c,64
	ld b,160
	ld l,128
; CG_PANEL_PART - DE = x, C = y, B = w, L = h inside the panel: clean again
CG_PANEL_PART:
	ld (CB_DX),de
	ld a,c
	ld (CB_DY),a
	xor a
	ld (CB_DY+1),a
	ld a,b
	ld (CB_W),a
	ld a,l
	ld (CB_H),a
	xor a
	ld (CB_W+1),a
	ld (CB_H+1),a
	ld hl,CG_PANEL_X-144
	add hl,de
	ld (CB_SX),hl
	ld l,c
	ld h,0
	ld de,CG_PANEL_Y-64
	add hl,de
	ld (CB_SY),hl
	ld a,V9_LOG_COPY
	jp CG_BLIT

; CG_BLIT - LMMM from (CB_SX, CB_SY) in VRAM to (CB_DX, CB_DY) of the
;   screen, CB_W x CB_H; A = logical operation
CG_BLIT:
	push af
	call PTR_HIDE
	ld hl,(CB_DX)
	ld de,SCREEN_X
	add hl,de
	ld (CB_DX),hl
	ld hl,(CB_DY)
	ld de,SCREEN_Y
	add hl,de
	ld (CB_DY),hl
	pop af
	ld hl,CB_CMD
	jp V9_LMMM

CB_CMD:
CB_SX:		dw 0
CB_SY:		dw 0
CB_DX:		dw 0
CB_DY:		dw 0
CB_W:		dw 0
CB_H:		dw 0

; ----------------------------------------------------------------------------
; Buttons (drawButton): a body of CCARGENB, its label over it
; ----------------------------------------------------------------------------
; CG_BUTTON - A = button (_chargenModButtons), C = 0 up / 1 pressed
CG_BUTTON:
	ld l,a
	ld h,0
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,de		; * 9
	ld de,CG_MODBTN
	add hl,de
	push hl
	pop ix
	ld a,(ix+6)		; the body: _chargenButtonBodyCoords[body + state]
	add a,c
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld hl,CG_BODIES
	add hl,de
	ld a,(hl)		; x / 8
	inc hl
	push hl
	call CG_X8
	ld de,CG_BOTTOM_X
	add hl,de
	ld (CB_SX),hl
	pop hl
	ld a,(hl)		; y (CCARGENB, from row 128)
	inc hl
	sub 128
	ld e,a
	ld d,0
	push hl
	ld hl,CG_BOTTOM_Y
	add hl,de
	ld (CB_SY),hl
	pop hl
	ld a,(hl)		; w / 8
	inc hl
	ld b,(hl)		; h
	push bc
	call CG_X8
	ld (CB_W),hl
	pop bc
	ld l,b
	ld h,0
	ld (CB_H),hl
	call CG_DEST
	ld a,V9_LOG_COPY
	call CG_BLIT
	; the label, over it
	ld a,(ix+2)
	or a
	ret z
	ld a,(ix+0)
	call CG_X8
	ld de,CG_BOTTOM_X
	add hl,de
	ld (CB_SX),hl
	ld a,(ix+1)
	sub 128
	ld l,a
	ld h,0
	ld de,CG_BOTTOM_Y
	add hl,de
	ld (CB_SY),hl
	ld a,(ix+2)
	call CG_X8
	ld (CB_W),hl
	ld l,(ix+3)
	ld h,0
	ld (CB_H),hl
	call CG_DEST
	ld hl,(CB_DX)
	ld e,(ix+4)
	ld d,0
	add hl,de
	ld (CB_DX),hl
	ld hl,(CB_DY)
	ld e,(ix+5)
	add hl,de
	ld (CB_DY),hl
	ld a,V9_LOG_TCOPY
	jp CG_BLIT

; CG_DEST - the place of button IX on the screen -> CB_DX, CB_DY
CG_DEST:
	ld a,(ix+7)
	call CG_X8
	ld (CB_DX),hl
	ld l,(ix+8)
	ld h,0
	ld (CB_DY),hl
	ret

; CG_X8 - HL = A * 8
CG_X8:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	ret

; CG_PRESS - A = button: pressed, the click, up again (processButtonClick)
CG_PRESS:
	ld (CG_PB),a
	ld c,1
	call CG_BUTTON
	ld a,76
	call SFX_PLAY
	ld b,5
.w:	push bc
	call CG_FRAME
	pop bc
	djnz .w
	ld a,(CG_PB)
	ld c,0
	jp CG_BUTTON

; ----------------------------------------------------------------------------
; Frames, input
; ----------------------------------------------------------------------------
; CG_FRAME - a frame: the pointer, the tick of the highlight and of the
;   sparkles, the music again when it ends
CG_FRAME:
	call V9_WAIT_VBLANK
	call MOUSE_UPDATE
	ld a,(CLICK)		; a click while busy waits for the next CG_POLL
	or a
	jr z,.nc
	ld (CG_CPEND),a
.nc:	call PTR_SHOW
	ld hl,CG_TICKF
	dec (hl)
	jr nz,.mus
	ld (hl),3		; a tick of the original: 55 ms
	call CG_HL_TICK
	ld a,(CG_SPARKON)
	or a
	call nz,CG_SPARK_TICK
.mus:	ld a,(CG_MUSIC)
	or a
	ret z
	ld a,(SFX_ACTIVE)
	or a
	ret nz
	ld a,20
	jp SFX_PLAY

; CG_POLL - CG_FRAME, then CG_K = a new key (KEY_*), CG_C = a click
CG_POLL:
	call CG_FRAME
	ld a,7			; RETURN as SPACE
	call KEY_ROW
	bit 7,a
	ld a,KEY_USE
	jr z,.k
	call KEYS_READ
.k:	ld hl,CG_KLAST
	cp (hl)
	ld (hl),a
	jr nz,.new
	xor a
.new:	ld (CG_K),a
	ld hl,CG_CPEND
	ld a,(hl)
	ld (hl),0
	ld (CG_C),a
	ret

; CG_HIT - HL = list of buttons (_chargenButtonDefs), B = how many
;   -> A = the position in the list of the one under the mouse, or FFh
CG_HIT:
	ld c,0
.lp:	push bc
	push hl
	ld a,(hl)
	call CG_INBTN
	pop hl
	pop bc
	ld a,c
	ret z
	inc hl
	inc c
	djnz .lp
	ld a,0FFh
	ret

; CG_INBTN - A = button -> Z if the mouse is in it
CG_INBTN:
	ld l,a
	ld h,0
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,de		; * 5
	ld de,CG_BTN
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ld hl,(MOUSE_X)
	or a
	sbc hl,de
	pop de
	jr c,.no
	ld a,h
	or a
	jr nz,.no
	ld a,(de)		; y
	ld b,a
	inc de
	ld a,(de)		; w
	inc de
	cp l
	jr c,.no
	jr z,.no
	ld a,(MOUSE_Y)
	sub b
	jr c,.no
	ex de,hl
	cp (hl)			; h
	jr nc,.no
	xor a
	ret
.no:	or 1
	ret

; ----------------------------------------------------------------------------
; The frame around a box (updateBoxFrameHighLight) and the sparkles in the
; box being made (updateMagicShapes)
; ----------------------------------------------------------------------------
; CG_HL_SET - A = frame (6..13) or FFh: the highlight moves there
CG_HL_SET:
	ld hl,CG_HLB
	cp (hl)
	ret z
	push af
	ld a,(hl)
	inc a
	jr z,.new
	ld a,C_BLACK		; the old one black
	call CG_HL_DRAW
.new:	pop af
	ld (CG_HLB),a
	xor a
	ld (CG_HLC),a
	ret

CG_HL_TICK:
	ld a,(CG_HLB)
	inc a
	ret z
	ld hl,CG_HLC
	ld a,(hl)
	inc a
	cp CG_HILITE_N
	jr c,.c
	xor a
.c:	ld (hl),a
	ld e,a
	ld d,0
	ld hl,CG_HILITE
	add hl,de
	ld a,(hl)
; CG_HL_DRAW - A = colour: the frame CG_HLB (drawBox)
CG_HL_DRAW:
	ld (CG_HLCOL),a
	ld a,(CG_HLB)
	sub 6
	add a,a
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld hl,CG_FRAMES
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)		; x1
	inc hl
	ld (CF_X1),de
	ld a,(hl)		; y1
	inc hl
	inc hl
	ld (CF_Y1),a
	ld e,(hl)
	inc hl
	ld d,(hl)		; x2
	inc hl
	ld a,(hl)		; y2
	ld (CF_Y2),a
	ex de,hl
	ld de,(CF_X1)
	or a
	sbc hl,de
	inc l
	ld a,l
	ld (CF_W),a
	ld a,(CF_Y2)
	ld hl,CF_Y1
	sub (hl)
	inc a
	ld (CF_H),a
	; top, bottom, left, right
	ld de,(CF_X1)
	ld a,(CF_Y1)
	ld c,a
	ld a,(CF_W)
	ld b,a
	ld l,1
	call .rect
	ld de,(CF_X1)
	ld a,(CF_Y2)
	ld c,a
	ld a,(CF_W)
	ld b,a
	ld l,1
	call .rect
	ld de,(CF_X1)
	ld a,(CF_Y1)
	ld c,a
	ld b,1
	ld a,(CF_H)
	ld l,a
	call .rect
	ld hl,(CF_X1)
	ld a,(CF_W)
	dec a
	ld e,a
	ld d,0
	add hl,de
	ex de,hl
	ld a,(CF_Y1)
	ld c,a
	ld b,1
	ld a,(CF_H)
	ld l,a
.rect:	ld a,(CG_HLCOL)
	jp FILL_RECT

; CG_BLACK_BOX - drawBox(boxX, boxY, boxX + 32, boxY + 33) in black: the
;   frame of the active box (as CG_HL_DRAW of frame 6 + box)
CG_BLACK_BOX:
	ld a,(CG_HLB)
	push af
	ld a,(CG_BOX)
	add a,6
	ld (CG_HLB),a
	ld a,C_BLACK
	call CG_HL_DRAW
	pop af
	ld (CG_HLB),a
	ret

; CG_SPARK_TICK - every two ticks the next sparkle over the empty box
CG_SPARK_TICK:
	ld hl,CG_SPT
	dec (hl)
	ret nz
	ld (hl),2
	ld hl,CG_SPI
	ld a,(hl)
	inc a
	cp 10
	jr c,.s
	xor a
.s:	ld (hl),a
	; the box (its body in CCARGENB: box * 32, row 128)
	ld a,(CG_BOX)
	add a,a
	add a,a
	call CG_X8
	ld de,CG_BOTTOM_X
	add hl,de
	ld (CB_SX),hl
	ld hl,CG_BOTTOM_Y
	ld (CB_SY),hl
	call .dest
	ld a,V9_LOG_COPY
	call CG_BLIT
	ld a,(CG_SPI)
	add a,a
	add a,a
	call CG_X8
	ld de,CG_SPARKS_X
	add hl,de
	ld (CB_SX),hl
	ld hl,CG_SPARKS_Y
	ld (CB_SY),hl
	call .dest
	ld a,V9_LOG_TCOPY
	jp CG_BLIT
.dest:	call CG_BOXXY
	ld (CB_DX),de
	inc c
	ld l,c
	ld h,0
	ld (CB_DY),hl
	ld hl,32
	ld (CB_W),hl
	ld (CB_H),hl
	ret

; CG_BOXXY - DE = x, C = y of the box CG_BOX (_chargenBoxX / Y)
CG_BOXXY:
	ld a,(CG_BOX)
	ld de,16
	bit 0,a
	jr z,.x
	ld e,80
.x:	ld c,63
	bit 1,a
	ret z
	ld c,127
	ret

; ----------------------------------------------------------------------------
; Texts
; ----------------------------------------------------------------------------
; CG_TEXT - HL = text (13 = new line), DE = x, C = y, A = colour: with the
;   black shadow of printShadedText (left, below, left below)
; CG_TEXTN - the same without the shadow
CG_TEXT:
	ld b,C_BLACK
	jr CT_GO
CG_TEXTN:
	ld b,0
CT_GO:	ld (CT_COL),a
	ld a,b
	ld (CT_SH),a
	ld (CT_X),de
	ld a,c
	ld (CT_Y),a
.line:	ld de,CT_BUF
.cp:	ld a,(hl)
	or a
	jr z,.end
	inc hl
	cp 13
	jr z,.end
	ld (de),a
	inc de
	jr .cp
.end:	push af
	xor a
	ld (de),a
	push hl
	call CT_LINE
	pop hl
	pop af
	or a
	ret z
	ld a,(TXT_FH)
	ld b,a
	ld a,(CT_Y)
	add a,b
	ld (CT_Y),a
	jr .line

CT_LINE:
	ld a,(CT_SH)
	or a
	jr z,.text
	ld hl,(CT_X)
	dec hl
	ex de,hl
	ld a,(CT_Y)
	ld c,a
	call .sh
	ld de,(CT_X)
	ld a,(CT_Y)
	inc a
	ld c,a
	call .sh
	ld hl,(CT_X)
	dec hl
	ex de,hl
	ld a,(CT_Y)
	inc a
	ld c,a
	call .sh
.text:	ld hl,CT_BUF
	ld de,(CT_X)
	ld a,(CT_Y)
	ld c,a
	ld a,(CT_COL)
	ld b,0
	jp TEXT_PRINT
.sh:	ld hl,CT_BUF
	ld a,(CT_SH)
	ld b,0
	jp TEXT_PRINT

; CG_CENTER - HL = text: DE = the x that centres it in the panel
CG_CENTER:
	push hl
	ld b,0
.l:	ld a,(hl)
	or a
	jr z,.e
	inc hl
	inc b
	jr .l
.e:	ld a,160/2
	ld c,b
	sla c
	sla c			; len * 8 / 2
	sub c
	jr nc,.ok
	xor a
.ok:	ld e,a
	ld d,0
	ld hl,144
	add hl,de
	ex de,hl
	pop hl
	ret

; ----------------------------------------------------------------------------
; The statistics of a character in the panel (printStats); mode 0 plain,
;   1 with REROLL MODIFY FACES KEEP, 2 with DELETE OK, 3 with + - OK, 4
;   without the portrait
; ----------------------------------------------------------------------------
CG_STATS:
	ld (CS_MODE),a
	call CG_PANEL
	ld a,(CG_BOX)
	call CHAR_PTR
	ld a,(CS_MODE)
	cp 4
	jr z,.nf
	ld e,(iy+P_FACE)
	ld d,0
	ld hl,SHP_FACE0
	add hl,de
	ld de,CG_FACEX
	ld c,CG_FACEY
	ld a,V9_LOG_COPY
	call BLIT_SCREEN
	ld a,(CG_BOX)
	call CHAR_PTR
.nf:	; name, race, class (centred)
	push iy
	pop hl
	inc hl
	call CG_CENTER
	ld c,99
	ld a,C_WHITE
	call CG_TEXT
	ld a,(iy+P_RACE)
	ld hl,CG_RACE
	call CG_STR
	call CG_CENTER
	ld c,109
	ld a,C_WHITE
	call CG_TEXT
	ld a,(iy+P_CLASS)
	ld hl,CG_CLASS
	call CG_STR
	call CG_CENTER
	ld c,118
	ld a,C_WHITE
	call CG_TEXT
	; the six labels and their values
	ld b,0
.st:	push bc
	ld a,b
	ld hl,CG_STAT
	call CG_STR
	pop bc
	push bc
	ld a,b
	add a,a
	add a,a
	add a,a
	add a,128
	ld c,a
	ld de,147
	ld a,C_WHITE
	call CG_TEXT
	pop bc
	push bc
	ld a,b
	call CG_STATVAL		; HL = the value as text
	pop bc
	push bc
	ld a,b
	add a,a
	add a,a
	add a,a
	add a,128
	ld c,a
	ld de,176
	ld a,C_WHITE
	call CG_TEXT
	pop bc
	inc b
	ld a,b
	cp 6
	jr c,.st
	ld hl,CG_S1_2		; "AC HP LVL"
	ld de,232
	ld c,128
	ld a,C_WHITE
	call CG_TEXT
	ld a,6			; armour class
	call CG_STATVAL
	ld de,264
	ld c,128
	ld a,C_WHITE
	call CG_TEXT
	ld a,7			; hit points
	call CG_STATVAL
	ld de,264
	ld c,136
	ld a,C_WHITE
	call CG_TEXT
	call CG_LEVELS
	ld de,264
	ld c,144
	ld a,C_WHITE
	call CG_TEXT
	; the buttons of the mode
	ld a,(CS_MODE)
	ld hl,CS_B1
	cp 1
	jr z,.btn
	ld hl,CS_B2
	cp 2
	jr z,.btn
	ld hl,CS_B3
	cp 3
	ret nz
.btn:	ld a,(hl)
	inc a
	ret z
	dec a
	push hl
	ld c,0
	call CG_BUTTON
	pop hl
	inc hl
	jr .btn
CS_B1:	db 4, 7, 8, 6, 0FFh
CS_B2:	db 16, 9, 0FFh
CS_B3:	db 10, 11, 9, 0FFh

; CG_STR - HL = table of texts, A = index -> HL = the text
CG_STR:
	add a,a
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ret

; CG_STATVAL - A = 0..5 a statistic, 6 armour class, 7 hit points of
;   character CG_BOX -> HL = text (getCharStrength for the strength)
CG_STATVAL:
	push af
	ld a,(CG_BOX)
	call CHAR_PTR
	pop af
	ld e,a
	ld d,0
	ld hl,CS_FIELDS
	add hl,de
	ld e,(hl)
	push iy
	pop hl
	add hl,de
	ld a,e
	cp P_STR
	ld a,(hl)
	jr nz,CG_NUM
	ld b,a
	ld a,(iy+P_STREXT)
	or a
	ld a,b
	jr z,CG_NUM
	; "18/xx" (100: "18/00")
	call NUM_STR
	ld de,CG_NUMBUF
	call .cp
	ld a,'/'
	ld (de),a
	inc de
	ld a,(iy+P_STREXT)
	cp 100
	jr c,.e
	xor a
.e:	ld b,'0'-1
.t:	inc b
	sub 10
	jr nc,.t
	add a,10+'0'
	ld c,a
	ld a,b
	ld (de),a
	inc de
	ld a,c
	ld (de),a
	inc de
	xor a
	ld (de),a
	ld hl,CG_NUMBUF
	ret
.cp:	ld a,(hl)
	or a
	ret z
	ld (de),a
	inc hl
	inc de
	jr .cp
CS_FIELDS:	db P_STR, P_INT, P_WIS, P_DEX, P_CON, P_CHA, P_AC, P_HPMAX

; CG_NUM - A = signed number -> HL = text
CG_NUM:
	bit 7,a
	jp z,NUM_STR
	neg
	call NUM_STR
	dec hl
	ld (hl),'-'
	ret

; CG_LEVELS - HL = "a", "a/b" or "a/b/c" (the levels of CG_BOX)
CG_LEVELS:
	ld a,(CG_BOX)
	call CHAR_PTR
	ld de,CG_NUMBUF
	ld b,0
.l:	push bc
	push de
	ld a,b
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld de,P_LEVELS
	add hl,de
	ld a,(hl)
	pop de
	pop bc
	or a
	jr z,.end
	push bc
	push de
	call NUM_STR
	pop de
	call CG_STATVAL.cp
	pop bc
	ld a,'/'
	ld (de),a
	inc de
	inc b
	ld a,b
	cp 3
	jr c,.l
.end:	dec de			; the last "/" goes
	xor a
	ld (de),a
	ld hl,CG_NUMBUF
	ret

; CG_NAMEFIELD - the name of the character of CG_BOX under its box
;   (processNameInput): black field, the name centred in the small font
CG_NAMEFIELD:
	ld (CN_COL),a
	ld a,(CG_BOX)
	ld de,2
	bit 0,a
	jr z,.x
	ld e,66
.x:	ld c,107
	bit 1,a
	jr z,.y
	ld c,171
.y:	ld (CN_X),de
	ld a,c
	ld (CN_Y),a
	ld b,60
	ld l,6
	ld a,C_BLACK
	call FILL_RECT
	call TEXT_FONT6
	ld a,(CG_BOX)
	call CHAR_PTR
	push iy
	pop hl
	inc hl
	ld b,0
	push hl
.l:	ld a,(hl)
	or a
	jr z,.e
	inc hl
	inc b
	jr .l
.e:	pop hl
	ld a,b			; x + (60 - len * 6) / 2
	add a,a
	add a,b
	ld b,a			; len * 3
	ld a,30
	sub b
	jr nc,.ok
	xor a
.ok:	ld e,a
	ld d,0
	push hl
	ld hl,(CN_X)
	add hl,de
	ex de,hl
	pop hl
	ld a,(CN_Y)
	ld c,a
	ld a,(CN_COL)
	ld b,0
	call TEXT_PRINT
	jp TEXT_FONT8

; CG_FACEBOX - the portrait of CG_BOX in its box (processFaceMenuSelection)
CG_FACEBOX:
	ld a,(CG_BOX)
	call CHAR_PTR
	ld e,(iy+P_FACE)
	ld d,0
	ld hl,SHP_FACE0
	add hl,de
	push hl
	call CG_BOXXY
	inc c
	pop hl
	ld a,V9_LOG_COPY
	jp BLIT_SCREEN

; ----------------------------------------------------------------------------
; A character that exists: its statistics, DELETE or OK; the boxes switch
; (viewDeleteCharacter) -> A = 1 if PLAY was chosen
; ----------------------------------------------------------------------------
CG_VIEW:
	ld a,2
	call CG_STATS
.lp:	ld a,(CG_BOX)
	call CG_HASNAME
	jp z,.out		; deleted, or an empty box chosen
	ld a,(CG_BOX)
	add a,6
	call CG_HL_SET
	call CG_POLL
	ld a,(CG_BOX)
	ld (CV_NEW),a
	ld a,(CG_K)
	cp KEY_USE
	jp z,.ok
	cp KEY_ESC
	jr z,.ok
	ld hl,CV_NEW
	cp KEY_TLEFT
	jr z,.x
	cp KEY_TRIGHT
	jr nz,.ny
.x:	ld a,(hl)
	xor 1
	ld (hl),a
	jr .sw
.ny:	cp KEY_FWD
	jr z,.y
	cp KEY_BACK
	jr nz,.cl
.y:	ld a,(hl)
	xor 2
	ld (hl),a
	jr .sw
.cl:	ld a,(CG_C)
	or a
	jr z,.lp
	ld hl,CG_L_VIEW
	ld b,7
	call CG_HIT
	cp 4
	jr z,.play
	cp 5
	jr z,.ok
	cp 6
	jr z,.del
	jr nc,.lp
	ld (CV_NEW),a
.sw:	; another box
	ld a,(CV_NEW)
	ld hl,CG_BOX
	cp (hl)
	jr z,.lp
	push af
	ld a,0FFh
	call CG_HL_SET
	pop af
	ld (CG_BOX),a
	call CG_HASNAME
	jr z,.out
	ld a,2
	call CG_STATS
	jp .lp
.del:	ld a,16
	call CG_PRESS
	ld a,(CG_BOX)
	call CHAR_PTR
	ld (iy+P_NAME),0
	ld a,C_BLACK
	call CG_NAMEFIELD
	ld a,(CG_BOX)		; the empty box again
	ld c,0
	call CG_BUTTON
	jp .lp
.ok:	ld a,9
	call CG_PRESS
.out:	ld a,0FFh
	call CG_HL_SET
	xor a
	ret
.play:	ld a,0FFh
	call CG_HL_SET
	ld a,1
	ret

; ----------------------------------------------------------------------------
; A new character in box CG_BOX (createPartyMember)
; ----------------------------------------------------------------------------
CG_CREATE:
	ld a,1
	ld (CG_SPARKON),a
	ld (CG_SPT),a
	call CG_BLACK_BOX
	ld a,(CG_BOX)
	call CHAR_PTR
	ld (iy+P_NAME),0
.race:	call CG_RACEMENU
	ld (iy+P_RACE),a
.class:	call CG_CLASSMENU
	inc a
	jr z,.race
	dec a
	ld (iy+P_CLASS),a
	call CG_ALIGNMENU
	inc a
	jr z,.class
	dec a
	ld (iy+P_ALIGN),a
	call CG_GENSTATS
	call CG_STATSFACES
	xor a
	ld (CG_SPARKON),a
	; the name, until there is one
.name:	call CG_FACEBOX
	xor a
	call CG_STATS
	ld hl,CG_NAME_T
	ld de,149
	ld c,100
	ld a,CG_C_LIGHTBLUE
	call CG_TEXT
	call CG_INPUT
	ld a,(CG_BOX)
	call CHAR_PTR
	ld a,(iy+P_NAME)
	or a
	jr z,.name
	ld a,C_BLUE
	jp CG_NAMEFIELD

; CG_RACEMENU -> A = race and sex (raceSexMenu)
CG_RACEMENU:
	ld hl,CG_RACE_T
	ld (CM_TITLE),hl
	ld hl,CG_RACE
	ld (CM_STRS),hl
	ld hl,0FFFFh
	ld (CM_MASK),hl
	ld a,12
	ld (CM_MAX),a
	xor a
	ld (CM_BACK),a
	call CG_MENU
	push af
	ld a,(CG_BOX)
	call CHAR_PTR
	pop af
	ret

; CG_CLASSMENU -> A = class, FFh back (classMenu)
CG_CLASSMENU:
	ld hl,0FFFFh		; an evil character in the party: no paladin
	ld b,4
.ev:	push bc
	ld a,b
	dec a
	call CHAR_PTR
	pop bc
	ld a,(iy+P_NAME)
	or a
	jr z,.ne
	ld a,(iy+P_ALIGN)
	cp 6
	jr c,.ne
	ld l,0FBh
.ne:	djnz .ev
	push hl
	ld a,(CG_BOX)
	call CHAR_PTR
	ld a,(iy+P_RACE)
	srl a
	add a,a
	ld e,a
	ld d,0
	ld hl,CG_CLASS_MASKS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	pop hl
	ld a,l
	and e
	ld l,a
	ld a,h
	and d
	ld h,a
	ld (CM_MASK),hl
	ld hl,CG_CLASS_T
	ld (CM_TITLE),hl
	ld hl,CG_CLASS
	ld (CM_STRS),hl
	ld a,15
	ld (CM_MAX),a
	ld a,1
	ld (CM_BACK),a
	call CG_MENU
	push af
	ld a,(CG_BOX)
	call CHAR_PTR
	pop af
	ret

; CG_ALIGNMENU -> A = alignment, FFh back (alignmentMenu)
CG_ALIGNMENU:
	ld hl,0FFFFh		; a paladin in the party: no evil
	ld b,4
.pa:	push bc
	ld a,b
	dec a
	call CHAR_PTR
	pop bc
	ld a,(iy+P_NAME)
	or a
	jr z,.np
	ld a,(iy+P_CLASS)
	cp 2
	jr nz,.np
	ld hl,0FE3Fh
.np:	djnz .pa
	push hl
	ld a,(CG_BOX)
	call CHAR_PTR
	ld a,(iy+P_CLASS)
	add a,a
	ld e,a
	ld d,0
	ld hl,CG_ALIGN_MASKS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	pop hl
	ld a,l
	and e
	ld l,a
	ld a,h
	and d
	ld h,a
	ld (CM_MASK),hl
	ld hl,CG_ALIGN_T
	ld (CM_TITLE),hl
	ld hl,CG_ALIGN
	ld (CM_STRS),hl
	ld a,9
	ld (CM_MAX),a
	ld a,1
	ld (CM_BACK),a
	call CG_MENU
	push af
	ld a,(CG_BOX)
	call CHAR_PTR
	pop af
	ret

; ----------------------------------------------------------------------------
; CG_MENU - a list in the panel (simpleMenu_setup / process): CM_TITLE,
;   CM_STRS (table of texts), CM_MASK (bit n: item n is there), CM_MAX,
;   CM_BACK (the BACK button) -> A = the item, FFh back
; ----------------------------------------------------------------------------
CM_X:		equ 152
CM_Y:		equ 80
CG_MENU:
	; the items there
	ld hl,(CM_MASK)
	ld de,CM_LIST
	ld b,0
	ld c,0
.it:	ld a,b
	ld a,(CM_MAX)
	cp b
	jr z,.got
	srl h
	rr l
	jr nc,.no
	ld a,b
	ld (de),a
	inc de
	inc c
.no:	inc b
	jr .it
.got:	ld a,c
	ld (CM_N),a
	call CG_PANEL
	ld hl,(CM_TITLE)
	ld de,147
	ld c,67
	ld a,CG_C_LIGHTBLUE
	call CG_TEXT
	ld a,(CM_BACK)
	or a
	jr z,.nb
	ld a,5
	ld c,0
	call CG_BUTTON
.nb:	xor a
	ld (CM_CUR),a
	ld b,0
.pr:	ld a,(CM_N)
	cp b
	jr z,.loop
	push bc
	ld a,b
	call CM_ITEM
	pop bc
	inc b
	jr .pr
.loop:	call CG_POLL
	; the pointer over an item: it is the chosen one
	call CM_MOUSE
	cp 0FFh
	jr z,.key
	ld hl,CM_CUR
	cp (hl)
	call nz,CM_MOVE
	ld a,(CG_C)
	or a
	jr z,.key
	jr .take
.key:	ld a,(CG_C)		; a click elsewhere: BACK?
	or a
	jr z,.k
	ld a,(CM_BACK)
	or a
	jr z,.k
	ld hl,CG_L_BACK
	ld b,1
	call CG_HIT
	or a
	jr z,.back
.k:	ld a,(CG_K)
	cp KEY_ESC
	jr nz,.k1
	ld a,(CM_BACK)
	or a
	jr nz,.back
.k1:	ld a,(CG_K)
	cp KEY_USE
	jr z,.take
	cp KEY_FWD
	jr nz,.k2
	ld a,(CM_CUR)
	dec a
	jp p,.mv
	ld a,(CM_N)
	dec a
	jr .mv
.k2:	cp KEY_BACK
	jr nz,.loop
	ld a,(CM_CUR)
	inc a
	ld hl,CM_N
	cp (hl)
	jr c,.mv
	xor a
.mv:	call CM_MOVE
	jr .loop
.take:	; the chosen one flashes (simpleMenu_flashSelection)
	ld b,3
.fl:	push bc
	ld a,C_LIGHTRED
	call .one
	ld a,C_WHITE
	call .one
	pop bc
	djnz .fl
	ld a,(CM_CUR)
	ld e,a
	ld d,0
	ld hl,CM_LIST
	add hl,de
	ld a,(hl)
	ret
.one:	ld (CM_COL),a
	ld a,(CM_CUR)
	call CM_TEXTXY
	ld a,(CM_COL)
	call CG_TEXTN
	ld b,2
.w:	push bc
	call CG_FRAME
	pop bc
	djnz .w
	ret
.back:	ld a,5
	call CG_PRESS
	ld a,0FFh
	ret

; CM_MOVE - A = item: the highlight goes there
CM_MOVE:
	push af
	ld a,(CM_CUR)
	ld b,a
	pop af
	ld (CM_CUR),a
	ld a,b
	call CM_ITEM
	ld a,(CM_CUR)
; CM_ITEM - A = item: printed (white with its shadow, red if current)
CM_ITEM:
	ld (CM_I),a
	call CM_TEXTXY
	ld a,C_WHITE
	push hl
	push de
	push bc
	call CG_TEXT
	pop bc
	pop de
	pop hl
	ld a,(CM_I)
	push hl
	ld hl,CM_CUR
	cp (hl)
	pop hl
	ret nz
	ld a,C_LIGHTRED
	jp CG_TEXTN

; CM_TEXTXY - A = item -> HL = text, DE = x, C = y
CM_TEXTXY:
	push af
	ld e,a
	ld d,0
	ld hl,CM_LIST
	add hl,de
	ld a,(hl)
	ld hl,(CM_STRS)
	call CG_STR
	pop af
	add a,a
	add a,a
	add a,a
	add a,CM_Y
	ld c,a
	ld de,CM_X
	ret

; CM_MOUSE -> A = item under the pointer or FFh
CM_MOUSE:
	ld hl,(MOUSE_X)
	ld de,CM_X
	or a
	sbc hl,de
	jr c,.no
	ld de,152
	sbc hl,de
	jr nc,.no
	ld a,(MOUSE_Y)
	sub CM_Y
	jr c,.no
	rrca
	rrca
	rrca
	and 1Fh
	ld hl,CM_N
	cp (hl)
	ret c
.no:	ld a,0FFh
	ret

; ----------------------------------------------------------------------------
; The rolls (generateStats)
; ----------------------------------------------------------------------------
CG_GENSTATS:
	ld a,(CG_BOX)
	call CHAR_PTR
	; levels and experience
	ld a,(iy+P_CLASS)
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld hl,CG_START_LEVELS
	add hl,de
	ld a,(hl)
	ld (iy+P_LEVELS),a
	ld (iy+P_LEVEL),a
	inc hl
	ld a,(hl)
	ld (iy+P_LEVELS+1),a
	inc hl
	ld a,(hl)
	ld (iy+P_LEVELS+2),a
	inc hl
	ld a,(hl)		; 5000 / the number of classes
	push iy
	ld hl,5000
	call DIV16_8
	pop iy
	ld b,3
	push iy
	pop ix
.ex:	ld (ix+P_EXP),l
	ld (ix+P_EXP+1),h
	ld (ix+P_EXP+2),0
	ld (ix+P_EXP+3),0
	inc ix
	inc ix
	inc ix
	inc ix
	djnz .ex
	; minimum and maximum of each statistic
	ld a,(iy+P_RACE)
	srl a
	ld c,a
	add a,a
	add a,c
	add a,a			; race * 6
	ld (CS_R6),a
	ld a,(iy+P_CLASS)
	ld c,a
	add a,a
	add a,c
	add a,a			; class * 6
	ld e,a
	ld d,0
	ld hl,CG_CLASS_MIN
	add hl,de
	push hl
	ld a,(CS_R6)
	ld e,a
	ld hl,CG_RACE_MIN
	add hl,de
	ex de,hl
	pop hl
	ld ix,CG_MIN
	ld b,6
.mn:	ld a,(de)
	cp (hl)
	jr nc,.m1
	ld a,(hl)
.m1:	ld (ix+0),a
	inc hl
	inc de
	inc ix
	djnz .mn
	ld a,(CS_R6)
	add a,a
	ld e,a
	ld d,0
	ld hl,CG_RACE_MAX
	add hl,de
	ld de,CG_MAX
	ld b,6
.mx:	ld a,(hl)
	ld (de),a
	inc hl
	inc hl
	inc de
	djnz .mx
	ld a,(CS_R6)
	add a,a
	ld e,a
	ld d,0
	ld hl,CG_RACE_MAX+1
	add hl,de
	ld a,(hl)
	ld (CG_MAXEXT),a
	ld e,(iy+P_CLASS)	; no exceptional strength but for the fighters
	ld d,0
	ld hl,CLASS_MODIFIER
	add hl,de
	ld a,(hl)
	or a
	jr z,.f
	ld a,18
	ld (CG_MAX),a
	xor a
	ld (CG_MAXEXT),a
.f:	; the six rolls
	ld b,0
.roll:	push bc
	call CG_ROLL4
	ld c,a
	ld a,(CS_R6)
	pop de
	push de
	add a,d
	ld e,a
	ld d,0
	ld hl,CG_RACE_MOD
	add hl,de
	ld a,(hl)
	add a,c			; + the race
	pop bc
	push bc
	ld e,b
	ld d,0
	ld hl,CG_MIN
	add hl,de
	cp (hl)
	jp p,.mok
	ld a,(hl)
.mok:	ld (CS_V),a
	xor a
	ld (CS_X),a
	ld a,b
	or a
	jr nz,.cap
	ld a,(CS_V)
	cp 18
	jr nz,.cap
	ld a,100		; 18: the exceptional strength 1d100
	call RND_RANGE
	ld (CS_X),a
.cap:	; above the maximum: the maximum (u16 ext << 8 | value)
	ld hl,CG_MAX
	add hl,de
	ld a,(CS_V)
	cp (hl)
	jr c,.ok
	jr nz,.max
	ld a,b
	or a
	jr nz,.ok
	ld a,(CG_MAXEXT)
	ld c,a
	ld a,(CS_X)
	cp c
	jr c,.ok
	jr z,.ok
	ld a,c
	ld (CS_X),a
	jr .ok
.max:	ld a,(hl)
	ld (CS_V),a
	ld a,b
	or a
	jr nz,.ok
	ld a,(CG_MAXEXT)
	ld (CS_X),a
.ok:	ld e,b
	ld d,0
	ld hl,CS_FIELDS
	add hl,de
	ld e,(hl)
	push iy
	pop hl
	add hl,de
	ld a,(CS_V)
	ld (hl),a
	ld a,b
	or a
	jr nz,.nx
	ld a,(CS_X)
	ld (iy+P_STREXT),a
.nx:	pop bc
	inc b
	ld a,b
	cp 6
	jp c,.roll
	; armour class, hit points
	call CG_AC
	jp CG_HITPOINTS

; CG_ROLL4 - 4d6 without the lowest -> A
CG_ROLL4:
	ld b,4
	ld c,10
	ld e,0
.lp:	ld a,6
	call RND_RANGE
	cp c
	jr nc,.m
	ld c,a
.m:	add a,e
	ld e,a
	djnz .lp
	ld a,e
	sub c
	ret

; CG_AC - IY = character: 10 + the dexterity modifier
CG_AC:
	ld e,(iy+P_DEX)
	ld d,0
	ld hl,CG_DEX_AC
	add hl,de
	ld a,(hl)
	add a,10
	ld (iy+P_AC),a
	ret

; CG_CONMOD - IY = character -> A = hit points per level from the
;   constitution (getClassAndConstHitpointsModifier)
CG_CONMOD:
	ld e,(iy+P_CON)
	ld d,0
	ld hl,CG_HP_CON
	add hl,de
	ld a,(hl)
	cp 3
	ret m			; <= 2
	ld e,(iy+P_CLASS)
	ld hl,CLASS_FLAGS
	add hl,de
	ld c,a
	ld a,(hl)
	and 31h
	ld a,c
	ret nz
	ld a,2
	ret

; CG_HITPOINTS - IY = character: the hit dice of its levels
;   (generateCharacterHitpointsByLevel)
CG_HITPOINTS:
	xor a
	ld (CS_HP),a
	ld b,0			; class index
.cl:	push bc
	call CG_CTYPE		; A = class type, C if none
	jr c,.nc
	ld (CS_T),a
	ld e,b
	ld d,0
	push iy
	pop hl
	add hl,de
	ld de,P_LEVELS
	add hl,de
	ld a,(hl)
	ld (CS_LV),a
	or a
	jr z,.nc
	ld b,a
.lv:	push bc
	; roll or the fixed bonus
	ld a,(CS_T)
	ld e,a
	ld d,0
	ld hl,CG_HP_INCR+6
	add hl,de
	ld a,(CS_LV)
	cp (hl)
	jr z,.roll
	jr c,.roll
	ld hl,CG_HP_INCR+12
	add hl,de
	ld a,(hl)
	jr .con
.roll:	ld hl,CG_HP_INCR
	add hl,de
	ld a,(hl)
	call RND_RANGE
.con:	push af
	call CG_CONMOD
	pop bc
	add a,b			; signed
	dec a
	jp m,.one		; <= 0
	inc a
	ld l,a
	ld h,0
	ld e,(iy+P_CLASS)
	ld d,0
	push hl
	ld hl,LEVELS_PER_CLASS
	add hl,de
	ld a,(hl)
	pop hl
	push iy
	call DIV16_8
	pop iy
	ld a,l
	or a
	jr nz,.add
.one:	ld a,1
.add:	ld hl,CS_HP
	add a,(hl)
	ld (hl),a
	pop bc
	djnz .lv
.nc:	pop bc
	inc b
	ld a,b
	cp 3
	jr c,.cl
	ld a,(CS_HP)
	ld (iy+P_HP),a
	ld (iy+P_HPMAX),a
	ret

; CG_CTYPE - IY = character, B = class index -> A = class type, C if none
CG_CTYPE:
	ld a,(iy+P_CLASS)
	ld c,a
	add a,a
	add a,c
	add a,b
	ld e,a
	ld d,0
	ld hl,CG_CLASS_TYPE
	add hl,de
	ld a,(hl)
	or a
	ret p
	scf
	ret

; CG_HPLIMIT - IY = character, C = 0 the most, 1 the least hit points its
;   levels can have (getMaxHp / getMinHp) -> A
CG_HPLIMIT:
	ld a,c
	ld (CS_MODE2),a
	call CG_CONMOD
	ld (CS_CM),a
	ld hl,0
	ld (CS_SUM),hl
	ld b,0
.cl:	push bc
	call CG_CTYPE
	jr c,.nc
	ld (CS_T),a
	ld e,b
	ld d,0
	push iy
	pop hl
	add hl,de
	ld de,P_LEVELS
	add hl,de
	ld a,(hl)
	ld (CS_LV),a
	; s = min(level, HP_INCR[6 + t])
	ld a,(CS_T)
	ld e,a
	ld d,0
	ld hl,CG_HP_INCR+6
	add hl,de
	ld a,(CS_LV)
	cp (hl)
	jr c,.s
	ld a,(hl)
.s:	ld (CS_S),a
	ld l,a
	ld h,0
	ld a,(CS_MODE2)
	or a
	jr nz,.m
	push hl
	ld hl,CG_HP_INCR
	add hl,de
	ld a,(hl)
	pop hl
	ld e,l
	call MUL8
.m:	; + (level - s) * HP_INCR[12 + t]
	ld a,(CS_S)
	ld c,a
	ld a,(CS_LV)
	sub c
	jr z,.k
	push hl
	ld e,a
	ld a,(CS_T)
	ld c,a
	ld b,0
	ld hl,CG_HP_INCR+12
	add hl,bc
	ld a,(hl)
	call MUL8
	pop de
	add hl,de
.k:	; + level * con (always for the most, for the least if > 0)
	ld a,(CS_MODE2)
	or a
	jr z,.c
	ld a,(CS_CM)
	dec a
	jp m,.add
.c:	ld a,(CS_LV)
	ld b,a
	ld a,(CS_CM)
	ld e,a
	rla
	sbc a,a
	ld d,a
	inc b
	jr .c2
.c1:	add hl,de
.c2:	djnz .c1
.add:	ld de,(CS_SUM)
	add hl,de
	ld (CS_SUM),hl
.nc:	pop bc
	inc b
	ld a,b
	cp 3
	jp c,.cl
	ld e,(iy+P_CLASS)
	ld d,0
	ld hl,LEVELS_PER_CLASS
	add hl,de
	ld a,(hl)
	ld hl,(CS_SUM)
	push iy
	call DIV16_8
	pop iy
	ld a,l
	ret

; ----------------------------------------------------------------------------
; The statistics with REROLL, MODIFY, FACES, KEEP (statsAndFacesMenu)
; ----------------------------------------------------------------------------
CG_STATSFACES:
	call CG_FACES
.show:	ld a,1
	call CG_STATS
.lp:	call CG_POLL
	ld a,(CG_K)
	cp KEY_USE
	jr z,.keep
	ld a,(CG_C)
	or a
	jr z,.lp
	ld hl,CG_L_STATS
	ld b,4
	call CG_HIT
	or a
	jr z,.reroll
	dec a
	jr z,.modify
	dec a
	jr z,.faces
	dec a
	jr nz,.lp
.keep:	ld a,6			; KEEP
	call CG_PRESS
	ld a,(CG_BOX)
	add a,6
	call CG_HL_SET
	ld a,0FFh
	jp CG_HL_SET
.reroll:
	ld a,4
	call CG_PRESS
	call CG_GENSTATS
	jr .show
.modify:
	ld a,7
	call CG_PRESS
	call CG_MODIFY
	jr .show
.faces:	ld a,8
	call CG_PRESS
	call CG_FACES
	jr .show

; ----------------------------------------------------------------------------
; The portrait (faceSelectMenu): four at a time, the arrows turn them
; ----------------------------------------------------------------------------
CG_FACES:
	ld a,(CG_BOX)
	call CHAR_PTR
	ld a,(iy+P_RACE)
	and 1
	ld (CF_SEX),a
	ld a,0
	jr z,.m
	ld a,26
.m:	ld c,1
	call CG_NEXTFACE
	ld (CF_SHP),a
	ld a,4
	call CG_STATS
	ld a,12
	ld c,0
	call CG_BUTTON
	ld a,13
	ld c,0
	call CG_BUTTON
	ld a,1
	ld (CF_SEL),a
.show:	; four free portraits from CF_SHP
	ld a,(CF_SHP)
	ld b,0
.four:	push bc
	ld e,b
	ld d,0
	ld hl,CF_SP
	add hl,de
	ld (hl),a
	push af
	ld e,a
	ld d,0
	ld hl,SHP_FACE0
	add hl,de
	push hl
	ld a,b
	add a,a
	add a,a
	call CG_X8
	ld de,176
	add hl,de
	ex de,hl
	pop hl
	ld c,66
	ld a,V9_LOG_COPY
	call BLIT_SCREEN
	pop af
	inc a
	ld c,1
	call CG_NEXTFACE
	pop bc
	inc b
	bit 2,b			; (four: B = 4)
	jr z,.four
.in:	ld a,(CF_SEL)
	add a,10
	call CG_HL_SET
	call CG_POLL
	ld a,(CG_K)
	cp KEY_TRIGHT
	jr z,.right
	cp KEY_TLEFT
	jr z,.left
	cp KEY_USE
	jr z,.take
	ld a,(CG_C)
	or a
	jr z,.in
	ld hl,CG_L_FACES
	ld b,6
	call CG_HIT
	or a
	jr z,.left
	dec a
	jr z,.right
	cp 5
	jr nc,.in
	dec a
	ld (CF_SEL),a
.take:	ld a,0FFh
	call CG_HL_SET
	ld a,(CF_SEL)
	ld e,a
	ld d,0
	ld hl,CF_SP
	add hl,de
	ld a,(hl)
	ld hl,CG_PORT
	ld de,(CG_BOX)
	ld d,0
	add hl,de
	ld (hl),a
	push af
	ld a,(CG_BOX)
	call CHAR_PTR
	pop af
	ld (iy+P_FACE),a
	ret
.left:	ld a,12
	call CG_PRESS
	ld a,(CF_SHP)
	dec a
	ld c,-1
	call CG_NEXTFACE
	ld (CF_SHP),a
	jp .show
.right:	ld a,13
	call CG_PRESS
	ld a,(CF_SHP)
	inc a
	ld c,1
	call CG_NEXTFACE
	ld (CF_SHP),a
	jp .show

; CG_NEXTFACE - A = portrait (FFh = -1: 43), C = step (1 / -1): the first
;   from there on that suits the sex (CF_SEX) and no character has
;   (getNextFreeFaceShape) -> A
CG_NEXTFACE:
	ld b,a
	ld a,c
	ld (CF_STEP),a
	ld a,b
	call .wrap
.lp:	ld (CF_CUR),a
	call .usable
	ld a,(CF_CUR)
	ret z
	ld hl,CF_STEP
	add a,(hl)
	call .wrap
	jr .lp
.wrap:	bit 7,a			; (A < 0 ? 43 : A) % 44
	jr z,.m
	ld a,43
.m:	cp 44
	ret c
	sub 44
	jr .m
.usable:			; Z if CF_CUR suits and is free
	ld a,(CF_SEX)
	or a
	ld a,(CF_CUR)
	jr z,.male
	cp 26
	jr c,.bad
	jr .free
.male:	cp 29
	jr nc,.bad
.free:	ld b,4
.c:	push bc
	ld a,b
	dec a
	call CHAR_PTR
	pop bc
	ld a,(iy+P_NAME)
	or a
	jr z,.n
	ld e,b
	dec e
	ld d,0
	ld hl,CG_PORT
	add hl,de
	ld a,(CF_CUR)
	cp (hl)
	jr z,.bad
.n:	djnz .c
	xor a
	ret
.bad:	or 1
	ret

; ----------------------------------------------------------------------------
; MODIFY: the statistics one by one with + and - (modifyMenu, modifyStat)
; ----------------------------------------------------------------------------
CG_MODIFY:
	ld a,3
	call CG_STATS
	xor a
.lp:	ld (CMO_I),a
	call CG_MODSTAT		; -> A = the next one, FEh done
	cp 0FEh
	jr z,.end
	cp 0FFh
	jr nz,.m
	ld a,6
.m:	cp 7
	jr c,.s
	xor a
.s:	push af
	ld a,3
	call CG_STATS
	pop af
	jr .lp
.end:	ret

; CG_MODSTAT - (CMO_I) = 0..5 a statistic, 6 the hit points -> A = the next
;   one (FFh up from the first), FEh OK
CG_MODSTAT:
	ld a,(CG_BOX)
	call CHAR_PTR
	ld a,(CMO_I)
	cp 6
	jr nz,.nhp
	call CG_HPRANGE
.nhp:	ld a,C_LIGHTRED
	call CMS_SHOW
.lp:	call CG_POLL
	ld a,(CG_K)
	cp KEY_TLEFT
	jr z,.minus
	cp KEY_TRIGHT
	jr z,.plus
	cp KEY_FWD
	jr z,.up
	cp KEY_BACK
	jr z,.down
	cp KEY_ESC
	jr z,.ok
	cp KEY_USE
	jr z,.ok
	ld a,(CG_C)
	or a
	jr z,.lp
	ld hl,CG_L_MOD
	ld b,10
	call CG_HIT
	cp 7
	jr z,.plus
	cp 8
	jr z,.minus
	cp 9
	jr z,.ok
	jr nc,.lp
	ld hl,CMO_I		; another statistic
	cp (hl)
	jr z,.lp
	jr .out
.up:	ld a,(CMO_I)
	dec a
	jr .out
.down:	ld a,(CMO_I)
	inc a
	jr .out
.ok:	ld a,9
	call CG_PRESS
	ld a,0FEh
.out:	push af
	ld a,C_WHITE		; its value white again
	call CMS_VALUE
	pop af
	ret
.plus:	ld a,10
	call CG_PRESS
	ld c,1
	jr .chg
.minus:	ld a,11
	call CG_PRESS
	ld c,-1
.chg:	call CMS_CHANGE
	jp .lp

; CMS_SHOW - A = colour: the value of statistic CMO_I over a clean place
CMS_SHOW:
	ld (CMS_COL),a
	call CMS_XY
	ld b,40
	ld l,8
	call CG_PANEL_PART
	call CMS_XY
	push de
	push bc
	ld a,(CMO_I)
	cp 6
	jr nz,.v
	inc a			; (CG_STATVAL: 7 the hit points)
.v:	call CG_STATVAL
	pop bc
	pop de
	ld a,(CMS_COL)
	jp CG_TEXT

; CMS_VALUE - A = colour: the value printed again, without shadow
CMS_VALUE:
	ld (CMS_COL),a
	ld a,(CMO_I)
	cp 6
	jr nz,.v
	inc a
.v:	call CG_STATVAL
	push hl
	call CMS_XY
	pop hl
	ld a,(CMS_COL)
	jp CG_TEXTN

; CMS_XY - DE = x, C = y of the value of statistic CMO_I
CMS_XY:
	ld a,(CMO_I)
	cp 6
	jr z,.hp
	add a,a
	add a,a
	add a,a
	add a,128
	ld c,a
	ld de,176
	ret
.hp:	ld de,264
	ld c,136
	ret

; CMS_CHANGE - C = +1 / -1: the value of statistic CMO_I changes within
;   its limits; constitution moves the hit points, dexterity the armour
CMS_CHANGE:
	ld a,(CG_BOX)
	call CHAR_PTR
	ld a,(CMO_I)
	or a
	jp z,.str
	cp 6
	jr z,.hp
	ld e,a
	ld d,0
	ld hl,CS_FIELDS
	add hl,de
	ld e,(hl)
	push iy
	pop hl
	add hl,de		; HL = the statistic
	ld a,(hl)
	add a,c
	ld e,a
	ld a,(CMO_I)
	call CMS_CLAMP
	cp (hl)
	ret z
	ld (hl),a
	ld a,C_LIGHTRED
	call CMS_SHOW
	ld a,(CMO_I)
	cp 3
	jr z,.dex
	cp 4
	ret nz
	; constitution: the hit points within the new limits
	call CG_HPRANGE
	ld a,(iy+P_HPMAX)
	ld e,a
	ld a,6
	call CMS_CLAMP
	cp (iy+P_HPMAX)
	ret z
	ld (iy+P_HP),a
	ld (iy+P_HPMAX),a
	ld de,264
	ld c,136
	ld a,7
	jr .other
.dex:	ld a,(iy+P_AC)
	push af
	call CG_AC
	pop af
	cp (iy+P_AC)
	ret z
	ld de,264
	ld c,128
	ld a,6
.other:	; another value of the panel changed (white)
	push af
	push de
	push bc
	ld b,40
	ld l,8
	call CG_PANEL_PART
	pop bc
	pop de
	pop af
	push de
	push bc
	call CG_STATVAL
	pop bc
	pop de
	ld a,C_WHITE
	jp CG_TEXT
.hp:	ld a,(iy+P_HPMAX)
	add a,c
	ld e,a
	ld a,6
	call CMS_CLAMP
	cp (iy+P_HPMAX)
	ret z
	ld (iy+P_HP),a
	ld (iy+P_HPMAX),a
	ld a,C_LIGHTRED
	jp CMS_SHOW
.str:	; strength: 18 then 18/01 .. 18/00 (100) if the class may
	ld a,(iy+P_STR)
	add a,c
	ld b,a			; v1
	ld a,(iy+P_STREXT)
	ld d,a			; v2
.s1:	ld a,b			; above 18: the exceptional strength
	cp 19
	jr c,.s2
	dec b
	inc d
	jr .s1
.s2:	ld a,d
	or a
	jr z,.s3
	ld a,b
	cp 18
	jr nc,.s3
	inc b
	dec d
	jr .s2
.s3:	ld e,b
	xor a
	call CMS_CLAMP
	ld b,a
	cp 18
	jr nz,.s0
	ld a,(CG_MAX)		; the maximum is 18/xx or more?
	cp 19
	jr nc,.sx
	ld a,(CG_MAXEXT)
	or a
	jr z,.s0
.sx:	ld a,d
	cp 101
	jr c,.s4
	ld a,100
	jr .s4
.s0:	xor a
.s4:	ld c,a
	ld a,(iy+P_STR)
	cp b
	jr nz,.sw
	ld a,(iy+P_STREXT)
	cp c
	ret z
.sw:	ld (iy+P_STR),b
	ld (iy+P_STREXT),c
	ld a,C_LIGHTRED
	jp CMS_SHOW

; CMS_CLAMP - E = value, A = statistic 0..6 -> A = within CG_MIN / CG_MAX
CMS_CLAMP:
	push hl
	ld l,a
	ld h,0
	ld bc,CG_MIN
	add hl,bc
	ld a,e
	bit 7,a
	jr nz,.lo
	cp (hl)
	jr nc,.n1
.lo:	ld a,(hl)
.n1:	ld bc,CG_MAX-CG_MIN
	add hl,bc
	cp (hl)
	jr c,.n2
	jr z,.n2
	ld a,(hl)
.n2:	pop hl
	ret

; CG_HPRANGE - IY = character: CG_MIN / CG_MAX + 6 = the limits of its hit
;   points
CG_HPRANGE:
	ld c,0
	call CG_HPLIMIT
	ld (CG_MAX+6),a
	ld c,1
	call CG_HPLIMIT
	ld (CG_MIN+6),a
	ret

; ----------------------------------------------------------------------------
; The name (getTextInput): letters, digits and spaces, BS, RETURN
; ----------------------------------------------------------------------------
CI_X:		equ 192
CI_Y:		equ 100
CI_MAX:		equ 10
CG_INPUT:
	ld a,(CG_BOX)
	call CHAR_PTR
	push iy
	pop hl
	inc hl
	ld (CI_NAME),hl
	ld b,11
.z:	ld (hl),0
	inc hl
	djnz .z
	xor a
	ld (CI_LEN),a
	ld (CI_CUR),a
	ld a,1
	ld (CI_T),a
	ld hl,CI_PREV		; the keys held now do not count
	ld b,9
.p:	ld (hl),0FFh
	inc hl
	djnz .p
.draw:	ld de,CI_X
	ld c,CI_Y
	ld b,(CI_MAX+1)*8
	ld l,9
	call CG_PANEL_PART
	ld hl,(CI_NAME)
	ld de,CI_X
	ld c,CI_Y
	ld a,C_WHITE
	call CG_TEXT
	ld a,(CI_CUR)
	or a
	jr z,.lp
	ld a,(CI_LEN)
	cp CI_MAX
	jr c,.cx
	dec a
.cx:	call CG_X8
	ld de,CI_X
	add hl,de
	ex de,hl
	ld c,CI_Y
	ld b,8
	ld l,8
	ld a,C_DARKRED
	call FILL_RECT
.lp:	call CG_FRAME
	ld hl,CI_T		; the cursor blinks every 4 ticks
	dec (hl)
	jr nz,.k
	ld (hl),12
	ld a,(CI_CUR)
	xor 1
	ld (CI_CUR),a
	jr .draw
.k:	call CI_KEY
	or a
	jr z,.lp
	cp 13
	jr nz,.nr
	ld a,KEY_USE		; (RETURN is no new key for the boxes)
	ld (CG_KLAST),a
	ret
.nr:	ld hl,CI_LEN
	cp 8
	jr nz,.ch
	ld a,(hl)		; BS
	or a
	jr z,.lp
	dec (hl)
	ld e,(hl)
	ld d,0
	ld hl,(CI_NAME)
	add hl,de
	ld (hl),0
	jr .draw
.ch:	ld b,a
	ld a,(hl)
	cp CI_MAX
	jr nc,.lp
	or a			; no space first
	jr nz,.put
	ld a,b
	cp ' '
	jr z,.lp
	xor a
.put:
	inc (hl)
	ld e,a
	ld d,0
	ld hl,(CI_NAME)
	add hl,de
	ld (hl),b
	jp .draw

; CI_KEY -> A = the character of a key just pressed (8 BS, 13 RETURN), 0;
;   letters are capitals (_textInputForceUppercase)
CI_KEY:
	ld c,0
.row:	ld a,c
	push bc
	call KEY_ROW
	pop bc
	cpl			; 1 = pressed
	ld b,a
	ld hl,CI_PREV
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	ld (hl),b
	cpl
	and b			; pressed now, not before
	jr nz,.new
	inc c
	ld a,c
	cp 9
	jr c,.row
	xor a
	ret
.new:	ld b,0			; its first bit
.bit:	rrca
	jr c,.got
	inc b
	jr .bit
.got:	ld a,c
	add a,a
	add a,a
	add a,a
	add a,b
	ld e,a
	ld d,0
	ld hl,CI_MAP
	add hl,de
	ld a,(hl)
	ret
; the MSX keyboard matrix, rows 0..8, bit 0 first
CI_MAP:	db "01234567"
	db "89",0,0,0,0,0,0
	db 0,0,0,0,0,0,"AB"
	db "CDEFGHIJ"
	db "KLMNOPQR"
	db "STUVWXYZ"
	db 0,0,0,0,0,0,0,0
	db 0,0,0,0,0,8,0,13
	db " ",0,0,0,0,0,0,0

; ----------------------------------------------------------------------------
; PLAY: the equipment of the four characters (finish, EOB1)
; ----------------------------------------------------------------------------
CG_FINISH:
	call CG_PANEL
	ld hl,CG_ENTER
	ld de,152
	ld c,96
	ld a,C_WHITE
	call CG_TEXT
	xor a			; the first one carries the letter of Waterdeep
	call CHAR_PTR
	ld hl,35
	call DUPLICATE_ITEM
	ld (iy+P_INV+4),l
	ld (iy+P_INV+5),h
	xor a
.ch:	ld (CFN_I),a
	call CHAR_PTR
	ld (iy+P_FLAGS),1
	ld (iy+P_FOOD),100
	ld a,(iy+P_HP)
	ld (iy+P_HPMAX),a
	ld hl,10		; rations
	call DUPLICATE_ITEM
	ld (iy+P_INV+6),l
	ld (iy+P_INV+7),h
	ld b,0
.it:	push bc
	call CFN_ITEM
	pop bc
	inc b
	ld a,b
	cp 4
	jr c,.it
	ld a,(CFN_I)
	call UCALL
	dw RECALC_AC
	ld a,(CFN_I)
	call CHAR_PTR
	ld e,(iy+P_CLASS)	; mages know some spells of their book
	ld d,0
	ld hl,CLASS_FLAGS
	add hl,de
	bit 1,(hl)
	jr z,.nm
	ld (iy+P_MKNOWN),6Ch
	ld (iy+P_MKNOWN+1),02h
.nm:	ld a,(CFN_I)
	inc a
	cp 4
	jr c,.ch
	ret

; CFN_ITEM - B = 0..3: the item B of the class of character IY
CFN_ITEM:
	ld a,(iy+P_CLASS)
	add a,a
	add a,a
	add a,b
	ld e,a
	ld d,0
	ld hl,CG_ITEMS_IDX
	add hl,de
	ld a,(hl)
	or a
	ret m
	add a,a
	ld e,a
	ld hl,CG_ITEMS
	add hl,de
	ld a,(hl)		; the item
	cp 0FFh
	ret z
	ld (CFN_D),a
	inc hl
	ld a,(hl)		; the slot, FFh a free hand
	cp 0FFh
	jr nz,.sl
	xor a
	call .used
	jr z,.sl
	inc a
	call .used
	jr z,.sl
	inc a
.sl:	ld (CFN_S),a
	cp 2
	jr z,.two
	call .used
	ret nz
.two:	ld a,(CFN_D)		; dwarves: an axe for the short sword
	cp 5
	jr nz,.nd
	ld a,(iy+P_RACE)
	srl a
	cp 3
	jr nz,.nd
	ld a,36
	ld (CFN_D),a
.nd:	ld a,(CFN_S)
	cp 2
	jr nz,.put
.free:	call .used
	jr z,.put
	inc a
	jr .free
.put:	ld (CFN_S),a
	ld a,(CFN_D)
	ld l,a
	ld h,0
	call DUPLICATE_ITEM
	ex de,hl
	ld a,(CFN_S)
	add a,a
	add a,P_INV
	ld c,a
	ld b,0
	push iy
	pop hl
	add hl,bc
	ld (hl),e
	inc hl
	ld (hl),d
	ret
.used:	; A = slot -> Z if it is empty (A kept)
	ld c,a
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld a,(hl)
	inc hl
	or (hl)
	ld a,c
	ret

; ----------------------------------------------------------------------------
; Data
; ----------------------------------------------------------------------------
; _chargenButtonDefsDOS: x (u16), y, w, h
CG_BTN:	dw 8
	db 55, 49, 50
	dw 72
	db 55, 49, 50
	dw 8
	db 119, 49, 50
	dw 72
	db 119, 49, 50
	dw 24
	db 181, 83, 16
	dw 264
	db 172, 38, 16
	dw 224
	db 172, 38, 16
	dw 264
	db 172, 38, 16
	dw 152
	db 80, 154, 8
	dw 152
	db 88, 154, 8
	dw 152
	db 96, 154, 8
	dw 152
	db 104, 154, 8
	dw 152
	db 112, 154, 8
	dw 152
	db 120, 154, 8
	dw 152
	db 128, 154, 8
	dw 152
	db 136, 154, 8
	dw 152
	db 144, 154, 8
	dw 152
	db 152, 154, 8
	dw 152
	db 160, 154, 8
	dw 152
	db 168, 154, 8
	dw 152
	db 176, 154, 8
	dw 144			; 21: the arrows, the four portraits
	db 66, 32, 16
	dw 144
	db 82, 32, 16
	dw 176
	db 66, 32, 32
	dw 208
	db 66, 32, 32
	dw 240
	db 66, 32, 32
	dw 272
	db 66, 32, 32
	dw 224			; 27: REROLL MODIFY FACES KEEP
	db 156, 38, 16
	dw 264
	db 156, 38, 16
	dw 224
	db 172, 38, 16
	dw 264
	db 172, 38, 16
	dw 144			; 31: the statistics, the hit points, + - OK
	db 128, 53, 8
	dw 144
	db 136, 53, 8
	dw 144
	db 144, 53, 8
	dw 144
	db 152, 53, 8
	dw 144
	db 160, 53, 8
	dw 144
	db 168, 53, 8
	dw 232
	db 136, 53, 8
	dw 216
	db 172, 21, 16
	dw 240
	db 172, 21, 16
	dw 264
	db 172, 37, 16
	dw 264			; 41: BACK of the menus
	db 171, 39, 16

CG_L_BOXES:	db 0, 1, 2, 3, 4
CG_L_VIEW:	db 0, 1, 2, 3, 4, 5, 6
CG_L_BACK:	db 41
CG_L_STATS:	db 27, 28, 29, 30
CG_L_FACES:	db 21, 22, 23, 24, 25, 26
CG_L_MOD:	db 31, 32, 33, 34, 35, 36, 37, 38, 39, 40

; _chargenModButtons: label x / 8, y, w / 8, h, its place on the body x, y,
;   the body, where x / 8, y
CG_MODBTN:
	db 00h, 00h, 00h, 00h, 00h, 00h, 00h, 02h, 40h
	db 00h, 00h, 00h, 00h, 00h, 00h, 01h, 0Ah, 40h
	db 00h, 00h, 00h, 00h, 00h, 00h, 02h, 02h, 80h
	db 00h, 00h, 00h, 00h, 00h, 00h, 03h, 0Ah, 80h
	db 00h, 0C0h, 04h, 05h, 07h, 05h, 08h, 1Ch, 9Ch
	db 04h, 0C0h, 03h, 05h, 0Ah, 05h, 08h, 21h, 0ACh
	db 07h, 0C0h, 03h, 05h, 0Bh, 05h, 08h, 21h, 0ACh
	db 0Ah, 0C0h, 04h, 05h, 06h, 05h, 08h, 21h, 9Ch
	db 18h, 0C0h, 03h, 05h, 09h, 05h, 08h, 1Ch, 0ACh
	db 0Eh, 0C0h, 02h, 05h, 0Fh, 05h, 08h, 21h, 0ACh
	db 10h, 0C0h, 01h, 05h, 09h, 05h, 04h, 1Bh, 0ACh
	db 11h, 0C0h, 01h, 01h, 09h, 07h, 04h, 1Eh, 0ACh
	db 12h, 0C0h, 03h, 07h, 07h, 04h, 06h, 12h, 42h
	db 15h, 0C0h, 03h, 07h, 07h, 04h, 06h, 12h, 52h
	db 00h, 00h, 00h, 00h, 00h, 00h, 0Ch, 03h, 0B5h
	db 00h, 00h, 00h, 00h, 00h, 00h, 0Dh, 03h, 0B5h
	db 00h, 00h, 00h, 00h, 00h, 00h, 0Ah, 1Ch, 0ACh
; _chargenButtonBodyCoords: x / 8, y, w / 8, h (in CCARGENB)
CG_BODIES:
	db 00h, 80h, 04h, 20h
	db 04h, 80h, 04h, 20h
	db 08h, 80h, 04h, 20h
	db 0Ch, 80h, 04h, 20h
	db 0Eh, 0A0h, 03h, 10h
	db 0Bh, 0A0h, 03h, 10h
	db 10h, 80h, 04h, 10h
	db 10h, 90h, 04h, 10h
	db 11h, 0A0h, 05h, 10h
	db 11h, 0B0h, 05h, 10h
	db 16h, 0A0h, 05h, 10h
	db 16h, 0B0h, 05h, 10h
	db 00h, 0A0h, 0Bh, 10h
	db 14h, 80h, 0Bh, 10h
	db 14h, 90h, 0Bh, 10h
; GUI_EoB::_highlightFramesDefault 6..13: the boxes, the four portraits
CG_FRAMES:
	dw 10h, 3Fh, 30h, 60h
	dw 50h, 3Fh, 70h, 60h
	dw 10h, 7Fh, 30h, 0A0h
	dw 50h, 7Fh, 70h, 0A0h
	dw 0B0h, 42h, 0D0h, 61h
	dw 0D0h, 42h, 0F0h, 61h
	dw 0F0h, 42h, 110h, 61h
	dw 110h, 42h, 130h, 61h

CG_F_V9:	db LANG_C1,LANG_C2,5Ch,"CHARGEN.V9",0
CG_F_PAL:	db LANG_C1,LANG_C2,5Ch,"CHARGEN.PAL",0
CG_F_SND:	db "CGSND.DAT",0

	include "../build/chargen.inc"

; variables
CG_SAVEY0:	dw 0
CG_MUSIC:	db 0
CG_HLB:		db 0FFh
CG_HLC:		db 0
CG_HLCOL:	db 0
CG_PORT:	ds 4
CG_BOX:		db 0
		db 0
CG_B0:		db 0
CG_SPARKON:	db 0
CG_SPT:		db 0
CG_SPI:		db 0
CG_KLAST:	db 0
CG_K:		db 0
CG_C:		db 0
CG_CPEND:	db 0
CG_TICKF:	db 0
CG_PB:		db 0
CF_X1:		dw 0
CF_Y1:		db 0
CF_Y2:		db 0
CF_W:		db 0
CF_H:		db 0
CT_COL:		db 0
CT_SH:		db 0
CT_X:		dw 0
CT_Y:		db 0
CT_BUF:		ds 48
CS_MODE:	db 0
CG_NUMBUF:	ds 12
CN_COL:		db 0
CN_X:		dw 0
CN_Y:		db 0
CV_NEW:		db 0
CM_TITLE:	dw 0
CM_STRS:	dw 0
CM_MASK:	dw 0
CM_MAX:		db 0
CM_BACK:	db 0
CM_LIST:	ds 16
CM_N:		db 0
CM_CUR:		db 0
CM_COL:		db 0
CM_I:		db 0
CS_R6:		db 0
CS_V:		db 0
CS_X:		db 0
CG_MIN:		ds 7
CG_MAX:		ds 7
CG_MAXEXT:	db 0
CS_HP:		db 0
CS_T:		db 0
CS_LV:		db 0
CS_MODE2:	db 0
CS_CM:		db 0
CS_SUM:		dw 0
CS_S:		db 0
CF_SEX:		db 0
CF_SHP:		db 0
CF_SEL:		db 0
CF_SP:		ds 4
CF_STEP:	db 0
CF_CUR:		db 0
CMO_I:		db 0
CMS_COL:	db 0
CI_NAME:	dw 0
CI_LEN:		db 0
CI_CUR:		db 0
CI_T:		db 0
CI_PREV:	ds 9
CFN_I:		db 0
CFN_D:		db 0
CFN_S:		db 0
CG_END:
	assert CG_END <= 0C000h	; the character generation overlay too big
