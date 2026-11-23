; ============================================================================
; turn.asm - clerics and paladins with a holy symbol in hand turn the undead
;   ahead by themselves (EoBEngine::turnUndeadAuto, levels 2 and 7; part of
;   the MAGIC overlay). The monsters are worked on in a copy in BOUNCE.
; ============================================================================
TU_HOLY:	equ 6		; extra properties of a holy symbol

; LEVEL_TICK - DOS EOB.EXE E35Ah..E42Dh schedules against the game clock.
; A due sound waits for the sewers; the first deadline is random as well.
LEVEL_TICK:
	ld hl,(AMB_TIMER)
	ld a,h
	or l
	jr z,.due
	dec hl
	ld (AMB_TIMER),hl
	jr .turn
.due:	ld a,(CUR_LEVEL)
	cp 4
	jr nc,.turn
	call AMB_RESET
	ld a,12
	call RND_RANGE
	dec a
	ld e,a
	ld d,0
	ld hl,(CUR_BLOCK)
	add hl,de
	ld a,h
	and 3
	ld h,a
	ld a,30
	call ENV_SOUND
.turn:	ld a,(CUR_LEVEL)
	cp 2
	jr z,TURN_AUTO
	cp 7
	ret nz
	jr TURN_AUTO

AMB_RESET:
	ld bc,010Ah		; (1d10 + 3) * 18 ticks
	ld a,3
	call ROLL_DICE
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,de
	add hl,hl
	ld (AMB_TIMER),hl
	ret
AMB_TIMER:	dw 0

TURN_AUTO:
	; the best turner: cleric level, or paladin level - 2
	xor a
	ld (TU_LEVEL),a
	ld c,0
.ch:	ld a,c
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.nc
	ld a,(iy+P_HP)
	dec a
	jp m,.nc
	ld a,(iy+P_FLAGS)
	and 0Ch			; paralyzed, stone
	jr nz,.nc
	call TU_SYMBOL
	jr nz,.nc
	ld a,c
	ld (MZ_CHAR_M),a
	push bc
	ld c,2			; cleric
	call TU_CLASS
	jr nz,.lv
	ld c,4			; paladin
	call TU_CLASS
	sub 2
	jr c,.nlv
	jr z,.nlv
.lv:	ld hl,TU_LEVEL
	cp (hl)
	jr c,.nlv
	jr z,.nlv
	ld (hl),a
	ld a,(MZ_CHAR_M)
	ld (TU_CHAR),a
.nlv:	pop bc
.nc:	inc c
	ld a,c
	cp 6
	jr c,.ch
	ld a,(TU_LEVEL)
	or a
	ret z
	; monsters ahead?
	ld a,(CUR_DIR)
	call BLOCK_AHEAD
	ld (TU_BLOCK),hl
	call BLOCKCNT_PTR
	ld de,BOUNCE
	ld bc,1
	call WCALL
	dw W_LDIR
	ld a,(BOUNCE)
	or a
	ret z
	ld hl,LEVELDAT+D_MONSTERS
	ld de,BOUNCE
	ld bc,30*MON_SIZE
	call WCALL
	dw W_LDIR
	ld a,20
	call RND_RANGE
	ld (TU_ROLL),a
	xor a
	ld (TU_HIT),a
	ld (TU_KILL),a
	ld ix,BOUNCE
	ld b,30
.mon:	push bc
	ld hl,(TU_BLOCK)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.nm
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.nm
	bit 4,(ix+M_FLAGS)	; once only
	jr nz,.nm
	call TU_PROPS		; IY = its properties
	bit 2,(iy+MP_TFLAGS)	; undead
	jr z,.nm
	set 4,(ix+M_FLAGS)
	call TU_HITM
.nm:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .mon
	; the copy back, then those destroyed
	ld hl,BOUNCE
	ld de,LEVELDAT+D_MONSTERS
	ld bc,30*MON_SIZE
	call WCALL
	dw W_LDIR
	ld a,(TU_KILL)
	or a
	jr z,.nk
	ld b,a
	ld hl,TU_KILLS
.k:	push bc
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	push hl
	push de
	pop ix
	ld de,500
	call WCALL
	dw INFLICT_MONSTER
	pop hl
	pop bc
	djnz .k
.nk:	ld a,(TU_HIT)
	or a
	ret z
	ld a,1
	ld (SCENE_DIRTY),a
	ld a,95
	call SFX_PLAY
	ld a,(TU_CHAR)
	ld hl,STR_TURN
	jp MSG_NAMED_M

; TU_HITM - IX = undead monster (copy), IY = its properties (turnUndeadHit)
TU_HITM:
	ld a,(iy+25)		; turn undead resistance
	ld l,a
	ld h,0
	add hl,hl
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,hl		; * 16
	or a
	sbc hl,de		; * 14 (16 - 2)
	ld a,(TU_LEVEL)
	cp 15
	jr c,.l
	ld a,14
.l:	ld e,a
	ld d,0
	add hl,de
	ld de,TU_EFFECT
	add hl,de
	ld a,(hl)
	cp 0FFh
	jr z,.kill
	ld c,a
	ld a,(TU_ROLL)
	cp c
	ret c			; resisted
	ld (ix+M_MODE),0	; it flees
	set 3,(ix+M_FLAGS)
	ld (ix+M_SPELL),40
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(CUR_BLOCK)
	call NEXT_MONSTER_DIR
	xor 4
	srl a
	and 3
	ld (ix+M_DIR),a
	jr .hit
.kill:	ld a,(TU_KILL)		; destroyed (after the copy goes back)
	cp 8
	jr nc,.hit
	add a,a
	ld e,a
	ld d,0
	ld hl,TU_KILLS
	add hl,de
	push ix
	pop de
	push hl
	ld hl,LEVELDAT+D_MONSTERS-BOUNCE
	add hl,de
	ex de,hl
	pop hl
	ld (hl),e
	inc hl
	ld (hl),d
	ld hl,TU_KILL
	inc (hl)
.hit:	ld a,1
	ld (TU_HIT),a
	ret

; TU_PROPS - IX = monster -> IY = its properties (MONPROPS, 27 bytes each)
TU_PROPS:
	ld a,(ix+M_TYPE)
	ld l,a
	ld h,0
	ld e,l
	ld d,h
	add hl,hl
	add hl,de		; 3
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,hl		; 24
	add hl,de		; 27
	ld de,MONPROPS
	add hl,de
	push hl
	pop iy
	ret

; TU_SYMBOL - IY = character: Z if a hand holds a holy symbol
TU_SYMBOL:
	push bc
	ld b,2
	push iy
	pop hl
	ld de,P_INV
	add hl,de
.h:	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,d
	or e
	jr z,.n
	push hl
	ex de,hl
	push iy
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	pop iy
	ld a,(hl)
	pop hl
	cp TU_HOLY
	jr z,.y
.n:	djnz .h
	or 1
.y:	pop bc
	ret

; TU_CLASS - MZ_CHAR_M = candidate, C = class type -> A = level or zero, NZ.
; The class-composition table belongs to UI (ST_CTYPE is in SCRIPT).
; Resolve through the existing bank-safe helper rather than reading another
; overlay's address while MAGIC is mapped.
TU_CLASS:
 ld a,(MZ_CHAR_M)
 call XCALL
 dw FX_CLASS_LEVEL
 or a
 ret

TU_LEVEL:	db 0
TU_CHAR:	db 0
MZ_CHAR_M:	db 0
TU_BLOCK:	dw 0
TU_ROLL:	db 0
TU_HIT:		db 0
TU_KILL:	db 0
TU_KILLS:	ds 16

; ----------------------------------------------------------------------------
; PARTY_CHECK - per tick: nobody can act (testCharacter 13 for all,
;   checkPartyStatus): the defeat message, then the last saved game, or DOS
; ----------------------------------------------------------------------------
PARTY_CHECK:
	ld c,0
.lp:	ld a,c
	call CHAR_PTR
	ld a,(iy+P_FLAGS)
	and 0Dh			; active, not paralyzed, not stone
	cp 1
	jr nz,.n
	ld a,(iy+P_HP)
	dec a
	ret p			; one standing: nothing
.n:	inc c
	ld a,c
	cp 6
	jr c,.lp
	call PANEL_DRAW_ALL
	call DLG_BOX
	xor a
	ld (TF_MORE),a
	ld hl,STR_DEFEAT
	call DLG_TEXT
	call DLG_CLICK
	call WCALL
	dw LOAD_GAME
	ret z			; a saved game goes on
	ld a,1
	ld (QUIT_REQ),a
	ret
