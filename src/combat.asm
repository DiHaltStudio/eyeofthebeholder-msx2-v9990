; ============================================================================
; combat.asm - Melee: the party hits (useSlotWeapon, closeDistanceAttack,
;              characterAttackHitTest, calcMonsterDamage) and the monsters
;              hit back (monsterCloseAttack, monsterAttackHitTest)
; Assembler: Sjasm 0.42c
;
; Slot status (P_STATUS0/1): damage done (> 0) or -1 miss, -2 hack,
;   -3 out of reach, -4 no ammunition; shown on the hand slot until the
;   slot timer (18 ticks) runs out.
; ============================================================================

SLOT_TICKS:	equ 18
DAMAGE_TICKS:	equ 18

; ----------------------------------------------------------------------------
; PARTY_ATTACK - A = character * 2 + hand slot
; ----------------------------------------------------------------------------
PARTY_ATTACK:
	ld c,a
	and 1
	ld (CB_SLOT),a
	ld a,c
	srl a
	ld (CB_CHAR),a
	call CHAR_PTR		; IY = character
	bit 0,(iy+P_FLAGS)
	ret z
	ld a,(iy+P_FLAGS)
	and 0Ch			; paralyzed or turned to stone
	ret nz
	ld a,(iy+P_HP)
	dec a
	ret m			; unconscious or dead
	; the slot must be ready
	ld a,(CB_SLOT)
	inc a
	ld b,a
	ld a,(iy+P_DISABLED)
.bit:	rrca
	djnz .bit
	ret c
	call XCALL
	dw FX_WEAPON_VALID
	ret z
	bit 6,(iy+P_EFFECT)	; an invisible character is seen again
	jr z,.vis
	ld a,(CB_CHAR)
	ld c,a
	ld a,8			; (removeCharacterEffect(8, ..))
	call MCALL
	dw EVENT_END
	ld a,(CB_CHAR)
	call CHAR_PTR
.vis:
	; the item in that hand (none: item type 0)
	ld a,(CB_SLOT)
	call HAND_ITEM
	ld (CB_ITEM),hl
	ld bc,0
	ld a,h
	or l
	jr z,.tp
	call ITEM_IX
	ld b,(ix+I_TYPE)
	ld c,(ix+I_VALUE)
.tp:	ld a,c
	ld (CB_VALUE),a
	ld a,b
	ld (CB_TYPE),a
	call ITEMTYPE_PTR	; HL = item type entry
	ld a,(hl)		; extra properties
	cp 2
	jr z,.thrown
	cp 3
	jr z,.missile
	cp 5
	jr z,.book
	cp 6
	jr z,.book
	cp 1
	jr z,.melee
	call MCALL		; scrolls, potions, wands, letters...
	dw USE_ITEM
	ret
.melee:	call CLOSE_ATTACK	; A = result
	push af
	ld a,32			; the swing
	call SFX_PLAY
	pop af
	or a
	jr nz,.r
	dec a			; 0 -> -1 (miss)
	jr .r
.thrown:
	call THROWN_ATTACK
	jr .r
.book:	; spellbook (5) or holy symbol (6): the book opens (not over the
	; inventory)
	sub 5
	ld c,a
	ld a,(CONTROL_MODE)
	or a
	ret nz
	ld a,(CB_CHAR)
	call MCALL
	dw BOOK_SHOW
	ret
.missile:
	call MISSILE_ATTACK
.r:	ld (CB_RESULT),a
	or a
	jp m,.noinflict
	jr z,.noinflict
	call MAGIC_HAND
	ld ix,(CB_MONSTER)
	ld e,a
	ld d,0
	call INFLICT_MONSTER
.noinflict:
	; disable the slot and show the result for SLOT_TICKS
	ld a,(CB_CHAR)
	call CHAR_PTR
	call XCALL
	dw FX_ATTACK_PHASE
	ld b,SLOT_TICKS
	ld a,(CB_SLOT)
	or a
	ld a,(CB_RESULT)
	jr nz,.s1
	ld (iy+P_STATUS0),a
	ld (iy+P_TIMER0),b
	set 0,(iy+P_DISABLED)
	jr .draw
.s1:	ld (iy+P_STATUS1),a
	ld (iy+P_TIMER1),b
	set 1,(iy+P_DISABLED)
.draw:	ld a,(CB_CHAR)
	jp PANEL_DRAW

; MAGIC_HAND - A = damage done with the hand item: vampiric touch (item flag
;   8) heals the attacker that much, shocking grasp (10h) is spent
;   (useSlotWeapon). Preserves A.
MAGIC_HAND:
	push af
	ld hl,(CB_ITEM)
	ld a,h
	or l
	jr z,.r
	call ITEM_IX
	ld a,(CB_CHAR)
	call CHAR_PTR
	bit 3,(ix+I_FLAGS)
	jr z,.ns
	pop af
	push af
	call XCALL
	dw FX_TEMP_HP
.ns:	bit 4,(ix+I_FLAGS)
	jr z,.r
	ld (ix+I_BLOCK),0FEh	; free for another magic weapon
	ld (ix+I_BLOCK+1),0FFh
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld de,IT_AC
	add hl,de
	ld (hl),-30
	ld a,(CB_SLOT)
	call SLOT_PTR
	xor a
	ld (hl),a
	inc hl
	ld (hl),a
.r:	pop af
	ret

; CLOSE_ATTACK -> A = damage (> 0) or negative status
CLOSE_ATTACK:
	ld a,(CB_CHAR)
	cp 2
	ld a,-3
	ret nc			; only the front row reaches
	ld hl,(CUR_BLOCK)
	ld a,(CUR_DIR)
	call NEW_BLOCK_POS
	call CLOSEST_MONSTER	; IX = monster or carry
	jr nc,.mon
	; nobody there: a web (special wall FFh) gets cut
	ld hl,(CB_BLOCK)
	ld a,(SIDE_D)
	call BLOCK_WALL
	ld c,a
	ld h,(LEVELDAT+D_WSPECIAL)>>8
	ld l,a
	ld a,(hl)
	inc a
	ld a,-1
	ret nz
	inc c
	ld hl,(CB_BLOCK)
	ld a,(SIDE_D)
	push bc
	call W_SET_WALL
	pop bc
	ld a,(SIDE_D)
	xor 2
	call W_SET_WALL
	call DIRTY
	ld a,-2
	ret
.mon:	ld (CB_MONSTER),ix
	call HIT_TEST
	ld a,-1
	ret c
	jp CALC_MONSTER_DAMAGE

; CLOSEST_MONSTER - HL = block -> IX = closest monster to (CB_CHAR), C if none
CLOSEST_MONSTER:
	ld (CB_BLOCK),hl
	; monsters by position
	ld hl,CB_POSMON
	ld b,10
	xor a
.clr:	ld (hl),a
	inc hl
	djnz .clr
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	ld hl,(CB_BLOCK)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.n
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.n
	ld a,(ix+M_POS)
	add a,a
	ld e,a
	ld d,0
	ld hl,CB_POSMON
	add hl,de
	push ix
	pop de
	ld (hl),e
	inc hl
	ld (hl),d
.n:	ld de,MON_SIZE
	add ix,de
	djnz .lp
	; the centre first, then the proximity order of the character's side
	ld hl,(CB_POSMON+8)
	ld a,h
	or l
	jr nz,.found
	ld a,(CUR_DIR)
	add a,a
	add a,a
	ld c,a
	ld a,(CB_CHAR)
	and 1
	add a,a			; 2 * front-row side, NOT 4
	add a,c
	add a,a			; dir * 8 + side * 4: eight groups of four
	ld e,a
	ld d,0
	ld hl,MON_PROXIMITY
	add hl,de
	ld b,4
.pr:	ld a,(hl)
	add a,a
	ld e,a
	ld d,0
	push hl
	ld hl,CB_POSMON
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	pop hl
	ld a,d
	or e
	jr nz,.fde
	inc hl
	djnz .pr
	scf
	ret
.fde:	ex de,hl
.found:	push hl
	pop ix
	or a
	ret

; HIT_TEST - characterAttackHitTest for (CB_CHAR) vs IX -> NC if hit
HIT_TEST:
	call MON_PROPS
	ld a,(iy+MP_AC)
	ld (CB_MAC),a
	set 0,(ix+M_FLAGS)
	ld a,(CB_CHAR)
	call CHAR_PTR
	; d = item value for types 1..3, + strength hit modifier
	ld c,0
	ld hl,(CB_ITEM)
	ld a,h
	or l
	jr z,.d
	ld a,(CB_TYPE)
	or a
	jr z,.d
	cp 4
	jr nc,.d
	ld a,(CB_VALUE)
	ld c,a
.d:	ld a,(CB_FLY)
	or a
	jr nz,.dex
	call STR_HIT_MOD	; A (melee: strength)
	jr .dm
.dex:	ld a,(iy+P_DEX)		; thrown: dexterity
	dec a
	cp 19
	jr c,.dx
	ld a,18
.dx:	ld e,a
	ld d,0
	ld hl,DEX_HIT_TAB
	add hl,de
	ld a,(hl)
.dm:	add a,c
	ld c,a
	; m = 20 - ((level - 1) / T1[cm]) * T2[cm] - monster AC - d
	ld a,(iy+P_CLASS)
	ld e,a
	ld d,0
	ld hl,CLASS_MODIFIER
	add hl,de
	ld e,(hl)
	ld hl,AC_HIT_T1
	add hl,de
	ld a,(hl)
	push af
	ld hl,AC_HIT_T2
	add hl,de
	ld b,(hl)
	ld a,(iy+P_LEVEL)
	dec a
	ld l,a
	ld h,0
	pop af
	push bc
	call DIV16_8		; L = (level - 1) / T1
	pop bc
	ld a,l
	ld e,b
	call MUL8		; HL = .. * T2
	ld a,20
	sub l
	ld hl,CB_MAC
	sub (hl)
	sub c
	ld c,a			; m
	ld a,20
	call RND_RANGE		; s = 1d20
	ld b,a
	ld a,(PARTY_EFFECTS+1)	; Bless or Prayer: one shared +1, never stacked
.party_bonus:
	and 84h
	jr z,.nb
	inc b
.nb:	bit 6,(iy+P_EFFECT)	; invisible (40h): + 1
	jr z,.ni
	inc b
.ni:	ld a,b
	cp 21			; at most 20
	jr c,.s
	ld a,20
.s:	cp c			; s >= m ?
	jr nc,.hit
	; signed: m may be <= 0 or > 20
	bit 7,c
	jr nz,.hit
	scf
	ret
.hit:	or a
	ret

; CALC_MONSTER_DAMAGE - calcMonsterDamage + calcDamageModifers -> A
CALC_MONSTER_DAMAGE:
	xor a
	ld (CB_DMG),a
	ld a,(CB_FLY)
	or a
	jr nz,.nostr		; thrown: no strength bonus
	ld a,(CB_CHAR)
	call CHAR_PTR
	call STR_DMG_MOD
	ld (CB_DMG),a
.nostr:
	ld ix,(CB_MONSTER)
	call MON_PROPS
	ld hl,(CB_ITEM)
	ld a,h
	or l
	jr nz,.item
	ld b,1
	ld c,2
	xor a
	call ROLL_DICE		; bare hands: 1d2
	jr .sum
.item:	ld a,(CB_TYPE)
	call ITEMTYPE_PTR
	inc hl
	bit 0,(iy+MP_CAPS)	; large monster: the large dice
	jr z,.small
	ld b,(hl)		; n (small)
	inc hl
	inc hl
	ld a,(hl)		; inc (small: the original uses it for both)
	inc hl
	ld b,(hl)		; n (large)
	inc hl
	ld c,(hl)		; pips (large)
	jr .roll
.small:	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld a,(hl)
.roll:	call ROLL_DICE
	ld a,(CB_VALUE)
	ld e,a
	rla
	sbc a,a
	ld d,a
	add hl,de		; + item value
.sum:	ld a,(CB_DMG)
	ld e,a
	rla
	sbc a,a
	ld d,a
	add hl,de
	bit 7,h
	jr z,.pos
	ld hl,0
.pos:	; a flying item that is not ammunition (or a launcher) does 1
	ld a,(CB_FLY)
	or a
	jr z,.half
	ld a,(CB_TYPE)
	push hl
	call ITEMTYPE_PTR
	ld a,(hl)
	pop hl
	cp 2
	jr z,.half
	cp 3
	jr z,.half
	ld hl,1
.half:	; edged weapons do half damage to some monsters (capsFlags 4)
	ld de,(CB_ITEM)
	ld a,d
	or e
	jr z,.done
	bit 2,(iy+MP_CAPS)
	jr z,.done
	push hl
	ld a,(CB_TYPE)
	call ITEMTYPE_PTR
	ld de,7
	add hl,de
	bit 2,(hl)
	pop hl
	jr nz,.done
	srl h
	rr l
.done:	ld a,h
	or a
	ld a,l
	ret z
	ld a,127
	ret

; ----------------------------------------------------------------------------
; INFLICT_MONSTER - IX = monster, DE = damage
; ----------------------------------------------------------------------------
INFLICT_MONSTER:
	ld l,(ix+M_HP)
	ld h,(ix+M_HP+1)
	or a
	sbc hl,de
	ld (ix+M_HP),l
	ld (ix+M_HP+1),h
	ld a,(ix+M_FLAGS)
	and 0F7h
	or 1
	ld (ix+M_FLAGS),a
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call SCENE_NEEDS_UPDATE
	bit 7,(ix+M_HP+1)
	jr nz,KILL_MONSTER
	ld a,(ix+M_HP)
	or (ix+M_HP+1)
	jr z,KILL_MONSTER
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(CUR_BLOCK)
	call BLOCK_DISTANCE
	cp 4
	ret nc
	ld hl,(CUR_BLOCK)
	ld (ix+M_DEST),l
	ld (ix+M_DEST+1),h
	ret

; KILL_MONSTER - IX = monster: drop carried items and award experience
KILL_MONSTER:
	ld (ix+M_HP),0FFh
	ld (ix+M_HP+1),0FFh
	; what it carried falls where it stood (the centre: a random quarter)
	ld a,(ix+M_POS)
	cp 4
	jr nz,.pos
	ld bc,0104h
	ld a,-1
	call ROLL_DICE
	ld a,l
.pos:	ld (KM_POS),a
	ld l,(ix+M_RITEM)
	ld h,(ix+M_RITEM+1)
	ld a,h
	or l
	jr z,.fixed
	push hl
	ld bc,0102h
	xor a
	call ROLL_DICE
	pop de
	dec l
	jr nz,.fixed		; half the times
	ex de,hl
	call KM_DROP
.fixed:	ld l,(ix+M_FITEM)
	ld h,(ix+M_FITEM+1)
	ld a,h
	or l
	call nz,KM_DROP
	; experience for the party
	call MON_PROPS
	ld l,(iy+MP_EXP)
	ld h,(iy+MP_EXP+1)
	push ix
	call SCALL
	dw PARTY_EXPERIENCE
	pop ix
	ld hl,0
	ld a,0FFh
	call MON_PLACE
	; The script overlay checks whether this was Xanathar and runs the
	; ending if it was. Keep the resident part within its 8000h limit.
	call SCALL
	dw BOSS_DEATH_IF_BOSS
	jp DIRTY

; KM_DROP - HL = item to copy onto the block of the monster IX
KM_DROP:
	push ix
	call DUPLICATE_ITEM
	pop ix
	ld c,l
	ld b,h
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld e,l
	ld d,h
	call DRAWOBJ_PTR
	ld a,(KM_POS)
	push ix
	call SET_ITEM_POS
	pop ix
	ret
KM_POS:	db 0

; ----------------------------------------------------------------------------
; MONSTER_CLOSE_ATTACK - IX = monster: hits one of the party (monsterCloseAttack)
; ----------------------------------------------------------------------------
MONSTER_CLOSE_ATTACK:
	call MON_PROPS
	ld a,(CUR_DIR)
	add a,a
	add a,a
	add a,(ix+M_DIR)
	ld e,a
	ld d,0
	ld hl,MON_CADST1
	add hl,de
	ld a,(hl)
	ld c,a
	add a,a
	add a,c
	add a,a
	add a,a			; *12
	ld (CB_FIRST),a
	ld a,(ix+M_POS)
	cp 4
	jr nz,.tab
	ld a,2
	call RND_RANGE
	dec a
	jr .v
.tab:	ld a,(ix+M_DIR)
	add a,a
	add a,a
	add a,(ix+M_POS)
	ld e,a
	ld d,0
	ld hl,MON_CACHK2
	add hl,de
	ld a,(hl)
.v:	or a
	jr nz,.v1
	ld a,(CB_FIRST)
	add a,6
	ld (CB_FIRST),a
.v1:	ld b,6
	ld a,(CB_FIRST)
	ld e,a
	ld d,0
	ld hl,MON_CADST2
	add hl,de
.lp:	push bc
	push hl
	ld a,(hl)
	ld (CB_TARGET),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.next
	ld a,(iy+P_HP)
	cp -9
	jp m,.next		; dead
	ld a,(iy+P_EFFECT)	; invisible (140h): missed 3 times of 4
	and 40h
	ld c,a
	ld a,(iy+P_EFFECT+1)
	and 1
	or c
	jr z,.seen
	ld a,20
	call RND_RANGE
	cp 5
	jr nc,.next
.seen:	call MON_STRIKE
	; only one target unless the monster hits everybody (capsFlags bit 14)
	pop hl
	pop bc
	ret
.next:	pop hl
	pop bc
	inc hl
	djnz .lp
	ret

; MON_STRIKE - IX = monster, IY = properties... the target is (CB_TARGET)
MON_STRIKE:
	call MON_PROPS
	ld hl,0
	ld (CB_SUM),hl
	ld a,(iy+MP_ATTACKS)
	or a
	ret z
	ld b,a
	push iy
	pop hl
	ld de,MP_DMG
	add hl,de
	ld (CB_DICE),hl
.att:	push bc
	; hit if 1d20 == 20 or 1d20 >= hitChance - target AC
	; 1d20 - 2 against protection from evil (800h), - 1 if the party
	; prays (8000h)
	ld a,(CB_TARGET)
	push iy
	call CHAR_PTR
	ld c,(iy+P_AC)
	ld e,0
	bit 3,(iy+P_EFFECT+1)
	jr z,.pe
	ld e,2
.pe:	pop iy
	ld a,(iy+MP_HIT)
	sub c
	ld c,a
	ld a,(PARTY_EFFECTS+1)
	rla
	ld a,e
	adc a,0
	ld e,a
	ld a,20
	call RND_RANGE
	cp 20
	jr z,.hit
	sub e			; (signed: both are small)
	sub c
	jp m,.miss
.hit:	call XCALL
	dw FX_STONE_HIT
	jr nz,.miss
	ld hl,(CB_DICE)
	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld a,(hl)
	call ROLL_DICE
	ld de,(CB_SUM)
	add hl,de
	ld (CB_SUM),hl
.miss:	ld hl,(CB_DICE)
	inc hl
	inc hl
	inc hl
	ld (CB_DICE),hl
	pop bc
	djnz .att
	ld hl,(CB_SUM)
	bit 7,h
	ret nz
	ld a,h
	or l
	ret z
	; Rust messages and damage portraits use IX for items/graphics. Keep
	; the attacking monster until its real status capabilities are checked.
	push ix
	call MON_PROPS
	bit 7,(iy+MP_CAPS)	; rust (80h): a metal item may go
	jr z,.nr
	ld a,(CB_TARGET)
	call SCALL
	dw RUST_ATTACK
.nr:	ld hl,(CB_SUM)		; (MON_PROPS takes HL)
	ld a,(CB_TARGET)
	call INFLICT_CHARACTER
	pop ix
	; poison (caps 10h) and paralysis (caps 20h)
.status_caps:
	call MON_PROPS
	ld a,(iy+MP_CAPS)
	push af
	and 10h
	ld c,2
	call nz,.status
	pop af
	and 20h
	ret z
	ld c,4
.status:
	ld a,(CB_TARGET)
	call MCALL
	dw STATUS_ATTACK
	ret

; INFLICT_CHARACTER - A = character, HL = damage (inflictCharacterDamage)
INFLICT_CHARACTER:
	ld (CB_TARGET),a
	call CHAR_PTR
	ld a,h
	or a
	jr z,.d
	ld l,127
.d:	call XCALL
	dw FX_DAMAGE_REMAINDERS
	ld (iy+P_DAMAGE),l
	ld (iy+P_DMGTIMER),DAMAGE_TICKS
	ld c,l
	ld b,0
	ld a,(iy+P_HP)
	ld l,a
	rla
	sbc a,a
	ld h,a			; HL = hit points
	or a
	sbc hl,bc
	ld de,-10
	push hl
	or a
	sbc hl,de
	pop hl
	jp p,.ok
	ld hl,-10
.ok:	ld a,l
	ld (iy+P_HP),a
	cp -10
	ld a,21			; hurt
	jr nz,.alive
	ld a,(iy+P_FLAGS)	; dead: only "active" is kept
	and 1
	ld (iy+P_FLAGS),a
	ld a,(CB_TARGET)
	call MCALL
	dw CLEAR_CHARACTER_EFFECTS
	ld a,22
.alive:	call SFX_PLAY
	ld a,(CB_TARGET)
	jp PANEL_DRAW

; ----------------------------------------------------------------------------
; CHAR_TIMERS_TICK - per tick: hand slots and the damage splat
; ----------------------------------------------------------------------------
CHAR_TIMERS_TICK:
	xor a
.lp:	ld (CB_TCHAR),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.next
	ld c,0			; redraw?
	ld a,(iy+P_TIMER0)
	or a
	jr z,.t1
	dec (iy+P_TIMER0)
	jr nz,.t1
	xor a
	call XCALL
	dw FX_SLOT_PHASE
	inc c
.t1:	ld a,(iy+P_TIMER1)
	or a
	jr z,.t2
	dec (iy+P_TIMER1)
	jr nz,.t2
	ld a,1
	call XCALL
	dw FX_SLOT_PHASE
	inc c
.t2:	ld a,(iy+P_DMGTIMER)
	or a
	jr z,.t3
	dec (iy+P_DMGTIMER)
	jr nz,.t3
	ld (iy+P_DAMAGE),0
	inc c
.t3:	ld a,c
	or a
	jr z,.next
	ld a,(CB_TCHAR)
	call PANEL_DRAW
.next:	ld a,(CB_TCHAR)
	inc a
	cp 6
	jr nz,.lp
	ret

; ----------------------------------------------------------------------------
; helpers
; ----------------------------------------------------------------------------
; CHAR_PTR - A = character -> IY = its PARTY record. Preserves BC, DE, HL.
CHAR_PTR:
	push hl
	push de
	rrca			; * P_SIZE (128)
	ld h,a
	and 80h
	ld l,a
	xor h
	ld h,a
	ld de,PARTY
	add hl,de
	push hl
	pop iy
	pop de
	pop hl
	ret

; ITEMTYPE_PTR - A = item type -> HL = ITEMTYPES entry (16 bytes, IT_*)
ITEMTYPE_PTR:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl		; 16 bytes per type
	push de
	ld de,ITEMTYPES
	add hl,de
	pop de
	ret

; STR_HIT_MOD / STR_DMG_MOD - IY = character -> A (signed)
STR_HIT_MOD:
	ld hl,STR_HIT_TAB
	ld de,STREXT_HIT_TAB
	jr STR_MOD
STR_DMG_MOD:
	ld hl,STR_DMG_TAB
	ld de,STREXT_DMG_TAB
STR_MOD:
	ld a,(iy+P_STREXT)
	or a
	jr nz,.ext
	ld a,(iy+P_STR)
	dec a
	cp 25
	jr c,.ok
	ld a,24
.ok:	add a,l
	ld l,a
	jr nc,.nc
	inc h
.nc:	ld a,(hl)
	ret
.ext:	; exceptional strength (18/xx)
	push bc
	ld b,a
	ld hl,STREXT_LIMITS
	ld c,0
.el:	ld a,b
	cp (hl)
	jr c,.ed
	inc c
	inc hl
	ld a,c
	cp 5
	jr nz,.el
.ed:	ld a,c
	or a
	jr z,.e0
	dec a
.e0:	add a,e
	ld e,a
	jr nc,.nc2
	inc d
.nc2:	ld a,(de)
	pop bc
	ret

STR_HIT_TAB:	db -4,-3,-3,-2,-2,-1,-1,0,0,0,0,0,0,0,0,0,1,1,3,3,4,4,5,6,7
STR_DMG_TAB:	db -3,-2,-1,-1,-1,0,0,0,0,0,0,0,0,0,0,1,1,2,7,8,9,10,11,12,14
STREXT_LIMITS:	db 1,51,76,91,100
STREXT_HIT_TAB:	db 1,2,2,2,3
STREXT_DMG_TAB:	db 3,3,4,5,6
CLASS_MODIFIER:	db 0,0,0,1,2,3,0,0,0,0,3,2,0,0,2
AC_HIT_T1:	db 3,2,1,3
AC_HIT_T2:	db 2,1,1,1

CB_CHAR:	db 0
CB_SLOT:	db 0
CB_ITEM:	dw 0
CB_TYPE:	db 0
CB_VALUE:	dw 0
CB_RESULT:	db 0
CB_MONSTER:	dw 0
CB_BLOCK:	dw 0
CB_POSMON:	ds 10
CB_DMG:		db 0
CB_FLY:		db 0		; 1: a flying item (dexterity, no strength)
DEX_HIT_TAB:	db -5,-4,-3,-2,-1,0,0,0,0,0,0,1,2,2,3,3,4,4,4
CB_MAC:		db 0
CB_FIRST:	db 0
CB_TARGET:	db 0
CB_SUM:		dw 0
CB_DICE:	dw 0
CB_TCHAR:	db 0

; STATUS_TIMER_ROOM - called with the MAGIC overlay mapped. NZ when the
; target of STATUS_ATTACK has a free event slot, Z when all four are busy.
; Preserve BC (C is the requested status) and IY (the character). Do not
; steal another effect's expiry or leave paralysis/poison without a timer.
STATUS_TIMER_ROOM:
	push bc
	ld a,(SA_CHAR)
	ld l,a
	ld h,0
	add hl,hl
	ld e,l
	ld d,h
	add hl,hl
	add hl,de
	add hl,hl
	ld de,CH_EVENTS
	add hl,de
	ld b,4
.loop:	ld a,(hl)
	inc hl
	or (hl)
	jr z,.free
	inc hl
	inc hl
	djnz .loop
	xor a
	pop bc
	ret
.free:	or 1
	pop bc
	ret

; CHAR_ALIVE_R - IY = character -> NZ if active, above -10 and not flag 8
CHAR_ALIVE_R:
	bit 0,(iy+P_FLAGS)
	ret z
	bit 3,(iy+P_FLAGS)
	jr nz,.no
	ld a,(iy+P_HP)
	cp -10
	jr z,.no
	or 1
	ret
.no:	xor a
	ret

LEVELS_PER_CLASS:	db 1,1,1,1,1,1,2,2,2,3,2,2,3,2,2

; ----------------------------------------------------------------------------
; THROWN_ATTACK - the hand item (darts, daggers...) flies (thrownAttack)
;   -> A = 0
; MISSILE_ATTACK - a bow or sling shoots its ammunition
;   (projectileWeaponAttack) -> A = 0, or -4 without ammunition
; ----------------------------------------------------------------------------
THROWN_ATTACK:
	call LAUNCH_SETUP	; HL = block, A = position
	ld bc,(CB_ITEM)
	call LAUNCH
	ld a,0
	ret z
	; the hand gets empty, then refilled from the belt (slots 24..22)
	ld a,(CB_CHAR)
	call CHAR_PTR
	ld a,(CB_SLOT)
	call SLOT_PTR
	ld (hl),0
	inc hl
	ld (hl),0
	dec hl
	ld (TA_HAND),hl
	ld a,24
.rl:	push af
	call SLOT_PTR
	ld a,(hl)
	inc hl
	or (hl)
	jr nz,.got
	pop af
	dec a
	cp 22
	jr nc,.rl
	xor a
	ret
.got:	pop af
	ld d,(hl)
	ld (hl),0
	dec hl
	ld e,(hl)
	ld (hl),0
	ld hl,(TA_HAND)
	ld (hl),e
	inc hl
	ld (hl),d
	xor a
	ret
TA_HAND:	dw 0

MISSILE_ATTACK:
	; the ammunition of this launcher: AMMO_TYPES[type - 7]
	ld a,(CB_TYPE)
	sub 7
	cp 8
	ld a,-4
	ret nc
	ld a,(CB_TYPE)
	sub 7
	ld e,a
	ld d,0
	ld hl,AMMO_TYPES
	add hl,de
	ld a,(hl)
	or a
	ld a,-4
	ret m
	ld a,(hl)
	ld (MA_AMMO),a
	ld a,(CB_CHAR)
	call CHAR_PTR
	ld a,(MA_AMMO)
	cp 16			; arrows: in a hand first, then the quiver
	jr nz,.any
	xor a
	call MA_TAKE
	jr nz,.fire
	ld a,1
	call MA_TAKE
	jr nz,.fire
	ld a,16
	call SLOT_PTR
	ld de,0FFFFh
	xor a
	call GET_QUEUED_ITEM
	ld a,h
	or l
	jr nz,.fire
	ld a,-4
	ret
.any:	xor a
.slot:	push af
	call MA_TAKE
	jr nz,.fire0
	pop af
	inc a
	cp 27
	jr c,.slot
	ld a,-4
	ret
.fire0:	pop af
.fire:	ld (MA_ITEM),hl
	call LAUNCH_SETUP
	ld hl,(CB_ITEM)
	ld (FL_WEAPON),hl
	ld bc,(MA_ITEM)
	ld hl,(CUR_BLOCK)
	ld a,(TS_POS)
	call LAUNCH
	xor a
	ret

; MA_TAKE - IY = character, A = slot: its item if of type (MA_AMMO) is
;   taken out -> HL, NZ
MA_TAKE:
	call SLOT_PTR
	push hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.no
	push hl
	call ITEM_IX
	pop hl
	ld a,(ix+I_TYPE)
	push hl
	ld hl,MA_AMMO
	cp (hl)
	pop hl
	jr nz,.no
	ex (sp),hl
	ld (hl),0
	inc hl
	ld (hl),0
	pop hl
	or 1
	ret
.no:	pop hl
	xor a
	ret

; LAUNCH_SETUP - the thrower (CB_CHAR) and its side of the party:
;   (FL_ATK), (FL_DIR), (TS_POS), HL = party block
LAUNCH_SETUP:
	ld a,(CB_CHAR)
	ld (FL_ATK),a
	cp 4
	jr c,.c
	sub 2
.c:	call THROW_START
	ld de,0
	ld (FL_WEAPON),de
	ld a,(TS_POS)
	ret

AMMO_TYPES:	db 16,-1,-1,-1,-1,-1,-1,18
MA_AMMO:	db 0
MA_ITEM:	dw 0
