; ============================================================================
; rest.asm - The rest of the camp menu (GUI_EoB::restParty, EOB1), in the
;            magic overlay: the spell lists (CH_SPELLS) are here
; Assembler: Sjasm 0.42c
;
; The original steps: 6 per hour; each one gives back a spell to whom has
; rested long enough (RS_CRS, 48 steps = 8 hours, then one more step per
; spell level), lets a healer cast his cure spells on the most injured, and
; moves the monsters five times. Each hour: the hours shown (160 ms), 10
; damage to the poisoned; each 8 hours: lay on hands for the paladins,
; 1 hit point and 5 food for whom has food. Texts and windows of the camp
; menu (UI overlay) through UCALL, with the text in TEXTBUF.
; ============================================================================

RS_STEPS:	equ 6		; steps per hour

; ----------------------------------------------------------------------------
; REST_PARTY -> NZ: the camp menu ends (monsters near, or nobody can act)
; ----------------------------------------------------------------------------
REST_PARTY:
	call RS_MONSTERS	; the monsters go first: one near, the warning
	ret nz
	call UCALL
	dw CM_WINDOW
	; a poisoned one: they will die, rest anyway?
	ld c,0
.po:	ld a,c
	call CHAR_PTR
	ld a,(iy+P_FLAGS)
	and 3
	cp 3
	jr z,.pq
	inc c
	ld a,c
	cp 6
	jr c,.po
	jr .np
.pq:	ld hl,RS_S_POISON
	call RS_CONFIRM
	ret z			; no: the camp menu again
.np:	xor a
	ld (RS_HEAL),a
	ld (RS_CONT),a
	ld (RS_STEP),a
	ld (RS_RES),a
	ld hl,0
	ld (RS_HOURS),hl
	ld hl,RS_CRS
	ld b,6
.cz:	ld (hl),a
	inc hl
	djnz .cz
	inc a
	ld (RS_LOOP),a
	call RS_LOWEST
	ld (RS_INJ),a
	or a
	jr z,.nh
	; a healer among them? (cleric or paladin, holy symbol, cure spells)
	ld c,0
.hc:	ld a,c
	ld (RS_C),a
	call CHAR_PTR
	call RS_CAN_ACT
	jr z,.hn
	call RS_CLERIC
	jr z,.hn
	ld a,30
	call RS_HAS
	jr z,.hn
	call RS_HAS_CURE
	jr z,.hn
	ld hl,RS_S_HEAL
	call RS_CONFIRM
	ld a,0
	jr z,.hs
	inc a
.hs:	ld (RS_HEAL),a
	jr .nh
.hn:	ld a,(RS_C)
	inc a
	ld c,a
	cp 6
	jr c,.hc
.nh:	; the message window cleared, the hours
	ld hl,RS_MSGCLR
	ld a,C_BLACK
	call V9_LMMV
	call RS_TIME_INIT
.loop:	ld hl,RS_STEP
	inc (hl)
	call RS_LEARN
	ld a,(RS_HEAL)
	or a
	call nz,RS_HEALERS
	ld a,(RS_STEP)
	cp RS_STEPS
	call z,RS_HOUR
	; the spells all back but still injured: rest until healed?
	call RS_TO_LEARN
	jr nz,.in
	ld a,(RS_LOOP)
	or a
	jr z,.in
	ld a,(RS_CONT)
	or a
	jr nz,.in
	ld a,(RS_INJ)
	or a
	jr z,.in
	ld hl,RS_S_CONT
	call RS_CONFIRM
	ld a,0
	jr z,.c0
	inc a
.c0:	ld (RS_CONT),a
	push af
	call RS_TIME_INIT
	pop af
	or a
	jr nz,.in
	ld (RS_LOOP),a
.in:	; a click or a key ends it
	call MOUSE_UPDATE
	ld a,(CLICK)
	or a
	jr nz,.stop
	call KEYS_READ
	or a
	jr z,.go
.stop:	xor a
	ld (RS_LOOP),a
.go:	ld a,(RS_LOOP)
	or a
	jr z,.end
	call RS_MONSTERS
	jr nz,.res
	call RS_STANDING
	jr nz,.end
.res:	ld a,1
	ld (RS_RES),a
.end:	call RS_TO_LEARN
	jr nz,.next
	ld a,(RS_CONT)
	ld hl,RS_HEAL
	or (hl)
	jr nz,.inj
	ld (RS_LOOP),a
.inj:	ld a,(RS_INJ)
	or a
	jr nz,.next
	ld (RS_LOOP),a
.next:	ld a,(RS_RES)
	or a
	jr nz,.out
	ld a,(RS_LOOP)
	or a
	jp nz,.loop
.out:	call SORT_SPELLS
	ld a,(RS_RES)
	or a
	ret nz
	ld a,(RS_INJ)
	or a
	jr nz,.z
	ld hl,RS_S_RESTED
	call RS_COPY
	call UCALL
	dw CM_TEXTBOX
.z:	xor a
	ret

; RS_HOUR - an hour has gone
RS_HOUR:
	call XCALL
	dw FX_REST
	xor a
	ld (RS_STEP),a
	ld hl,(RS_HOURS)
	inc hl
	ld (RS_HOURS),hl
	call RS_TIME
	; the poison: 10 damage
	ld c,0
.p:	ld a,c
	call CHAR_PTR
	ld a,(iy+P_FLAGS)
	and 3
	cp 3
	jr nz,.pn
	push bc
	ld a,c
	ld hl,10
	call INFLICT_CHARACTER
	ld b,5			; (delayWithTicks(5))
.pw:	call V9_WAIT_VBLANK
	djnz .pw
	pop bc
.pn:	inc c
	ld a,c
	cp 6
	jr c,.p
	; each 8 hours
	ld a,(RS_HOURS)
	and 7
	ret nz
	xor a
	ld (RS_STARVE),a
	ld c,a
.c:	ld a,c
	ld (RS_C),a
	call CHAR_PTR
	ld a,(iy+P_CLASS)	; a paladin: lay on hands again
	cp 2
	call z,RS_LAYON
	call RS_ALIVE
	jr z,.nx
	ld a,(iy+P_FOOD)
	or a
	jr z,.hungry
	ld a,(iy+P_HP)
	cp (iy+P_HPMAX)
	jp p,.full
	inc (iy+P_HP)
	ld a,(RS_C)
	call PANEL_DRAW
	ld a,(RS_C)
	call CHAR_PTR
.full:	call RS_SUSTAIN		; a ring of sustenance: no food
	jr z,.nx
	ld a,(iy+P_FOOD)
	cp 6
	jr nc,.food
	xor a
	ld (iy+P_FOOD),a
	inc a
	ld (RS_STARVE),a
	jr .nx
.food:	sub 5
	ld (iy+P_FOOD),a
	jr .nx
.hungry:
	ld hl,(RS_HOURS)	; each 24 hours: 1 damage
	ld a,24
	call DIV16_8
	or a
	jr nz,.nx
	ld a,1
	ld (RS_STARVE),a
	ld a,(RS_C)
	ld hl,1
	call INFLICT_CHARACTER
.nx:	ld a,(RS_C)
	inc a
	ld c,a
	cp 6
	jr c,.c
	ld a,(RS_STARVE)
	or a
	jr z,.inj
	ld hl,RS_S_STARVE
	call RS_CONFIRM
	jr nz,.goon
	xor a
	ld (RS_CONT),a
	ld (RS_LOOP),a
.goon:	call RS_TIME_INIT
.inj:	ld a,(RS_LOOP)
	or a
	call nz,RS_LOWEST
	ld (RS_INJ),a
	ret

; RS_LEARN - each character: a step more of rest; a spell may come back
RS_LEARN:
	xor a
.c:	ld (RS_C),a
	ld e,a
	ld d,0
	ld hl,RS_CRS
	add hl,de
	inc (hl)
	call CHAR_PTR
	ld a,(iy+P_FOOD)
	or a
	jr z,.n
	ld a,(iy+P_FLAGS)	; testCharacter(5): there, standing, not stone
	and 9
	cp 1
	jr nz,.n
	ld a,(iy+P_HP)
	dec a
	jp m,.n
	ld a,30			; the holy symbol: a cleric spell
	call RS_HAS
	ld a,1
	call nz,RS_LEARN1
	ld a,(RS_C)
	call CHAR_PTR
	ld a,29			; the spellbook: a mage spell
	call RS_HAS
	ld a,0
	call nz,RS_LEARN1
.n:	ld a,(RS_C)
	inc a
	cp 6
	jr c,.c
	ret

; RS_LEARN1 - A = 0 mage / 1 cleric list of RS_C: the first cast spell
;   whose level the rest allows comes back (crs > 48 + entry / 10, the mage
;   list / 6 as the original) and is told
RS_LEARN1:
	ld (RS_KIND),a
	call RS_LIST		; HL = list
	ld de,(RS_C)
	ld d,0
	ld ix,RS_CRS
	add ix,de
	ld c,0			; entry
.e:	ld a,(RS_KIND)
	or a
	ld a,c
	ld b,6
	jr z,.dv
	ld b,10
.dv:	; A = entry / B
	ld e,0
.d:	sub b
	jr c,.q
	inc e
	jr .d
.q:	ld a,e
	add a,48
	cp (ix+0)
	ret nc			; (48 + entry / n >= crs: not yet)
	ld a,(hl)
	or a
	jp p,.nx
	neg
	ld (hl),a
	ld (ix+0),48
	; "<name> obtiene <spell>." (cleric) / "memoriza" (mage)
	ld b,a
	ld a,(RS_KIND)
	or a
	ld a,b
	jr z,.m
	add a,CLERIC_OFS
.m:	call SPELL_NAME_TB	; TEXTBUF = the name of the spell
	ld a,(RS_KIND)
	xor 1			; RS_F0 cleric, RS_F1 mage
	ld de,TEXTBUF
	call RS_FORMAT
	ld b,5			; (delay(80))
	jp RS_MSG
.nx:	inc hl
	inc c
	ld a,c
	cp 50
	jr c,.e
	ret

; RS_HEALERS - (useHealers) a cleric or paladin with his cure spells ready
;   casts them on the most injured (RS_INJ); one with a cure spell coming
;   back (crs >= 48) ends this step
RS_HEALERS:
	xor a
.c:	ld (RS_C),a
	ld a,(RS_INJ)
	or a
	ret z
	ld a,(RS_C)
	call CHAR_PTR
	call RS_CLERIC
	jp z,.n
	ld a,30
	call RS_HAS
	jp z,.n
	ld a,1
	ld (RS_KIND),a
	ld de,(RS_C)
	ld d,0
	ld hl,RS_CRS
	add hl,de
	ld a,(hl)
	cp 48
	jr c,.ready
	call RS_LIST		; a cast cure spell: it comes back first
	ld b,50
.f:	ld a,(hl)
	cp -2
	ret z
	cp -15
	ret z
	cp -20
	ret z
	inc hl
	djnz .f
.ready:	call RS_LIST
	ld b,50
.e:	push bc
	push hl
	ld a,(hl)
	ld bc,0108h		; 1d8
	ld e,0
	cp 2
	jr z,.heal
	ld bc,0208h		; 2d8 + 1
	ld e,1
	cp 15
	jr z,.heal
	ld bc,0308h		; 3d8 + 3
	ld e,3
	cp 20
	jr nz,.ne
.heal:	neg
	ld (hl),a		; cast
	ld a,e
	call ROLL_DICE		; HL = hit points
	ld (RS_HP),hl
	ld de,(RS_C)
	ld d,0
	ld hl,RS_CRS
	add hl,de
	ld (hl),0
	; "<healer> cura a <injured>."
	ld a,(RS_INJ)
	dec a
	call CHAR_PTR
	push iy
	pop hl
	inc hl			; P_NAME
	ld de,TEXTBUF
	ld bc,10
	ldir
	xor a
	ld (de),a
	ld a,(RS_C)
	call CHAR_PTR
	ld a,2
	call RS_FORMAT
	ld b,5
	call RS_MSG
	; Use the same signed, widened heal as ordinary spells. Comparing the
	; wrapped byte with HPMAX can turn a small cure at -9 HP into full HP.
	ld a,(RS_HP)
	ld c,a
	ld a,(RS_INJ)
	dec a
	call HEAL_CHAR
.ne:	pop hl
	pop bc
	inc hl
	djnz .e
.n:	ld a,(RS_C)
	inc a
	cp 6
	jp c,.c
	ret
RS_CURES:	db 2, 15, 20	; cure light, serious, critical wounds

; RS_LAYON - IY = a paladin: lay on hands (24) back in his first level
RS_LAYON:
	ld a,1
	ld (RS_KIND),a
	call RS_LIST
	ld b,10
	push hl
.f:	ld a,(hl)
	cp 24
	jr z,.got
	cp -24
	jr z,.got
	inc hl
	djnz .f
	pop hl
	ld b,10
.z:	ld a,(hl)
	or a
	jr z,.set
	inc hl
	djnz .z
	ret
.got:	pop af
.set:	ld (hl),24
	ret

; RS_LIST - IY = character, (RS_KIND) 0 mage / 1 cleric -> HL = its list
;   (CH_SPELLS + character * 100, + 50 for the cleric one). Preserves DE.
RS_LIST:
	push de
	push iy
	pop hl
	ld de,PARTY
	or a
	sbc hl,de		; character * 128
	add hl,hl		; H = character
	ld l,h
	ld h,0
	add hl,hl
	add hl,hl		; * 4
	ld e,l
	ld d,h
	add hl,hl
	add hl,hl
	add hl,hl		; * 32
	ld b,h
	ld c,l
	add hl,hl		; * 64
	add hl,bc
	add hl,de		; * 100
	ld de,CH_SPELLS
	add hl,de
	ld a,(RS_KIND)
	or a
	jr z,.m
	ld de,50
	add hl,de
.m:	pop de
	ret

; RS_FORMAT - A = format (0 obtiene / 1 memoriza / 2 cura a), IY = the
;   first character, TEXTBUF = the second part -> RS_BUF = the message
RS_FORMAT:
	add a,a
	ld e,a
	add a,a
	add a,e			; * 6
	ld e,a
	ld d,0
	ld hl,RS_FMTS
	add hl,de
	ld de,RS_BUF
	call .part
	push hl
	push iy
	pop hl
	inc hl			; P_NAME
	ld b,10
.nm:	ld a,(hl)
	or a
	jr z,.ne
	ld (de),a
	inc hl
	inc de
	djnz .nm
.ne:	pop hl
	call .part
	push hl
	ld hl,TEXTBUF
	call RS_CAT
	pop hl
	call .part
	xor a
	ld (de),a
	ret
.part:	ld a,(hl)
	inc hl
	push hl
	ld h,(hl)
	ld l,a
	call RS_CAT
	pop hl
	inc hl
	ret
RS_FMTS:	dw RS_F0_0, RS_F0_1, RS_F0_2, RS_F1_0, RS_F1_1, RS_F1_2, RS_F2_0, RS_F2_1, RS_F2_2

; RS_CAT - HL = text -> DE (without its end)
RS_CAT:	ld a,(hl)
	or a
	ret z
	ld (de),a
	inc hl
	inc de
	jr RS_CAT

; RS_MSG - RS_BUF in the message window (FONT6), then B frames
RS_MSG:	push bc
	call TEXT_FONT6
	ld hl,RS_BUF
	call MSG_PRINT
	call TEXT_FONT8
	pop bc
.w:	call V9_WAIT_VBLANK
	djnz .w
	ret

; RS_MONSTERS - the monsters move five times (restParty_updateMonsters)
;   -> NZ: one came near, warned
RS_MONSTERS:
	call WCALL
	dw W_REST_MONSTERS
	ret z
	call TEXT_FONT6
	ld hl,RS_S_NEAR
	call MSG_PRINT
	call TEXT_FONT8
	or 1
	ret

; RS_TIME_INIT / RS_TIME - the window with "Descansar grupo." and the hours
;   (restParty_updateRestTime); RS_TIME waits 160 ms
RS_TIME_INIT:
	call UCALL
	dw CM_WINDOW
	ld hl,RS_S_TITLE
	call RS_COPY
	ld hl,TEXTBUF
	ld de,8
	ld c,5
	ld a,C_LIGHTBLUE
	call UCALL
	dw SHADED_TEXT
RS_TIME:
	ld de,8
	ld c,20
	ld b,152
	ld l,10
	ld a,C_FILL
	call FILL_RECT
	ld hl,RS_S_HOURS
	call RS_COPY		; DE = its end
	ld hl,(RS_HOURS)
	call RS_NUM
	ld hl,TEXTBUF
	ld de,8
	ld c,20
	ld a,C_WHITE
	call UCALL
	dw SHADED_TEXT
	ld b,10
.w:	call V9_WAIT_VBLANK
	djnz .w
	ret

; RS_NUM - HL = number -> its digits at DE (with the end)
RS_NUM:	ld bc,RS_NUMB+5
	xor a
	ld (bc),a
.d:	push bc
	ld a,10
	push de
	call DIV16_8
	pop de
	pop bc
	dec bc
	add a,'0'
	ld (bc),a
	ld a,h
	or l
	jr nz,.d
	ld h,b
	ld l,c
.c:	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	or a
	jr nz,.c
	ret
RS_NUMB:	ds 6

; RS_COPY - HL = text -> TEXTBUF (with the end); HL = TEXTBUF, DE = the end
RS_COPY:
	ld de,TEXTBUF
.c:	ld a,(hl)
	ld (de),a
	inc hl
	or a
	jr z,.e
	inc de
	jr .c
.e:	ld hl,TEXTBUF
	ret

; RS_CONFIRM - HL = question -> NZ for yes (confirmDialogue of the camp)
RS_CONFIRM:
	call RS_COPY
	ld hl,TEXTBUF
	call UCALL
	dw CM_CONFIRM
	ret

; RS_LOWEST -> A = 1 + the living character with fewest hit points under
;   his maximum, 0 none (restParty_getCharacterWithLowestHp)
RS_LOWEST:
	ld bc,0FFFFh		; B = the best so far (-1), C = its hit points + 128
	ld e,0
.c:	ld a,e
	call CHAR_PTR
	call RS_ALIVE
	jr z,.n
	ld a,(iy+P_HPMAX)
	xor 80h
	ld d,a
	ld a,(iy+P_HP)
	xor 80h			; (signed compares as unsigned + 128)
	cp d
	jr nc,.n		; not injured
	cp c
	jr nc,.n		; not fewer
	ld c,a
	ld b,e
.n:	inc e
	ld a,e
	cp 6
	jr c,.c
	ld a,b
	inc a
	ret

; RS_ALIVE - IY = character -> NZ: there, above -10, not stone
;   (testCharacter(3))
RS_ALIVE:
	ld a,(iy+P_FLAGS)
	and 9
	cp 1
	jr nz,.no
	ld a,(iy+P_HP)
	xor 80h
	cp 77h			; hit points > -10 (-9 + 128)
	jr c,.no
	or 1
	ret
.no:	xor a
	ret

; RS_CAN_ACT - IY = character -> NZ: there, standing, not paralysed nor
;   stone (testCharacter(13))
RS_CAN_ACT:
	ld a,(iy+P_FLAGS)
	and 0Dh
	cp 1
	jr nz,.no
	ld a,(iy+P_HP)
	dec a
	jp m,.no
	or 1
	ret
.no:	xor a
	ret

; RS_STANDING -> NZ: somebody can act (checkPartyStatus)
RS_STANDING:
	ld c,0
.c:	ld a,c
	call CHAR_PTR
	call RS_CAN_ACT
	ret nz
	inc c
	ld a,c
	cp 6
	jr c,.c
	xor a
	ret

; RS_CLERIC - IY = character -> NZ: a cleric or a paladin class
;   (getCharacterLevelIndex 2 or 4)
RS_CLERIC:
	ld a,2
	call RS_CTYPE
	ret nz
	ld a,4
; RS_CTYPE - IY = character, A = class type -> NZ: his class has it
RS_CTYPE:
	ld c,a
	ld a,(iy+P_CLASS)
	ld b,a
	add a,a
	add a,b
	ld e,a
	ld d,0
	ld hl,RS_CLASS_TYPE
	add hl,de
	ld b,3
.t:	ld a,(hl)
	cp c
	jr z,.y
	inc hl
	djnz .t
	xor a
	ret
.y:	or 1
	ret
RS_CLASS_TYPE:
	db 0,-1,-1,5,-1,-1,4,-1,-1,1,-1,-1,2,-1,-1,3,-1,-1,0,2,-1,0,3,-1,0,1,-1,0,1,3,3,1,-1,2,3,-1,0,2,1,5,2,-1,2,1,-1

; RS_HAS - IY = character, A = item type -> NZ: one in his inventory
;   (checkInventoryForItem)
RS_HAS:
	ld (RS_TYPE),a
	ld c,0
.s:	ld a,c
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.n
	call ITEM_IX
	ld a,(RS_TYPE)
	cp (ix+I_TYPE)
	jr z,.y
.n:	inc c
	ld a,c
	cp 27
	jr c,.s
	xor a
	ret
.y:	or 1
	ret

; RS_SUSTAIN - IY = character -> Z: a ring of sustenance on a finger
;   (checkInventoryForRings(.., 2): type 47, value 2)
RS_SUSTAIN:
	ld a,25
	call .ring
	ret z
	ld a,26
.ring:	call SLOT_PTR
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

; RS_HAS_CURE - IY = character -> NZ: a cure spell in his list, cast or
;   not (restParty_checkHealSpells)
RS_HAS_CURE:
	ld a,1
	ld (RS_KIND),a
	call RS_LIST
	ld b,50
.e:	ld a,(hl)
	or a
	jp p,.p
	neg
.p:	cp 2
	jr z,.y
	cp 15
	jr z,.y
	cp 20
	jr z,.y
	inc hl
	djnz .e
	xor a
	ret
.y:	or 1
	ret

; RS_TO_LEARN -> NZ: a spell still has to come back to somebody who rests
;   for it (restParty_checkSpellsToLearn)
RS_TO_LEARN:
	xor a
.c:	ld (RS_C2),a
	call CHAR_PTR
	call RS_ALIVE		; testCharacter(0x43): and food
	jr z,.n
	ld a,(iy+P_FOOD)
	or a
	jr z,.n
	call RS_CLERIC
	jr z,.mg
	ld a,30
	call RS_HAS
	jr z,.mg
	ld a,1
	call .cast
	ret nz
.mg:	ld a,1
	call RS_CTYPE
	jr z,.n
	ld a,29
	call RS_HAS
	jr z,.n
	xor a
	call .cast
	ret nz
.n:	ld a,(RS_C2)
	inc a
	cp 6
	jr c,.c
	xor a
	ret
.cast:	ld (RS_KIND),a
	call RS_LIST
	ld b,50
.e:	ld a,(hl)
	or a
	jp m,.y
	inc hl
	djnz .e
	xor a
	ret
.y:	or 1
	ret

; SORT_SPELLS - every list of the party: ready spells first (by number),
;   then the cast ones, the empty entries last (sortCharacterSpellList)
SORT_SPELLS:
	ld hl,CH_SPELLS
	ld b,60			; 6 characters x 2 kinds x 5 levels
.lv:	push bc
	push hl
.pass:	pop hl
	push hl
	ld b,9
	ld c,0			; swapped
.cmp:	ld a,(hl)
	call .key
	ld d,a
	inc hl
	ld a,(hl)
	call .key
	cp d
	jr nc,.ok
	ld a,(hl)		; swap
	dec hl
	ld e,(hl)
	ld (hl),a
	inc hl
	ld (hl),e
	ld c,1
.ok:	djnz .cmp
	ld a,c
	or a
	jr nz,.pass
	pop hl
	ld de,10
	add hl,de
	pop bc
	djnz .lv
	ret
.key:	or a			; 0 -> 80, < 0 -> 40 - n, > 0 -> n
	jr nz,.k1
	ld a,80
	ret
.k1:	ret p
	neg
	add a,40
	ret

RS_MSGCLR:	dw SCREEN_X+MSG_X, SCREEN_Y+MSG_Y, MSG_W, 18
RS_HOURS:	dw 0
RS_HP:		dw 0
RS_CRS:		ds 6
RS_C:		db 0
RS_C2:		db 0
RS_KIND:	db 0
RS_TYPE:	db 0
RS_STEP:	db 0
RS_LOOP:	db 0
RS_RES:		db 0
RS_INJ:		db 0
RS_HEAL:	db 0
RS_CONT:	db 0
RS_STARVE:	db 0
RS_BUF:		ds 64
