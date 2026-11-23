; ============================================================================
; npc.asm - the dialogues of the NPC sequences (part of the MAGIC overlay):
;   the box under the view, texts of TEXT.DAT with page breaks, the answer
;   buttons, the figures of OUTTAKE.CPS over the view and new party members
;   (EoBCoreEngine::runDialogue, npcJoinDialogue, EoBEngine::drawNpcScene).
;   The script overlay decides what happens (NPC_RUN) and calls these with
;   MCALL.
; ============================================================================

DLG_X:		equ 8		; text field (screen dim 9)
DLG_Y:		equ 125
DLG_LH:		equ 7		; line height
DLG_LINES:	equ 8		; lines of a page
DLG_COLS:	equ 50
DLG_BTN_W:	equ 95
DLG_BTN_H:	equ 9

; ----------------------------------------------------------------------------
; DLG_START - the figures of a scene over the view: BOUNCE = its entry of
;   the scene table of LEVELn.INF (count, then sx, sy, w, h, dx, dy each);
;   NPCn.V9 is loaded first if A <> 0. Then an empty box.
; ----------------------------------------------------------------------------
DLG_START:
	or a
	jr z,.draw
	; the figures go to the shape cache area: save the entry first
	ld hl,BOUNCE
	ld de,DS_ENTRY
	ld bc,25
	ldir
	ld a,(CUR_LEVEL)
	call NUM_STR
	ld de,DS_NAME+3
	ld c,b
	ld b,0
	ldir
	ld hl,DS_EXT
	ld bc,5
	ldir
	ld de,DS_NAME
	call LOAD_V9_KEEP
	ld hl,176		; the rows of the figures stay
	call WCALL
	dw CACHE_RESERVE
	ld hl,DS_ENTRY
	ld de,BOUNCE
	ld bc,25
	ldir
.draw:	call PTR_HIDE
	; the clean view (VIEW_BUF) back on the screen
	ld hl,CMD_DLGVIEW
	ld a,V9_LOG_COPY
	call V9_LMMM
	ld hl,BOUNCE
	ld a,(hl)
	inc hl
	or a
	jr z,.box
	ld b,a
.fig:	push bc
	ld de,DS_CMD
	ldi			; sx
	ldi
	ldi			; sy
	ldi
	ld e,(hl)		; w
	inc hl
	ld d,(hl)		; h
	inc hl
	ld (DS_CMD+8),de
	xor a
	ld (DS_CMD+9),a
	ld (DS_CMD+11),a
	ld a,d
	ld (DS_CMD+10),a
	ld e,(hl)		; dx
	inc hl
	ld d,0
	push hl
	ld hl,SCREEN_X
	add hl,de
	ld (DS_CMD+4),hl
	pop hl
	ld e,(hl)		; dy
	inc hl
	push hl
	ld hl,SCREEN_Y
	add hl,de
	ld (DS_CMD+6),hl
	ld hl,DS_CMD
	ld a,V9_LOG_TCOPY
	call V9_LMMM
	pop hl
	pop bc
	djnz .fig
.box:	jp DLG_BOX

CMD_DLGVIEW:	dw VIEWBUF_X, VIEWBUF_Y, SCREEN_X, SCREEN_Y, 176, 120
DS_CMD:		ds 12
DS_ENTRY:	ds 25
DS_NAME:	db "NPC"
		ds 8
DS_EXT:		db ".V9",0,0

; DLG_END - the play field again
DLG_END:
	ld a,2			; (restoreAfterDialogueSequence)
	call SFX_PLAY
	jp SCREEN_RESTORE

; ----------------------------------------------------------------------------
; DLG_BOX - an empty box (gui_drawDialogueBox): gui_drawBox(0, 121, 320, 79)
; ----------------------------------------------------------------------------
DLG_BOX:
	xor a
	ld (DT_LINE),a
	ld ix,DLG_RECTS
	ld b,8
DLG_RECTLP:
	push bc
	ld e,(ix+0)
	ld d,(ix+1)
	ld c,(ix+2)
	ld b,(ix+3)
	ld l,(ix+4)
	ld a,(ix+5)
	push ix
	call FILL_RECT
	pop ix
	ld de,6
	add ix,de
	pop bc
	djnz DLG_RECTLP
	ret
DLG_RECTS:
	dw 1
	db 122, 159, 77, C_FILL
	dw 160
	db 122, 159, 77, C_FILL
	dw 1
	db 121, 160, 1, C_FRAME2
	dw 161
	db 121, 159, 1, C_FRAME2
	dw 319
	db 121, 1, 78, C_FRAME2
	dw 0
	db 121, 1, 79, C_FRAME1
	dw 0
	db 199, 160, 1, C_FRAME1
	dw 160
	db 199, 160, 1, C_FRAME1

; ----------------------------------------------------------------------------
; DLG_SAY - A = text (TEXT.DAT, 0 = the farewell of Armun) in a new box;
;   C = 1: then a MAS button to go on (printDialogueText with a page break)
; DLG_SAYHL - the same with HL = text
; ----------------------------------------------------------------------------
DLG_SAY:
	push bc
	call DLG_FETCH
	jr DLG_SAY2
DLG_SAYHL:
	xor a
	ld (TF_MORE),a
	push bc
DLG_SAY2:
	push hl
	call DLG_BOX
	pop hl
	call DLG_TEXT
	pop bc
	dec c
	ret nz
	; fall through
; DLG_MORE - the MAS button, a click, an empty box
DLG_MORE:
	ld a,(DV_FIN)
	or a
	jr nz,.fin
	ld de,285
	ld c,189
	ld b,31
	ld hl,STR_MORE
	call DLG_BUTTON
	call DLG_CLICK
	jp DLG_BOX
.fin:	ld de,139		; the finale: in its own box
	ld c,162
	ld b,31
	ld hl,STR_MORE
	call DLG_BUTTON
	call DLG_CLICK
	jp FIN_BOX

; DLG_FETCH - A = text -> HL
DLG_FETCH:
	or a
	jp nz,TXT_FETCH
	ld (TF_MORE),a
	ld hl,DLG_S0_0
	ret

; DLG_TEXT - HL = text: from line (DT_LINE) of the box, a new page (MAS)
;   when the box is full
DLG_TEXT:
.lp:	ld a,(TF_MORE)		; a long text: the next part when near the end
	or a
	jr z,.w
	push hl
	ex de,hl
	ld hl,(TF_END)
	or a
	sbc hl,de
	ld a,h
	or a
	jr nz,.nr
	ld a,l
	cp 64
	jr nc,.nr
	pop hl
	call TXT_REFILL
	jr .w
.nr:	pop hl
.w:	ld a,(DV_COLS)
	call WRAP_LINE
	ret z
	ld a,(DV_LINES)
	ld b,a
	ld a,(DT_LINE)
	cp b
	jr c,.pr
	push hl
	call DLG_MORE
	pop hl
.pr:	push hl
	ld a,(DT_LINE)
	ld b,a
	inc a
	ld (DT_LINE),a
	ld a,b
	add a,a
	add a,a
	add a,a
	sub b			; * 7
	ld hl,DV_Y
	add a,(hl)
	ld c,a
	ld hl,MSG_LINE
	ld de,DLG_X
	ld a,C_WHITE
	ld b,0
	call TEXT_PRINT
	pop hl
	jr .lp
DT_LINE:	db 0
DV_FIN:		db 0		; 1: the text field of the finale
DV_Y:		db DLG_Y
DV_COLS:	db DLG_COLS
DV_LINES:	db DLG_LINES

; ----------------------------------------------------------------------------
; DLG_ASK - A = text, C = button set (DLG_SETS) -> A = the button (0..)
;   (runDialogue); the box is empty again at the end
; DLG_ASKB - only the buttons: HL = list of B labels (u16 pointers)
; ----------------------------------------------------------------------------
DLG_ASK:
	push bc
	call DLG_FETCH
	push hl
	call DLG_BOX
	pop hl
	call DLG_TEXT
	pop bc
	ld a,c
	add a,a
	ld e,a
	ld d,0
	ld hl,DLG_SETS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	ld b,(hl)		; count, then the labels one after another
	inc hl
	ld de,DA_LIST
	push bc
.ls:	ld a,l
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
.z:	ld a,(hl)
	inc hl
	or a
	jr nz,.z
	djnz .ls
	pop bc
	ld hl,DA_LIST
DLG_ASKB:
	ld a,b
	ld (DA_N),a
	ld (DA_PTR),hl
	; room for the rows of buttons under the text?
	dec a
	ld c,0
.rows:	sub 3
	jr c,.r
	inc c
	jr .rows
.r:	ld b,0			; C = rows after the first: too many lines?
	ld hl,DA_MAXL
	add hl,bc
	ld a,(hl)
	ld hl,DT_LINE
	cp (hl)
	call c,DLG_MORE
	; the buttons: y = DLG_Y + 4 + lines * 7
	ld a,(DT_LINE)
	ld b,a
	add a,a
	add a,a
	add a,a
	sub b
	add a,DLG_Y+4
	ld (DA_Y),a
	ld a,(DA_N)
	cp 3
	ld hl,DLG_POS2
	jr c,.p
	ld hl,DLG_POS3
.p:	ld (DA_POS),hl
	ld b,a
	ld c,0
.btn:	push bc
	ld hl,(DA_PTR)
	ld a,c
	add a,a
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	push hl
	call DA_RECT		; -> DE = x, A = y
	pop hl
	ld c,a
	ld b,DLG_BTN_W
	call DLG_BUTTON
	pop bc
	inc c
	djnz .btn
	; wait for a click on one of them
.wait:	call DLG_CLICK
	ld a,(DA_N)
	ld b,a
	ld c,0
.hit:	push bc
	call DA_RECT
	ld b,a			; y
	ld hl,(MOUSE_X)
	or a
	sbc hl,de
	jr c,.no
	ld de,DLG_BTN_W
	sbc hl,de
	jr nc,.no
	ld a,(MOUSE_Y)
	sub b
	jr c,.no
	cp DLG_BTN_H
	jr nc,.no
	pop bc
	push bc
	call DLG_BOX
	pop bc
	ld a,c
	ret
.no:	pop bc
	inc c
	djnz .hit
	jr .wait

; DA_RECT - C = button -> DE = x, A = y (preserves BC)
DA_RECT:
	ld hl,(DA_POS)
	ld a,c
	add a,a
	add a,c
	ld e,a
	ld d,0
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,(DA_Y)
	add a,(hl)
	ret
DLG_POS2:	dw 59
	db 0
	dw 166
	db 0
DLG_POS3:	dw 4
	db 0
	dw 112
	db 0
	dw 220
	db 0
	dw 4
	db 12
	dw 112
	db 12
	dw 220
	db 12
	dw 4
	db 24
	dw 112
	db 24
	dw 220
	db 24
DA_MAXL:	db 8, 7, 5	; most lines of text above 1, 2, 3 rows of buttons
DA_N:		db 0
DA_Y:		db 0
DA_POS:		dw 0
DA_PTR:		dw 0
DA_LIST:	ds 18

; DLG_BUTTON - DE = x, C = y, B = width, HL = label: a framed button with
;   the label in the middle
DLG_BUTTON:
	ld (DB_X),de
	ld (DB_TXT),hl
	ld (BOX_X),de
	ld a,c
	ld (DB_Y),a
	ld (BOX_Y),a
	ld a,b
	ld (DB_W),a
	ld (BOX_W),a
	ld a,DLG_BTN_H
	ld (BOX_H),a
	ld a,C_FRAME1
	ld (BOX_C1),a
	ld a,C_FRAME2
	ld (BOX_C2),a
	ld a,C_FILL
	ld (BOX_FILL),a
	call GUI_BOX
	ld hl,(DB_TXT)
	call STR_LEN		; B = length
	ld a,b
	add a,a
	add a,b			; 3 per character: half the text
	ld c,a
	add a,a
	add a,2
	ld hl,DB_W
	cp (hl)
	jr c,.fit
	; too long: 5 pixels per character
	ld a,1
	ld (TXT_SQZ),a
	ld a,b
	add a,a
	add a,a
	add a,b
	srl a
	ld c,a
.fit:	ld b,c
	ld a,(DB_W)
	srl a
	sub b
	jr nc,.x
	xor a
.x:	ld e,a
	ld d,0
	ld hl,(DB_X)
	add hl,de
	ex de,hl
	ld a,(DB_Y)
	add a,2
	ld c,a
	ld hl,(DB_TXT)
	ld a,C_WHITE
	ld b,0
	call TEXT_PRINT
	xor a
	ld (TXT_SQZ),a
	ret
DB_X:		dw 0
DB_Y:		db 0
DB_W:		db 0
DB_TXT:		dw 0

; DLG_CLICK - waits for a click (the mouse moves meanwhile)
DLG_CLICK:
	call V9_WAIT_VBLANK
	call MOUSE_UPDATE
	call PTR_SHOW
	ld a,(CLICK)
	or a
	jr z,DLG_CLICK
	xor a
	ld (CLICK),a
	ret

; ----------------------------------------------------------------------------
; DLG_JOIN - A = NPC (preset), B = question, C = text when it joins (0: "<name>
;   se une al grupo."), D = text when it does not (0: none)
;   -> A = 1 if the party said yes (npcJoinDialogue)
; ----------------------------------------------------------------------------
DLG_JOIN:
	ld (DJ_NPC),a
	ld a,c
	ld (DJ_YES),a
	ld a,d
	ld (DJ_NO),a
	ld a,b
	ld c,11			; si / no
	call DLG_ASK
	or a
	jr nz,.no
	ld a,(DJ_YES)
	or a
	jr z,.name
	ld c,1
	call DLG_SAY
	jr .add
.name:	ld a,(DJ_NPC)
	call NPC_PRESET
	inc hl			; its name
	ld de,TEXTBUF
	ld bc,10
	ldir
	xor a
	ld (de),a
	ld hl,STR_SP
	call TEXT_APPEND
	ld hl,STR_NPCJOIN
	call TEXT_APPEND
	ld hl,TEXTBUF
	ld c,1
	call DLG_SAYHL
.add:	ld a,(DJ_NPC)
	call NPC_ADD
	ld a,1
	ret
.no:	ld a,(DJ_NO)
	or a
	ld c,1
	call nz,DLG_SAY
	xor a
	ret
DJ_NPC:		db 0
DJ_YES:		db 0
DJ_NO:		db 0

; NPC_PRESET - A = NPC -> HL = its record
NPC_PRESET:
	rrca
	ld h,a
	and 80h
	ld l,a
	xor h
	ld h,a
	ld de,NPC_PRESETS
	add hl,de
	ret

; NPC_ADD - A = NPC: into the first free place of the party
;   (prepareForNewPartyMember + initNpc); the bones of a raised NPC go away
NPC_ADD:
	ld (DJ_NPC),a
	inc a			; DOS frees this NPC's bones before allocating its gear
	ld c,a
	ld b,BONES_TYPE
	call DEL_PARTY_ITEMS
	ld c,0
.free:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.ok
	inc c
	ld a,c
	cp 6
	jr c,.free
	ld hl,STR_NPCMAX
	ld c,0
	call DLG_SAYHL
	ld hl,NPC_PARTY_NAMES
	ld b,7
	call DLG_ASKB
	cp 6
	ret z			; same six members when the player cancels
	push af
	call UCALL
	dw UI_REMOVE_MEMBER
	pop af
	ld c,a
	call CHAR_PTR
.ok:	push bc
	call NPC_CLEAR_MAGIC
	ld a,(DJ_NPC)
	call NPC_PRESET
	push iy
	pop de
	ld bc,P_SIZE
	ldir
	call NPC_EQUIP
	pop bc
	ld a,c
	push bc
	call RECALC_AC_U
	pop bc
	ld a,c
	jp PANEL_DRAW
NPC_PARTY_NAMES:
	dw PARTY+P_NAME, PARTY+P_SIZE+P_NAME, PARTY+2*P_SIZE+P_NAME
	dw PARTY+3*P_SIZE+P_NAME, PARTY+4*P_SIZE+P_NAME, PARTY+5*P_SIZE+P_NAME
	dw .cancel
.cancel:	db "CANCEL",0	; the button in both PC editions
BONES_TYPE:	equ 33

; DEL_PARTY_ITEMS - B = type, C = value (FFh: any), NZ if the party carried
; a match in inventory. DOS FB8Ah only considers the cursor after such a
; match, comparing its type literally and ignoring its value.
DEL_PARTY_ITEMS:
	ld (DP_TYPE),bc
	xor a
	ld (DP_ANY),a
	ld c,0
.ch:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.nc
	push iy
	pop hl
	ld de,P_INV
	add hl,de
	ld b,27
.sl:	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or e
	jr z,.ns
	ex de,hl
	call DP_MATCH
	ex de,hl
	jr nz,.ns
	ld (hl),0
	dec hl
	ld (hl),0
	inc hl
.ns:	inc hl
	djnz .sl
.nc:	inc c
	ld a,c
	cp 6
	jr c,.ch
	ld a,(DP_ANY)
	or a
	ret z
	ld hl,(HAND)
	call ITEM_IX
	ld a,(DP_TYPE+1)
	cp (ix+I_TYPE)
	jr nz,.end
	call DP_REMOVE
	ld hl,0
	ld (HAND),hl
.end:	ld a,(DP_ANY)
	or a
	ret
; DP_MATCH - HL = item: Z (and gone from the map) if it is one of them.
;   Preserves BC, DE, HL.
DP_MATCH:
	push bc
	call ITEM_IX
	ld bc,(DP_TYPE)
	ld a,b
	inc a
	jr z,.v
	ld a,(ix+I_TYPE)
	cp b
	jr nz,.n
.v:	ld a,c
	inc a
	jr z,.y
	ld a,(ix+I_VALUE)
	cp c
	jr nz,.n
.y:	call DP_REMOVE
	ld a,1
	ld (DP_ANY),a
	xor a
.n:	pop bc
	ret
DP_REMOVE:
	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
	ret
DP_TYPE:	dw 0		; value, type
DP_ANY:		db 0

; ----------------------------------------------------------------------------
; RAISE_DLG - the dwarven cleric raises somebody (resurrectionSelectDialogue):
;   dead members of the party, and NPCs whose bones the party carries
;   -> A = 0 nobody (no candidates), 1 done, 80h + NPC: that one (the script
;   shows it and asks it to join)
; RAISE_COUNT - -> A = the candidates (countResurrectionCandidates)
; ----------------------------------------------------------------------------
RAISE_COUNT:
	xor a
	ld (RR_N),a
	ld c,0
.ch:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.nc
	ld a,(iy+P_HP)
	cp -10
	jr nz,.nc
	push iy
	pop hl
	inc hl			; the name
	ld a,c
	call RR_ADD
.nc:	inc c
	ld a,c
	cp 6
	jr c,.ch
	; the bones (item types with extra properties 8)
	ld c,0
.cb:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.nb
	push iy
	pop hl
	ld de,P_INV
	add hl,de
	ld b,27
.sl:	push bc
	push hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or e
	jr z,.ns
	ex de,hl
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld a,(hl)
	cp 8
	jr nz,.ns
	ld a,(ix+I_VALUE)	; NPC + 1
	dec a
	cp 9
	jr nc,.ns
	push af
	call NPC_PRESET
	inc hl
	pop af
	or 80h			; an NPC
	call RR_ADD
.ns:	pop hl
	pop bc
	inc hl
	inc hl
	djnz .sl
.nb:	inc c
	ld a,c
	cp 6
	jr c,.cb
	ld a,(RR_N)
	ret
; RR_ADD - HL = name, A = id (80h + NPC for bones)
RR_ADD:
	push bc
	ld c,a
	ld a,(RR_N)
	cp 9
	jr nc,.full
	ld e,a
	inc a
	ld (RR_N),a
	ld d,0
	push hl
	ld hl,RR_ID
	add hl,de
	ld (hl),c
	pop hl
	ex de,hl
	add hl,hl
	ld bc,DA_LIST
	add hl,bc
	ld (hl),e
	inc hl
	ld (hl),d
.full:	pop bc
	ret
RR_N:		db 0
RR_ID:		ds 9

RAISE_DLG:
	call RAISE_COUNT
	or a
	ret z
	call DLG_BOX
	xor a
	ld (TF_MORE),a
	ld hl,DLG_S0_1		; "Quien debe ser resucitado?"
	call DLG_TEXT
	ld a,(RR_N)
	ld b,a
	ld hl,DA_LIST
	call DLG_ASKB
	ld e,a
	ld d,0
	ld hl,RR_ID
	add hl,de
	ld a,(hl)
	bit 7,a
	jr nz,.npc
	; a member of the party: back with all hit points
	call CHAR_PTR
	ld a,(iy+P_HPMAX)
	ld (iy+P_HP),a
	ld a,(iy+P_FLAGS)
	and 0F1h		; no poison, paralysis, ...
	ld (iy+P_FLAGS),a
	ld a,(hl)
	call PANEL_DRAW
	ld a,1
	ret
.npc:	and 7Fh			; an NPC: its bones go, the script asks
	push af
	inc a
	ld c,a
	ld b,BONES_TYPE
	call DEL_PARTY_ITEMS
	pop af
	or 80h
	ret

; HEAL_PARTY - the cleric heals (healParty): 3 to 5 wounded members get
;   1d8 + 9 hit points, and lose poison and paralysis
HEAL_PARTY:
	ld bc,0103h
	ld a,2
	call ROLL_DICE
	ld a,l
	ld (DS_ENTRY),a
	ld c,0
.lp:	ld a,c
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.n
	ld a,(iy+P_FLAGS)
	and 0F9h		; no paralysis (4), no poison (2)
	ld (iy+P_FLAGS),a
	ld a,(iy+P_HP)
	bit 7,a
	jr nz,.w
	cp (iy+P_HPMAX)
	jr nc,.d
.w:	push bc
	ld bc,0108h
	ld a,9
	call ROLL_DICE
	pop bc
	ld a,(iy+P_HP)
	add a,l
	jp m,.max
	cp (iy+P_HPMAX)
	jr c,.s
.max:	ld a,(iy+P_HPMAX)
.s:	ld (iy+P_HP),a
	ld hl,DS_ENTRY
	dec (hl)
.d:	ld a,c
	push bc
	call PANEL_DRAW
	pop bc
	ld a,(DS_ENTRY)
	or a
	ret z
.n:	inc c
	ld a,c
	cp 6
	jr c,.lp
	ret

; ----------------------------------------------------------------------------
; XDEATH - HL = first VRAM row of XDEATH.V9: the death of Xanathar
;   (EoBEngine::seq_xdeath): 6 frames, 4 shapes over the last one, then
;   a figure falls from above
; ----------------------------------------------------------------------------
XDEATH:
	ld (XD_TOP),hl
	ld de,F_XDEATH
	call LOAD_V9_KEEP
	ld hl,272
	call WCALL
	dw CACHE_RESERVE
	call PTR_HIDE
	ld hl,(XD_TOP)
	call XD_VIEW_INIT
	ld hl,XD_STEPS
	ld b,10
.st:	push bc
	call XD_SOUND
	call XD_BLIT
	push hl
	call XD_VIEW_SHOW
	ld b,12			; plus the presentation blank (4 ticks total)
	call WAIT_FRAMES
	pop hl
	pop bc
	djnz .st
	; the fall: 19 steps of 5 rows, from 90 rows above the view
	ld c,0
.fall:	push bc
	ld a,119
	call SFX_PLAY
	call XD_VIEW_CLEAR	; compose the last frame of each sequence again
	ld hl,XD_STEPS+5*6
	call XD_BLIT
	ld hl,XD_STEPS+9*6
	call XD_BLIT
	pop bc
	push bc
	ld a,c
	add a,a
	add a,a
	add a,c			; * 5
	sub 3			; visible rows: 95 - (98 - 5*c)
	jr c,.show		; the first position is entirely clipped
	ld (XD_CMD+10),a
	neg
	add a,95
	ld e,a			; source rows hidden above view row 8
	ld d,0
	ld hl,(XD_VIEW_SHOW_CMD+2)
	add hl,de
	ld (XD_CMD+2),hl	; sy
	ld hl,0
	ld (XD_CMD),hl		; sx
	ld hl,(XD_VIEW_SHOW_CMD+2)
	ld (XD_CMD+6),hl	; dy
	ld hl,XD_VIEW_X
	ld (XD_CMD+4),hl
	ld hl,128
	ld (XD_CMD+8),hl
	ld hl,XD_CMD
	ld a,V9_LOG_TCOPY
	call V9_LMMM
.show:	call XD_VIEW_SHOW
	ld b,6			; plus the presentation blank (2 ticks total)
	call WAIT_FRAMES
	pop bc
	inc c
	ld a,c
	cp 19
	jr c,.fall
	ld a,5
	call SFX_PLAY
	ld b,200		; 60 ticks
	jp WAIT_FRAMES

; DOS EOB.EXE 3F333h–3F3B4h: extra cues precede the effect for each
; of the ten frames. The four overlays each add a second effect.
XD_SOUND:
	ld a,b
	cp 8			; frame 2
	ld a,72
	call z,SFX_PLAY
	ld a,b
	cp 6			; frame 4
	jr z,.extra
	cp 4			; frame 6
	jr nz,.main
.extra:	ld a,54
	call SFX_PLAY
.main:	ld a,34
	call SFX_PLAY
	ld a,b
	cp 5
	ret nc
	ld a,42
	jp SFX_PLAY

; XD_BLIT - HL = a step (sx, row, w, h, operation): compose at view (32, 10)
;   -> HL = the next step
XD_BLIT:
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (XD_CMD),de
	ld e,(hl)
	inc hl
	push hl
	ld d,0
	ld hl,(XD_TOP)
	add hl,de
	ld (XD_CMD+2),hl
	ld hl,XD_VIEW_X+8
	ld (XD_CMD+4),hl
	ld hl,(XD_VIEW_SHOW_CMD+2)
	inc hl
	inc hl
	ld (XD_CMD+6),hl
	pop hl
	ld e,(hl)
	inc hl
	ld d,0
	ld (XD_CMD+8),de
	ld e,(hl)
	inc hl
	ld (XD_CMD+10),de
	ld a,(hl)
	inc hl
	push hl
	ld hl,XD_CMD
	call V9_LMMM
	pop hl
	ret

; WAIT_FRAMES - B = frames
WAIT_FRAMES:
	push bc
	call V9_WAIT_VBLANK
	pop bc
	djnz WAIT_FRAMES
	ret

XD_STEPS:	; sx, row, w, h, operation
	dw 0
	db 0, 104, 88, V9_LOG_COPY
	dw 104
	db 0, 104, 88, V9_LOG_COPY
	dw 208
	db 0, 104, 88, V9_LOG_COPY
	dw 0
	db 88, 104, 88, V9_LOG_COPY
	dw 104
	db 88, 104, 88, V9_LOG_COPY
	dw 208
	db 88, 104, 88, V9_LOG_COPY
	dw 312
	db 0, 112, 88, V9_LOG_TCOPY
	dw 312
	db 88, 112, 88, V9_LOG_TCOPY
	dw 128
	db 176, 112, 88, V9_LOG_TCOPY
	dw 240
	db 176, 112, 88, V9_LOG_TCOPY
XD_TOP:		dw 0
XD_CMD:		ds 12
F_XDEATH:	db "XDEATH.V9",0

; ----------------------------------------------------------------------------
; FINALE - A = 1 if the twelve special quests were done: the last text, the
;   winners and their password (EoBEngine::seq_playFinale)
; ----------------------------------------------------------------------------
FINALE:
	ld (FN_BONUS),a
	ld a,20
	call SFX_PLAY
	call FIN_MODE
	ld a,51
	call TXT_FETCH
	call DLG_TEXT
	call DLG_MORE
	ld a,(FN_BONUS)
	or a
	jr z,.end
	ld hl,FIN_B0
	ld de,BOUNCE
	call FN_CPY
	ld c,0
.nm:	ld a,c
	call CHAR_PTR
	ld hl,FIN_B1
	call FN_CPY
	bit 0,(iy+P_FLAGS)
	jr z,.nn
	push iy
	pop hl
	inc hl
	call FN_CPY
.nn:	inc c
	ld a,c
	cp 4			; the DOS epilogue lists the four original slots
	jr c,.nm
	push de
	call FN_PASSWORD
	pop de
	ld hl,FIN_B2
	call FN_CPY
	ld hl,FN_HEX
	call FN_CPY
	ld hl,FIN_B3
	call FN_CPY
	xor a
	ld (TF_MORE),a
	ld hl,BOUNCE
	call DLG_TEXT
	call DLG_MORE
.end:	; fall through
; DLG_MODE - the text field of the dialogues again
DLG_MODE:
	xor a
	ld (DV_FIN),a
	ld a,DLG_Y
	ld (DV_Y),a
	ld a,DLG_COLS
	ld (DV_COLS),a
	ld a,DLG_LINES
	ld (DV_LINES),a
	ret
; FIN_MODE - the text field of the big box over the view, the box drawn
FIN_MODE:
	ld a,1
	ld (DV_FIN),a
	ld a,4
	ld (DV_Y),a
	ld a,26
	ld (DV_COLS),a
	ld a,21
	ld (DV_LINES),a
	call PTR_HIDE
	jp FIN_BOX
FN_BONUS:	db 0

; FN_CPY - HL = text -> DE (ends with 0, DE on it)
FN_CPY:
	ld a,(hl)
	ld (de),a
	or a
	ret z
	inc hl
	inc de
	jr FN_CPY

; FN_PASSWORD - DOS squares the signed name bytes of all active members.
; Its 16-bit sprintf("%04x") prints the low word, including leading zeroes.
FN_PASSWORD:
	ld hl,0
	ld (FN_SUM),hl
	ld c,0
.ch:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.nc
	push iy
	pop ix
	inc ix
	ld b,10
.ltr:	ld a,(ix+0)
	or a
	jr z,.nc
	jp p,.positive
	neg
.positive:
	push bc
	ld e,a
	ld d,0
	ld b,a
	ld hl,0
.sq:	add hl,de
	djnz .sq
	ld de,(FN_SUM)
	add hl,de
	ld (FN_SUM),hl
	pop bc
	inc ix
	djnz .ltr
.nc:	inc c
	ld a,c
	cp 6
	jr c,.ch
	ld hl,FN_SUM+1
	ld de,FN_HEX
	ld b,2
.by:	ld a,(hl)
	push af
	rrca
	rrca
	rrca
	rrca
	call .dig
	pop af
	call .dig
	dec hl
	djnz .by
	xor a
	ld (de),a
	ret
.dig:	and 0Fh
	add a,'0'
	cp '9'+1
	jr c,.st
	add a,'a'-'9'-1
.st:	ld (de),a
	inc de
	ret
FN_SUM:		ds 2
FN_HEX:		ds 5

; FIN_BOX - the box of the finale: gui_drawBox(0, 0, 176, 175)
FIN_BOX:
	xor a
	ld (DT_LINE),a
	ld ix,FIN_RECTS
	ld b,5
	jp DLG_RECTLP
FIN_RECTS:
	dw 1
	db 1, 174, 173, C_FILL
	dw 1
	db 0, 175, 1, C_FRAME2
	dw 175
	db 0, 1, 174, C_FRAME2
	dw 0
	db 0, 1, 175, C_FRAME1
	dw 0
	db 174, 176, 1, C_FRAME1

; ----------------------------------------------------------------------------
; SEQ_PORTAL - HL = first VRAM row of PORTALn.V9: the party goes through a
;   portal (EoBCoreEngine::seq_portal): the stone frame lights up
; ----------------------------------------------------------------------------
SEQ_PORTAL:
	ld (PT_TOP),hl
	ld a,(CUR_LEVEL)
	call NUM_STR
	ld de,PT_NAME+6
	ld c,b
	ld b,0
	ldir
	ld hl,DS_EXT
	ld bc,5
	ldir
	ld de,PT_NAME
	call LOAD_V9_KEEP
	ld hl,172
	call WCALL
	dw CACHE_RESERVE
	call PTR_HIDE
	ld bc,0
	call PT_DRAW
	ld a,33
	call SFX_PLAY
	ld a,19
	call SFX_PLAY
	ld b,100		; 30 ticks
	call WAIT_FRAMES
	ld hl,PORTAL_SEQ
	xor a
	ld (PT_PREV),a
.lp:	ld a,(hl)
	cp 0FFh
	jr z,.end
	ld b,a
	inc hl
	ld c,(hl)
	inc hl
	push hl
	push bc
	call PT_SND
	pop bc
	call PT_DRAW
	ld b,7			; 2 ticks
	call WAIT_FRAMES
	pop hl
	jr .lp
.end:	ld a,1
	ld (SCENE_DIRTY),a
	ret

; PT_SND - B = strips, C = middle: the sounds of the sequence
PT_SND:
	ld a,b
	dec a
	jr nz,.m
	ld a,(PT_PREV)		; the strips light up from 0 to 1
	or a
	jr nz,.m
	ld a,24
	call SFX_PLAY
	ld a,86
	call SFX_PLAY
.m:	ld a,b
	ld (PT_PREV),a
	ld a,c
	cp 2			; frame 1
	ld a,31
	jr z,.s
	ld a,c
	cp 4			; frame 3
	ret nz
	ld a,90
.s:	jp SFX_PLAY
PT_PREV:	db 0

; PT_DRAW - B = strips (0..4), C = middle (0 the stone, n: frame n - 1)
PT_DRAW:
	push bc
	; the top strip at (28, 9)
	ld a,b
	cp 4
	jr z,.t4
	ld l,a			; * 120
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	or a
	sbc hl,de
	ld de,154
	ld bc,28*256+9
	ld a,120
	call PT_BLIT18
	jr .sides
.t4:	ld hl,432		; in two halves
	ld de,77
	ld bc,28*256+9
	ld a,60
	call PT_BLIT18
	ld hl,432
	ld de,95
	ld bc,88*256+9
	ld a,60
	call PT_BLIT18
.sides:	pop bc
	push bc
	ld a,b			; the side strips at (34, 28) and (120, 28)
	add a,a
	add a,a
	add a,a
	ld c,a
	add a,a
	add a,c			; * 24
	ld e,a
	ld d,0
	push de
	ld hl,192
	add hl,de
	ld (PT_CMD),hl
	ld bc,34*256+28
	call PT_SIDE
	pop de
	ld hl,312
	add hl,de
	ld (PT_CMD),hl
	ld bc,120*256+28
	call PT_SIDE
	; the middle at (56, 27)
	pop bc
	ld a,c
	or a
	jr nz,.frame
	ld hl,128
	ld de,77
	ld a,V9_LOG_TCOPY
	jr .mid
.frame:	dec a
	ld de,0
	cp 8
	jr c,.f
	sub 8
	ld de,77
.f:	ld l,a			; * 64
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	ld a,V9_LOG_COPY
.mid:	ld (PT_CMD),hl
	push af
	ld hl,(PT_TOP)
	add hl,de
	ld (PT_CMD+2),hl
	ld hl,64
	ld (PT_CMD+8),hl
	ld hl,77
	ld (PT_CMD+10),hl
	ld bc,56*256+27
	call PT_DEST
	pop af
	ld hl,PT_CMD
	jp V9_LMMM

; PT_BLIT18 - HL = sx, DE = row, A = width, B = x, C = y: 18 rows
PT_BLIT18:
	ld (PT_CMD),hl
	ld l,a
	ld h,0
	ld (PT_CMD+8),hl
	ld hl,18
	ld (PT_CMD+10),hl
	jr PT_ROW
; PT_SIDE - (PT_CMD) = sx, B = x, C = y: a 24 x 75 strip from row 77
PT_SIDE:
	ld hl,24
	ld (PT_CMD+8),hl
	ld hl,75
	ld (PT_CMD+10),hl
	ld de,77
PT_ROW:	ld hl,(PT_TOP)
	add hl,de
	ld (PT_CMD+2),hl
	call PT_DEST
	ld hl,PT_CMD
	ld a,V9_LOG_TCOPY
	jp V9_LMMM
; PT_DEST - B = x, C = y of the view
PT_DEST:
	ld l,b
	ld h,0
	ld de,SCREEN_X
	add hl,de
	ld (PT_CMD+4),hl
	ld l,c
	ld h,0
	ld de,SCREEN_Y
	add hl,de
	ld (PT_CMD+6),hl
	ret
PT_TOP:		dw 0
PT_CMD:		ds 12
PT_NAME:	db "PORTAL"
		ds 8
