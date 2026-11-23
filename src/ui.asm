; ============================================================================
; ui.asm - The inventory page (gui_drawCharPortraitWithStats in control
;          mode 1, gui_drawInventoryItem, gui_processInventorySlotClick and
;          the buttons of the inventory)
; Assembler: Sjasm 0.42c
;
; An overlay: assembled to build/UI.OVL, it lives in the UI segment at
; 8000h and runs with that segment in page 2 (resident code calls it with
; UCALL). Resident routines that need the world segment are called with
; WCALL.
;
; The inventory replaces the party panel (176, 0)-(319, 167); the panel is
; saved to PANELBUF (VRAM) when the inventory opens and put back when it
; closes, then the portraits are drawn again.
; ============================================================================

	output "../build/UI.OVL"
	org UI_BASE

; ----------------------------------------------------------------------------
; INV_OPEN - A = character: the inventory page replaces the party panel
; ----------------------------------------------------------------------------
INV_OPEN:
	push af
	call MCALL
	dw BOOK_CLOSE
	pop af
	ld (UPDATE_CHAR),a
	ld a,(CONTROL_MODE)
	or a
	jr nz,INV_DRAW
	inc a
	ld (CONTROL_MODE),a
	call PTR_HIDE
	ld hl,CMD_PANELSAVE
	ld a,V9_LOG_COPY
	call V9_LMMM
	; fall through

; INV_DRAW - the whole page for UPDATE_CHAR
INV_DRAW:
	call PTR_HIDE
	call V9_WAIT_CE
	; the background, row by row from the RLE data
	ld hl,INVBG
	ld b,0			; row
.row:	push bc
	push hl
	; VRAM address (SCREEN_Y + row) * 512 + SCREEN_X + INVBG_X
	ld a,b
	add a,SCREEN_Y
	add a,a			; bit 7 of the row -> carry
	ld c,0
	rl c			; C = row >> 7
	ld h,a
	ld l,0
	ld de,SCREEN_X+INVBG_X
	add hl,de
	call V9_SETWADDR
	pop hl
	ld b,INVBG_W
.rle:	ld a,(hl)
	inc hl
	bit 7,a
	jr nz,.run
	ld c,a			; literal bytes
.lit:	ld a,(hl)
	inc hl
	out (V9_VRAM),a
	dec b
	dec c
	jr nz,.lit
	jr .more
.run:	and 7Fh
	ld c,a
	ld a,(hl)
	inc hl
.r1:	out (V9_VRAM),a
	dec b
	dec c
	jr nz,.r1
.more:	ld a,b
	or a
	jr nz,.rle
	pop bc
	inc b
	ld a,b
	cp INVBG_H
	jr c,.row
	call INV_HEADER
	ld a,(IV_STATS)
	or a
	jr nz,.stats
	; the items
	xor a
.it:	push af
	call INV_ITEM
	pop af
	inc a
	cp 27
	jr c,.it
	ret
.stats:	ld a,(UPDATE_CHAR)
	call SCALL
	dw STATS_DRAW
	ret

CMD_PANELSAVE:	dw SCREEN_X+176, SCREEN_Y, PANELBUF_X, PANELBUF_Y, PANEL_W, PANEL_H
CMD_PANELBACK:	dw PANELBUF_X, PANELBUF_Y, SCREEN_X+176, SCREEN_Y, PANEL_W, PANEL_H

; ----------------------------------------------------------------------------
; INV_CLOSE - the party panel comes back (clickedPortraitRestore)
; ----------------------------------------------------------------------------
INV_CLOSE:
	xor a
	ld (CONTROL_MODE),a
	ld (IV_STATS),a
	call PTR_HIDE
	ld hl,CMD_PANELBACK
	ld a,V9_LOG_COPY
	call V9_LMMM
	call PANEL_DRAW_ALL
	ld a,1
	ret

; ----------------------------------------------------------------------------
; INV_HEADER - face, name, hit points, food and state of UPDATE_CHAR
; ----------------------------------------------------------------------------
INV_HEADER:
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	; face (a dead one shows the skull; out of combat: the grid over it)
	ld a,(iy+P_HP)
	cp -10
	ld hl,SHP_DEADCHAR
	jr z,.face
	ld e,(iy+P_FACE)
	ld d,0
	ld hl,SHP_FACE0
	add hl,de
.face:	ld de,181
	ld c,3
	ld a,V9_LOG_COPY
	call BLIT_SCREEN
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	ld a,(iy+P_HP)
	dec a
	jp p,.name
	cp -11
	jr z,.name
	ld hl,SHP_DISABLEDGRID
	ld de,181
	ld c,3
	ld a,V9_LOG_TCOPY
	call BLIT_SCREEN
.name:	; the name, white with a black shadow
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	push iy
	pop hl
	inc hl			; P_NAME
	push hl
	ld de,220
	ld c,7
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	pop hl
	ld de,219
	ld c,6
	ld a,C_WHITE
	ld b,0
	call TEXT_PRINT
	; hit points: (hp + 10) of (max + 10)
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	ld a,(iy+P_HP)
	add a,10
	jp p,.cur
	xor a
.cur:	ld b,a
	ld a,(iy+P_HPMAX)
	add a,10
	ld c,a
	; colour: <= 10 dark red, below a third yellow, else green
	ld a,b
	cp 11
	ld e,C_DARKRED
	jr c,.hcol
	push bc
	ld a,c
	ld b,3
	call DIV8
	pop bc
	cp b
	ld e,C_YELLOW
	jr z,.hg
	jr nc,.hcol
.hg:	ld e,C_DARKGREEN
.hcol:	ld a,16
	ld (BAR_Y),a
	call INV_BAR
	; food
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	ld a,(iy+P_FOOD)
	ld b,a
	ld c,100
	cp 20
	ld e,C_DARKRED
	jr c,.fcol
	cp 33
	ld e,C_YELLOW
	jr c,.fcol
	ld e,C_DARKGREEN
.fcol:	ld a,25
	ld (BAR_Y),a
	call INV_BAR
	; the state line
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	ld a,(iy+P_HP)
	cp -10
	ld hl,STR_ST_DEAD
	ld de,247
	jr z,.st
	dec a
	ld hl,STR_ST_UNCON
	ld de,226
	jp m,.st		; hp < 1
	bit 1,(iy+P_FLAGS)
	ld hl,STR_ST_POISON
	ld de,235
	jr nz,.st
	bit 2,(iy+P_FLAGS)
	ld hl,STR_ST_PARA
	ld de,232
	ret z
.st:	push hl
	push de
	inc de
	ld c,159
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	pop de
	pop hl
	ld c,158
	ld a,C_LIGHTRED
	ld b,0
	jp TEXT_PRINT

; INV_BAR - B = value, C = maximum, E = colour, (BAR_Y): a bar at x 250,
;   51 x 5 with its frame (gui_drawHorizontalBarGraph)
INV_BAR:
	ld a,e
	ld (BAR_COL),a
	ld a,b
	cp c
	jr c,.le
	ld b,c
.le:	push bc
	; frame: (249, y - 1) 54 x 7, frame2 on the left and bottom
	ld hl,249
	ld (BOX_X),hl
	ld a,(BAR_Y)
	dec a
	ld (BOX_Y),a
	ld a,54
	ld (BOX_W),a
	ld a,7
	ld (BOX_H),a
	ld a,C_FRAME2
	ld (BOX_C1),a
	ld a,C_FRAME1
	ld (BOX_C2),a
	xor a
	ld (BOX_FILL),a
	call GUI_BOX
	pop bc
	; t = value * 52 / maximum (at least 1 if value > 0)
	push bc
	ld a,b
	ld e,52
	call MUL8
	pop bc
	push bc
	ld a,c
	call DIV16_8
	pop bc
	ld a,l
	or a
	jr nz,.t
	ld a,b
	or a
	jr z,.t
	ld a,1
.t:	ld (BAR_T),a
	or a
	jr z,.rest
	ld b,a
	ld de,250
	ld a,(BAR_Y)
	ld c,a
	ld l,5
	ld a,(BAR_COL)
	call FILL_RECT
.rest:	ld a,(BAR_T)
	cp 52
	ret nc
	ld e,a
	ld d,0
	ld hl,250
	add hl,de
	ex de,hl
	ld a,52
	ld hl,BAR_T
	sub (hl)
	ld b,a
	ld a,(BAR_Y)
	ld c,a
	ld l,5
	ld a,C_BARGRAPH
	jp FILL_RECT

BAR_Y:		db 0
BAR_COL:	db 0
BAR_T:		db 0

; ----------------------------------------------------------------------------
; INV_ITEM - A = slot: its box (redrawn) and the icon of its item
;   (gui_drawInventoryItem with redraw = 1)
; ----------------------------------------------------------------------------
INV_ITEM:
	ld (IV_SLOT),a
	; position
	ld e,a
	ld d,0
	ld hl,INV_SLOT_Y
	add hl,de
	ld a,(hl)
	ld (IV_Y),a
	ld hl,INV_SLOT_X
	add hl,de
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (IV_X),de
	; the box: 18 x 18 (rings: 10 x 10), frame1 / frame2, filled (the quiver not)
	dec de
	ld (BOX_X),de
	ld a,(IV_Y)
	dec a
	ld (BOX_Y),a
	ld a,(IV_SLOT)
	cp 25
	ld a,18
	jr c,.wh
	ld a,10
.wh:	ld (BOX_W),a
	ld (BOX_H),a
	ld a,C_FRAME1
	ld (BOX_C1),a
	ld a,C_FRAME2
	ld (BOX_C2),a
	ld a,(IV_SLOT)
	cp 16
	ld a,C_FILL
	jr nz,.fill
	xor a
.fill:	ld (BOX_FILL),a
	call GUI_BOX
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	ld a,(IV_SLOT)
	cp 16
	jr z,.quiver
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	ret z
	call ITEM_IX
	call XCALL
	dw FX_ICON_IX
	ld de,(IV_X)
	ld a,(IV_Y)
	ld c,a
	ld a,(IV_SLOT)
	cp 25
	jr c,.draw
	dec de			; the rings sit 4 pixels up and left
	dec de
	dec de
	dec de
	ld a,c
	sub 4
	ld c,a
.draw:	ld a,V9_LOG_TCOPY
	jp BLIT_SCREEN
.quiver:
	; a black field with the number of items in it
	ld de,(IV_X)
	inc de
	inc de
	inc de
	ld a,(IV_Y)
	add a,9
	ld c,a
	ld b,12
	ld l,5
	ld a,C_BLACK
	call FILL_RECT
	ld a,16
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	call QUEUE_COUNT	; A = items
	push af
	call NUM_STR		; HL = digits
	pop af
	ld de,(IV_X)
	cp 10
	ld a,8
	jr c,.qx
	ld a,2
.qx:	add a,e
	ld e,a
	jr nc,.qy
	inc d
.qy:	ld c,65
	ld a,C_WHITE
	ld b,0
	jp TEXT_PRINT

IV_SLOT:	db 0
IV_X:		dw 0
IV_Y:		db 0

; QUEUE_COUNT - HL = the newest item of a queue (0: none) -> A = items
QUEUE_COUNT:
	xor a
	ld (QC_N),a
	ld a,h
	or l
	ret z
	ld (QC_FIRST),hl
.lp:	ld a,(QC_N)
	inc a
	ld (QC_N),a
	call ITEM_IX
	ld l,(ix+I_PREV)
	ld h,(ix+I_PREV+1)
	ld de,(QC_FIRST)
	or a
	sbc hl,de
	add hl,de
	jr nz,.lp
	ld a,(QC_N)
	ret
QC_N:		db 0
QC_FIRST:	dw 0

; ----------------------------------------------------------------------------
; Clicks while the inventory is open (button lists 3): checked in order, a
; handler returning A = 0 lets the next areas try
; ----------------------------------------------------------------------------
INV_CLICKS:
	ld a,(IV_STATS)		; the statistics page hides the slots
	or a
	jr nz,.areas
	; the 27 slot areas come from the slot positions
	xor a
.slot:	ld (IV_SLOT),a
	ld e,a
	ld d,0
	ld hl,INV_SLOT_X
	add hl,de
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,(MOUSE_X)
	or a
	sbc hl,de
	jr c,.ns
	ld a,(IV_SLOT)
	cp 25
	ld bc,16
	jr c,.w
	ld c,10
.w:	sbc hl,bc
	jr z,.xin
	jr nc,.ns
.xin:	ld a,(IV_SLOT)
	ld e,a
	ld d,0
	ld hl,INV_SLOT_Y
	add hl,de
	ld a,(MOUSE_Y)
	sub (hl)
	jr c,.ns
	cp c
	jr z,.hit
	jr nc,.ns
.hit:	ld a,(IV_SLOT)
	jp INV_SLOT_CLICK
.ns:	ld a,(IV_SLOT)
	inc a
	cp 27
	jr c,.slot
.areas:	ld ix,INV_AREAS
	jp UI_SCAN

; INV_CAMP - the camp from the inventory: the panel first
INV_CAMP:
	call INV_CLOSE
	call CAMP
	ld a,1
	ret

; INV_STATS - the statistics page on / off
INV_STATS:
	ld a,(IV_STATS)
	xor 1
	ld (IV_STATS),a
	call INV_DRAW
	ld a,1
	ret
IV_STATS:	db 0

INV_AREAS:
	dw 24
	db 8, 128, 96, 3
	dw UI_SPECIAL
	db 1
	dw 236
	db 37, 31, 16, 3
	dw INV_EAT
	db 0
	dw 291
	db 149, 25, 17, 3
	dw INV_STATS
	db 0
	dw 181
	db 3, 32, 32, 3
	dw INV_CLOSE
	db 0
	dw 297
	db 35, 20, 15, 3
	dw INV_NEXT
	db 0
	dw 274
	db 35, 20, 15, 3
	dw INV_PREV
	db 0
	dw 289
	db 177, 31, 21, 3
	dw INV_CAMP
	db 0
	dw 0
	db 102, 88, 18, 3
	dw UI_PICKUP
	db 0
	dw 89
	db 102, 88, 18, 3
	dw UI_PICKUP
	db 1
	dw 0
	db 72, 88, 29, 3
	dw UI_PICKUP
	db 2
	dw 89
	db 72, 88, 29, 3
	dw UI_PICKUP
	db 3
	dw 24
	db 128, 21, 16, 3
	dw UI_ARROW
	db KEY_FWD
	dw 24
	db 144, 21, 16, 3
	dw UI_ARROW
	db KEY_BACK
	dw 3
	db 144, 21, 16, 3
	dw UI_ARROW
	db KEY_SLEFT
	dw 45
	db 144, 21, 16, 3
	dw UI_ARROW
	db KEY_SRIGHT
	dw 3
	db 128, 21, 16, 3
	dw UI_ARROW
	db KEY_TLEFT
	dw 45
	db 128, 21, 16, 3
	dw UI_ARROW
	db KEY_TRIGHT
	dw 0
	db 8, 88, 48, 3
	dw UI_THROW
	db 0
	dw 88
	db 8, 88, 48, 3
	dw UI_THROW
	db 1
	dw 0FFFFh

; UI_SCAN - IX = areas (format of CLICK_AREAS, handlers in this overlay)
UI_SCAN:
	ld a,(ix+0)
	and (ix+1)
	inc a
	ret z
	ld hl,(MOUSE_X)
	ld e,(ix+0)
	ld d,(ix+1)
	or a
	sbc hl,de
	jr c,.next
	ld e,(ix+3)
	ld d,0
	sbc hl,de
	jr z,.xin
	jr nc,.next
.xin:	ld a,(MOUSE_Y)
	sub (ix+2)
	jr c,.next
	cp (ix+4)
	jr z,.yin
	jr nc,.next
.yin:	ld a,(CLICK)
	and (ix+5)
	jr z,.next
	push ix
	ld l,(ix+6)
	ld h,(ix+7)
	ld a,(ix+8)
	call .jp
	pop ix
	or a
	ret nz
.next:	ld de,9
	add ix,de
	jr UI_SCAN
.jp:	jp (hl)

; the play screen handlers, through the world segment
UI_SPECIAL:
	call WCALL
	dw CLK_SCENE_SPECIAL
	ret
UI_PICKUP:
	call WCALL
	dw CLK_DROP_PICKUP
	ret
UI_ARROW:
	call WCALL
	dw CLK_ARROW
	ret
UI_THROW:
	call WCALL
	dw CLK_THROW
	ret
UI_DONE:
	ld a,1
	ret

; ----------------------------------------------------------------------------
; INV_SLOT_CLICK - A = slot: the hand item and the slot item change places
;   (gui_processInventorySlotClick, validateInventorySlotForItem)
; ----------------------------------------------------------------------------
INV_SLOT_CLICK:
	ld (IV_SLOT),a
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	; armour the class cannot wear
	ld a,(IV_SLOT)
	cp 17
	jr nz,.cursed
	ld hl,(HAND)
	ld a,h
	or l
	jr z,.cursed
	call ITEM_USABLE
	jr nz,.cursed
	ld hl,STR_VAL_ARMOR
	call MSG_NAMED
	ld a,1
	ret
.cursed:
	ld a,(IV_SLOT)
	call SLOT_PTR
	ld (IV_PTR),hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld (IV_ITEM),hl
	call ITEM_IX
	bit 5,(ix+I_FLAGS)
	jr z,.flags
	ld a,1			; a cursed item does not come off
	ret
.flags:	; the slot must accept the hand item
	ld de,0FFFFh
	ld hl,(HAND)
	ld a,h
	or l
	jr z,.v
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld de,IT_INVF
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
.v:	ld a,(IV_SLOT)
	add a,a
	ld l,a
	ld h,0
	ld bc,SLOT_FLAGS
	add hl,bc
	ld a,(hl)
	and e
	ld c,a
	inc hl
	ld a,(hl)
	and d
	or c
	jr nz,.ok
	ld hl,STR_NODROP
	call MSG_PRINT
	ld a,1
	ret
.ok:	ld a,(IV_SLOT)
	cp 16
	jr z,.quiver
	; exchange
	ld hl,(IV_PTR)
	ld de,(HAND)
	ld (hl),e
	inc hl
	ld (hl),d
	ld hl,(IV_ITEM)
	call SET_HAND_ITEM
	ld a,(IV_SLOT)
	call INV_ITEM
	ld a,(UPDATE_CHAR)
	call RECALC_AC
	ld a,1
	ret
.quiver:
	; the quiver is a queue of items (arrows, darts...)
	ld hl,(HAND)
	ld a,h
	or l
	jr z,.take
	ld c,l
	ld b,h
	ld hl,(IV_PTR)
	ld de,-2
	xor a
	call SET_ITEM_POS
	ld hl,0
	call SET_HAND_ITEM
	jr .qd
.take:	ld hl,(IV_PTR)
	ld de,0FFFFh
	xor a
	call GET_QUEUED_ITEM
	call SET_HAND_ITEM
.qd:	ld a,16
	call INV_ITEM
	ld a,1
	ret

IV_PTR:		dw 0
IV_ITEM:	dw 0

; MSG_NAMED - HL = text: printed after the name of UPDATE_CHAR ("%s ...")
MSG_NAMED:
	push hl
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	push iy
	pop hl
	inc hl
	ld de,TEXTBUF
	ld bc,10
	ldir
	xor a
	ld (de),a
	ld hl,STR_SPACE
	call TEXT_APPEND
	pop hl
	call TEXT_APPEND
	ld hl,TEXTBUF
	jp MSG_PRINT
STR_SPACE:	db " ",0

; ----------------------------------------------------------------------------
; INV_EAT - the hand item feeds the character (eatItemInHand)
; ----------------------------------------------------------------------------
INV_EAT:
	ld a,(UPDATE_CHAR)
	call CHAR_PTR
	; must be able to act (testCharacter 5: active, hp > 0)
	bit 0,(iy+P_FLAGS)
	jr z,.cannot
	ld a,(iy+P_HP)
	dec a
	jp p,.can
.cannot:
	ld hl,STR_NOEAT
	call MSG_NAMED
	ld a,1
	ret
.can:	ld hl,(HAND)
	ld a,h
	or l
	jr z,.food
	call ITEM_IX
	ld a,(ix+I_TYPE)
	cp 31			; rations
	jr z,.food
	cp 49
	jr z,.food
	ld hl,STR_EATFOOD
	call MSG_PRINT
	ld a,1
	ret
.food:	ld hl,(HAND)
	call ITEM_IX
	ld a,(ix+I_VALUE)
	inc a
	jr nz,.eat
	ld hl,STR_EATFOOD	; value -1: (printWarning)
	call MSG_PRINT
	ld a,1
	ret
.eat:	dec a
	add a,(iy+P_FOOD)
	cp 101
	jr c,.f
	ld a,100
.f:	ld (iy+P_FOOD),a
	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
	ld hl,0
	call SET_HAND_ITEM
	call INV_HEADER
	ld a,9			; eaten
	call SFX_PLAY
	ld a,1
	ret

; INV_NEXT / INV_PREV - another character (the next / previous active one)
INV_NEXT:
	ld c,1
	jr INV_STEP
INV_PREV:
	ld c,5
INV_STEP:
	ld a,(UPDATE_CHAR)
	ld b,6
.lp:	add a,c
	cp 6
	jr c,.in
	sub 6
.in:	push af
	call CHAR_PTR
	pop af
	bit 0,(iy+P_FLAGS)
	jr nz,.got
	djnz .lp
	ld a,1
	ret
.got:	call INV_OPEN
	ld a,1
	ret

; ============================================================================
; The camp (clickedCamp, GUI_EoB::runCampMenu): menus over the view; the
; game stands still while it is open
; ============================================================================
CAMP:
	; damage splats and slot results go away (clickedCamp)
	xor a
.ch:	push af
	call CHAR_PTR
	ld (iy+P_DAMAGE),0
	ld (iy+P_DMGTIMER),0
	ld (iy+P_STATUS0),0
	ld (iy+P_STATUS1),0
	pop af
	push af
	call PANEL_DRAW
	pop af
	inc a
	cp 6
	jr c,.ch
	; the strip below the view (rows 120-143) waits in VIEW_BUF
	call PTR_HIDE
	ld hl,CMD_CAMPSAVE
	ld a,V9_LOG_COPY
	call V9_LMMM
	call TEXT_FONT8
	xor a
	ld (CM_MENU),a
	ld (CM_QUIT),a
	ld (CM_NEED),a
	dec a
	ld (CM_LASTM),a
.menu:	call CM_DRAW
.loop:	call CM_SELECT		; A = button
	ld c,a
	ld a,(CM_MENU)
	or a
	jr nz,.m1
	ld a,c
	or a
	jr z,.rest
	cp 1
	jr z,.mem
	cp 2
	jr z,.pray
	cp 3
	jr z,.scribe
	cp 4
	jr z,.prefs
	cp 5
	jr z,.opts
	cp 6
	jr z,.salir
	jr .loop
.salir:	ld a,(CM_NEED)		; memorized and not rested: the warning
	or a
	jp z,.exit
	ld hl,STR_NEEDREST
	call CM_TEXTBOX
	jp .exit
.scribe:
	call CM_SCRIBE
	jr .menu
.prefs:	ld a,3
	ld (CM_MENU),a
	jr .menu
.rest:	call MCALL
	dw REST_PARTY
	jp nz,.exit		; monsters near, nobody standing: the camp ends
	ld (CM_NEED),a		; (A = 0: rested)
	jr .menu
.mem:	xor a
	jr .mp
.pray:	ld a,1
.mp:	call MEMORIZE
	jr .menu
.opts:	ld a,1
	ld (CM_MENU),a
	jr .menu
.m1:	cp 3
	jr nz,.m1o
	ld a,c			; preferences: the sound effects on / off
	or a
	jr nz,.back
	ld a,(SFX_HW)
	or a
	jr z,.menu
	ld a,(SFX_ON)
	xor 1
	ld (SFX_ON),a
	call z,SFX_STOP
	jp .menu
.m1o:	ld a,c
	or a
	jr z,.load
	dec a
	jr z,.save
	dec a
	jr z,.drop
	dec a
	jr z,.quit
.back:	xor a
	ld (CM_MENU),a
	jp .menu
.drop:	call CM_DROP
	jr .back
.save:	call WCALL
	dw SAVE_GAME
	ld hl,STR_SAVED
	jr z,.box
	ld hl,STR_SAVEERR
.box:	call CM_TEXTBOX
	jp .opts		; (runCampMenu: the options again)
.load:	call WCALL
	dw LOAD_GAME
	jr nz,.lerr
	ret			; (the frame is new: no strip to put back)
.lerr:	ld hl,STR_LOADERR
	jr .box
.quit:	ld hl,STR_QUITQ
	call CM_CONFIRM
	jr z,.back
	ld a,1
	ld (CM_QUIT),a
.exit:	call MCALL		; (sortCharacterSpellList as the camp ends)
	dw SORT_SPELLS
	call TEXT_FONT6
	call PTR_HIDE
	ld hl,CMD_CAMPBACK
	ld a,V9_LOG_COPY
	call V9_LMMM
	ld a,1
	ld (SCENE_DIRTY),a
	ld a,(CM_QUIT)
	ld (QUIT_REQ),a
	ld a,1
	ret

CMD_CAMPSAVE:	dw SCREEN_X, SCREEN_Y+120, VIEWBUF_X, VIEWBUF_Y, 176, 24
CMD_CAMPBACK:	dw VIEWBUF_X, VIEWBUF_Y, SCREEN_X, SCREEN_Y+120, 176, 24
CM_MENU:	db 0
CM_QUIT:	db 0

; ----------------------------------------------------------------------------
; CM_SCRIBE - a mage copies scrolls into the spell book (scribeScrollDialogue)
; ----------------------------------------------------------------------------
CM_SCRIBE:
	; the scrolls (type 34, value = spell) of the party: SB_SLOT = slot + 1
	ld hl,SB_SLOT
	ld b,32
.cl:	ld (hl),0
	inc hl
	djnz .cl
	xor a
	ld (SB_N),a
	ld c,0
.ch:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.nc
	ld b,0
.sl:	push bc
	ld a,b
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or e
	jr z,.ns
	ex de,hl
	call ITEM_IX
	ld a,(ix+I_TYPE)
	cp 34
	jr nz,.ns
	ld a,(ix+I_VALUE)
	dec a
	cp 32
	jr nc,.ns
	ld e,a
	ld d,0
	ld hl,SB_SLOT
	add hl,de
	ld a,(hl)
	or a
	jr nz,.ns		; one is enough
	pop bc
	push bc
	ld a,b
	inc a
	ld (hl),a
	ld hl,SB_CHAR
	add hl,de
	ld (hl),c
	ld hl,SB_N
	inc (hl)
.ns:	pop bc
	inc b
	ld a,b
	cp 27
	jr c,.sl
.nc:	inc c
	ld a,c
	cp 6
	jr c,.ch
	ld a,(SB_N)
	or a
	ld hl,STR_SC2
	jp z,CM_TEXTBOX
	; the mage
	ld hl,STR_SC1
	xor a
	call CM_PICK
	cp 0FEh
	ret nc			; (aborted, or no mage: the scrolls were checked)
	ld (MZ_CHAR),a
	call CHAR_PTR
	ld c,1
	call CLASS_LEVEL
	or a
	ld hl,STR_SC4
	jp z,CM_TEXTBOX
	; the spells it knows already do not count
	ld a,(MZ_CHAR)
	call CHAR_PTR
	ld hl,SB_SLOT
	ld c,0
.kn:	ld a,c
	call SB_KNOWN
	jr z,.kx
	ld (hl),0
.kx:	inc hl
	inc c
	ld a,c
	cp 32
	jr c,.kn
	call SB_LIST
	ld hl,STR_SC3
	jp z,CM_TEXTBOX
.menu:	call SB_LIST
	ret z
	call CM_WINDOW
	ld hl,STR_SC0
	call CM_LINES
	ld a,(SB_N)
	ld b,a
	ld c,0
.pr:	push bc
	ld e,c
	ld d,0
	ld hl,SB_MENU
	add hl,de
	ld a,(hl)
	inc a
	call MCALL		; its name -> TEXTBUF
	dw SPELL_NAME_TB
	pop bc
	push bc
	ld a,c
	add a,a
	add a,a
	add a,a
	add a,c
	add a,50
	ld c,a
	ld hl,TEXTBUF
	ld de,8
	ld a,C_WHITE
	call SHADED_TEXT
	pop bc
	inc c
	djnz .pr
	ld hl,128		; the exit button (any click off the list leaves)
	ld (BOX_X),hl
	ld a,122
	ld (BOX_Y),a
	ld a,40
	ld (BOX_W),a
	ld a,14
	ld (BOX_H),a
	call MENU_BOX
	ld hl,SB_EXIT
	call CM_LABEL
	call CM_WAIT_CLICK
	ld a,(MOUSE_X+1)
	or a
	ret nz
	ld a,(MOUSE_X)
	cp 8
	ret c
	cp 176
	ret nc
	ld a,(MOUSE_Y)
	sub 50
	ret c
	ld c,0
.row:	sub 9
	jr c,.got
	inc c
	jr .row
.got:	ld a,(SB_N)
	dec a
	cp c
	ret c
	; copied: the mage knows it, the scroll goes
	ld e,c
	ld d,0
	ld hl,SB_MENU
	add hl,de
	ld c,(hl)		; spell - 1
	ld a,(MZ_CHAR)
	call CHAR_PTR
	ld a,c
	call SB_BIT		; HL = byte of P_MKNOWN, A = bit
	or (hl)
	ld (hl),a
	ld b,0
	ld hl,SB_CHAR
	add hl,bc
	ld a,(hl)
	push af
	call CHAR_PTR
	ld hl,SB_SLOT
	add hl,bc
	ld a,(hl)
	ld (hl),0
	dec a
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld e,(hl)
	ld (hl),0
	inc hl
	ld d,(hl)
	ld (hl),0
	ex de,hl
	call ITEM_IX
	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
	pop af
	call PANEL_DRAW
	jp .menu

; SB_KNOWN - A = spell - 1, IY = character -> NZ if it knows it
SB_KNOWN:
	push hl
	call SB_BIT
	and (hl)
	pop hl
	ret
; SB_BIT - A = spell - 1, IY = character -> HL = its byte of P_MKNOWN, A = mask
SB_BIT:
	push bc
	ld c,a
	srl a
	srl a
	srl a
	add a,P_MKNOWN
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld a,c
	and 7
	ld b,a
	ld a,1
	jr z,.m
.s:	add a,a
	djnz .s
.m:	pop bc
	ret
; SB_LIST - SB_MENU = the first 6 scrolls left, SB_N -> Z if none
SB_LIST:
	ld hl,SB_SLOT
	ld de,SB_MENU
	ld bc,0
.lp:	ld a,(hl)
	or a
	jr z,.n
	ld a,c
	ld (de),a
	inc de
	inc b
	ld a,b
	cp 6
	jr z,.e
.n:	inc hl
	inc c
	ld a,c
	cp 32
	jr c,.lp
.e:	ld a,b
	ld (SB_N),a
	or a
	ret
SB_EXIT:	db 128, 122, 40, 14, 4
	dw STR_CM7
SB_SLOT:	ds 32
SB_CHAR:	ds 32
SB_MENU:	ds 6
SB_N:		db 0

; ----------------------------------------------------------------------------
; CM_DROP - a character leaves the party (dropCharacter): its things stay on
;   the floor; the last one takes its place
; ----------------------------------------------------------------------------
CM_DROP:
	ld bc,0
.cnt:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.cn
	inc b
.cn:	inc c
	ld a,c
	cp 6
	jr c,.cnt
	ld a,b
	cp 5
	ld hl,STR_DROP0
	jp c,CM_TEXTBOX
	ld hl,STR_DROP1
	ld a,2
	call CM_PICK
	cp 0FEh
	ret nc
	or a
	ret z			; (not the first one)
	call UI_REMOVE_MEMBER
.moved:	; the last one takes the place (exchangeCharacters)
	ld a,(MZ_CHAR)
	cp 5
	jr nc,.draw
	ld a,5
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	ld a,5
	jr nz,.x
	dec a
.x:	ld c,a
	ld a,(MZ_CHAR)
	cp c
	jr nc,.draw
	call CHAR_PTR
	push iy
	pop de
	ld a,c
	call CHAR_PTR
	push iy
	pop hl
	ld b,P_SIZE
.sw:	ld a,(de)
	ld c,(hl)
	ld (hl),a
	ld a,c
	ld (de),a
	inc hl
	inc de
	djnz .sw
.draw:	jp PANEL_DRAW_ALL

; UI_REMOVE_MEMBER - A = occupied party slot. Leave every item in the
; current block, including the individual arrows of a quiver.
UI_REMOVE_MEMBER:
	ld (MZ_CHAR),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	ret z
	ld (iy+P_FLAGS),0
	; its things: the slots but the quiver, then the quiver queue
	ld b,0
.it:	push bc
	ld a,b
	cp 16
	jr z,.ni
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	ld a,(MZ_CHAR)
	call CHAR_PTR
	push iy
	pop hl
	add hl,de
	ld e,(hl)
	ld (hl),0
	inc hl
	ld d,(hl)
	ld (hl),0
	ld a,d
	or e
	jr z,.ni
	ex de,hl
	call UI_PLACE
.ni:	pop bc
	inc b
	ld a,b
	cp 27
	jr c,.it
.q:	ld a,(MZ_CHAR)
	call CHAR_PTR
	push iy
	pop hl
	ld de,P_INV+32
	add hl,de
	ld a,(hl)
	inc hl
	or (hl)
	ret z
	dec hl
	ld de,0FFFFh
	xor a
	call GET_QUEUED_ITEM
	ld a,h
	or l
	ret z
	call UI_PLACE
	jr .q

; UI_PLACE - HL = item: on the floor of the party block
UI_PLACE:
	push hl
	ld a,2
	call RND_RANGE
	dec a
	ld c,a
	ld a,(CUR_DIR)
	add a,a
	add a,a
	add a,c
	ld e,a
	ld d,0
	ld hl,DROP_DIR
	add hl,de
	ld a,(hl)
	ld (UP_POS),a
	pop bc
	ld hl,(CUR_BLOCK)
	ld e,l
	ld d,h
	call WCALL
	dw DRAWOBJ_PTR
	ld a,(UP_POS)
	call WCALL
	dw SET_ITEM_POS
	ld a,1
	ld (SCENE_DIRTY),a
	ret
UP_POS:		db 0

; CM_WAIT_CLICK - the pointer moves until a button goes down
CM_WAIT_CLICK:
	call V9_WAIT_VBLANK
	call MOUSE_UPDATE
	call PTR_SHOW
	ld a,(CLICK)
	or a
	jr z,CM_WAIT_CLICK
	ret

; CM_TABLE - the buttons of CM_MENU -> HL = table (count, then x, y, w,
;   h, flags, text), A = count
CM_TABLE:
	ld a,(CM_MENU)
	or a
	ld hl,CM_MENU0
	jr z,.t
	cp 2
	ld hl,CM_YESNO
	jr z,.t
	cp 3
	ld hl,CM_MENUP
	jr z,.t
	cp 4
	ld hl,CM_PKBTN
	jr z,.t
	ld hl,CM_MENU1
.t:	ld a,(hl)
	inc hl
	ret

CM_MENU0:
	db 7
	db 12, 20, 158, 14, 0
	dw STR_CM1
	db 12, 37, 158, 14, 0
	dw STR_CM2
	db 12, 54, 158, 14, 0
	dw STR_CM3
	db 12, 71, 158, 14, 0
	dw STR_CM4
	db 12, 88, 158, 14, 0
	dw STR_CM5
	db 12, 105, 158, 14, 0
	dw STR_CM6
	db 128, 122, 40, 14, 4
	dw STR_CM7
CM_MENUP:
	db 2
	db 12, 20, 158, 14, 0
	dw PF_SOUND
	db 128, 122, 40, 14, 4
	dw STR_CM7

; PF_LABELS - build the sound effects label with its current state.
PF_LABELS:
	ld hl,STR_PF_SOUND
	ld de,PF_SOUND
	ld bc,STR_OFF
	ld a,(SFX_ON)
	or a
	jr z,.e
	ld bc,STR_ON
.e:	call .cp
	ld l,c
	ld h,b
.cp:	ld a,(hl)
	ld (de),a
	or a
	ret z
	inc hl
	inc de
	jr .cp
PF_L_LEN:	equ 24
PF_SOUND:	ds PF_L_LEN

CM_MENU1:
	db 5
	db 12, 20, 158, 14, 0
	dw STR_CO0
	db 12, 37, 158, 14, 0
	dw STR_CO1
	db 12, 54, 158, 14, 0
	dw STR_CO2
	db 12, 71, 158, 14, 0
	dw STR_CO3
	db 128, 122, 40, 14, 4
	dw STR_CM7

; CM_DRAW - the window, its title and buttons (initMenu; the titles of
;   runCampMenu: "Campamento:", "Preferencias:", "Opciones:")
CM_DRAW:
	call CM_WINDOW
	call PF_LABELS
	ld a,(CM_MENU)
	or a
	ld hl,STR_HEAD0
	jr z,.t
	cp 3
	ld hl,STR_HEAD1
	jr z,.t
	ld hl,STR_CO4
.t:	ld de,5
	ld c,5
	ld a,C_LIGHTBLUE
	call SHADED_TEXT
; CM_BUTTONS - the buttons of CM_MENU, the lit one in light red (a new
;   menu lights its first one)
CM_BUTTONS:
	call CM_TABLE
	ld b,a
.lp:	push bc
	push hl
	call CM_BOXOF
	call MENU_BOX
	pop hl
	push hl
	call CM_LABEL
	pop hl
	ld de,7
	add hl,de
	pop bc
	djnz .lp
	ld a,(CM_MENU)
	ld hl,CM_LASTM
	cp (hl)
	ld (hl),a
	jr z,.same
	xor a
	ld (CM_LIT),a
.same:	ld hl,CM_LIT
	ld a,(hl)
	ld (hl),0FFh		; (none lit on the new buttons)
	cp 0FFh
	ret z
; CM_LIGHT - A = button: lit (light red), the one lit before white again
CM_LIGHT:
	ld hl,CM_LIT
	cp (hl)
	ret z
	ld b,(hl)
	ld (hl),a
	push af
	ld a,b
	cp 0FFh
	ld c,C_WHITE
	call nz,CM_LTEXT
	pop af
	ld c,C_LIGHTRED
; CM_LTEXT - A = button, C = colour: its label again, without a shadow
;   (drawMenuButton with noFill)
CM_LTEXT:
	ld b,a
	ld a,c
	ld (CM_TCOL),a
	ld a,b
	call CM_ENTRY
	call CM_LPOS
	ld a,(CM_TCOL)
	ld b,0
	jp TEXT_PRINT

; CM_ENTRY - A = button -> HL = its entry in the table of CM_MENU
CM_ENTRY:
	push af
	call CM_TABLE
	pop af
	ld b,a
	add a,a
	add a,a
	add a,a
	sub b			; * 7
	ld e,a
	ld d,0
	add hl,de
	ret

; CM_BOXOF - HL = button entry -> BOX_X, BOX_Y, BOX_W, BOX_H
CM_BOXOF:
	ld e,(hl)
	ld d,0
	ld (BOX_X),de
	inc hl
	ld a,(hl)
	ld (BOX_Y),a
	inc hl
	ld a,(hl)
	ld (BOX_W),a
	inc hl
	ld a,(hl)
	ld (BOX_H),a
	ret

; CM_PRESS - A = button: its frame pressed for 80 ms (drawMenuButton with
;   clicked)
CM_PRESS:
	call CM_ENTRY
	call CM_BOXOF
	ld a,C_FILL
	ld (BOX_C1),a
	ld (BOX_C2),a
	xor a
	ld (BOX_FILL),a
	call GUI_BOX
	ld b,5
.w:	push bc
	call V9_WAIT_VBLANK
	pop bc
	djnz .w
	ld a,C_FRAME1
	ld (BOX_C1),a
	ld a,C_FRAME2
	ld (BOX_C2),a
	jp GUI_BOX

; CM_SELECT - the buttons of CM_MENU as runCampMenu / confirmDialogue: the
;   one under the pointer is lit, up / down (left / right in a question)
;   move the light, RETURN or SPACE take the lit one, ESC the last one
;   (Salir; nothing in a question), a click the one under the pointer
;   -> A = button (shown pressed)
CM_SELECT:
	call KEYS_READ
	ld (CM_KLAST),a
.lp:	call V9_WAIT_VBLANK
	call AMCALL
	dw AM_FRAME
	call MOUSE_UPDATE
	call PTR_SHOW
	call CM_HIT
	cp 0FFh
	jr z,.key
	ld b,a
	ld a,(CLICK)
	or a
	ld a,b
	jr nz,.take
	call CM_LIGHT
.key:	call KEYS_READ
	or a
	jr nz,.k
	ld a,7			; RETURN (KEYS_READ has not it)
	call KEY_ROW
	bit 7,a
	ld a,0
	jr nz,.k
	ld a,KEY_USE
.k:	ld hl,CM_KLAST
	cp (hl)
	ld (hl),a
	jr z,.lp		; (held)
	cp KEY_USE
	jr z,.lit
	ld c,a
	ld a,(CM_MENU)
	cp 2
	ld a,c
	jr z,.q
	cp KEY_ESC
	jr z,.esc
	cp KEY_FWD
	jr z,.up
	cp KEY_BACK
	jr z,.down
	jr .lp
.q:	cp KEY_TLEFT
	jr z,.down
	cp KEY_TRIGHT
	jr z,.down
	jr .lp
.esc:	call CM_TABLE
	dec a
	jr .take
.up:	call CM_TABLE
	ld b,a
	ld a,(CM_LIT)
	inc a
	jr z,.ul
	dec a
	jr nz,.u1
.ul:	ld a,b
.u1:	dec a
	jr .mv
.down:	call CM_TABLE
	ld b,a
	ld a,(CM_LIT)
	inc a
	cp b
	jr c,.mv
	xor a
.mv:	call CM_LIGHT
	jp .lp
.lit:	ld a,(CM_LIT)
	cp 0FFh
	jp z,.lp
.take:	push af
	call CM_LIGHT
	pop af
	push af
	call CM_PRESS
	pop af
	ret

CM_LIT:		db 0FFh
CM_LASTM:	db 0FFh
CM_KLAST:	db 0
CM_TCOL:	db 0
CM_NEED:	db 0		; spells memorized: the party needs a rest (_needRest)

; CM_LABEL - HL = button entry: its text, white with a shadow
CM_LABEL:
	call CM_LPOS
	ld a,C_WHITE
	jp SHADED_TEXT

; CM_LPOS - HL = button entry -> HL = its text, DE = x, C = y
CM_LPOS:
	ld e,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)		; w
	inc hl
	inc hl
	ld a,(hl)		; flags
	inc hl
	push af
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	pop af
	ld d,0
	bit 2,a
	jr nz,.centre
	inc e
	inc e
	inc e
	inc e
	inc c
	inc c
	inc c
	ret
.centre:
	; x + (w - 8 * len) / 2 + 1, y + (h - 7) / 2 = y + 3
	push hl
	push de
	push bc
	call STR_LEN
	ld a,b
	pop bc
	pop de
	add a,a
	add a,a
	add a,a
	ld l,a
	ld a,b
	sub l
	srl a
	inc a
	add a,e
	ld e,a
	inc c
	inc c
	inc c
	pop hl
	ret

; CM_HIT - the button under the mouse -> A (FFh: none)
CM_HIT:
	call CM_TABLE
; CM_HIT_TAB - HL = entries, A = count
CM_HIT_TAB:
	ld b,a
	ld c,0
.lp:	ld a,(MOUSE_X+1)
	or a
	jr nz,.no
	ld a,(MOUSE_X)
	sub (hl)
	jr c,.n
	inc hl
	inc hl
	cp (hl)
	dec hl
	dec hl
	jr nc,.n
	ld a,(MOUSE_Y)
	inc hl
	sub (hl)
	dec hl
	jr c,.n
	inc hl
	inc hl
	inc hl
	cp (hl)
	dec hl
	dec hl
	dec hl
	jr nc,.n
	ld a,c
	ret
.n:	ld de,7
	add hl,de
	inc c
	djnz .lp
.no:	ld a,0FFh
	ret

; ----------------------------------------------------------------------------
; CM_PICK - HL = the question, A = 0 a mage, 1 a cleric or paladin, 2 anybody
;   -> A = the character, FFh: aborted, FEh: nobody can (selectCharacterDialogue)
;   The ones who cannot get a grid over their name (only those standing and
;   fed can learn spells); one alone is taken at once. Otherwise a frame of
;   changing colours marks one: the cursor keys move it, RETURN or SPACE take
;   it, ESC or Salir give up; a click on a box takes that one.
; ----------------------------------------------------------------------------
CM_PICK:
	ld (PK_KIND),a
	ld (PK_Q),hl
	ld hl,PK_OK
	ld b,6
.cl:	ld (hl),0
	inc hl
	djnz .cl
	ld c,0
	ld e,0			; how many
.e:	ld a,c
	ld (MZ_CHAR),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.en
	ld a,(PK_KIND)
	cp 2
	jr z,.ok
	push bc
	push de
	or a
	ld c,1			; a mage
	jr z,.ct
	ld c,2			; a cleric or a paladin
	call CLASS_LEVEL
	or a
	jr nz,.cy
	ld c,4
.ct:	call CLASS_LEVEL
.cy:	pop de
	pop bc
	or a
	jr z,.en
	ld a,c
	call CHAR_PTR
	ld a,(iy+P_FOOD)
	or a
	jr z,.en
	bit 3,(iy+P_FLAGS)	; stone
	jr nz,.en
	ld a,(iy+P_HP)
	dec a
	jp m,.en
.ok:	ld hl,PK_OK
	ld b,0
	add hl,bc
	ld (hl),1
	inc e
	ld a,c
	ld (PK_CUR),a		; (the last one)
.en:	inc c
	ld a,c
	cp 6
	jr c,.e
	ld a,e
	or a
	ld a,0FEh
	ret z			; nobody
	dec e
	ld a,(PK_CUR)
	ret z			; one alone
	; the question, Salir, the grids
	call CM_WINDOW
	ld hl,(PK_Q)
	call CM_LINES
	ld a,(CM_MENU)
	ld (PK_MENU),a
	ld a,4
	ld (CM_MENU),a
	ld (CM_LASTM),a
	ld a,0FFh
	ld (CM_LIT),a
	call CM_BUTTONS
	ld c,0
.g:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.gn
	ld hl,PK_OK
	ld b,0
	add hl,bc
	ld a,(hl)
	or a
	jr nz,.gn
	call PK_BOXXY		; DE = x, A = y of box C
	ld b,4
.g4:	push bc
	push de
	push af
	ld c,a
	ld hl,SHP_SMALLGRID
	ld a,V9_LOG_TCOPY
	call BLIT_SCREEN
	pop af
	pop de
	ld hl,16
	add hl,de
	ex de,hl
	pop bc
	djnz .g4
.gn:	inc c
	ld a,c
	cp 6
	jr c,.g
	; the first one that can
	ld a,5
	ld (PK_CUR),a
	call PK_NEXT
	xor a
	ld (PK_COL),a
	call KEYS_READ
	ld (CM_KLAST),a
.lp:	call V9_WAIT_VBLANK
	call PK_STEP
	call MOUSE_UPDATE
	call PTR_SHOW
	ld a,(CLICK)
	or a
	jr z,.key
	call CHAR_AT_MOUSE
	cp 0FFh
	jr z,.salir
	ld c,a
	ld b,0
	ld hl,PK_OK
	add hl,bc
	ld a,(hl)
	or a
	jr z,.lp
	ld a,c
	jr .take
.salir:	call CM_HIT
	or a
	jr nz,.lp
.abort:	call PK_OFF
	xor a
	call CM_PRESS
	ld a,0FFh
	jr .end
.key:	call KEYS_READ
	or a
	jr nz,.kk
	ld a,7			; RETURN
	call KEY_ROW
	bit 7,a
	ld a,0
	jr nz,.kk
	ld a,KEY_USE
.kk:	ld hl,CM_KLAST
	cp (hl)
	ld (hl),a
	jr z,.lp
	cp KEY_ESC
	jr z,.abort
	cp KEY_USE
	jr z,.cur
	cp KEY_TLEFT
	jr z,.prev
	cp KEY_FWD
	jr z,.prev
	cp KEY_TRIGHT
	jr z,.next
	cp KEY_BACK
	jp nz,.lp
.next:	call PK_OFF
	call PK_NEXT
	jp .lp
.prev:	call PK_OFF
	ld b,6
.pv:	ld a,(PK_CUR)
	dec a
	jp p,.pp
	ld a,5
.pp:	ld (PK_CUR),a
	ld e,a
	ld d,0
	ld hl,PK_OK
	add hl,de
	ld a,(hl)
	or a
	jp nz,.lp
	djnz .pv
	jp .lp
.cur:	ld a,(PK_CUR)
.take:	push af
	call PK_OFF
	pop af
.end:	push af
	ld a,(PK_MENU)
	ld (CM_MENU),a
	call PANEL_DRAW_ALL	; (the grids go)
	pop af
	ret
; PK_STEP - cycle the portrait frame every three frames. Leave the pointer
; and its saved background alone. If it covers the border, keep that frame
; colour until it moves clear.
PK_STEP:
	ld hl,PK_TICK
	dec (hl)
	ret nz
	ld (hl),3
	ld a,(PTR_ON)
	or a
	jr z,.draw
	ld a,(PK_CUR)
	ld c,a
	call PK_BOXXY
	dec de			; frame x
	add a,50		; frame bottom (inclusive)
	ld hl,(PTR_Y)
	sub l			; bottom minus cursor top
	cp 67			; 52 rows plus 15 for the cursor
	jr nc,.draw
	ld b,a
	ld hl,(PTR_X)
	or a
	sbc hl,de
	ld de,15
	add hl,de		; cursor right minus frame left
	ld a,h
	or a
	jr nz,.draw
	ld a,l
	cp 80			; 65 columns plus 15 for the cursor
	jr nc,.draw
	sub 16			; the cursor may be wholly inside the frame
	cp 48
	ret nc
	ld a,b
	sub 16
	cp 35
	ret nc
.draw:	ld a,(PTR_ON)
	push af
	xor a			; the fills are clear of the saved pointer area
	ld (PTR_ON),a
	ld a,(PK_COL)
	inc a
	and 15
	ld (PK_COL),a
	ld e,a
	ld d,0
	ld hl,PK_COLS
	add hl,de
	ld a,(hl)
	call PK_FRAME
	pop af
	ld (PTR_ON),a
	ret
; PK_NEXT - the next one that can after PK_CUR
PK_NEXT:
	ld b,6
.n:	ld a,(PK_CUR)
	inc a
	cp 6
	jr c,.s
	xor a
.s:	ld (PK_CUR),a
	ld e,a
	ld d,0
	ld hl,PK_OK
	add hl,de
	ld a,(hl)
	or a
	ret nz
	djnz .n
	ret
; PK_OFF - the frame of PK_CUR black again
PK_OFF:	ld a,C_BLACK
; PK_FRAME - A = colour: the frame around the box of PK_CUR (_highlightFrames)
PK_FRAME:
	ld (BOX_C1),a
	ld (BOX_C2),a
	xor a
	ld (BOX_FILL),a
	ld a,(PK_CUR)
	ld c,a
	call PK_BOXXY
	dec de
	ld (BOX_X),de
	dec a
	ld (BOX_Y),a
	ld a,65
	ld (BOX_W),a
	ld a,52
	ld (BOX_H),a
	jp GUI_BOX
; PK_BOXXY - C = character -> DE = x, A = y of its box. Preserves C.
PK_BOXXY:
	ld a,c
	ld de,184
	rrca
	jr nc,.l
	ld de,256
.l:	and 7Fh			; the row
	push hl
	ld hl,PK_ROWY
	add a,l
	ld l,a
	adc a,h
	sub l
	ld h,a
	ld a,(hl)
	pop hl
	ret
PK_ROWY:	db 2, 54, 106
PK_KIND:	db 0
PK_Q:		dw 0
PK_OK:		ds 6
PK_CUR:		db 0
PK_COL:		db 0
PK_TICK:	db 3
PK_MENU:	db 0
CM_PKBTN:
	db 1
	db 128, 122, 40, 14, 4
	dw STR_CM7

; CM_WINDOW - the fill and the double frame of the window (0, 0)-(175, 143)
CM_WINDOW:
	ld de,0
	ld c,0
	ld b,176
	ld l,144
	ld a,C_FILL
	call FILL_RECT
	ld hl,0
	ld (BOX_X),hl
	xor a
	ld (BOX_Y),a
	ld a,176
	ld (BOX_W),a
	ld a,144
	ld (BOX_H),a
	; fall through

; MENU_BOX - (BOX_X..BOX_H): drawMenuButtonBox (two frames, filled)
MENU_BOX:
	ld a,C_FRAME1
	ld (BOX_C1),a
	ld a,C_FRAME2
	ld (BOX_C2),a
	xor a
	ld (BOX_FILL),a
	call GUI_BOX
	ld hl,(BOX_X)
	inc hl
	ld (BOX_X),hl
	ld hl,BOX_Y
	inc (hl)
	ld hl,BOX_W
	dec (hl)
	dec (hl)
	ld hl,BOX_H
	dec (hl)
	dec (hl)
	ld a,C_FILL
	ld (BOX_FILL),a
	jp GUI_BOX

; SHADED_TEXT - HL = text, DE = x, C = y, A = colour: a black shadow one
;   pixel down and right
SHADED_TEXT:
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

; CM_TEXTBOX - HL = text (CR breaks lines): displayTextBox, in the box of
;   dim 11 from (13, 25); 1.44 s or a click end it
CM_TEXTBOX:
	push hl
	call CM_BOX11
	pop hl
	ld de,13
	ld c,25
	ld a,8
	call CM_LINES_AT
	ld b,86			; 1440 ms
.w:	push bc
	call V9_WAIT_VBLANK
	call MOUSE_UPDATE
	call PTR_SHOW
	pop bc
	ld a,(CLICK)
	or a
	ret nz
	djnz .w
	ret

; CM_BOX11 - the box of dim 11 (8, 20)-(167, 75): text boxes, questions
CM_BOX11:
	ld hl,8
	ld (BOX_X),hl
	ld a,20
	ld (BOX_Y),a
	ld a,160
	ld (BOX_W),a
	ld a,56
	ld (BOX_H),a
	jp MENU_BOX

; CM_LINES - HL = text: lines from (5, 5), 9 pixels apart
; CM_LINES_AT - HL = text, DE = x, C = y, A = pixels from line to line
CM_LINES:
	ld de,5
	ld c,5
	ld a,9
CM_LINES_AT:
	ld (CL_X),de
	ld (CL_STEP),a
.line:	ld de,TEXTBUF
.cp:	ld a,(hl)
	or a
	jr z,.last
	inc hl
	cp 13
	jr z,.eol
	ld (de),a
	inc de
	jr .cp
.eol:	call .out
	jr .line
.last:	call .out
	ret
.out:	xor a
	ld (de),a
	push hl
	push bc
	ld hl,TEXTBUF
	ld de,(CL_X)
	ld a,C_WHITE
	call SHADED_TEXT
	pop bc
	pop hl
	ld a,(CL_STEP)
	add a,c
	ld c,a
	ret
CL_X:		dw 0
CL_STEP:	db 0

; CM_CONFIRM - HL = question: Si / No -> NZ for yes (confirmDialogue: the
;   box of menu 5, the question from (16, 24), "Si" lit first)
CM_CONFIRM:
	push hl
	ld hl,8
	ld (BOX_X),hl
	ld a,20
	ld (BOX_Y),a
	ld a,160
	ld (BOX_W),a
	ld a,84			; room for six wrapped lines and the buttons
	ld (BOX_H),a
	call MENU_BOX
	pop hl
	ld c,24
.line:	ld a,18			; x=16, right edge=168, FONT8 + shadow
	push bc
	call WRAP_LINE
	pop bc
	jr z,.buttons
	push hl
	ld hl,MSG_LINE
	ld de,16
	ld a,8
	call CM_LINES_AT
	pop hl
	jr .line
.buttons:
	ld a,(CM_MENU)
	push af
	ld a,2
	ld (CM_MENU),a
	call CM_BUTTONS
	call CM_SELECT
	ld c,a
	pop af
	ld (CM_MENU),a
	push bc
	call PANEL_DRAW_ALL	; (a long question goes over the portraits)
	pop bc
	ld a,c
	xor 1			; 0 yes -> NZ
	ret
CM_YESNO:
	db 2
	db 16, 82, 32, 14, 4
	dw STR_YES
	db 128, 82, 32, 14, 4
	dw STR_NO


; RING2 - IY = character, A = slot -> Z if a ring of type 47 value 2 is there
RING2:
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.no
	call ITEM_IX
	ld a,(ix+I_TYPE)
	cp 47
	ret nz
	ld a,(ix+I_VALUE)
	cp 2
	ret
.no:	or 1
	ret


; STR_COPY - HL = text -> DE (with its end)
STR_COPY:
	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	or a
	jr nz,STR_COPY
	ret

; NUM16_STR - HL = number -> HL = its digits (ASCIIZ)
NUM16_STR:
	ld de,NUM16_BUF+5
	xor a
	ld (de),a
.lp:	ld a,10
	push de
	call DIV16_8
	pop de
	dec de
	add a,'0'
	ld (de),a
	ld a,h
	or l
	jr nz,.lp
	ex de,hl
	ret
NUM16_BUF:	ds 6

; ============================================================================
; Hands and armour class (moved here from the resident part)
; ============================================================================
; ----------------------------------------------------------------------------
; SWAP_HAND_SLOT - C = character, A = slot: exchanges the hand item with
;   the item of the slot, if the slot accepts it
;   (gui_processWeaponSlotClickLeft)
; ----------------------------------------------------------------------------
SWAP_HAND_SLOT:
	ld (SW_SLOT),a
	ld a,c
	ld (SW_CHAR),a
	call CHAR_PTR
	ld a,(SW_SLOT)
	call SLOT_PTR
	ld (SW_PTR),hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld (SW_ITEM),hl
	call ITEM_IX
	bit 5,(ix+I_FLAGS)	; cursed: it stays
	ret nz
	; the inventory flags of the hand item (none: all)
	ld de,0FFFFh
	ld hl,(HAND)
	ld a,h
	or l
	jr z,.v
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld de,IT_INVF
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
.v:	ld a,(SW_SLOT)
	add a,a
	ld l,a
	ld h,0
	ld bc,SLOT_FLAGS
	add hl,bc
	ld a,(hl)
	and e
	ld c,a
	inc hl
	ld a,(hl)
	and d
	or c
	jr z,.ac
	ld hl,(SW_PTR)
	ld de,(HAND)
	ld (hl),e
	inc hl
	ld (hl),d
	ld hl,(SW_ITEM)
	call SET_HAND_ITEM
	ld a,(SW_CHAR)
	call PANEL_DRAW
.ac:	ld a,(SW_CHAR)
	jp RECALC_AC

SW_SLOT:	db 0
SW_CHAR:	db 0
SW_PTR:		dw 0
SW_ITEM:	dw 0

; ----------------------------------------------------------------------------
; RECALC_AC - A = character: its armour class (recalcArmorClass)
; ----------------------------------------------------------------------------
RECALC_AC:
	ld (RA_CHAR),a
	call CHAR_PTR
	ld e,(iy+P_DEX)
	ld d,0
	ld hl,DEX_AC_MOD
	add hl,de
	ld a,(hl)
	add a,10
	ld (RA_AC),a
	ld hl,RA_SLOTS
	ld b,4
.lp:	push bc
	push hl
	ld a,(hl)
	ld (RA_SLOT),a
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.next
	ld (RA_ITEM),hl
	; the shield hand counts only when that hand may be used
	ld a,(RA_SLOT)
	cp 1
	jr nz,.valid
	call VALIDATE_SLOT1
	jr z,.next
.valid:	ld hl,(RA_ITEM)
	call ITEM_IX
	ld a,(ix+I_TYPE)
	ld (RA_TYPE),a
	call ITEMTYPE_PTR
	push hl
	call CLASS_FLAG		; A = class flags of the character
	pop hl
	push hl
	ld de,IT_CLASSES
	add hl,de
	and (hl)
	pop hl
	jr z,.next
	ld a,(hl)		; extra properties: only plain items
	or a
	jr nz,.next
	ld a,(RA_SLOT)
	cp 2
	jr nc,.add		; slots 17, 18
	ld a,(RA_TYPE)
	cp 27			; the hands: shields only
	jr nz,.next
.add:	ld de,IT_AC
	add hl,de
	ld a,(RA_AC)
	add a,(hl)
	sub (ix+I_VALUE)
	ld (RA_AC),a
.next:	pop hl
	pop bc
	inc hl
	djnz .lp
	; no magic armour: the best protection ring helps
	ld a,17
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	call ITEM_IX
	ld a,(ix+I_VALUE)
	or a
	jr nz,.done
	ld a,25
	call RING_BONUS
	ld c,a
	ld a,26
	call RING_BONUS
	cp c
	jp m,.m1		; signed max
	ld c,a
.m1:	ld a,(RA_AC)
	sub c
	ld (RA_AC),a
.done:	; armor spell: base armour 6 (+ dexterity) while it lasts
	ld a,(iy+P_EFFREM)
	or a
	jr z,.shield
	ld e,(iy+P_DEX)
	ld d,0
	ld hl,DEX_AC_MOD
	add hl,de
	ld a,(hl)
	add a,6
	ld c,a
	ld a,(RA_AC)
	cp c
	jp m,.armgone
	jr z,.armgone
	ld a,c
	ld (RA_AC),a
	jr .shield
.armgone:
	ld (iy+P_EFFREM),0
	res 0,(iy+P_EFFECT)
.shield:	; shield spell: 4 at worst
	bit 3,(iy+P_EFFECT)
	jr z,.vest
	ld a,(RA_AC)
	cp 5
	jp m,.vest
	ld a,4
	ld (RA_AC),a
.vest:	; corrected Vestment: protection improves with caster level
	bit 6,(iy+P_EFFECT+1)
	jr z,.set
	ld a,(RA_AC)
	call XCALL
	dw FX_VEST_AC
	ld (RA_AC),a
.set:	ld a,(RA_AC)
	ld (iy+P_AC),a
	ret

; RING_BONUS - IY = character, A = slot -> A = value of a plain item there (0)
RING_BONUS:
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	ret z
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld a,(hl)
	or a
	ld a,0
	ret nz
	ld a,(ix+I_VALUE)
	ret

; VALIDATE_SLOT1 - IY = character -> NZ if the second hand may be used
;   (validateWeaponSlotItem for slot 1)
VALIDATE_SLOT1:
	ld a,0
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld (VS_ITEM1),hl
	; a two-handed item in the first hand
	or h
	jr z,.h2
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld de,IT_HANDS
	add hl,de
	ld a,(hl)
	cp 2
	jr z,.no
.h2:	ld a,1
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.yes
	push hl
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld a,(hl)		; extra properties
	pop de
	or a
	jr z,.usable
	cp 4
	jr nc,.usable
	push de
	ld de,IT_HANDS
	add hl,de
	ld a,(hl)
	pop de
	or a
	jr nz,.no		; a weapon that needs hands
.usable:
	ex de,hl
	jp ITEM_USABLE
.no:	xor a
	ret
.yes:	or 1
	ret

DEX_AC_MOD:	db 5,5,5,4,3,2,1,0,0,0,0,0,0,0,0,-1,-2,-3,-4,-4,-5,-5,-5,-6,-6
RA_SLOTS:	db 17, 0, 1, 18
RA_CHAR:	db 0
RA_AC:		db 0
RA_SLOT:	db 0
RA_TYPE:	db 0
RA_ITEM:	dw 0
VS_ITEM1:	dw 0


; ============================================================================
; MEMORIZE - A = 0 memorize (mages) / 1 pray (clerics): which spells the
;   character will have after the next rest (runMemorizePrayMenu, EOB1)
; ============================================================================
MEMORIZE:
	ld (MZ_TYPE),a
	; the character
	or a
	ld hl,STR_SP0
	jr z,.p
	ld hl,STR_SP3
.p:	call CM_PICK
	cp 0FFh
	ret z
	cp 0FEh			; nobody can
	jr nz,.got
	ld a,(MZ_TYPE)
	or a
	jr z,.nomage
	jr .nocler
.got:	ld (MZ_CHAR),a
	call CHAR_PTR
	; can it? the class, the state, the book
	ld a,(MZ_TYPE)
	or a
	ld c,1			; class type 1: mage
	jr z,.ct
	ld c,2			; 2: cleric
.ct:	call CLASS_LEVEL	; A = level in that class, 0 none
	or a
	jr nz,.class
	ld a,(MZ_TYPE)
	or a
	jr z,.nomage
	ld c,4			; a paladin prays too
	call CLASS_LEVEL
	or a
	jr z,.nocler
	ld b,a
	ld a,1
	ld (MZ_PAL),a
	ld a,b
	jr .lvl
.nomage:
	ld hl,STR_SP5
	jp CM_TEXTBOX
.nocler:
	ld hl,STR_SP4
	jp CM_TEXTBOX
.class:	ld b,a
	xor a
	ld (MZ_PAL),a
	ld a,b
.lvl:	; (A = level of the class)
	call CLASS_LEVEL_A
	ld (MZ_LV),a
	ld a,(MZ_CHAR)
	call CHAR_PTR
	ld a,(iy+P_HP)
	dec a
	jp p,.alive
	ld a,(MZ_TYPE)
	or a
	ld hl,STR_SP6
	jr z,.box
	ld hl,STR_SP7
.box:	jp CM_TEXTBOX
.alive:	ld a,(MZ_TYPE)
	or a
	jr nz,.slots
	; a mage needs the spellbook (item type 29)
	ld b,27
	ld c,0
.book:	push bc
	ld a,c
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.nb
	call ITEM_IX
	ld a,(ix+I_TYPE)
	cp 29
	jr z,.hasbook
.nb:	pop bc
	inc c
	djnz .book
	ld hl,STR_SP2
	jp CM_TEXTBOX
.hasbook:
	pop bc
.slots:	; slots per spell level
	ld a,(MZ_LV)
	dec a
	ld c,a
	add a,a
	add a,a
	add a,c			; (level - 1) * 5
	ld e,a
	ld d,0
	ld a,(MZ_TYPE)
	or a
	ld hl,UI_NUM_MAGE
	jr z,.tab
	ld hl,UI_NUM_CLERIC
	ld a,(MZ_PAL)
	or a
	jr z,.tab
	ld hl,UI_NUM_PAL
.tab:	add hl,de
	ld de,MZ_NP
	ld bc,5
	ldir
	ld a,(MZ_TYPE)
	or a
	jr nz,.wizdone
	ld a,(MZ_CHAR)
	call XCALL
	dw FX_WIZARDRY
	or a
	jr z,.wizdone
	ld hl,MZ_NP+3
	sla (hl)
	inc hl
	sla (hl)
.wizdone:
	ld a,(MZ_TYPE)
	or a
	jr z,.np
	ld a,(MZ_PAL)
	or a
	jr nz,.np
	; clerics: wisdom over 12 adds
	ld a,(MZ_CHAR)
	call CHAR_PTR
	ld a,(iy+P_WIS)
	sub 12
	jr nc,.wm
	xor a
.wm:	cp 8
	jr c,.wm2
	ld a,7
.wm2:	ld c,a
	add a,a
	add a,a
	add a,c
	ld e,a
	ld d,0
	ld hl,UI_NUM_WISADJ
	add hl,de
	ld de,MZ_NP
	ld b,5
.wa:	ld a,(de)
	or a
	jr z,.wz
	add a,(hl)
	ld (de),a
.wz:	inc hl
	inc de
	djnz .wa
.np:	; the current list of the character, then the counts per spell
	ld a,(MZ_CHAR)
	ld c,a
	ld a,(MZ_TYPE)
	ld b,a
	ld a,c
	ld c,b
	call MCALL
	dw SPELLS_GET
	ld hl,MZ_PAGE
	ld b,5+64
.cz:	ld (hl),0
	inc hl
	djnz .cz
	ld hl,BOUNCE
	ld b,50
.cnt:	ld a,(hl)
	inc hl
	or a
	jr z,.cn
	ld c,0
	jp p,.cr
	neg
	inc c
.cr:	; spell a (1..31): total + 1; ready + 1 when > 0
	push hl
	dec a
	push af
	add a,a
	ld e,a
	ld d,0
	ld hl,MZ_COUNT
	add hl,de
	inc (hl)		; total
	inc hl
	ld a,c
	or a
	jr nz,.used
	inc (hl)		; ready
.used:	pop af
	call MZ_LEVELOF		; A = page 0..4
	ld e,a
	ld d,0
	ld hl,MZ_PAGE
	add hl,de
	inc (hl)
	pop hl
.cn:	djnz .cnt
	xor a
	ld (MZ_PG),a
	dec a
	ld (MZ_MOUSE_Y),a		; first hover samples the current pointer
	ld a,(MZ_CHAR)		; the frame of changing colours on the character
	ld (PK_CUR),a
	call KEYS_READ
	ld (CM_KLAST),a
.page:	xor a			; a new page: its first spell lit
	ld (MZ_HL),a
.draw:	call MZ_DRAW
	call MZ_LIGHT
	; the pointer over the list lights its row, the keys move the light
.loop:	call V9_WAIT_VBLANK
	call PK_STEP
	call MOUSE_UPDATE
	call MZ_HOVER
	call PTR_SHOW		; restore it after repainting the frame or spell row
	ld a,(CLICK)
	or a
	jr nz,.click
	call MZ_KEY
	ld hl,CM_KLAST
	cp (hl)
	ld (hl),a
	jr z,.loop		; (held)
	cp KEY_USE
	jp z,.add
	cp KEY_ESC
	jp z,.done
	cp KEY_FWD
	jr z,.up
	cp KEY_BACK
	jr z,.down
	cp MZ_K_HOME
	jr z,.home
	cp KEY_TLEFT
	jr z,.left
	cp KEY_TRIGHT
	jr z,.right
	cp MZ_K_MINUS
	jp z,.minus
	jr .loop
.up:	ld a,(MZ_HL)		; (from the first one to the last one)
	dec a
	jp p,.hl
	call MZ_ROWS
	dec a
	jr .hl
.down:	call MZ_ROWS
	ld b,a
	ld a,(MZ_HL)
	inc a
	cp b
	jr c,.hl
.home:	xor a
.hl:	call MZ_SETHL
	jr .loop
.left:	ld a,(MZ_PG)
	dec a
	jp p,.pg
	ld a,4
	jr .pg
.right:	ld a,(MZ_PG)
	inc a
	cp 5
	jr c,.pg
	xor a
.pg:	ld (MZ_PG),a
	jp .page
.click:	; bounded mouse hit tests; right click removes a copy
	call XCALL
	dw FX_MZ_CLICK
	cp 5
	jr c,.pg
	jp z,.add
	cp 6
	jr z,.minus
	cp 7
	jr z,.clear
	cp 8
	jr z,.done
	jp .loop
.add:	ld a,(MZ_HL)
	ld c,a
	call MZ_ENTRY		; A = spell (1..) of row C, 0 none
	or a
	jp z,.loop
	ld (MZ_SPELL),a
	; room on this page?
	call MZ_PGPTR
	ld a,(hl)
	ld hl,MZ_PAGE
	add hl,de
	cp (hl)
	jp z,.loop
	jp c,.loop
	inc (hl)
	ld a,(MZ_SPELL)
	call MZ_CNTPTR
	inc (hl)
	jp .draw
.minus:	; one less of the lit spell
	ld a,(MZ_HL)
	ld c,a
	call MZ_ENTRY
	or a
	jp z,.loop
	ld (MZ_SPELL),a
	call MZ_CNTPTR
	ld a,(hl)
	or a
	jp z,.loop
	dec (hl)
	call MZ_PGPTR
	ld hl,MZ_PAGE
	add hl,de
	dec (hl)
	jp .draw
.done:	call PK_OFF
	jp MZ_DONE
.clear:	; Borrar: no spells on this page
	ld c,0
.cl:	push bc
	call MZ_ENTRY
	pop bc
	or a
	jr z,.cl2
	dec a
	add a,a
	ld e,a
	ld d,0
	ld hl,MZ_COUNT
	add hl,de
	ld (hl),0
	inc hl
	ld (hl),0
.cl2:	inc c
	ld a,c
	cp 8
	jr c,.cl
	ld a,(MZ_PG)
	ld e,a
	ld d,0
	ld hl,MZ_PAGE
	add hl,de
	ld (hl),0
	jp .draw

; MZ_DONE - the new list: ready spells first (as many as stay), the rest
;   as used ones that come back with the rest
MZ_DONE:
	ld hl,BOUNCE
	ld b,50
.z:	ld (hl),0
	inc hl
	djnz .z
	ld c,1			; spell
.sp:	ld a,c
	dec a
	add a,a
	ld e,a
	ld d,0
	ld hl,MZ_COUNT
	add hl,de
	ld a,(hl)		; total
	inc hl
	cp (hl)
	jr nc,.rk
	ld (hl),a		; ready <= total
.rk:	or a
	jr z,.next
	ld b,a			; total
	ld e,(hl)		; ready
.put:	push bc
	push de
	; page of the spell
	ld a,c
	dec a
	call MZ_LEVELOF
	ld l,a
	add a,a
	add a,a
	add a,l
	add a,a			; *10
	ld e,a
	ld d,0
	ld hl,BOUNCE
	add hl,de
	ld b,10
.fr:	ld a,(hl)
	or a
	jr z,.fr2
	inc hl
	djnz .fr
	pop de
	pop bc
	jr .next
.fr2:	pop de
	ld a,e
	or a
	ld a,c
	jr nz,.rd
	neg			; not ready: after the rest
	ld (CM_NEED),a
	jr .w
.rd:	dec e
.w:	ld (hl),a
	pop bc
	djnz .put
.next:	inc c
	ld a,c
	cp 32
	jr c,.sp
	ld a,(MZ_CHAR)
	ld c,a
	ld a,(MZ_TYPE)
	ld b,a
	ld a,c
	ld c,b
	call MCALL
	dw SPELLS_PUT
	ret

; MZ_LEVELOF - A = spell - 1 -> A = its page (level - 1)
MZ_LEVELOF:
	ld e,a
	ld d,0
	ld a,(MZ_TYPE)
	or a
	ld hl,UI_MAGE_LEVELS
	jr z,.t
	ld hl,UI_CLERIC_LEVELS
.t:	add hl,de
	ld a,(hl)
	dec a
	ret p
	xor a
	ret

; MZ_ENTRY - C = row of the list -> A = the C-th spell (1..) of the page
;   the character may learn (0: none)
MZ_ENTRY:
	ld b,0			; spell - 1
	ld e,c			; rows to skip
.lp:	ld a,b
	cp 31
	jr nc,.none
	push de
	call MZ_AVAIL
	pop de
	jr z,.n
	ld a,b
	push de
	call MZ_LEVELOF
	pop de
	ld hl,MZ_PG
	cp (hl)
	jr nz,.n
	ld a,e
	or a
	jr z,.got
	dec e
.n:	inc b
	jr .lp
.got:	ld a,b
	inc a
	ret
.none:	xor a
	ret

; MZ_AVAIL - B = spell - 1 -> NZ if the character may have it (mages: the
;   spells they know; clerics, paladins: a fixed set)
MZ_AVAIL:
	ld a,(MZ_TYPE)
	or a
	jr nz,.cl
	ld a,b
	cp 4
	jr z,.basic
	cp 8
	jr z,.basic
	ld a,(MZ_CHAR)
	call CHAR_PTR
	push iy
	pop hl
	ld de,P_MKNOWN
	add hl,de
	jr .bit
.cl:	ld hl,MZ_CLERIC
	ld a,(MZ_PAL)
	or a
	jr z,.bit
	ld hl,MZ_PALADIN
.bit:	ld a,b
	cp 26
	jr nc,.no
	srl a
	srl a
	srl a
	ld e,a
	ld d,0
	add hl,de
	ld a,b
	and 7
	ld c,a
	ld a,(hl)
	inc c
.sh:	dec c
	jr z,.t
	rrca
	jr .sh
.t:	and 1
	ret
.no:	xor a
	ret
.basic:
	or 1
	ret
MZ_CLERIC:	dd 7BFFFFh
MZ_PALADIN:	dd 800FF2h

; MZ_DRAW - the menu: title, tabs, "n de m restantes.", the spells of the page
MZ_DRAW:
	call CM_WINDOW
	ld hl,STR_SPTITLE
	ld de,5
	ld c,5
	ld a,C_LIGHTBLUE
	call SHADED_TEXT
	; tabs 1..5
	ld b,0
.tab:	push bc
	ld a,b
	add a,a
	add a,a
	add a,a
	add a,a
	add a,a
	add a,8
	ld l,a
	ld h,0
	ld (BOX_X),hl
	ld a,16
	ld (BOX_Y),a
	ld a,24
	ld (BOX_W),a
	ld a,20
	ld (BOX_H),a
	call MENU_BOX
	pop bc
	push bc
	ld a,b
	add a,'1'
	ld (MZ_NUM),a
	ld hl,MZ_NUM
	ld a,(BOX_X)
	add a,7
	ld e,a
	ld d,0
	ld c,22
	ld a,(MZ_PG)
	cp b
	ld a,C_WHITE
	jr nz,.tc
	ld a,C_LIGHTRED
.tc:	call SHADED_TEXT
	pop bc
	inc b
	ld a,b
	cp 5
	jr c,.tab
	; n de m restantes
	ld a,(MZ_PG)
	ld e,a
	ld d,0
	ld hl,MZ_NP
	add hl,de
	ld a,(hl)
	ld hl,MZ_PAGE
	add hl,de
	sub (hl)
	call NUM_STR
	ld de,TEXTBUF
	call STR_COPY
	ld hl,STR_LEFT
	call TEXT_APPEND
	ld a,(MZ_PG)
	ld e,a
	ld d,0
	ld hl,MZ_NP
	add hl,de
	ld a,(hl)
	call NUM_STR
	call TEXT_APPEND
	ld hl,STR_LEFT2
	call TEXT_APPEND
	ld hl,TEXTBUF
	ld de,8
	ld c,40
	ld a,C_LIGHTBLUE
	call SHADED_TEXT
	; the list
	ld c,0
.row:	push bc
	ld a,C_WHITE
	call MZ_ROW
	pop bc
	jr z,.rend
	inc c
	ld a,c
	cp 8
	jr c,.row
.rend:
	; Clear, minus, plus, Exit: all changes are visible mouse actions.
	ld hl,MZ_BUTTONS
	ld b,4
.bt:	push bc
	push hl
	ld e,(hl)
	ld d,0
	ld (BOX_X),de
	inc hl
	ld a,(hl)
	ld (BOX_Y),a
	inc hl
	ld a,(hl)
	ld (BOX_W),a
	inc hl
	ld a,(hl)
	ld (BOX_H),a
	call MENU_BOX
	pop hl
	push hl
	call CM_LABEL
	pop hl
	ld de,7
	add hl,de
	pop bc
	djnz .bt
	ret

; MZ_ROW - C = row of the list, A = colour: the spell and its count
;   (memorizePrayMenuPrintString) -> Z: no spell there
MZ_ROW:
	ld (MZ_RCOL),a
	ld a,c
	ld (MZ_RROW),a
	call MZ_ENTRY
	or a
	ret z
	ld (MZ_RSP),a
	add a,a
	ld e,a
	ld d,0
	ld a,(MZ_TYPE)
	or a
	ld hl,UI_BOOKM
	jr z,.nm
	ld hl,UI_BOOKC
.nm:	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld de,TEXTBUF
	call STR_COPY
	; padded to 18, then the count
	ld hl,TEXTBUF
	call STR_LEN
	ld e,b
	ld d,0
	add hl,de
	ld a,b
.pad:	cp 18
	jr nc,.cnt
	ld (hl),' '
	inc hl
	inc a
	jr .pad
.cnt:	push hl
	ld a,(MZ_RSP)
	call MZ_CNTPTR
	ld a,(hl)
	pop hl
	add a,'0'
	ld (hl),a
	inc hl
	ld (hl),0
	ld a,(MZ_RROW)
	ld c,a
	add a,a
	add a,a
	add a,a
	add a,c			; *9
	add a,50
	ld c,a
	ld hl,TEXTBUF
	ld de,8
	ld a,(MZ_RCOL)
	call SHADED_TEXT
	or 1
	ret

; MZ_SETHL - A = the row to light: the old one white again
MZ_SETHL:
	ld hl,MZ_HL
	cp (hl)
	ret z
	push af
	ld c,(hl)
	ld a,C_WHITE
	call MZ_ROW
	pop af
	ld (MZ_HL),a
; MZ_LIGHT - the lit row in light red
MZ_LIGHT:
	ld a,(MZ_HL)
	ld c,a
	ld a,C_LIGHTRED
	jp MZ_ROW

; MZ_HOVER - pointer movement/click selects a row. A stationary pointer
; must not undo keyboard selection on the following frame.
MZ_HOVER:
	ld a,(CLICK)
	or a
	jr nz,.moved
	ld hl,(MOUSE_X)
	ld de,(MZ_MOUSE_X)
	or a
	sbc hl,de
	jr nz,.moved
	ld a,(MOUSE_Y)
	ld hl,MZ_MOUSE_Y
	cp (hl)
	ret z
.moved:
	ld hl,(MOUSE_X)
	ld (MZ_MOUSE_X),hl
	ld a,(MOUSE_Y)
	ld (MZ_MOUSE_Y),a
	ld a,(MOUSE_X+1)
	or a
	ret nz
	ld a,(MOUSE_X)
	cp 8
	ret c
	cp 168
	ret nc
	ld a,(MOUSE_Y)
	sub 50
	ret c
	cp 72
	ret nc
	ld c,0
.d9:	sub 9
	jr c,.r
	inc c
	jr .d9
.r:	ld a,(MZ_HL)
	cp c
	ret z
	push bc
	call MZ_ROWS
	pop bc
	or a
	ret z
	dec a
	cp c
	jr c,MZ_SETHL		; (the last one)
	ld a,c
	jr MZ_SETHL

; MZ_ROWS -> A = the spells on the page
MZ_ROWS:
	ld c,0
.l:	push bc
	call MZ_ENTRY
	pop bc
	or a
	jr z,.e
	inc c
	ld a,c
	cp 8
	jr c,.l
.e:	ld a,c
	ret

; MZ_KEY -> A = the key down: KEYS_READ, RETURN as KEY_USE, - and HOME
MZ_KEY:
	call KEYS_READ
	or a
	ret nz
	ld a,7
	call KEY_ROW
	bit 7,a
	ld a,KEY_USE
	ret z
	ld a,1
	call KEY_ROW
	bit 2,a
	ld a,MZ_K_MINUS
	ret z
	ld a,8
	call KEY_ROW
	bit 1,a
	ld a,MZ_K_HOME
	ret z
	xor a
	ret
MZ_K_MINUS:	equ 40h
MZ_K_HOME:	equ 41h
MZ_MOUSE_X:	dw 0FFFFh
MZ_MOUSE_Y:	db 0FFh

; MZ_PGPTR -> HL = MZ_NP of the page, DE = the page
MZ_PGPTR:
	ld a,(MZ_PG)
	ld e,a
	ld d,0
	ld hl,MZ_NP
	add hl,de
	ret

; MZ_CNTPTR - A = spell (1..) -> HL = its counts in MZ_COUNT
MZ_CNTPTR:
	dec a
	add a,a
	ld e,a
	ld d,0
	ld hl,MZ_COUNT
	add hl,de
	ret

MZ_BUTTONS:
	db 8, 126, 48, 14, 4
	dw STR_SPCLEAR
	db 64, 126, 24, 14, 4
	dw MZ_MINUS_TEXT
	db 96, 126, 24, 14, 4
	dw MZ_PLUS_TEXT
	db 128, 126, 40, 14, 4
	dw STR_CM7
MZ_MINUS_TEXT:	db "-",0
MZ_PLUS_TEXT:	db "+",0

; CHAR_AT_MOUSE - the character box under the mouse -> A (FFh: none)
CHAR_AT_MOUSE:
	ld hl,(MOUSE_X)
	ld de,184
	or a
	sbc hl,de
	jr c,.no
	ld a,l
	ld c,0
	cp 72
	jr c,.col
	inc c
.col:	ld a,(MOUSE_Y)
	sub 2
	jr c,.no
	ld b,0
.row:	sub 52
	jr c,.got
	inc b
	jr .row
.got:	ld a,b
	cp 3
	jr nc,.no
	add a,a
	add a,c
	ret
.no:	ld a,0FFh
	ret

; CLASS_LEVEL - C = class type (1 mage, 2 cleric, 4 paladin), (MZ_CHAR)
;   -> A = the level of the character in it (0: not of that class)
CLASS_LEVEL:
	ld a,(MZ_CHAR)
	call CHAR_PTR
	ld a,(iy+P_CLASS)
	ld b,a
	add a,a
	add a,b
	ld e,a
	ld d,0
	ld hl,CLASS_TYPE
	add hl,de
	ld b,0
.lp:	ld a,(hl)
	cp c
	jr z,.got
	inc hl
	inc b
	ld a,b
	cp 3
	jr c,.lp
	xor a
	ret
.got:	ld a,b
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld de,P_LEVELS
	add hl,de
	ld a,(hl)
	or a
	ret nz
	inc a
	ret

; CLASS_LEVEL_A - A = the class level (from CLASS_LEVEL); a paladin prays
;   from level 9 on (level - 8)
CLASS_LEVEL_A:
	ld c,a
	ld a,(MZ_PAL)
	or a
	ld a,c
	ret z
	sub 8
	ret nc
	ld a,1
	ret

MZ_TYPE:	db 0
MZ_CHAR:	db 0
MZ_PAL:		db 0
MZ_LV:		db 0
MZ_PG:		db 0
MZ_SPELL:	db 0
MZ_HL:		db 0		; the lit row
MZ_RCOL:	db 0
MZ_RROW:	db 0
MZ_RSP:		db 0
MZ_NUM:		db 0, 0
MZ_NP:		ds 5		; slots per page
MZ_PAGE:	ds 5		; spells chosen per page
MZ_COUNT:	ds 64		; per spell: total, ready

; FOOD_TICK - everybody gets a bit hungrier (timerUpdateFoodStatus)
FOOD_TICK:
	xor a
.lp:	push af
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.n
	ld a,(iy+P_HP)
	cp -10
	jr z,.n
	ld a,(iy+P_FOOD)
	or a
	jr z,.n
	ld a,25			; a ring of sustenance
	call RING2
	jr z,.n
	ld a,26
	call RING2
	jr z,.n
	dec (iy+P_FOOD)
	pop af
	push af
	ld c,a
	ld a,(CONTROL_MODE)
	or a
	jr z,.n
	ld a,(UPDATE_CHAR)
	cp c
	call z,INV_HEADER
.n:	pop af
	inc a
	cp 6
	jr c,.lp
	ret


	include "../build/uidata.inc"

UI_END:
	assert UI_END <= 0C000h	; UI overlay too big
