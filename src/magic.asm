; ============================================================================
; magic.asm - Spells: the spellbook below the view, casting, spell effects
;             and their timers (magic_eob.cpp, gui_drawSpellbook,
;             clickedSpellbookTab / List, castSpell, startSpell)
; Assembler: Sjasm 0.42c
;
; An overlay: assembled to build/MAGIC.OVL, it lives in the magic segment
; at 8000h with the spell lists of the party (CH_SPELLS) and runs with that
; segment in page 2 (MCALL). World data: WCALL, or a copy in BOUNCE
; (W_FETCH).
;
; Spells are numbered as the original (EOB1): 1-25 mage, 26-49 cleric
; (cleric list entry n = spell 25 + n). CH_SPELLS keeps per character
; 5 levels x 10 entries for each kind: > 0 ready, < 0 cast (back after a
; rest), 0 empty.
; ============================================================================

	output "../build/MAGIC.OVL"
	org MAGIC_BASE

BOOK_X:		equ 64		; the book covers (64, 121)-(175, 176)
BOOK_Y:		equ 121
BOOK_W:		equ 112
BOOK_H:		equ 56
CLERIC_OFS:	equ 25

; ----------------------------------------------------------------------------
; BOOK_SHOW - A = character, C = 0 spellbook (mage) / 1 holy symbol
;   (useMagicBookOrSymbol)
; ----------------------------------------------------------------------------
BOOK_SHOW:
	ld (BOOK_CHAR),a
	ld a,c
	ld (BOOK_TYPE),a
	ld a,(BOOK_ON)
	or a
	jr nz,.drawn
	; what is below the book waits below the shape cache (PANELBUF keeps
	; the party panel while the inventory is open: both can be at once)
	call PTR_KEEP_ARROW
	ld hl,CMD_BOOKSAVE
	call BOOK_COPY3
	ld a,1
	ld (BOOK_ON),a
.drawn:	; the level and entry the character used last
	call BOOK_LIST		; HL = list of the level
	ld a,(BOOK_SEL)
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	dec a
	jp p,BOOK_DRAW
	call BOOK_FIRST
	; fall through

; BOOK_DRAW - tabs, the spells of the level, ABORTAR (gui_drawSpellbook)
BOOK_DRAW:
	call AMCALL
	dw BOOK_STAGE_BEGIN
	call BOOK_PAINT
	call AMCALL
	dw BOOK_STAGE_SHOW
	ret
BOOK_PAINT:
	call PTR_KEEP_ARROW
	ld de,BOOK_X
	ld c,BOOK_Y
	ld b,BOOK_W
	ld l,BOOK_H
	ld a,C_BLACK
	call FILL_RECT
	call TEXT_FONT6
	; the five tabs (the open one in the normal colours)
	ld b,0
.tab:	push bc
	ld a,b
	ld e,a
	add a,a
	add a,a
	add a,a
	add a,a
	add a,e
	add a,e
	add a,e
	add a,e
	add a,e			; *21
	add a,71
	ld l,a
	ld h,0
	ld (BOX_X),hl
	ld a,122
	ld (BOX_Y),a
	ld a,21
	ld (BOX_W),a
	ld a,9
	ld (BOX_H),a
	ld a,(BOOK_LEVEL)
	cp b
	ld a,C_INACT1
	ld c,C_INACT2
	ld d,C_INACTFILL
	jr nz,.tc
	ld a,C_FRAME1
	ld c,C_FRAME2
	ld d,C_FILL
.tc:	ld (BOX_C1),a
	ld a,c
	ld (BOX_C2),a
	ld a,d
	ld (BOX_FILL),a
	call GUI_BOX
	pop bc
	push bc
	ld a,b
	add a,a
	ld e,a
	ld d,0
	ld hl,BOOK_TABS
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld de,(BOX_X)
	inc de
	inc de
	ld c,123
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	pop bc
	inc b
	ld a,b
	cp 5
	jr c,.tab
	; the list box
	ld hl,71
	ld (BOX_X),hl
	ld a,131
	ld (BOX_Y),a
	ld a,105
	ld (BOX_W),a
	ld a,44
	ld (BOX_H),a
	ld a,C_FRAME1
	ld (BOX_C1),a
	ld a,C_FRAME2
	ld (BOX_C2),a
	ld a,C_FILL
	ld (BOX_FILL),a
	call GUI_BOX
	; six spells and ABORTAR
	ld b,0
.ent:	push bc
	call BOOK_LIST
	ld e,b
	ld d,0
	add hl,de
	ld a,(hl)
	or a
	jp m,.next		; cast (or empty: 0 prints nothing)
	jr z,.next
	call BOOK_NAME		; HL = its name
	ld a,b
	add a,a
	ld e,a
	add a,a
	add a,e			; *6
	add a,132
	ld c,a
	ld de,73
	ld a,(BOOK_SEL)
	cp b
	ld a,C_WHITE
	ld b,0
	jr nz,.pr
	ld b,C_DARKBLUE		; the selected one on a dark field
.pr:	call TEXT_PRINT_BOOK
.next:	pop bc
	inc b
	ld a,b
	cp 6
	jr c,.ent
	ld hl,STR_ABORT
	ld de,73
	ld c,168
	ld a,(BOOK_SEL)
	cp 6
	ld a,C_WHITE
	ld b,0
	jr nz,.ab
	ld b,C_DARKBLUE
.ab:	call TEXT_PRINT
	; just used: the grid over it
	call BOOK_CHARPTR
	bit 2,(iy+P_DISABLED)
	ret z
	ld hl,GRID_POS
	ld b,12
.grid:	push bc
	push hl
	ld e,(hl)
	ld d,0
	inc hl
	ld c,(hl)
	ld hl,SHP_WEAPONGRID
	ld a,V9_LOG_TCOPY
	call BLIT_SCREEN
	pop hl
	inc hl
	inc hl
	pop bc
	djnz .grid
	ret

GRID_POS:	db 44h,82h, 62h,82h, 80h,82h, 90h,82h
		db 44h,92h, 62h,92h, 80h,92h, 90h,92h
		db 44h,98h, 62h,98h, 80h,98h, 90h,98h
; the 112 x 56 below the book go to VRAM rows 1000-1019 beside the pointer
; background (x 16-351) in three strips of 20, 20 and 16 rows (row 1023 is
; the hardware cursors')
BOOKBUF_X:	equ PTR_SAVE_X+16
BOOKBUF_Y:	equ PTR_SAVE_Y
CMD_BOOKSAVE:	dw SCREEN_X+BOOK_X, SCREEN_Y+BOOK_Y, BOOKBUF_X, BOOKBUF_Y, BOOK_W, 20
		dw SCREEN_X+BOOK_X, SCREEN_Y+BOOK_Y+20, BOOKBUF_X+BOOK_W, BOOKBUF_Y, BOOK_W, 20
		dw SCREEN_X+BOOK_X, SCREEN_Y+BOOK_Y+40, BOOKBUF_X+2*BOOK_W, BOOKBUF_Y, BOOK_W, BOOK_H-40
CMD_BOOKBACK:	dw BOOKBUF_X, BOOKBUF_Y, SCREEN_X+BOOK_X, SCREEN_Y+BOOK_Y, BOOK_W, 20
		dw BOOKBUF_X+BOOK_W, BOOKBUF_Y, SCREEN_X+BOOK_X, SCREEN_Y+BOOK_Y+20, BOOK_W, 20
		dw BOOKBUF_X+2*BOOK_W, BOOKBUF_Y, SCREEN_X+BOOK_X, SCREEN_Y+BOOK_Y+40, BOOK_W, BOOK_H-40
	assert BOOK_H > 40 && BOOK_H <= 60 && BOOKBUF_X+3*BOOK_W <= 512

; BOOK_COPY3 - HL = three LMMM blocks (CMD_BOOKSAVE / CMD_BOOKBACK)
BOOK_COPY3:
	ld b,3
.lp:	push bc
	ld a,V9_LOG_COPY
	call V9_LMMM		; (HL = the next block after it)
	pop bc
	djnz .lp
	ret

; BOOK_CLOSE - the book goes away (clickedSpellbookAbort)
BOOK_CLOSE:
	ld a,(BOOK_ON)
	or a
	ret z
	xor a
	ld (BOOK_ON),a
	call PTR_KEEP_ARROW
	ld hl,CMD_BOOKBACK
	call BOOK_COPY3
	call WCALL		; (the compass shapes are in the world segment)
	dw DRAW_COMPASS
	ret

; BOOK_CHARPTR - IY = the character of the book
BOOK_CHARPTR:
	ld a,(BOOK_CHAR)
	jp CHAR_PTR

; BOOK_LIST - HL = the entries of (BOOK_CHAR, BOOK_TYPE, BOOK_LEVEL)
;   Preserves BC.
BOOK_LIST:
	push bc
	ld a,(BOOK_CHAR)
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl		; 4
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,hl		; 32
	ld c,l
	ld b,h
	add hl,hl		; 64
	add hl,bc
	add hl,de		; 100
	ld a,(BOOK_TYPE)
	or a
	jr z,.m
	ld de,50
	add hl,de
.m:	ld a,(BOOK_LEVEL)
	add a,a
	ld c,a
	add a,a
	add a,a
	add a,c			; *10
	ld e,a
	ld d,0
	add hl,de
	ld de,CH_SPELLS
	add hl,de
	pop bc
	ret

; BOOK_NAME - A = list entry (> 0) -> HL = its name for the book
BOOK_NAME:
	add a,a
	ld e,a
	ld d,0
	ld hl,BOOK_MAGE
	ld a,(BOOK_TYPE)
	or a
	jr z,.m
	ld hl,BOOK_CLERIC
.m:	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ret

; BOOK_FIRST - the first ready spell of the level becomes the selected one
BOOK_FIRST:
	call BOOK_LIST
	ld b,0
.lp:	ld a,(hl)
	dec a
	jp p,.got
	inc hl
	inc b
	ld a,b
	cp 6
	jr c,.lp
.got:	ld a,b
	ld (BOOK_SEL),a
	ret

; ----------------------------------------------------------------------------
; BOOK_CLICKS - a click while the book is open -> A <> 0 if it was the book's
; ----------------------------------------------------------------------------
BOOK_CLICKS:
	ld a,(CAST_WHO)
	or a
	jp nz,WHO_CLICK
	ld a,(MOUSE_X+1)
	or a
	jp nz,.no
	ld a,(MOUSE_Y)
	cp 122
	jr c,.no
	cp 131
	jr nc,.list
	; a tab: (x - 71) / 21
	ld a,(MOUSE_X)
	sub 71
	jr c,.no
	ld c,0
.div:	sub 21
	jr c,.tab
	inc c
	jr .div
.tab:	ld a,c
	cp 5
	jr nc,.no
	ld (BOOK_LEVEL),a
	call BOOK_FIRST
	call BOOK_DRAW
	ld a,1
	ret
.list:	ld a,(MOUSE_X)
	cp 71
	jr c,.no
	cp 176
	jr nc,.no
	ld a,(MOUSE_Y)
	cp 168
	jr nc,.abort
	sub 132
	jr c,.no
	ld c,0
.d6:	sub 6
	jr c,.row
	inc c
	jr .d6
.row:	ld a,c
	cp 6
	jr nc,.no
	ld (BOOK_SEL),a
	; a ready spell, the book not resting: cast it
	call BOOK_LIST
	ld e,c
	ld d,0
	add hl,de
	ld a,(hl)
	dec a
	jp m,.redraw
	call BOOK_CHARPTR
	bit 2,(iy+P_DISABLED)
	jr nz,.redraw
	call BOOK_DRAW
	call CAST
	ld a,1
	ret
.redraw:
	call BOOK_DRAW
	ld a,1
	ret
.abort:	cp 177
	jr nc,.no
	call BOOK_CLOSE
	ld a,1
	ret
.no:	xor a
	ret

; ----------------------------------------------------------------------------
; CAST - the selected spell of the book (castSpell)
; ----------------------------------------------------------------------------
CAST:
	call BOOK_LIST
	ld a,(BOOK_SEL)
	ld e,a
	ld d,0
	add hl,de		; HL = the entry
	ld a,(hl)
	ld (CS_ENTRY),a
	ld c,a
	ld a,(BOOK_TYPE)
	or a
	ld a,c
	jr z,.m
	add a,CLERIC_OFS
.m:	ld (ACTIVE_SPELL),a
	push hl
	call CS_FREEHAND
	pop hl
	ret nz
.hand:	; the entry is used: the rest moves up, it goes to the end as < 0
	ld a,(BOOK_SEL)
	ld b,a
	ld a,8
	sub b
	jr z,.last
	jr c,.last
	ld c,a
	ld b,0
	ld e,l
	ld d,h
	inc hl
	ldir
	ex de,hl
.last:	call BOOK_LIST
	ld de,8
	add hl,de
	ld a,(CS_ENTRY)
	neg
	ld (hl),a
	; fall through
; CS_ANNOUNCE - (ACTIVE_SPELL) of (BOOK_CHAR): "<name> conjura <spell>.",
;   then on whom, or it starts (castSpell)
CS_ANNOUNCE:
	call SPELL_PTR		; a harmful spell (100h): an invisible caster
	bit 0,(ix+1)		; is seen again
	jr z,.seen
	call BOOK_CHARPTR
	bit 6,(iy+P_EFFECT)
	jr z,.seen
	ld a,(ACTIVE_SPELL)
	push af
	ld a,(BOOK_CHAR)
	ld c,a
	ld a,8
	call EVENT_END
	pop af
	ld (ACTIVE_SPELL),a
.seen:	call BOOK_CHARPTR
	push iy
	pop hl
	inc hl
	ld de,TEXTBUF
	ld bc,10
	ldir
	xor a
	ld (de),a
	ld hl,STR_CASTS
	call TEXT_APPEND
	ld a,(ACTIVE_SPELL)
	add a,a
	ld e,a
	ld d,0
	ld hl,SPELL_NAMES
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	call TEXT_APPEND
	ld hl,STR_DOT
	call TEXT_APPEND
	ld hl,TEXTBUF
	call MSG_PRINT
	; the position of the caster for flying spells
	ld a,(BOOK_CHAR)
	cp 4
	jr c,.ci
	sub 2
.ci:	call THROW_START
	; on whom?
	call SPELL_PTR
	bit 5,(ix+0)		; flag 20h
	jr z,.self
	ld hl,STR_CHOOSE
	call MSG_PRINT
	ld a,1
	ld (CAST_WHO),a
	ret
.self:	ld a,(BOOK_CHAR)
	ld (ACTIVE_CHAR),a
	jp START_SPELL

STR_DOT:	db ".",0
CS_ENTRY:	db 0

; CS_FREEHAND - the spell (ACTIVE_SPELL) of (BOOK_CHAR) may need a free hand
;   -> NZ (and the warning) if both hands hold something
CS_FREEHAND:
	call SPELL_PTR		; IX = its flags
	bit 2,(ix+1)		; flag 400h
	ret z
	call BOOK_CHARPTR
	ld a,0
	call SLOT_PTR
	ld a,(hl)
	inc hl
	or (hl)
	push af
	ld a,1
	call SLOT_PTR
	pop af
	ld c,a
	ld a,(hl)
	inc hl
	or (hl)
	and c
	ret z
	ld hl,STR_FREEHAND
	call WARNING
	or 1
	ret

; WHO_CLICK - the target of a spell cast on a character (castOnWhomDialogue,
;   clickedCastSpellOnCharacter): its box, anything else aborts
WHO_CLICK:
	xor a
	ld (CAST_WHO),a
	ld hl,(MOUSE_X)
	ld de,184
	or a
	sbc hl,de
	jr c,.abort
	ld a,l
	ld c,0
	cp 72
	jr c,.col
	inc c
.col:	ld a,(MOUSE_Y)
	sub 2
	jr c,.abort
	ld b,0
.row:	sub 52
	jr c,.got
	inc b
	jr .row
.got:	ld a,b
	cp 3
	jr nc,.abort
	add a,a
	add a,c
	ld (ACTIVE_CHAR),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.abort
	call START_SPELL
	ld a,1
	ret
.abort:	ld hl,STR_ABORTED
	call MSG_PRINT
	ld a,1
	ret

; SPELL_PTR - (ACTIVE_SPELL) -> IX = its SPELL_TAB entry (5 bytes). Keeps HL.
SPELL_PTR:
	ld a,(ACTIVE_SPELL)
	cp 22
	ld ix,STONE_RULE
	ret z
	cp 37
	ld ix,VEST_RULE
	ret z
	push hl
	ld l,a
	ld h,0
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,de
	ld de,SPELL_TAB
	add hl,de
	push hl
	pop ix
	pop hl
	ret
; Stoneskin owns a separate flag/counter; sharing Armor's flag strands
; recasting after the last protected blow and prevents independent effects.
STONE_RULE:
	dw 0031h,0004h
	db 0
; The original entry lacks this port's AC-refresh bit. Recalculate both
; on application and expiry, rather than waiting for an equipment change.
VEST_RULE:
	dw 009Bh,4000h
	db 0

; ----------------------------------------------------------------------------
; START_SPELL - (ACTIVE_SPELL) on (ACTIVE_CHAR) (startSpell)
; ----------------------------------------------------------------------------
START_SPELL:
	ld a,(ACTIVE_SPELL)	; its sound
	ld e,a
	ld d,0
	ld hl,SPELL_SND
	add hl,de
	ld a,(hl)
	call SFX_PLAY
	call SPELL_PTR
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	; already under this effect: nothing
	ld a,(ix+0)
	and 30h
	jr z,.party
	ld a,(ix+2)
	and (iy+P_EFFECT)
	ld c,a
	ld a,(ix+3)
	and (iy+P_EFFECT+1)
	or c
	jp nz,.done
.party:	ld a,(ix+0)
	and 50h
	jr z,.go
	ld a,(ix+2)
	ld hl,PARTY_EFFECTS
	and (hl)
	ld c,a
	ld a,(ix+3)
	inc hl
	and (hl)
	or c
	jr z,.go
	ld a,(ix+3)		; bless (400h): "already blessed"
	cp 4
	jp nz,.done
	ld hl,STR_BLESSED
	call MSG_PRINT
	jp .done
.go:	; a timed effect
	bit 3,(ix+0)
	jr z,.untimed
	call EFFECT_TIMER
	jp c,.done
.untimed:
	; the spell itself
	xor a
	ld (SPELL_RET),a
	ld a,(ACTIVE_SPELL)
	push af			; expiry callbacks may select the spell being removed
	add a,a
	ld e,a
	ld d,0
	ld hl,SPELL_START
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	call .jp
	pop af
	ld (ACTIVE_SPELL),a
	ld a,(SPELL_RET)
	or a
	jr nz,.done
	; effect flags: the caster (1), the party (4), all characters (200h)
	call SPELL_PTR
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	bit 0,(ix+0)
	jr z,.np
	ld a,(ix+2)
	or (iy+P_EFFECT)
	ld (iy+P_EFFECT),a
	ld a,(ix+3)
	or (iy+P_EFFECT+1)
	ld (iy+P_EFFECT+1),a
.np:	bit 2,(ix+0)
	jr z,.all
	ld hl,PARTY_EFFECTS
	ld a,(ix+2)
	or (hl)
	ld (hl),a
	inc hl
	ld a,(ix+3)
	or (hl)
	ld (hl),a
.all:	bit 1,(ix+1)
	jr z,.ac
	xor a
.ch:	push af
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.nc
	ld a,(ix+2)
	or (iy+P_EFFECT)
	ld (iy+P_EFFECT),a
	ld a,(ix+3)
	or (iy+P_EFFECT+1)
	ld (iy+P_EFFECT+1),a
.nc:	pop af
	inc a
	cp 6
	jr c,.ch
.ac:	bit 1,(ix+0)
	jr z,.draw
	ld a,(ACTIVE_CHAR)
	call UCALL
	dw RECALC_AC
.draw:	call PANEL_DRAW_ALL
.done:	; the book rests 72 ticks
	ld a,(US_ITEMCAST)
	or a
	jr nz,.itemdone		; scrolls/wands recover their hand in US_CAST
	ld a,(BOOK_CHAR)
	ld c,a
	ld hl,72
	xor a			; event 0: the book
	call ADD_EVENT
	jr c,.bookfull
	call BOOK_CHARPTR
	set 2,(iy+P_DISABLED)
.bookfull:
	ld a,(BOOK_ON)
	or a
	call nz,BOOK_DRAW
.itemdone:
	ld a,1
	ld (SCENE_DIRTY),a
	ret
.jp:	jp (hl)

SPELL_RET:	db 0

; ----------------------------------------------------------------------------
; Timed effects: per character 4 events (ticks, spell); event 0 is the rest
; of the book after a cast
; ----------------------------------------------------------------------------

; EFFECT_TIMER - the duration of (ACTIVE_SPELL) for (ACTIVE_CHAR)
;   (setSpellEventTimer): len * base + len * level * levelFactor ticks
EFFECT_TIMER:
	ld a,(ACTIVE_SPELL)
	ld e,a
	ld d,0
	ld hl,SPELL_TIME
	add hl,de
	ld a,(hl)		; 0: none, else base + 16 * levelFactor (len 546)
	or a
	ret z
	ld c,a
	and 0Fh
	ld b,a			; base
	ld a,c
	rrca
	rrca
	rrca
	rrca
	and 0Fh
	ld c,a			; level factor
	or a
	jr z,.base
	call CASTER_LEVEL
	ld e,a
	ld a,c
	push bc			; MUL8 uses B for its loop
	call MUL8
	pop bc
	ld a,l
.base:	add a,b
	ld b,a
	ld hl,0
	ld de,546		; EOB.EXE timer unit (0x222 ticks)
.units:	add hl,de
	djnz .units
	ld a,(ACTIVE_CHAR)
	ld c,a
	ld a,(ACTIVE_SPELL)
	jp ADD_EVENT

; CASTER_LEVEL - the level of (BOOK_CHAR) in the kind of the book -> A
CASTER_LEVEL:
	push bc
	push de
	push hl
	ld a,(BOOK_TYPE)
	ld c,a
	ld a,(US_ITEMCAST)
	ld b,a
	ld a,(BOOK_CHAR)
	call XCALL
	dw FX_CASTER_LEVEL
	pop hl
	pop de
	pop bc
	ret

; ADD_EVENT - C = character, A = event (spell, 0 book), HL = ticks
ADD_EVENT:
	ld (AE_ID),a
	push af
	push hl
	ld a,c
	add a,a
	add a,a
	ld e,a
	add a,a
	add a,e			; *12
	ld e,a
	ld d,0
	ld hl,CH_EVENTS
	add hl,de
	ld b,4
	push hl
.find:
	inc hl
	inc hl
	ld a,(AE_ID)
	cp (hl)
	jr nz,.skip
	dec hl
	ld a,(hl)
	dec hl
	or (hl)
	jr nz,.refresh
	inc hl
	inc hl
.skip:
	inc hl
	djnz .find
	pop hl
	ld b,4
.free:	ld a,(hl)
	inc hl
	or (hl)
	dec hl
	jr z,.got
	inc hl
	inc hl
	inc hl
	djnz .free
	pop hl
	pop af
	scf
	ret
.got:	pop de
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	pop af
	ld (hl),a
	ld hl,MAGIC_ACTIVE
	inc (hl)
	or a
	ret
.refresh:
	pop de
	pop de
	ld (hl),e
	inc hl
	ld (hl),d
	pop af
	or a
	ret
AE_ID: db 0

 ; C=character, A=event -> NZ if that event is active. Preserves IY.
EVENT_EXISTS:
 ld e,a
 ld a,c
 add a,a
 add a,a
 ld l,a
 add a,a
 add a,l
 ld l,a
 ld h,0
 ld bc,CH_EVENTS
 add hl,bc
 ld b,4
.loop:
 ld a,(hl)
 inc hl
 or (hl)
 inc hl
 jr z,.next
 ld a,(hl)
 cp e
 jr z,.yes
.next:
 inc hl
 djnz .loop
 xor a
 ret
.yes:
 or 1
 ret

; MAGIC_TICK - per tick (MAGIC_ACTIVE > 0): the events count down
MAGIC_TICK:
	ld a,(SWAP_CHAR)
	inc a
	call nz,SWAP_BLINK
	ld ix,CH_EVENTS
	ld c,0			; character
.ch:	ld b,4
.ev:	ld l,(ix+0)
	ld h,(ix+1)
	ld a,h
	or l
	jr z,.next
	dec hl
	ld (ix+0),l
	ld (ix+1),h
	ld a,h
	or l
	jr nz,.next
	push bc
	push ix
	ld a,(ix+2)
	call EVENT_END
	pop ix
	pop bc
	ld hl,MAGIC_ACTIVE
	dec (hl)
.next:	inc ix
	inc ix
	inc ix
	djnz .ev
	inc c
	ld a,c
	cp 6
	jr c,.ch
	ret

; EVENT_END - C = character, A = event: the book is ready again, or the
;   effect of a spell ends (removeCharacterEffect), or poison / paralysis
EVENT_END:
	cp 53
	jr c,.normal
	cp 55
	jr nc,.normal
	call XCALL
	dw FX_EXPIRE
	ret
.normal:
	or a
	jp m,STATUS_EVENT
	jr nz,.spell
	ld a,c
	call CHAR_PTR
	res 2,(iy+P_DISABLED)
	ld a,(BOOK_ON)
	or a
	ret z
	ld a,(BOOK_CHAR)
	cp c
	ret nz
	jp BOOK_DRAW
.spell:	ld (ACTIVE_SPELL),a
	ld a,c
	ld (ACTIVE_CHAR),a
	call SPELL_PTR
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	; "<STR_EXPIRES0><name><STR_EXPIRES><spell><STR_EXPIRES2>"
	xor a
	ld (TEXTBUF),a
	ld hl,STR_EXPIRES0
	call TEXT_APPEND
	call NAME_APPEND
	ld hl,STR_EXPIRES
	call TEXT_APPEND
	ld a,(ACTIVE_SPELL)
	add a,a
	ld e,a
	ld d,0
	ld hl,SPELL_NAMES
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	call TEXT_APPEND
	ld hl,STR_EXPIRES2
	call TEXT_APPEND
	ld hl,TEXTBUF
	call MSG_PRINT
	; the flags go
	call SPELL_PTR
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	ld a,(ix+2)
	cpl
	and (iy+P_EFFECT)
	ld (iy+P_EFFECT),a
	ld a,(ix+3)
	cpl
	and (iy+P_EFFECT+1)
	ld (iy+P_EFFECT+1),a
	bit 2,(ix+0)
	jr z,.all
	ld hl,PARTY_EFFECTS
	ld a,(ix+2)
	cpl
	and (hl)
	ld (hl),a
	inc hl
	ld a,(ix+3)
	cpl
	and (hl)
	ld (hl),a
.all:	bit 1,(ix+1)
	jr z,.ac
	xor a
.ch:	push af
	call CHAR_PTR
	ld a,(ix+2)
	cpl
	and (iy+P_EFFECT)
	ld (iy+P_EFFECT),a
	ld a,(ix+3)
	cpl
	and (iy+P_EFFECT+1)
	ld (iy+P_EFFECT+1),a
	pop af
	inc a
	cp 6
	jr c,.ch
.ac:	bit 1,(ix+0)
	ld a,(ACTIVE_CHAR)
	call nz,RECALC_AC_U
	; the end callbacks
	ld a,(ACTIVE_CHAR)
	ld c,a
	call CHAR_PTR
	ld a,(ACTIVE_SPELL)
	cp 31
	jr nz,.nAid
	ld a,(iy+P_HP)		; aid: its hit points go
	sub (iy+P_AID)
	ld (iy+P_HP),a
	ld (iy+P_AID),0
.nAid:	ld a,(ACTIVE_SPELL)
	cp 19
	jr nz,.nVamp
	ld a,(iy+P_HP)		; vampiric touch: not above the maximum
	bit 7,a
	jr nz,.nVamp
	cp (iy+P_HPMAX)
	jr c,.nVamp
	ld a,(iy+P_HPMAX)
	ld (iy+P_HP),a
.nVamp:	ld a,(ACTIVE_SPELL)
	cp 7
	jr z,.we
	cp 19
	jr z,.we
	cp 32
	jr nz,.pd
.we:	ld a,(ACTIVE_CHAR)
	ld c,a
	call WEAPON_END
.pd:	jp PANEL_DRAW_ALL

; ----------------------------------------------------------------------------
; STATUS_ATTACK - A = character, C = 2 poison / 4 paralysis: a monster's
;   special attack (statusAttack); a saving throw may avoid it
; STATUS_EVENT - A = 88h poison bites / 89h paralysis ends, C = character
; ----------------------------------------------------------------------------
STATUS_ATTACK:
	push af
	ld a,c
	sub 2			; poison2 -> save0; melee paralysis4 -> save2
	ld e,a
	pop af
; A=character, C=status, E=source-specific original saving category.
STATUS_ATTACK_SAVE:
	ld (SA_CHAR),a
	ld a,e
	ld (SA_SAVE),a
	ld a,c
	ld (SA_FLAG),a
	ld a,(SA_CHAR)
	call CHAR_PTR
	ld a,(iy+P_FLAGS)
	and c
	ret nz			; already
	call CHAR_ALIVE_R
	ret z
	; Never apply a status whose expiry/repeat event cannot be registered.
	call STATUS_TIMER_ROOM
	ret z
	ld a,(SA_SAVE)
	ld c,a
	ld a,(SA_CHAR)
	call XCALL
	dw FX_CHAR_SAVE
	ret nc
	ld a,(SA_CHAR)
	call CHAR_PTR
	ld a,(SA_FLAG)
	or (iy+P_FLAGS)
	ld (iy+P_FLAGS),a
	ld a,(SA_FLAG)
	cp 2
	ld hl,546
	ld a,88h
	ld de,STR_POISONED
	jr z,.ev
	ld hl,5*546
	ld a,89h
	ld de,STR_PARALYZED
.ev:	push de
	push af
	ld a,(SA_CHAR)
	ld c,a
	pop af
	call ADD_EVENT
	; a paralyzed caster loses the book
	ld a,(SA_FLAG)
	cp 4
	jr nz,.msg
	ld a,(BOOK_ON)
	or a
	jr z,.msg
	ld a,(BOOK_CHAR)
	ld hl,SA_CHAR
	cp (hl)
	call z,BOOK_CLOSE
.msg:	ld a,(SA_CHAR)
	call PANEL_DRAW
	pop hl
	ld a,(SA_CHAR)
	call MSG_NAMEIS		; "<name> es <hl>!"
	ret

STATUS_EVENT:
	ld (SA_EV),a
	ld a,c
	ld (SA_CHAR),a
	call CHAR_PTR
	ld a,(SA_EV)
	cp 89h
	jr z,.para
	; poison: 5 damage each 546 ticks while poisoned (not slowed)
	bit 1,(iy+P_FLAGS)
	ret z
	ld hl,546
	ld a,(SA_CHAR)
	ld c,a
	ld a,88h
	call ADD_EVENT
	ld a,(SA_CHAR)
	call CHAR_PTR
	bit 5,(iy+P_EFFECT+1)	; slow poison (2000h)
	ret nz
	ld a,(SA_CHAR)
	ld hl,STR_POISONHIT
	call MSG_NAMED_M
	ld a,(SA_CHAR)
	ld hl,5
	jp INFLICT_CHARACTER
.para:	bit 2,(iy+P_FLAGS)
	ret z
	res 2,(iy+P_FLAGS)
	ld a,(SA_CHAR)
	call PANEL_DRAW
	ld a,(SA_CHAR)
	ld hl,STR_UNPARA
	jp MSG_NAMED_M

; MSG_NAMED_M - A = character, HL = text: "<name> <text>"
MSG_NAMED_M:
	push hl
	call CHAR_PTR
	push iy
	pop hl
	inc hl
	ld de,TEXTBUF
	ld bc,10
	ldir
	xor a
	ld (de),a
	ld hl,STR_SP
	call TEXT_APPEND
	pop hl
	call TEXT_APPEND
	ld hl,TEXTBUF
	jp MSG_PRINT

; MSG_NAMEIS - A = character, HL = state: "<name> es <state>!"
MSG_NAMEIS:
	push hl
	ld hl,STR_ES
	call MSG_NAMED_PRE
	pop hl
	call TEXT_APPEND
	ld hl,STR_EXCL
	call TEXT_APPEND
	ld hl,TEXTBUF
	jp MSG_PRINT
MSG_NAMED_PRE:
	push hl
	call CHAR_PTR
	push iy
	pop hl
	inc hl
	ld de,TEXTBUF
	ld bc,10
	ldir
	xor a
	ld (de),a
	pop hl
	jp TEXT_APPEND

SA_CHAR:	db 0
SA_FLAG:	db 0
SA_SAVE:	db 0
SA_EV:		db 0
STR_SP:		db " ",0
; STR_ES, STR_EXCL, STR_POISONED, STR_PARALYZED, STR_POISONHIT, STR_UNPARA,
;   STR_EXPIRES0/1/2, STR_ABORTED, STR_NOTFRONT: in magicdata.inc (language)

; NAME_APPEND - IY = character: the name (10 characters at most) at the end
;   of TEXTBUF
NAME_APPEND:
	push iy
	pop de
	inc de
	ld hl,TEXTBUF
.end:	ld a,(hl)
	or a
	jr z,.cp
	inc hl
	jr .end
.cp:	ld b,10
.lp:	ld a,(de)
	ld (hl),a
	or a
	ret z
	inc de
	inc hl
	djnz .lp
	ld (hl),0
	ret

; ----------------------------------------------------------------------------
; Two characters change places (clickedCharNameLabelRight, exchangeCharacters):
; a right click on a name, then on another. Meanwhile the first one shows
; "Swapping" and its name in turn every 9 ticks (timerProcessCharacterExchange,
; MAGIC_ACTIVE counts the exchange so that MAGIC_TICK runs), and only the
; names and the panel take clicks (gui_setSwapCharacterButtons).
; ----------------------------------------------------------------------------

; SWAP_LABEL - A = character, right click in its box: on its name the
;   exchange starts -> A = 1, else A = 0 (the next areas try)
SWAP_LABEL:
	ld (SW_TO),a
	call SW_ONLABEL
	ld a,0
	ret nz
	call BOOK_CLOSE
	ld a,(SW_TO)
	ld (SWAP_CHAR),a
	ld hl,MAGIC_ACTIVE
	inc (hl)
	ld a,1
	ld (SW_TIME),a
	xor a
	ld (SW_SHOW),a
	call SWAP_BLINK
	ld a,1
	ret

; SW_ONLABEL - (SW_TO) = character whose box was clicked: Z if the mouse
;   is on the name (the top 9 rows of the box)
SW_ONLABEL:
	ld a,(SW_TO)
	srl a
	ld e,a
	ld d,0
	ld hl,PANEL_BOXY
	add hl,de
	ld a,(MOUSE_Y)
	sub (hl)
	cp 9
	jr nc,.no
	xor a			; Z
	ret
.no:	or 1			; NZ
	ret

; SWAP_CLICKS - a click during the exchange: a right click on the name of
;   a character ends it there, a click anywhere else on the panel aborts
;   it (clickedAbortCharSwitch) -> A = 1
SWAP_CLICKS:
	ld hl,(MOUSE_X)
	ld de,184
	or a
	sbc hl,de
	jr c,.done		; not the panel
	ld a,(MOUSE_Y)
	cp 157
	jr nc,.done
	ld a,(CLICK)
	cp 2
	jr nz,.abort
	; the box: column (x < 72 from 184: left), row (54 rows each)
	ld a,l
	cp 72
	ld c,0
	jr c,.col
	inc c
.col:	ld a,(MOUSE_Y)
	ld b,0
.row:	sub 52
	jr c,.got
	inc b
	jr .row
.got:	ld a,b
	add a,a
	add a,c
	ld (SW_TO),a
	call SW_ONLABEL
	jr nz,.abort
	ld a,(SW_TO)
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.done		; an empty box: nothing
	call SWAP_DO
	jr .done
.abort:	ld a,(MOUSE_Y)		; (the abort area ends at row 120)
	cp 121
	jr nc,.done
	call SWAP_END
	ld a,(SW_FROM)
	call PANEL_DRAW
.done:	ld a,1
	ret

; SWAP_END - the exchange mode ends; (SW_FROM) = its character
SWAP_END:
	ld a,(SWAP_CHAR)
	ld (SW_FROM),a
	ld a,0FFh
	ld (SWAP_CHAR),a
	ld hl,MAGIC_ACTIVE
	dec (hl)
	ret

; SWAP_DO - (SWAP_CHAR) and (SW_TO) change places: their records, spell
;   lists and timed events; the second becomes the selected one
SWAP_DO:
	call SWAP_END
	ld a,(SW_FROM)
	call CHAR_PTR
	push iy
	ld a,(SW_TO)
	call CHAR_PTR
	push iy
	pop de
	pop hl
	ld bc,P_SIZE
	call SWAP_MEM
	ld hl,CH_SPELLS
	ld c,100
	call .tab
	ld hl,CH_EVENTS
	ld c,12
	call .tab
	ld a,(SW_TO)
	ld (SEL_CHAR),a
	jp PANEL_DRAW_ALL
.tab:	; HL = table, C = bytes per character
	push hl
	ld a,(SW_FROM)
	ld e,a
	ld a,c
	push bc
	call MUL8
	pop bc
	pop de
	push de
	add hl,de
	ex (sp),hl		; HL = table, (SP) = the first
	push hl
	ld a,(SW_TO)
	ld e,a
	ld a,c
	push bc
	call MUL8
	pop bc
	pop de
	add hl,de
	ex de,hl		; DE = the second
	pop hl
	ld b,0
; SWAP_MEM - exchanges BC bytes at HL and DE
SWAP_MEM:
	ld a,(de)
	push af
	ld a,(hl)
	ld (de),a
	pop af
	ld (hl),a
	inc hl
	inc de
	dec bc
	ld a,b
	or c
	jr nz,SWAP_MEM
	ret

; SWAP_BLINK - per tick: every 9 the name of (SWAP_CHAR) and "Swapping"
;   change places
SWAP_BLINK:
	ld hl,SW_TIME
	dec (hl)
	ret nz
	ld (hl),9
	ld hl,SW_SHOW
	ld a,(hl)
	xor 1
	ld (hl),a
	ld a,(SWAP_CHAR)
	jp z,PANEL_DRAW		; the name
	; the label, dark red, over the name
	push af
	call PANEL_DRAW		; (PN_X, PN_Y = its box)
	pop af
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	ret z
	ld de,(PN_X)
	inc de
	inc de
	ld a,(PN_Y)
	add a,2
	ld c,a
	ld b,60
	ld l,7
	ld a,C_FILL
	call FILL_RECT
	ld hl,STR_SWAPPING
	ld de,(PN_X)
	inc de
	inc de
	ld a,(PN_Y)
	add a,2
	ld c,a
	ld a,C_DARKRED
	ld b,C_FILL
	jp TEXT_PRINT

SW_TO:		db 0
SW_FROM:	db 0
SW_TIME:	db 0
SW_SHOW:	db 0

RECALC_AC_U:
	call UCALL
	dw RECALC_AC
	ret

; ----------------------------------------------------------------------------
; The spells (spellCallback_start_*); no callback: the flags do it all
; ----------------------------------------------------------------------------
SP_EXT:
	call CASTER_LEVEL
	ld b,a
	ld a,(BOOK_CHAR)
	ld c,a
	ld a,(ACTIVE_CHAR)
	ld e,a
	ld a,(ACTIVE_SPELL)
	call XCALL
	dw FX_SPELL
	ret

SP_NONE:
	ret

SP_NOEFFECT:
	ld hl,STR_NOEFFECT
; WARNING - HL = text: printed with the warning sound (printWarning)
WARNING:
	ld a,79
	call SFX_PLAY
	jp MSG_PRINT

; 1 armor: base armour 6 for a while (effectsRemainder[0] = level + 8)
SP_ARMOR:
	call CASTER_LEVEL
	add a,8
	ld c,a
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	ld (iy+P_EFFREM),c
	ret

SP_STONESKIN:
 call CASTER_LEVEL
 ld c,a
 ld a,(ACTIVE_CHAR)
 call XCALL
 dw FX_STONESKIN
 ret

SP_VESTMENT:
 call CASTER_LEVEL
 ld c,a
 ld a,(ACTIVE_CHAR)
 ld e,a
 ld a,c
 call XCALL
 dw FX_VEST_START
 ret

; 2 burning hands: the monsters in front take 1d3 + 2 * level
SP_BURNING:
	call CASTER_LEVEL
	add a,a
	ld (SP_DMGINC),a
	ld bc,0103h
	ld (SP_DICE),bc
	jp SP_FRONT_DAMAGE

; 4 magic missile, 13 fireball, 18 lightning bolt, 10 melf's arrow,
; 14 flame arrow, 16 / 33 hold person, 21 ice storm, 25 hold monster,
; 47 flame strike: flying magic
SP_MISSILE:
	xor a
	jr SP_LAUNCH
SP_MELF:
	ld a,1
	jr SP_LAUNCH
SP_FIREBALL:
	ld a,2
	jr SP_LAUNCH
SP_FLAMEARROW:
	ld a,3
	jr SP_LAUNCH
SP_HOLDPERSON:
	ld a,4
	jr SP_LAUNCH
SP_LIGHTNING:
	ld a,5
	jr SP_LAUNCH
SP_ICESTORM:
	ld a,6
	jr SP_LAUNCH
SP_HOLDMONSTER:
	ld a,7
	jr SP_LAUNCH
SP_FLAMESTRIKE:
	ld a,8
SP_LAUNCH:
	call SP_LAUNCH_PROPS
	jr SP_LAUNCH2
; SP_LAUNCH_PROPS - A = flight type: FLY_NEW gets its properties
SP_LAUNCH_PROPS:
	; FLIGHT_PROPS[type]: spell of the hit, distance, flags, shape
	ld (FL_MTYPE),a
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld hl,FLIGHT_PROPS
	add hl,de
	ld de,FLY_NEW+FO_CB
	ld a,(hl)
	ld (de),a
	inc hl
	ld a,(hl)
	ld (FLY_NEW+FO_DIST),a
	inc hl
	ld a,(hl)
	ld (FLY_NEW+FO_FLAGS),a
	inc hl
	ld a,(hl)
	ld (FLY_NEW+FO_TYPE),a
	ld a,2
	ld (FLY_NEW+FO_EN),a
	ld a,1
	ld (FLY_NEW+FO_START),a
	ld a,(FL_MTYPE)
	ld l,a
	ld h,0
	ld (FLY_NEW+FO_ITEM),hl
	ret
SP_LAUNCH2:
	ld a,(FL_DIR)
	ld (FLY_NEW+FO_DIR),a
	ld hl,(CUR_BLOCK)
	ld (FLY_NEW+FO_BLOCK),hl
	ld a,(TS_POS)
	ld (FLY_NEW+FO_POS),a
	ld a,(BOOK_CHAR)
	ld (FLY_NEW+FO_ATK),a
	call CASTER_LEVEL
	ld (FLY_NEW+FO_LEVEL),a
	call WCALL
	dw FLY_ADD
	ret
FL_MTYPE:	db 0

; 26 bless, 30 protection from evil, 6 shield, 3 / 29 detect magic,
; 43 protection 10': only flags (SP_NONE)

; 7 shocking grasp, 19 vampiric touch, 32 flame blade: a magic weapon in a
;   hand of the caster (createMagicWeaponType / createMagicWeaponItem)
SP_SHOCKING:
	call CASTER_LEVEL
	ld bc,0108h
	ld de,1052h		; item flags 10h, icon 82
	jr SP_WEAPON
SP_VAMPIRIC:
	call CASTER_LEVEL
	srl a
	ld b,a
	ld c,6
	xor a
	ld de,1853h		; flags 18h, icon 83
	jr SP_WEAPON
SP_FLAMEBLADE:
	ld bc,0104h
	ld a,4
	ld de,0054h		; icon 84
SP_WEAPON:
	ld (SW_INC),a
	ld (SW_DICE),bc
	ld (SW_ITM),de
	; a free type of 51..56 (armour class -30)
	ld a,51
.ty:	push af
	call ITEMTYPE_PTR
	ld de,IT_AC
	add hl,de
	ld a,(hl)
	cp -30
	jr z,.tok
	pop af
	inc a
	cp 57
	jr c,.ty
	ret
.tok:	ld (hl),0		; armour class 0
	inc hl
	ld (hl),0		; hands
	ld de,-IT_AC-1
	add hl,de
	ld (hl),1		; extra properties
	inc hl
	ld bc,(SW_DICE)
	ld a,(SW_INC)
	ld e,2
.dc:	ld (hl),b
	inc hl
	ld (hl),c
	inc hl
	ld (hl),a
	inc hl
	dec e
	jr nz,.dc
	ld (hl),0Fh		; any class
	inc hl
	xor a
	ld b,4
.z:	ld (hl),a		; slot and hand flags
	inc hl
	djnz .z
	pop af
	ld (SW_TYPE),a
	; a free item of 11..16 (block -2)
	ld hl,11
.it:	call ITEM_IX
	ld a,(ix+I_BLOCK)
	cp 0FEh
	jr nz,.ni
	ld a,(ix+I_BLOCK+1)
	inc a
	jr z,.iok
.ni:	inc hl
	ld a,l
	cp 17
	jr c,.it
	ret
.iok:	push hl
	ld de,(SW_ITM)
	ld a,d
	or 20h
	ld (ix+I_FLAGS),a
	ld (ix+I_ICON),e
	ld a,(SW_TYPE)
	ld (ix+I_TYPE),a
	xor a
	ld (ix+I_VALUE),a
	ld (ix+I_POS),a
	ld (ix+I_NAMEID),a
	ld (ix+I_NAMEUNID),a
	ld (ix+I_BLOCK),a
	ld (ix+I_BLOCK+1),a
	ld (ix+I_NEXT),a
	ld (ix+I_NEXT+1),a
	ld (ix+I_PREV),a
	ld (ix+I_PREV+1),a
	; into hand 1 if it is free, else hand 0 (getMagicWeaponSlot)
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	pop de
	ld a,(iy+P_INV+2)
	or (iy+P_INV+3)
	jr nz,.h0
	ld (iy+P_INV+2),e
	ld (iy+P_INV+3),d
	jr .drawn
.h0:	ld (iy+P_INV),e
	ld (iy+P_INV+1),d
.drawn:	ld a,(ACTIVE_CHAR)
	jp PANEL_DRAW
SW_DICE:	dw 0
SW_INC:		db 0
SW_ITM:	dw 0
SW_TYPE:	db 0

; WEAPON_END - C = character: its magic weapons go
;   (spellCallback_end_shockingGraspFlameBlade)
WEAPON_END:
	ld a,c
	call CHAR_PTR
	push iy
	pop hl
	ld de,P_INV
	add hl,de
	ld b,2
.h:	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or a
	jr nz,.n
	ld a,e
	sub 11
	cp 7
	jr nc,.n
	ld (hl),0
	dec hl
	ld (hl),0
	inc hl
	push hl
	ex de,hl
	call ITEM_IX
	ld (ix+I_BLOCK),0FEh
	ld (ix+I_BLOCK+1),0FFh
	ld (ix+I_LEVEL),0FFh
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld de,IT_AC
	add hl,de
	ld (hl),-30
	pop hl
.n:	inc hl
	djnz .h
	ret

; 12 / 36 dispel magic: the spells on the chosen character end
SP_DISPEL:
	ld hl,STR_DISPELLED
	ld de,TEXTBUF
.cp:	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	or a
	jr nz,.cp
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	push iy
	pop hl
	inc hl
	call TEXT_APPEND
	ld hl,STR_DISPELLED2
	call TEXT_APPEND
	ld hl,TEXTBUF
	call MSG_PRINT
	ld a,(ACTIVE_CHAR)
; A=character, also used by death cleanup without printing the cast message.
CLEAR_CHARACTER_EFFECTS:
	ld (ACTIVE_CHAR),a
	ld c,a
	add a,a
	add a,a
	ld b,a
	add a,a
	add a,b			; * 12: 4 events of 3 bytes
	ld e,a
	ld d,0
	ld ix,CH_EVENTS
	add ix,de
	ld b,4
.ev:	ld a,(ix+0)
	or (ix+1)
	jr z,.n
	ld a,(ix+2)
	or a
	jr z,.n
	jp m,.n			; poison, paralysis stay
	ld (ix+0),0
	ld (ix+1),0
	push bc
	push ix
	call EVENT_END
	pop ix
	pop bc
	ld hl,MAGIC_ACTIVE
	dec (hl)
.n:	inc ix
	inc ix
	inc ix
	djnz .ev
	ld a,c
	call XCALL
	dw FX_CLEAR_UNTIMED
	ret

; 20 fear: the monsters ahead flee
SP_FEAR:
	ld a,(CUR_DIR)
	call WCALL
	dw BLOCK_AHEAD
	ld (FLY_HITREC+FO_BLOCK),hl
	ld bc,0103h		; fear, persons and monsters
	call WCALL
	dw W_HOLD
	ret

; 24 cone of cold: the monsters of 7 blocks in front take level d4 + level
SP_CONE:
	ld a,24
	ld (FLY_HITREC+FO_CB),a	; own damage context, not the previous projectile
	ld a,98
	call SFX_PLAY
	call CASTER_LEVEL
	ld (WD_TIMES),a
	ld bc,0104h
	ld (WD_DICE),bc
	ld a,1
	ld (WD_INC),a
	ld a,0Ah		; the whole block, saving throw for half
	ld (FLY_HITREC+FO_FLAGS),a
	ld a,(BOOK_CHAR)
	ld (FLY_HITREC+FO_ATK),a
	ld a,(CUR_DIR)
	ld e,a
	add a,a
	add a,a
	add a,a
	sub e			; * 7
	ld e,a
	ld d,0
	ld hl,CONE_DEST
	add hl,de
	ld b,7
.bl:	push bc
	push hl
	ld e,(hl)
	ld a,e
	rla
	sbc a,a
	ld d,a
	ld hl,(CUR_BLOCK)
	add hl,de
	ld a,h
	and 3
	ld h,a
	ld (FLY_HITREC+FO_BLOCK),hl
	call WCALL
	dw W_MAGIC_DAMAGE
	pop hl
	pop bc
	inc hl
	djnz .bl
	ret

; 31 aid: 1d8 extra hit points while it lasts
SP_AID:
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	call CHAR_ALIVE_R
	jp z,SP_NOEFFECT
	ld a,(iy+P_AID)
	or a
	ld hl,STR_AIDFAIL
	jp nz,MSG_PRINT
	push iy
	ld bc,0108h
	xor a
	call ROLL_DICE
	pop iy
	call XCALL
	dw FX_AID_ADD
	ld a,(ACTIVE_CHAR)
	jp PANEL_DRAW

; 27 cure light, 40 cure serious, 45 cure critical
SP_CURELIGHT:
	ld bc,0108h
	xor a
	jr SP_CURE
SP_CURESERIOUS:
	ld bc,0208h
	ld a,1
	jr SP_CURE
SP_CURECRITICAL:
	ld bc,0308h
	ld a,3
SP_CURE:
	call ROLL_DICE
	ld c,l
	ld a,(ACTIVE_CHAR)
	jp HEAL_CHAR

; 49 lay on hands: 2 * level of the caster
SP_LAYONHANDS:
	call BOOK_CHARPTR
	ld a,(iy+P_LEVEL)
	add a,a
	ld c,a
	ld a,(ACTIVE_CHAR)
	jp HEAL_CHAR

; HEAL_CHAR - A = character, C = hit points (modifyCharacterHitpoints)
HEAL_CHAR:
	call XCALL
	dw FX_HEAL
	ret

; 28 cause light, 41 cause serious, 46 cause critical: a touch
SP_CAUSELIGHT:
	ld bc,0108h
	xor a
	jr SP_CAUSE
SP_CAUSESERIOUS:
	ld bc,0208h
	ld a,1
	jr SP_CAUSE
SP_CAUSECRITICAL:
	ld bc,0308h
	ld a,3
SP_CAUSE:
	ld (WD_DICE),bc
	ld (WD_INC),a
	ld a,(BOOK_CHAR)
	cp 2
	jr nc,.far		; only the front row touches
	ld (CB_CHAR),a
	ld hl,0
	ld (CB_ITEM),hl
	call WCALL
	dw CAUSE_WOUNDS
	ret
.far:	ld hl,STR_NOTFRONT	; A = the caster: "<name> must be in front..."
	call MSG_NAMED_PRE
	ld hl,TEXTBUF
	jp MSG_PRINT

; 42 neutralize poison
SP_NEUTRALIZE:
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	bit 1,(iy+P_FLAGS)
	jp z,SP_NOEFFECT
	res 1,(iy+P_FLAGS)
	res 5,(iy+P_EFFECT+1)
	ld a,(ACTIVE_CHAR)
	jp PANEL_DRAW

; 34 slow poison: only on the poisoned
SP_SLOWPOISON:
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	bit 1,(iy+P_FLAGS)
	jr z,.no
	; Unlike the generic timed effects, this spell has type flags 28h:
	; its target bit is set but the automatic effect bit is not. Set the
	; poison-delay flag here; EVENT_END clears it when the timer expires.
	set 5,(iy+P_EFFECT+1)
	ret
.no:
	ld a,1
	ld (SPELL_RET),a
	jp SP_NOEFFECT

; 39 remove paralysis: up to 4 characters
SP_REMOVEPARA:
	ld c,4
	xor a
.lp:	push af
	push bc
	call CHAR_PTR
	pop bc
	bit 2,(iy+P_FLAGS)
	jr z,.next
	res 2,(iy+P_FLAGS)
	dec c
.next:	pop af
	ld b,a
	ld a,c
	or a
	jr z,.done
	ld a,b
	inc a
	cp 6
	jr c,.lp
.done:
	jp PANEL_DRAW_ALL

; 35 create food: everybody full
SP_CREATEFOOD:
	xor a
.lp:	push af
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.n
	ld (iy+P_FOOD),100
.n:	pop af
	inc a
	cp 6
	jr c,.lp
	ret

; 48 raise dead: a dead character (not an elf) gets 1 hit point
SP_RAISEDEAD:
	ld a,(ACTIVE_CHAR)
	call CHAR_PTR
	ld a,(iy+P_HP)
	cp -10
	jp nz,SP_NOEFFECT
	ld a,(iy+P_RACE)
	srl a
	cp 1
	jp z,SP_NOEFFECT
	ld (iy+P_HP),1
	ld a,(ACTIVE_CHAR)
	jp PANEL_DRAW

; SP_FRONT_DAMAGE - (SP_DICE), (SP_DMGINC): the monsters on the block ahead
SP_FRONT_DAMAGE:
	ld bc,(SP_DICE)
	ld a,(SP_DMGINC)
	ld (WD_DICE),bc
	ld (WD_INC),a
	call WCALL
	dw W_FRONT_DAMAGE
	ret

SP_DICE:	dw 0
SP_DMGINC:	db 0
SP_TMP:		db 0

; the start routine of each spell
SPELL_START:
	dw SP_NONE, SP_ARMOR, SP_BURNING, SP_EXT, SP_MISSILE		; 0-4
	dw SP_EXT, SP_NONE, SP_SHOCKING, SP_NONE, SP_EXT		; 5-9
	dw SP_MELF, SP_EXT, SP_DISPEL, SP_FIREBALL, SP_FLAMEARROW	; 10-14
	dw SP_EXT, SP_HOLDPERSON, SP_NONE, SP_LIGHTNING, SP_VAMPIRIC	; 15-19
	dw SP_FEAR, SP_ICESTORM, SP_STONESKIN, SP_EXT, SP_CONE		; 20-24
	dw SP_HOLDMONSTER, SP_NONE, SP_CURELIGHT, SP_CAUSELIGHT, SP_EXT	; 25-29
	dw SP_NONE, SP_AID, SP_FLAMEBLADE, SP_HOLDPERSON, SP_SLOWPOISON	; 30-34
	dw SP_CREATEFOOD, SP_DISPEL, SP_VESTMENT, SP_NONE, SP_REMOVEPARA	; 35-39
	dw SP_CURESERIOUS, SP_CAUSESERIOUS, SP_NEUTRALIZE, SP_NONE, SP_NONE	; 40-44
	dw SP_CURECRITICAL, SP_CAUSECRITICAL, SP_FLAMESTRIKE, SP_RAISEDEAD, SP_LAYONHANDS	; 45-49
	dw SP_NONE, SP_NONE, SP_NONE

; Low nibble = base units; high nibble = caster-level multiplier.
; Retail DOS timer calls with fixed durations: Detect Magic (127A6h) = 2,
; Shield (1286Ch) = 5, Bless (131F0h) = 6, Protection (13285h) = 3,
; Aid (1332Ch) and Prayer (13566h) = 2 units, independently of caster level.
SPELL_TIME:
	db 0, 0, 0, 02h, 0, 0, 05h, 10h, 0, 0		; 0-9
	db 0, 0, 0, 0, 0, 13h, 0, 0, 0, 10h		; 10-19
	db 0, 0, 0, 0, 0, 0, 06h, 0, 0, 02h		; 20-29
	db 03h, 02h, 14h, 0, 11h, 0, 0, 50h, 02h, 0	; 30-39
	db 0, 0, 0, 30h, 0, 0, 0, 0, 0, 0		; 40-49
	db 0, 0, 0

; ----------------------------------------------------------------------------
; MAGIC_HIT - a magic flight reaches (FS_BLOCK, FS_POS); IY = its record
;   copy (FLY_HITREC) -> A <> 0 if it hit (spellCallback_end_*)
; ----------------------------------------------------------------------------
MAGIC_HIT:
 call XCALL
 dw FX_MAGIC_HIT
 ret

; SPELL_NAME_TB - A = spell: its name -> TEXTBUF
SPELL_NAME_TB:
	add a,a
	ld e,a
	ld d,0
	ld hl,SPELL_NAMES
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld de,TEXTBUF
.cp:	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	or a
	jr nz,.cp
	ret

; MON_CAST - A = magic flight type: a monster casts it from (MC_BLOCK,
;   MC_POS) towards (MC_DIR) (monsterSpellCast / launchMagicObject(-1, ..))
MON_CAST:
	call SP_LAUNCH_PROPS
	ld a,(MC_DIR)
	ld (FLY_NEW+FO_DIR),a
	ld hl,(MC_BLOCK)
	ld (FLY_NEW+FO_BLOCK),hl
	ld a,(MC_POS)
	ld (FLY_NEW+FO_POS),a
	ld a,0FFh
	ld (FLY_NEW+FO_ATK),a
	ld a,5			; the level of a monster caster
	ld (FLY_NEW+FO_LEVEL),a
	call WCALL
	dw FLY_ADD
	ret

; DEATH_SPELL - a beholder's death spell reaches the party: up to 1d4
;   characters below level 8 die (spellCallback_end_monster_deathSpell)
DEATH_SPELL:
	call AT_PARTY
	ret z
	ld hl,STR_DEATHSPELL
	call MSG_PRINT
	ld bc,0104h
	xor a
	call ROLL_DICE
	ld a,l
	ld (DS_LEFT),a
	call FIRST_TARGET
.lp:	ld a,1
	ret c
	ld a,(DS_TARGET)
	call CHAR_PTR
	ld a,(iy+P_LEVEL)
	cp 8
	jr nc,.nx
	ld a,(DS_TARGET)
	ld hl,300
	call INFLICT_CHARACTER
	ld hl,DS_LEFT
	dec (hl)
	ld a,1
	ret z
.nx:	call NEXT_TARGET
	jr .lp

; DISINTEGRATE - a random character dies (the original ignores the saving
;   throw: spellCallback_end_monster_disintegrate)
DISINTEGRATE:
	call AT_PARTY
	ret z
	call FIRST_TARGET
	ld a,1
	ret c
	ld a,(DS_TARGET)
	ld hl,300
	call INFLICT_CHARACTER
	ld a,(DS_TARGET)
	ld hl,STR_DISINT
	call MSG_NAMED_M
	ld a,1
	ret

; AT_PARTY - Z (A = 0) unless the object is in the party block
AT_PARTY:
	ld hl,(FLY_HITREC+FO_BLOCK)
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	ld a,0
	ret nz
	inc a
	ret

; FIRST_TARGET / NEXT_TARGET - the living characters from a random one
;   (findFirstCharacterSpellTarget) -> A = (DS_TARGET), C if none left
FIRST_TARGET:
	ld a,6
	call RND_RANGE
	dec a
	ld (DS_TARGET),a
	ld a,6
	ld (DS_COUNT),a
	jr NT_TEST
NEXT_TARGET:
	ld hl,DS_COUNT
	dec (hl)
	scf
	ret z
NT_NEXT:
	ld a,(DS_TARGET)
	inc a
	cp 6
	jr c,.s
	xor a
.s:	ld (DS_TARGET),a
NT_TEST:
	ld a,(DS_TARGET)
	call CHAR_PTR
	call CHAR_ALIVE_R
	ld a,(DS_TARGET)
	ret nz			; NC
	ld hl,DS_COUNT
	dec (hl)
	scf
	ret z
	jr NT_NEXT
DS_TARGET:	db 0
DS_COUNT:	db 0
DS_LEFT:	db 0

; BEHOLDER_ATTACK - one time in four its eyes hurt everybody, else a
;   fireball, a death spell or a disintegration ray
BEHOLDER_ATTACK:
	ld a,4
	call RND_RANGE
	cp 4
	jr z,.rays
	ld e,a
	ld d,0
	ld hl,BEHOLDER_SFX-1
	add hl,de
	ld a,(hl)
	call MC_SOUND
	ld hl,BEHOLDER_SPELLS-1
	add hl,de
	ld a,(hl)
	jp MON_CAST
.rays:	ld a,108
	call MC_SOUND
	xor a
.lp:	ld (DS_TARGET),a
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.nx
	ld a,(DS_TARGET)
	ld hl,STR_EYERAY
	call MSG_NAMED_M
	ld bc,0208h
	ld a,1
	call ROLL_DICE
	ld a,(DS_TARGET)
	call INFLICT_CHARACTER
.nx:	ld a,(DS_TARGET)
	inc a
	cp 6
	jr c,.lp
	ret
BEHOLDER_SPELLS:	db 2,10,11
BEHOLDER_SFX:	db 98,83,64

; MIND_BLAST - the mind flayer: everybody may be paralyzed
MIND_BLAST:
	ld hl,STR_MINDBLAST
	call MSG_PRINT
	xor a
.lp:	push af
	ld c,4
	ld e,1			; Mind Blast uses wands, not melee paralysis
	call STATUS_ATTACK_SAVE
	pop af
	inc a
	cp 6
	jr c,.lp
	ret

	include "rest.asm"

; SPELLS_GET / SPELLS_PUT - A = character, C = 0 mage / 1 cleric: its 50
;   entries to / from BOUNCE (for the memorize menu of the UI overlay)
SPELLS_GET:
	call SPELLS_AT
	ld de,BOUNCE
	ld bc,50
	ldir
	ret
SPELLS_PUT:
	call SPELLS_AT
	ex de,hl
	ld hl,BOUNCE
	ld bc,50
	ldir
	ret
SPELLS_AT:
	ld (BOOK_CHAR),a
	ld a,c
	ld (BOOK_TYPE),a
	xor a
	ld (BOOK_LEVEL),a
	jp BOOK_LIST


BOOK_CHAR:	db 0
BOOK_TYPE:	db 0
BOOK_LEVEL:	db 0
BOOK_SEL:	db 0
CAST_WHO:	db 0
ACTIVE_SPELL:	db 0
ACTIVE_CHAR:	db 0
CH_EVENTS:	ds 6*12		; per character 4 x (ticks u16, event)

	include "npc.asm"
	include "title.asm"
	include "useitem.asm"
	include "turn.asm"
	include "../build/magicdata.inc"


MAGIC_END:
	assert MAGIC_END <= 0C000h	; magic overlay too big
