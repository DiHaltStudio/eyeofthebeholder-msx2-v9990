; ============================================================================
; gui.asm - Interface: text (FONT6 through CMMC), message window, boxes,
;           bar graphs, shapes on the screen and the party panel
; Assembler: Sjasm 0.42c
;
; Coordinates are those of the 320x200 game image (the original's); the
; routines add SCREEN_X / SCREEN_Y.
; Party (PARTY.DAT, 6 x P_SIZE bytes): see tools/conv_global.py.
; ============================================================================

V9_OP_CMMC:	equ 50h		; CPU character data -> colour expansion

; ----------------------------------------------------------------------------
; TEXT_PRINT - HL = text (0-terminated), DE = x, C = y, A = colour,
;              B = background colour (0 = transparent)
; ----------------------------------------------------------------------------
TEXT_PRINT:
	call PTR_KEEP_ARROW
	ld (TXT_FG),a
	ld a,b
	ld (TXT_BG),a
	ld (TXT_X),de
	ld a,c
	ld (TXT_Y),a
.lp:	ld a,(hl)
	or a
	ret z
	inc hl
	push hl
	call TEXT_CHAR
	ld a,(TXT_SQZ)
	ld e,a
	ld hl,(TXT_X)
	ld a,(TXT_FH)		; the advance: 6 or 8, as the height (- TXT_SQZ)
	sub e
	ld e,a
	ld d,0
	add hl,de
	ld (TXT_X),hl
	pop hl
	jr .lp

TXT_SQZ:	db 0		; 1: one pixel less between the characters

; Long translated spell names need compact spacing inside the spell list.
TEXT_PRINT_BOOK:
	push af
	push bc
	push hl
	ld b,18
.length:
	ld a,(hl)
	inc hl
	or a
	jr z,.print
	djnz .length
	ld a,1
	ld (TXT_SQZ),a
.print:	pop hl
	pop bc
	pop af
	call TEXT_PRINT
	xor a
	ld (TXT_SQZ),a
	ret

; TEXT_CHAR - A = character at (TXT_X, TXT_Y)
TEXT_CHAR:
	and 7Fh
	sub 32			; the fonts start at the space
	jr nc,.c
	xor a
.c:	ld l,a
	ld h,0
	ld a,(TXT_FONT)
	or a
	jr nz,.f8
	ld e,l
	ld d,h
	add hl,hl
	add hl,de
	add hl,hl		; *6
	ld de,FONT6
	jr .glyph
.f8:	add hl,hl
	add hl,hl
	add hl,hl		; *8
	ld de,FONT8
.glyph:	add hl,de
	push hl
	call V9_WAIT_CE
	ld hl,(TXT_X)
	ld de,(GUI_BASE_X)
	add hl,de
	ld (TXT_CMD),hl		; DX
	ld a,(TXT_Y)
	call GUI_Y
	ld (TXT_CMD+2),hl	; DY
	ld a,(TXT_BG)
	ld b,a
	ld c,V9_LOG_COPY
	or a
	jr nz,.opq
	ld c,V9_LOG_TCOPY
.opq:	ld a,V9R_CMD_SX+4
	out (V9_REGSEL),a
	ld hl,TXT_CMD
	ld a,(hl)
	out (V9_REGDAT),a	; R#36 DX
	inc hl
	ld a,(hl)
	out (V9_REGDAT),a
	inc hl
	ld a,(hl)
	out (V9_REGDAT),a	; R#38 DY
	inc hl
	ld a,(hl)
	out (V9_REGDAT),a
	ld a,8
	out (V9_REGDAT),a	; R#40 NX = 8
	xor a
	out (V9_REGDAT),a
	ld a,(TXT_FH)
	out (V9_REGDAT),a	; R#42 NY
	xor a
	out (V9_REGDAT),a
	out (V9_REGDAT),a	; R#44 ARG
	ld a,c
	out (V9_REGDAT),a	; R#45 LOG
	ld a,0FFh
	out (V9_REGDAT),a	; R#46-47 WM
	out (V9_REGDAT),a
	ld a,(TXT_FG)
	out (V9_REGDAT),a	; R#48-49 FC
	out (V9_REGDAT),a
	ld a,b
	out (V9_REGDAT),a	; R#50-51 BC
	out (V9_REGDAT),a
	ld a,V9_OP_CMMC
	out (V9_REGDAT),a	; R#52 OP
	pop hl
	ld a,(TXT_FH)
	ld b,a
.data:	in a,(V9_STATUS)
	rla			; TR: ready for the next byte
	jr nc,.data
	ld a,(hl)
	out (V9_CMD),a
	inc hl
	djnz .data
	ret

TXT_FONT:	db 0		; 0 FONT6, 1 FONT8 (TEXT_FONT8 / TEXT_FONT6)
TXT_FH:		db FONT_H
TXT_FG:		db 0
TXT_BG:		db 0
TXT_X:		dw 0
TXT_Y:		db 0
TXT_CMD:	ds 4

; TEXT_FONT6 / TEXT_FONT8 - the font of TEXT_PRINT
TEXT_FONT6:
	xor a
	ld (TXT_FONT),a
	ld a,FONT_H
	ld (TXT_FH),a
	ret
TEXT_FONT8:
	ld a,1
	ld (TXT_FONT),a
	ld a,FONT8_H
	ld (TXT_FH),a
	ret

; ----------------------------------------------------------------------------
; MSG_PRINT - HL = text: scrolls the 3-line message window and prints it on
;   the bottom line
; ----------------------------------------------------------------------------
MSG_X:		equ 8
MSG_Y:		equ 179
MSG_W:		equ 276

MSG_PRINT:
	ld a,C_WHITE
	jr MSG_PRINT_C
; MSG_LINE_C - HL = one line of text, A = colour
MSG_LINE_C:
	call PTR_KEEP_ARROW
	ld (MSG_COL),a
	push hl
	ld hl,CMD_MSGSCROLL
	ld a,V9_LOG_COPY
	call V9_LMMM
	ld hl,CMD_MSGCLEAR
	ld a,C_BLACK
	call V9_LMMV
	; The log is laid out in six-pixel rows, even while a camp menu
	; with FONT8 is open. Restore the caller's font after printing.
	ld de,(TXT_FONT)	; TXT_FONT and TXT_FH are adjacent
	call TEXT_FONT6
	pop hl
	push de
	ld de,MSG_X
	ld c,MSG_Y+12
	ld a,(MSG_COL)
	ld b,0
	call TEXT_PRINT
	pop hl
	ld (TXT_FONT),hl
	ret
MSG_COL:	db 0

; ----------------------------------------------------------------------------
; MSG_PRINT_C - HL = text, A = colour: printed in lines of the message
;   window, broken at spaces (and at CR)
; ----------------------------------------------------------------------------
MSG_COLS:	equ 46

MSG_WRAP:
MSG_PRINT_C:
	ld (MW_COL),a
.line:	ld a,MSG_COLS
	call WRAP_LINE
	ret z
	push hl
	ld a,(MW_COL)
	ld hl,MSG_LINE
	call MSG_LINE_C
	pop hl
	jr .line

; WRAP_LINE - HL = text, A = columns: its next line, broken at a space (or
;   at CR) -> MSG_LINE, HL = the rest; Z at the end of the text
WRAP_LINE:
	ld (MW_COLS),a
	ld a,(hl)
	or a
	ret z
	ld (MW_START),hl
	ld de,0			; last space
	ld b,0
.scan:	ld a,(hl)
	or a
	jr z,.cut
	cp 13
	jr z,.cut
	cp ' '
	jr nz,.ns
	ld e,l
	ld d,h
.ns:	inc hl
	inc b
	ld a,(MW_COLS)
	cp b
	jr nz,.scan
	; too long: back to the last space if there is one
	ld a,(hl)
	or a
	jr z,.cut
	cp ' '
	jr z,.cut
	cp 13
	jr z,.cut
	ld a,d
	or e
	jr z,.cut
	ex de,hl
.cut:	; copy [start, hl) to MSG_LINE
	push hl
	ld de,(MW_START)
	or a
	sbc hl,de
	ld c,l
	ld b,0
	ex de,hl
	ld de,MSG_LINE
	ld a,c
	or a
	jr z,.empty
	ldir
.empty:	xor a
	ld (de),a
	pop hl
	; skip one separator
	ld a,(hl)
	cp ' '
	jr z,.skip
	cp 13
	jr nz,.nz
.skip:	inc hl
.nz:	or 1
	ret

MSG_LINE:	ds 52
MW_COL:		db 0
MW_COLS:	db 0
MW_START:	dw 0

; ----------------------------------------------------------------------------
; TXT_FETCH - A = string (1..) of TEXT.DAT -> HL = BOUNCE, its first part
;   (up to ROWBUF, 767 characters; TF_MORE = 1 if there is more)
; TXT_REFILL - HL = the next character in BOUNCE: the rest goes to the
;   start of BOUNCE, more of the text after it -> HL = BOUNCE
;   The page-2 segment stays.
; ----------------------------------------------------------------------------
TXT_FETCH:
	ld c,a
	ld a,(CUR_P2)
	push af
	ld a,(TEXT_SEG)
	call PUT_SEG_P2
	ld l,c
	dec l
	ld h,0
	add hl,hl
	set 7,h
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	set 7,h
	ld de,BOUNCE
	jr TF_COPY
TXT_REFILL:
	ld a,(TF_MORE)
	or a
	ret z
	ld a,(CUR_P2)
	push af
	ex de,hl		; [HL, TF_END) to the start
	ld hl,(TF_END)
	or a
	sbc hl,de
	ld c,l
	ld b,h
	ex de,hl
	ld de,BOUNCE
	ld a,b
	or c
	jr z,.m
	ldir
.m:	ld a,(TEXT_SEG)
	call PUT_SEG_P2
	ld hl,(TF_SRC)
TF_COPY:
	xor a
	ld (TF_MORE),a
.cp:	ld a,(hl)
	ld (de),a
	or a
	jr z,.end
	inc hl
	inc de
	ld a,d			; up to ROWBUF: the pointer may be uploaded meanwhile
	cp (ROWBUF-1)>>8
	jr c,.cp
	ld a,e
	cp (ROWBUF-1)&255
	jr c,.cp
	xor a
	ld (de),a
	inc a
	ld (TF_MORE),a
.end:	ld (TF_SRC),hl
	ld (TF_END),de
	pop af
	call PUT_SEG_P2
	ld hl,BOUNCE
	ret
TF_MORE:	db 0
TF_SRC:		dw 0
TF_END:		dw 0

; LOAD_V9_KEEP - LOAD_V9 (DE = name) that keeps the page-2 segment
LOAD_V9_KEEP:
	ld a,(CUR_P2)
	push af
	call LOAD_V9
	pop af
	jp PUT_SEG_P2

; SCREEN_RESTORE - the play field again after a dialogue (gui_restorePlayField);
;   the page-2 segment stays
SCREEN_RESTORE:
	ld a,(CUR_P2)
	push af
	ld de,F_UI
	call LOAD_V9
	call TEXT_FONT6
	call CACHE_RESET
	ld a,1
	ld (SCENE_DIRTY),a
	call PANEL_DRAW_ALL
	pop af
	jp PUT_SEG_P2

CMD_MSGSCROLL:	dw SCREEN_X+MSG_X, SCREEN_Y+MSG_Y+6, SCREEN_X+MSG_X, SCREEN_Y+MSG_Y, MSG_W, 12
CMD_MSGCLEAR:	dw SCREEN_X+MSG_X, SCREEN_Y+MSG_Y+12, MSG_W, 6

; ----------------------------------------------------------------------------
; FILL_RECT - DE = x, C = y, B = w, L = h, A = colour (game coordinates)
; ----------------------------------------------------------------------------
FILL_RECT:
	call PTR_KEEP_ARROW
	push af
	push hl
	ld hl,(GUI_BASE_X)
	add hl,de
	ld (FR_CMD),hl
	ld a,c
	call GUI_Y
	ld (FR_CMD+2),hl
	ld h,0
	ld l,b
	ld (FR_CMD+4),hl
	pop hl
	ld h,0
	ld (FR_CMD+6),hl
	pop af
	ld hl,FR_CMD
	jp V9_LMMV
FR_CMD:		ds 8

; ----------------------------------------------------------------------------
; GUI_BOX - gui_drawBox: (BOX_X, BOX_Y, BOX_W, BOX_H), BOX_C1 = frame 1
;   (left and bottom), BOX_C2 = frame 2 (top and right), BOX_FILL (0 = none)
; ----------------------------------------------------------------------------
GUI_BOX:
	ld a,(BOX_FILL)
	or a
	jr z,.frame
	ld de,(BOX_X)
	inc de
	ld a,(BOX_Y)
	inc a
	ld c,a
	ld a,(BOX_W)
	sub 2
	ld b,a
	ld a,(BOX_H)
	sub 2
	ld l,a
	ld a,(BOX_FILL)
	call FILL_RECT
.frame:	; top: x+1 .. x+w-1, colour 2
	ld de,(BOX_X)
	inc de
	ld a,(BOX_Y)
	ld c,a
	ld a,(BOX_W)
	dec a
	ld b,a
	ld l,1
	ld a,(BOX_C2)
	call FILL_RECT
	; right: x+w-1, y .. y+h-2, colour 2
	ld de,(BOX_X)
	ld a,(BOX_W)
	dec a
	ld l,a
	ld h,0
	add hl,de
	ex de,hl
	ld a,(BOX_Y)
	ld c,a
	ld a,(BOX_H)
	dec a
	ld l,a
	ld b,1
	ld a,(BOX_C2)
	call FILL_RECT
	; left: x, y .. y+h-1, colour 1
	ld de,(BOX_X)
	ld a,(BOX_Y)
	ld c,a
	ld a,(BOX_H)
	ld l,a
	ld b,1
	ld a,(BOX_C1)
	call FILL_RECT
	; bottom: x .. x+w-1, y+h-1, colour 1
	ld de,(BOX_X)
	ld a,(BOX_Y)
	ld hl,BOX_H
	add a,(hl)
	dec a
	ld c,a
	ld a,(BOX_W)
	ld b,a
	ld l,1
	ld a,(BOX_C1)
	jp FILL_RECT

BOX_X:		dw 0
BOX_Y:		db 0
BOX_W:		db 0
BOX_H:		db 0
BOX_C1:		db 0
BOX_C2:		db 0
BOX_FILL:	db 0

; ----------------------------------------------------------------------------
; BLIT_SCREEN - HL = shape id, DE = x, C = y, A = logical operation:
;   copies a whole shape to the screen (no clipping)
; ----------------------------------------------------------------------------
BLIT_SCREEN:
	call PTR_KEEP_ARROW
	ld (BS_LOG),a
	push de
	push bc
	ld (SHP_ID),hl
	call SHAPE_ENTRY
	pop bc
	pop de
	ret c
	ld a,(ix+3)
	inc a
	jr nz,.vram
	push de
	push bc
	ld b,0
	call MCACHE_GET
	pop bc
	pop de
.vram:	ld l,(ix+0)
	ld h,(ix+1)
	ld (BS_CMD),hl
	ld l,(ix+2)
	ld h,(ix+3)
	ld (BS_CMD+2),hl
	ld hl,(GUI_BASE_X)
	add hl,de
	ld (BS_CMD+4),hl
	ld a,c
	call GUI_Y
	ld (BS_CMD+6),hl
	ld h,0
	ld l,(ix+4)
	ld (BS_CMD+8),hl
	ld l,(ix+5)
	ld (BS_CMD+10),hl
	ld hl,BS_CMD
	ld a,(BS_LOG)
	jp V9_LMMM
BS_LOG:		db 0
BS_CMD:		ds 12

; ----------------------------------------------------------------------------
; Party panel (gui_drawCharPortraitWithStats, VGA coordinates)
; ----------------------------------------------------------------------------
PANEL_DRAW_ALL:
	ld a,5
.lp:	push af
	call PANEL_DRAW
	pop af
	dec a
	jp p,.lp
	ret

; PANEL_DRAW - A = character 0..5
PANEL_DRAW:
	ld (PN_INDEX),a
	ld b,a
	ld a,(CONTROL_MODE)
	or a
	jr z,.panel
	ld a,(UPDATE_CHAR)	; the inventory is open: only its character
	cp b
	ret nz
	call UCALL
	dw INV_DRAW
	ret
.panel:	call AMCALL
	dw PN_RENDER
	ret

; HAND_ICON - IY = character, A = hand 0/1 -> A = icon of the item held
;   (85 / 86: the empty hands)
HAND_ICON:
	push af
	call HAND_ITEM
	pop bc
	ld a,h
	or l
	ld a,85
	jr z,.empty
	call ITEM_PTR
	ld de,I_ICON
	add hl,de
	ld a,(hl)
	ret
.empty:	add a,b
	ret

; HAND_ITEM - IY = character, A = hand 0/1 -> HL = item number (0 = none)
HAND_ITEM:
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ret

; PANEL_SLOT - A = 0/1: the hand slot box and its item icon
PANEL_SLOT:
	ld (PN_SLOT),a
	ld hl,(PN_X)
	ld de,32
	add hl,de
	ld (BOX_X),hl
	ld a,(PN_SLOT)
	or a
	ld a,(PN_Y)
	jr z,.y0
	add a,16
.y0:	add a,9
	ld (BOX_Y),a
	ld a,31
	ld (BOX_W),a
	ld a,16
	ld (BOX_H),a
	ld a,C_FRAME1
	ld (BOX_C1),a
	ld a,C_FRAME2
	ld (BOX_C2),a
	ld a,C_FILL
	ld (BOX_FILL),a
	call GUI_BOX
	; result of the last attack instead of the icon
	ld a,(PN_SLOT)
	or a
	ld a,(iy+P_STATUS0)
	jr z,.st
	ld a,(iy+P_STATUS1)
.st:	or a
	jp nz,SLOT_STATUS
	ld a,(PN_SLOT)
	call XCALL
	dw FX_HAND_SHAPE
	ld de,(BOX_X)
	ld a,8
	add a,e
	ld e,a
	jr nc,.nc
	inc d
.nc:	ld a,(BOX_Y)
	ld c,a
	ld a,V9_LOG_TCOPY
	call BLIT_SCREEN
	; disabled slot (just used, or the character is down): grid over it
	ld a,(PN_SLOT)
	inc a
	ld b,a
	ld a,(iy+P_DISABLED)
.db:	rrca
	djnz .db
	jr c,.grid
	ld a,(iy+P_HP)
	dec a
	ret p
.grid:	ld hl,SHP_WEAPONGRID
	ld de,(BOX_X)
	ld a,(BOX_Y)
	ld c,a
	ld a,V9_LOG_TCOPY
	jp BLIT_SCREEN

; SLOT_STATUS - A = status of the slot at (BOX_X, BOX_Y) (gui_drawWeaponSlotStatus)
SLOT_STATUS:
	ld (PN_STATUS),a
	cp -2
	jp p,.splat		; > -3: green splat
	ld a,C_WARN1
	ld (BOX_C1),a
	ld a,C_WARN2
	ld (BOX_C2),a
	ld a,C_WARNFILL
	ld (BOX_FILL),a
	call GUI_BOX
	ld a,(PN_STATUS)
	cp -3
	ld hl,STR_NOREACH1
	ld de,STR_NOREACH2
	jr z,.two
	ld hl,STR_NOAMMO1
	ld de,STR_NOAMMO2
.two:	push de
	push hl
	call STR_LEN
	pop hl
	call .x			; DE = x
	ld a,(BOX_Y)
	add a,2
	ld c,a
	push de
	ld a,C_WHITE
	ld b,0
	call TEXT_PRINT
	pop de
	pop hl
	ld a,(BOX_Y)
	add a,9
	ld c,a
	ld a,C_WHITE
	ld b,0
	jp TEXT_PRINT
.splat:	ld hl,(BOX_X)
	dec hl
	ex de,hl
	ld a,(BOX_Y)
	ld c,a
	ld hl,SHP_GREENSPLAT
	ld a,V9_LOG_TCOPY
	call BLIT_SCREEN
	ld a,(PN_STATUS)
	ld hl,STR_MISS
	cp -1
	jr z,.one
	ld hl,STR_HACK
	cp -2
	jr z,.one
	call NUM_STR
.one:	push hl
	call STR_LEN
	pop hl
	call .x
	ld a,(BOX_Y)
	add a,5
	ld c,a
	ld a,C_WHITE
	ld b,0
	jp TEXT_PRINT
.x:	; DE = BOX_X + 16 - length * 3 (length in B)
	ld a,b
	add a,a
	add a,b
	ld b,a
	ld a,16
	sub b
	ld e,a
	rla
	sbc a,a
	ld d,a
	push hl
	ld hl,(BOX_X)
	add hl,de
	ex de,hl
	pop hl
	ret

; STR_LEN - HL = text -> B = length (preserves HL)
STR_LEN:
	push hl
	ld b,0
.lp:	ld a,(hl)
	or a
	jr z,.e
	inc hl
	inc b
	jr .lp
.e:	pop hl
	ret

; NUM_STR - A = 0..255 -> HL = decimal text, B = length
NUM_STR:
	ld hl,NUM_BUF+3
	ld (hl),0
	ld b,0
.lp:	push bc
	push hl
	ld l,a
	ld h,0
	ld a,10
	call DIV16_8		; L = A / 10, A = remainder
	ld c,l
	pop hl
	dec hl
	add a,'0'
	ld (hl),a
	ld a,c
	pop bc
	inc b
	or a
	jr nz,.lp
	ret
NUM_BUF:	ds 4

; PANEL_HP - the "PV" label and the hit point bar
PANEL_HP:
	ld hl,(PN_X)
	ld de,15
	add hl,de
	ld (PN_HPX),hl
	ld a,(PN_Y)
	add a,44
	ld (PN_HPY),a
	; label
	ld hl,(PN_HPX)
	ld de,-13
	add hl,de
	ex de,hl
	ld a,(PN_HPY)
	dec a
	ld c,a
	ld hl,STR_HP
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	; frame
	ld hl,(PN_HPX)
	dec hl
	ld (BOX_X),hl
	ld a,(PN_HPY)
	dec a
	ld (BOX_Y),a
	ld a,41
	ld (BOX_W),a
	ld a,5
	ld (BOX_H),a
	ld a,C_FRAME2
	ld (BOX_C1),a
	ld a,C_FRAME1
	ld (BOX_C2),a
	xor a
	ld (BOX_FILL),a
	call GUI_BOX
	; bar: cur = hp + 10, max = hpmax + 10, t = cur * 39 / max
	ld a,(iy+P_HP)
	add a,10
	jp p,.pos
	xor a
.pos:	ld b,a			; cur
	ld a,(iy+P_HPMAX)
	add a,10
	ld c,a			; max
	ld a,b
	cp c
	jr c,.le
	ld b,c
.le:	; colour
	ld a,b
	cp 11
	ld e,C_DARKRED
	jr c,.col
	push bc
	ld a,c
	ld b,3
	call DIV8		; A = max / 3
	pop bc
	cp b
	ld e,C_YELLOW
	jr z,.green
	jr nc,.col
.green:	ld e,C_DARKGREEN
.col:	ld a,e
	ld (PN_COL),a
	; t
	push bc
	ld a,b
	ld e,39
	call MUL8		; HL = cur * 39
	pop bc
	ld a,c
	call DIV16_8		; HL = HL / A
	ld a,l
	or a
	jr nz,.t
	ld a,b
	or a
	jr z,.t
	ld a,1
.t:	ld (PN_T),a
	or a
	jr z,.rest
	ld de,(PN_HPX)
	ld a,(PN_HPY)
	ld c,a
	ld a,(PN_T)
	ld b,a
	ld l,3
	ld a,(PN_COL)
	call FILL_RECT
.rest:	ld a,(PN_T)
	cp 39
	ret nc
	ld hl,(PN_HPX)
	ld e,a
	ld d,0
	add hl,de
	ex de,hl
	ld a,39
	ld hl,PN_T
	sub (hl)
	ld b,a
	ld a,(PN_HPY)
	ld c,a
	ld l,3
	ld a,C_BARGRAPH
	jp FILL_RECT

PANEL_BOXY:	db 2, 54, 106
; GUI_Y - game Y in A, physical Y in HL. Preserves BC and DE.
GUI_Y:
	ld hl,(GUI_BASE_Y)
	add a,l
	ld l,a
	ret nc
	inc h
	ret
GUI_BASE_Y:	db SCREEN_Y
PN_STAGE:	db 0		; GUI destination Y high byte: screen/staging
GUI_BASE_X:	dw SCREEN_X	; physical X origin of the GUI
PN_INDEX:	db 0
PN_ROW:		db 0
PN_SLOT:	db 0
PN_X:		dw 0
PN_Y:		db 0
PN_HPX:		dw 0
PN_HPY:		db 0
PN_COL:		db 0
PN_T:		db 0
PN_STATUS:	db 0

; ----------------------------------------------------------------------------
; arithmetic
; ----------------------------------------------------------------------------
; MUL8 - HL = A * E
MUL8:
	ld hl,0
	ld d,0
	ld b,8
.lp:	add hl,hl
	rla
	jr nc,.n
	add hl,de
.n:	djnz .lp
	ret

; DIV16_8 - HL = HL / A (A != 0), remainder in A
DIV16_8:
	ld c,a
	xor a
	ld b,16
.lp:	add hl,hl
	rla
	jr c,.sub
	cp c
	jr c,.n
.sub:	sub c
	inc l
.n:	djnz .lp
	ret

; DIV8 - A = A / B
DIV8:
	ld l,a
	ld h,0
	ld a,b
	call DIV16_8
	ld a,l
	ret
