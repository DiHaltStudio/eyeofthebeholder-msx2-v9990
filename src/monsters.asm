; ============================================================================
; monsters.asm - Monsters: drawing (drawMonsters) and behaviour
;                (updateMonsters and the routines it calls, EOB1 variant)
; Assembler: Sjasm 0.42c
;
; Monster table (LEVELDAT+D_MONSTERS, 30 entries of MON_SIZE bytes):
; ============================================================================
M_BLOCK:	equ 0		; u16, 0 = none
M_POS:		equ 2		; position in the block (0-3, 4 = centre)
M_DIR:		equ 3
M_TYPE:		equ 4		; MONPROPS index
M_SHP:		equ 5		; shape set (0/1)
M_UNIT:		equ 6		; timer unit 0..3
M_MODE:		equ 7		; 0 hunt, 1-3 follow path, 4 still, 5-6 stray, 7/10 spell, 8 friendly
M_HP:		equ 8		; s16
M_DEST:		equ 10		; u16
M_FLAGS:	equ 12		; 1 attacked, 2 flash, 4 attack phase, 8 fear, 20h inactive
M_ANIM:		equ 13		; animation step 0/1
M_STRAY:	equ 14		; s8
M_ATTFRM:	equ 15		; s8: -2/-1 = attack frames
M_SPELL:	equ 16
M_DIRCHG:	equ 17
M_RITEM:	equ 18		; item left half the times (0: none)
M_FITEM:	equ 20		; item always left (0: none)
M_RSTEPS:	equ 22		; steps since its last distance attack
M_RCOUNT:	equ 23		; distance attacks left (FFh: no end)

; monster properties (MONPROPS, 27 bytes per type)
MP_AC:		equ 0
MP_HIT:		equ 1
MP_LEVEL:	equ 2
MP_ATTACKS:	equ 3
MP_DMG:		equ 4
MP_CAPS:	equ 14
MP_EXP:		equ 19		; experience (u16)
MP_REMOTE:	equ 24		; distance attacks
MP_U30:		equ 21
MP_TFLAGS:	equ 15		; 1 a person, 2 a monster (hold spells)
MP_SND1:	equ 22		; attack sound
MP_SND2:	equ 23		; step sound
MP_EVADE:	equ 26

; ----------------------------------------------------------------------------
; MONSTERS_INIT - after loading a level: hit points, block counters, timers
; ----------------------------------------------------------------------------
MONSTERS_INIT:
	ld hl,BLOCKCNT
	ld de,BLOCKCNT+1
	ld bc,1023
	ld (hl),0
	ldir
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	push bc
	ld a,(ix+M_BLOCK)
	or (ix+M_BLOCK+1)
	jr z,.next
	call MON_PROPS		; IY = properties
	ld a,(iy+MP_LEVEL)
	cp 0FFh
	ld b,1
	ld c,4
	jr z,.roll
	ld b,a
	ld c,8
.roll:	xor a
	call ROLL_DICE
	ld (ix+M_HP),l
	ld (ix+M_HP+1),h
	ld a,(ix+M_FLAGS)
	or 40h
	ld (ix+M_FLAGS),a
	call MON_RANGED_INIT
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call BLOCKCNT_PTR
	inc (hl)
.next:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .lp
	; unit timers: even ones a full interval, odd ones half of it
	ld hl,LEVELDAT+D_MONTIMERS
	ld de,MON_TIMERS
	ld b,4
	ld c,0
.tm:	ld a,(hl)
	bit 0,c
	jr z,.full
	srl a
	jr nz,.full
	inc a
.full:	ld (de),a
	inc hl
	inc de
	inc c
	djnz .tm
	ret

; MONSTERS_TICK - unit timers (one tick = 55 ms)
MONSTERS_TICK:
	ld hl,MON_TIMERS
	ld c,0
.lp:	dec (hl)
	jr nz,.next
	push hl
	push bc
	ld a,c
	ld de,LEVELDAT+D_MONTIMERS
	add a,e
	ld e,a
	jr nc,.nc
	inc d
.nc:	ld a,(de)
	ld (hl),a
	ld a,c
	call UPDATE_MONSTERS
	pop bc
	pop hl
.next:	inc hl
	inc c
	ld a,c
	cp 4
	jr nz,.lp
	ret

; BLOCKCNT_PTR - HL = block -> HL = its monster counter
BLOCKCNT_PTR:
	ld a,h
	and 3
	add a,BLOCKCNT>>8
	ld h,a
	ret

; MON_SND - A = sound (<= 0 none), HL = block: heard if near enough
; MON_SND_HERE - the same at the party block
MON_SND_HERE:
	ld hl,(CUR_BLOCK)
MON_SND:
	dec a
	ret m
	inc a
	jp ENV_SOUND

; MON_PROPS - IX = monster -> IY = its properties. Preserves BC, IX.
MON_PROPS:
	push bc
	ld a,(ix+M_TYPE)
	ld l,a
	ld h,0
	ld c,l
	ld b,h
	add hl,hl		; *2
	add hl,bc		; *3
	ld c,l
	ld b,h
	add hl,hl
	add hl,hl
	add hl,hl		; *24
	add hl,bc		; *27
	ld bc,MONPROPS
	add hl,bc
	push hl
	pop iy
	pop bc
	ret

; ============================================================================
; Drawing
; ============================================================================

; DRAW_MONSTERS - A = visible block index (0..14)
DRAW_MONSTERS:
	ld (MON_INDEX),a
	add a,a
	ld l,a
	ld h,0
	ld de,VISBLK
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or e
	ret z
	ld (MON_BL),de
	ex de,hl
	call BLOCKCNT_PTR
	ld a,(hl)
	or a
	ret z			; nobody there
	ld a,(MON_INDEX)
	ld e,a
	ld d,0
	ld hl,DSC_DIMMAP
	add hl,de
	ld e,(hl)
	ld hl,DIST_MAP
	add hl,de
	ld a,(hl)
	cp 3
	ret nc
	ld (MON_DIST),a
	; --- the (up to) 5 monsters of the block, by draw position ---
	ld hl,MON_OBJS
	ld b,10
	xor a
.clr:	ld (hl),a
	inc hl
	djnz .clr
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.scan:	ld hl,(MON_BL)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.ns
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.ns
	ld a,(CUR_DIR)
	ld c,a
	add a,a
	add a,a
	add a,c			; dir * 5
	add a,(ix+M_POS)
	ld e,a
	ld d,0
	ld hl,DSC_OBJPOSINDEX
	add hl,de
	ld a,(hl)
	add a,a
	ld e,a
	ld hl,MON_OBJS
	add hl,de
	push ix
	pop de
	ld (hl),e
	inc hl
	ld (hl),d
.ns:	ld de,MON_SIZE
	add ix,de
	djnz .scan
	; --- draw them, back to front ---
	ld hl,MON_OBJS
	ld b,5
.draw:	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,d
	or e
	jr z,.nd
	push hl
	push bc
	push de
	pop ix
	call MON_DRAW1
	pop bc
	pop hl
.nd:	djnz .draw
	ret

; MON_DRAW1 - IX = monster entry
MON_DRAW1:
	call MON_PROPS
	ld a,(iy+MP_CAPS)
	ld (MON_CAPS),a
	ld a,(iy+MP_U30)
	ld (MON_U30),a
	; frame: table[(anim << 4) + (dir << 2) + monster facing], negative = mirrored
	ld a,(ix+M_ANIM)
	add a,a
	add a,a
	ld c,a
	ld a,(CUR_DIR)
	add a,c
	add a,a
	add a,a
	add a,(ix+M_DIR)
	ld e,a
	ld d,0
	ld hl,DSC_MONFRM2
	ld a,(MON_CAPS)
	bit 1,a
	jr z,.t2
	ld hl,DSC_MONFRM1
.t2:	add hl,de
	ld a,(hl)
	ld b,a
	; attack frames, only next to the party
	ld a,(MON_DIST)
	or a
	jr nz,.noatt
	ld a,(ix+M_ATTFRM)
	or a
	jp p,.noatt
	add a,7
	ld b,a
.noatt:	ld a,(ix+M_ATTFRM)
	or a
	jp p,.keep
	inc (ix+M_ATTFRM)	; the original advances it at each draw
.keep:	ld a,b
	ld (MON_F),a
	or a
	jp p,.fp
	neg
.fp:	ld (MON_SUB),a		; 1..6
	; shape id = D_MONSHAPE[((set * 6 + sub - 1) * 3 + dist)]
	ld c,0
	ld a,(ix+M_SHP)
	or a
	jr z,.s0
	ld c,6
.s0:	ld a,(MON_SUB)
	dec a
	add a,c
	ld c,a
	add a,a
	add a,c			; *3
	ld hl,MON_DIST
	add a,(hl)
	add a,a			; words
	ld e,a
	ld d,0
	ld hl,LEVELDAT+D_MONSHAPE
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (MON_SID),de
	ld a,d
	and e
	inc a
	ret z
	; position in the block: 4 = centre, else rotated by the facing
	ld a,(ix+M_POS)
	cp 4
	jr z,.p4
	ld c,a
	ld a,(CUR_DIR)
	add a,a
	add a,a
	add a,c
	ld e,a
	ld d,0
	ld hl,DSC_ITEMPOSINDEX
	add hl,de
	ld a,(hl)
.p4:	ld c,a
	ld a,(MON_INDEX)
	ld b,a
	add a,a
	add a,a
	add a,b			; index * 5
	add a,c
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl		; (x, y) words
	ld de,DSC_SHAPECOORDS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	push de			; x offset
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,127
	add hl,de		; y = coord + 127
	ld a,(MON_U30)
	cp 1
	jr nz,.noyadd
	ld a,(MON_SUB)
	cp 1
	jr z,.yadd
	cp 4
	jr c,.noyadd
.yadd:	ld a,(MON_DIST)
	ld e,a
	ld d,0
	push hl
	ld hl,MONSTER_YADD
	add hl,de
	ld e,(hl)
	pop hl
	add hl,de
.noyadd:
	ld (MON_Y),hl
	pop de
	ld hl,88
	add hl,de
	ld (MON_X),hl
	; centre horizontally, stand on the floor
	push ix
	ld hl,(MON_SID)
	call SHAPE_ENTRY
	ld a,(ix+4)
	ld c,(ix+5)
	pop ix
	srl a
	ld e,a
	ld d,0
	ld hl,(MON_X)
	or a
	sbc hl,de
	push hl
	ld hl,(MON_Y)
	ld b,0
	or a
	sbc hl,bc
	ld c,l			; y
	pop de			; x
	ld a,(MON_F)
	rlca
	and 1
	ld b,a			; mirrored if the frame is negative
	ld hl,(MON_SID)
	push ix
	call DRAW_SHAPE
	pop ix
	ret

; ============================================================================
; Behaviour (EoBCoreEngine::updateMonsters and friends)
; ============================================================================

; UPDATE_MONSTERS - A = unit (0..3)
UPDATE_MONSTERS:
	ld (UM_UNIT),a
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	push bc
	ld a,(ix+M_UNIT)
	ld hl,UM_UNIT
	cp (hl)
	jr nz,.next
	ld a,(ix+M_BLOCK)
	or (ix+M_BLOCK+1)
	jr z,.next
	bit 7,(ix+M_HP+1)
	jr nz,.next
	ld a,(ix+M_HP)
	or (ix+M_HP+1)
	jr z,.next
	bit 5,(ix+M_FLAGS)
	jr nz,.next
	ld a,(ix+M_DIRCHG)
	or a
	jr z,.go
	ld (ix+M_DIRCHG),0
	jr .next
.go:	call MON_UPDATE1
.next:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .lp
	ret

MON_UPDATE1:
	call MON_UPDATE_DEST
	ld a,(ix+M_MODE)
	or a
	call nz,MON_ATTACK_MODE
	ld a,(ix+M_MODE)
	or a
	jr nz,.m1
	call MON_MOVE
	jr .anim
.m1:	cp 1
	jr nz,.m2
	ld a,2
	call MON_FOLLOW
	jr .anim
.m2:	cp 2
	jr nz,.m3
	ld a,-1
	call MON_FOLLOW
	jr .anim
.m3:	cp 3
	jr nz,.m5
	ld a,1
	call MON_FOLLOW
	jr .anim
.m5:	cp 5
	jr nz,.m6
	ld a,-1
	call MON_STRAY
	jr .anim
.m6:	cp 6
	jr nz,.m7
	ld a,1
	call MON_STRAY
	jr .anim
.m7:	cp 7
	jr z,.spell
	cp 10
	jr nz,.anim
.spell:	ld a,(ix+M_SPELL)
	or a
	jr z,.anim
	dec (ix+M_SPELL)
	jr nz,.anim
	ld (ix+M_MODE),0
.anim:	ld a,(ix+M_MODE)
	cp 4
	jr z,.noanim
	cp 10
	jr z,.noanim
	cp 7
	jr z,.noanim
	cp 8
	jr z,.noanim
	ld a,(ix+M_ANIM)
	xor 1
	ld (ix+M_ANIM),a
.noanim:
	call MON_PROPS
	ld a,(iy+MP_U30)
	cp 1
	ret nz
	; setBlockMonsterDirection: the others of the block take this facing
	ld e,(ix+M_BLOCK)
	ld d,(ix+M_BLOCK+1)
	ld c,(ix+M_DIR)
	push ix
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.sd:	ld a,(ix+M_BLOCK)
	cp e
	jr nz,.sdn
	ld a,(ix+M_BLOCK+1)
	cp d
	jr nz,.sdn
	ld a,(ix+M_DIR)
	cp c
	jr z,.sdn
	ld (ix+M_DIR),c
	ld (ix+M_DIRCHG),1
.sdn:	push de
	ld de,MON_SIZE
	add ix,de
	pop de
	djnz .sd
	pop ix
	ret

; MON_UPDATE_DEST - updateMonsterDest
MON_UPDATE_DEST:
	ld a,(ix+M_MODE)
	cp 7
	jr c,.ok
	cp 11
	ret c
.ok:	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(CUR_BLOCK)
	call BLOCK_DISTANCE
	cp 4
	ret nc
	ld (UM_DIST),a
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(CUR_BLOCK)
	call NEXT_MONSTER_DIR	; A = 0..7 or -1
	ld c,a
	ld a,(ix+M_DIR)
	add a,a
	add a,3
	ld b,a
	ld a,c
	sub b			; s = d - dir*2 - 3
	jp p,.pos
	add a,8
.pos:	cp 3
	jr nc,.set		; s > 2
	ld a,(UM_DIST)
	cp 2
	ret nc			; s <= 2 and dist >= 2: keep going
.set:	ld (ix+M_MODE),0
	ld hl,(CUR_BLOCK)
	ld (ix+M_DEST),l
	ld (ix+M_DEST+1),h
	ret

; MON_ATTACK_MODE - updateMonsterAttackMode
MON_ATTACK_MODE:
	bit 0,(ix+M_FLAGS)
	ret z
	ld a,(ix+M_MODE)
	cp 10
	ret z
	ld (ix+M_MODE),0
	ld hl,(CUR_BLOCK)
	ld (ix+M_DEST),l
	ld (ix+M_DEST+1),h
	ret

; MON_MOVE - updateMoveMonster, including distance attacks
MON_MOVE:
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld a,(ix+M_DIR)
	call NEW_BLOCK_POS	; HL = block ahead of the monster
	ld (UM_AHEAD),hl
	; reached its destination without finding the party: stray
	ld e,(ix+M_DEST)
	ld d,(ix+M_DEST+1)
	or a
	sbc hl,de
	jr nz,.go
	ld hl,(UM_AHEAD)
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	jr z,.go
	ld a,2
	call RND_RANGE
	add a,4			; 5 or 6
	ld (ix+M_MODE),a
	ret
.go:	call MON_TRY_DISTANCE
	ret c
	ld hl,(UM_AHEAD)
	call MON_TRY_CLOSE_ATTACK
	ret c
	ld (ix+M_ATTFRM),0
	ld e,(ix+M_DEST)
	ld d,(ix+M_DEST+1)
	call MON_WALK
	call MON_PROPS
	bit 3,(iy+MP_CAPS)
	ret z
	ld hl,0FFFFh
	jp MON_TRY_CLOSE_ATTACK

; MON_TRY_CLOSE_ATTACK - HL = block (FFFFh = ahead of the monster)
;   -> C set if the monster used its turn on the party
MON_TRY_CLOSE_ATTACK:
	ld a,h
	and l
	inc a
	jr nz,.blk
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld a,(ix+M_DIR)
	call NEW_BLOCK_POS
.blk:	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	jr z,.adj
	or a			; NC: not next to the party (or not facing it)
	ret
.adj:
	; may it hit from its position in the block?
	ld a,(ix+M_POS)
	cp 4
	ld a,1
	jr z,.r
	ld a,(ix+M_DIR)
	add a,a
	add a,a
	add a,(ix+M_POS)
	ld e,a
	ld d,0
	ld hl,MON_CACHK1
	add hl,de
	ld a,(hl)
.r:	or a
	jr z,.reposition
	; every other turn: strike
	ld a,(ix+M_FLAGS)
	xor 4
	ld (ix+M_FLAGS),a
	bit 2,a
	scf
	ret z
	; facing the party: show the attack frames
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(VISBLK+13*2)
	or a
	sbc hl,de
	jr nz,.hit
	ld (ix+M_ATTFRM),-2
	ld a,3
	ld (UM_FRAMES),a
.anim:	push ix
	call SCENE_DRAW
	call V9_WAIT_CE
	ld b,ATTACK_FRAME_WAIT
.w:	call V9_WAIT_VBLANK
	djnz .w
	pop ix
	ld hl,UM_FRAMES
	dec (hl)
	jr z,.hit
	ld a,(ix+M_ATTFRM)
	or a
	jp m,.anim
.hit:	call MON_PROPS		; its attack sound (sound1)
	ld a,(iy+MP_SND1)
	call MON_SND_HERE
	push ix			; damage/UI drawing uses IX for shapes
	call MONSTER_CLOSE_ATTACK
	pop ix
	ld (ix+M_ATTFRM),0
	ld a,(ix+M_ANIM)
	xor 1
	ld (ix+M_ANIM),a
	call DIRTY
	scf
	ret
.reposition:
	; move to a position of the block from where it can hit
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	push hl
	call BLOCKCNT_PTR
	ld a,(hl)
	pop hl
	cp 1
	jr nz,.np
	ld (ix+M_POS),4
	jr .dirty
.np:	call MON_NEXT_POS	; A = position or -1
	or a
	jp m,.dirty
	ld (ix+M_POS),a
.dirty:	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call SCENE_NEEDS_UPDATE
	scf
	ret

ATTACK_FRAME_WAIT:	equ 8

; MON_WALK - walkMonster: DE = destination block
MON_WALK:
	ld (UM_DEST),de
	ld hl,MON_STEPCNT
	inc (hl)
	ld a,(hl)
	cp 11
	jr c,.cnt
	ld (hl),0
	ld a,(MON_STEPMODE)
	xor 1
	ld (MON_STEPMODE),a
.cnt:	ld hl,MON_STEPTAB2
	ld a,(MON_STEPMODE)
	or a
	jr z,.tb
	ld hl,MON_STEPTAB3
.tb:	ld (UM_TABLE),hl
	ld a,(ix+M_DIR)
	add a,a
	ld (UM_S),a		; s = dir << 1
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(UM_DEST)
	call NEXT_MONSTER_DIR
	cp 0FFh
	ret z
	bit 3,(ix+M_FLAGS)
	jr z,.nofear
	xor 4
.nofear:
	ld (UM_D),a
	ld hl,UM_S
	sub (hl)
	and 7
	ld (UM_D2),a
	; next to the party (straight line): just turn towards it
	ld a,(UM_D)
	bit 0,a
	jr nz,.notnext
	srl a
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call NEW_BLOCK_POS
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	jr nz,.notnext
	ld a,(UM_D2)
	ld c,(ix+M_DIR)
	cp 5
	jr c,.lt5
	dec c
	jr .turn
.lt5:	or a
	jr nz,.inc
	sla c			; d2 = 0: the original keeps s = dir << 1
	jr .turn
.inc:	inc c
.turn:	ld a,c
	and 3
	ld hl,0FFFFh
	jp MON_NEXT_STEP
.notnext:
	ld a,(UM_D2)
	or a
	jr z,.try
	ld b,a
	ld a,(UM_D)
	and 1
	xor 1
	inc a			; 1 + ((d & 1) ^ 1)
	ld c,a
	ld a,b
	cp 5
	ld a,(UM_S)
	jr c,.plus
	sub c
	jr .st
.plus:	add a,c
.st:	and 7
	ld (UM_S),a
.try:	; try the 8 directions of the table
	ld b,8
	ld hl,(UM_TABLE)
	ld de,7
	add hl,de		; from the last entry backwards
.tl:	push bc
	push hl
	ld a,(UM_S)
	add a,(hl)
	and 7
	ld (UM_S),a
	bit 0,a
	jr nz,.tn		; diagonals do not move
	srl a
	ld (UM_SDIR),a
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call NEW_BLOCK_POS
	ld a,h
	or l
	jr z,.tn
	ld a,(UM_SDIR)
	call MON_NEXT_STEP
	jr c,.done
.tn:	pop hl
	pop bc
	dec hl
	djnz .tl
	ret
.done:	pop hl
	pop bc
	ret

; MON_NEXT_STEP - walkMonsterNextStep: HL = destination block (FFFFh = stay),
;   A = direction (FFh = keep) -> C set if done
MON_NEXT_STEP:
	ld (UM_NDIR),a
	ld (UM_NBLK),hl
	ld e,(ix+M_BLOCK)
	ld d,(ix+M_BLOCK+1)
	ld (UM_OBL),de
	ld a,h
	and l
	inc a
	jr z,.nomove
	or a
	sbc hl,de
	jr z,.nomove
	; may not walk into the party
	ld hl,(UM_NBLK)
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	ret z			; NC
	ld a,(UM_NDIR)
	cp 0FFh
	jr nz,.d
	ld a,(ix+M_DIR)
	ld (UM_NDIR),a
.d:	; the wall of the destination facing the monster must let monsters pass
	xor 2
	ld hl,(UM_NBLK)
	call BLOCK_WALL
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	bit 2,(hl)
	jr nz,.pass
	or a			; NC: the wall stops monsters
	ret
.pass:
	; a free position in an occupied block
	ld hl,(UM_NBLK)
	push hl
	call BLOCKCNT_PTR
	ld a,(hl)
	pop hl
	or a
	jr z,.place
	call MON_NEXT_POS
	cp 0FFh
	ret z			; full (NC)
	ld (ix+M_POS),a
.place:	ld hl,(UM_NBLK)
	ld a,(UM_NDIR)
	call MON_PLACE
	call MON_PROPS		; its steps (sound2), heard from afar
	ld a,(iy+MP_SND2)
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call MON_SND
	ld a,0FFh
	ld (UM_NDIR),a
.nomove:
	ld a,(UM_NDIR)
	cp 0FFh
	jr z,.nd
	ld (ix+M_DIR),a
.nd:	ld hl,(UM_OBL)
	call SCENE_NEEDS_UPDATE
	scf
	ret

; MON_PLACE - placeMonster: HL = new block (0 = removed), A = direction (FFh = keep)
MON_PLACE:
	push af
	push hl
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call SCENE_NEEDS_UPDATE
	call BLOCKCNT_PTR
	ld a,(hl)
	or a
	jr z,.z
	dec (hl)
.z:	pop hl
	ld (ix+M_BLOCK),l
	ld (ix+M_BLOCK+1),h
	push hl
	call BLOCKCNT_PTR
	inc (hl)
	pop hl
	pop af
	cp 0FFh
	jr z,.nd
	ld (ix+M_DIR),a
.nd:	jp SCENE_NEEDS_UPDATE

; MON_FOLLOW - updateMonsterFollowPath: A = turn steps when blocked
MON_FOLLOW:
	ld (UM_TURN),a
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld a,(ix+M_DIR)
	call NEW_BLOCK_POS
	ld a,0FFh
	call MON_NEXT_STEP
	ret c
	ld a,(UM_TURN)
	add a,(ix+M_DIR)
	and 3
	ld (ix+M_DIR),a
	ld hl,0FFFFh
	jp MON_NEXT_STEP

; MON_STRAY - updateMonstersStraying: A = side (+1 / -1)
MON_STRAY:
	ld (UM_TURN),a
	ld a,(ix+M_STRAY)
	or a
	jp m,.walk
	jr nz,.nz
	; stray == 0: follow the path the other way first
	ld a,(UM_TURN)
	neg
	call MON_FOLLOW
.nz:	ld a,(UM_TURN)
	add a,(ix+M_DIR)
	and 3
	ld (UM_SDIR),a
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	call NEW_BLOCK_POS
	; flag 4 of the wall of that block facing the facing table entry
	ld a,(UM_SDIR)
	ld e,a
	ld d,0
	push hl
	ld hl,DSC_BLOCKMAP
	add hl,de
	ld a,(hl)
	pop hl
	call BLOCK_WALL
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	ld a,(hl)
	and 4
	ld c,a
	ld a,(ix+M_STRAY)
	or a
	jr nz,.s1
	ld a,c
	or a
	ret nz
	ld (ix+M_STRAY),-1
	ret
.s1:	ld a,c
	or a
	jr z,.walk
	ld a,(UM_SDIR)
	ld hl,0FFFFh
	call MON_NEXT_STEP
	ld (ix+M_STRAY),-1
	ret
.walk:	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld a,(ix+M_DIR)
	call NEW_BLOCK_POS
	ld a,0FFh
	call MON_NEXT_STEP
	jr nc,.blocked
	ld (ix+M_STRAY),1
	ret
.blocked:
	ld a,(UM_TURN)
	ld b,a
	ld a,(ix+M_DIR)
	sub b
	and 3
	ld hl,0FFFFh
	call MON_NEXT_STEP
	ld (ix+M_STRAY),0
	ret

; MON_NEXT_POS - getNextMonsterPos: HL = block -> A = free position, FFh = none
MON_NEXT_POS:
	push iy
	push hl			; MON_PROPS replaces HL with the property address
	call MON_PROPS
	ld a,(iy+MP_U30)
	pop hl			; FIND_FREE_POS needs the destination block
	pop iy
	or a
	ld a,0FFh
	ret nz			; big monsters take the whole block
	call FIND_FREE_POS	; A = bit mask, or negative
	or a
	jp m,.none
	ld c,a
	ld a,(ix+M_DIR)
	and 1
	add a,a
	add a,a
	ld e,a
	ld d,0
	ld hl,MON_CAPOS2
	add hl,de
	ld b,4
.lp:	ld a,(hl)
	xor (ix+M_DIR)
	and 3			; (the table holds 0..3)
	push bc
	ld b,a
	inc b
	ld a,c
.sh:	rrca
	djnz .sh
	pop bc
	jr nc,.free
	inc hl
	djnz .lp
.none:	ld a,0FFh
	ret
.free:	ld a,(hl)
	xor (ix+M_DIR)
	and 3
	ret

; FIND_FREE_POS - HL = block -> A = mask of the taken positions (only
;   monsters of size 0), 80h if the block is full or holds a bigger one
FIND_FREE_POS:
	ld (UM_FBLK),hl
	call BLOCKCNT_PTR
	ld a,(hl)
	cp 4
	ld a,80h
	ret nc			; also reject overfull blocks from an older save
	ld a,(hl)
	ld (UM_NM),a
	xor a
	ld (UM_MASK),a
	push ix
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	ld hl,(UM_FBLK)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.n
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.n
	call MON_PROPS
	ld a,(iy+MP_U30)
	or a
	jr nz,.big
	ld a,(ix+M_POS)
	cp 4
	jr nz,.p
	ld e,(ix+M_DIR)
	ld d,0
	ld hl,MON_CAPOS1
	add hl,de
	ld a,(hl)
	ld (ix+M_POS),a
.p:	ld c,a
	ld a,1
	inc c
.sh:	dec c
	jr z,.set
	add a,a
	jr .sh
.set:	ld hl,UM_MASK
	or (hl)
	ld (hl),a
	ld hl,UM_NM
	dec (hl)
	jr z,.done
.n:	ld de,MON_SIZE
	add ix,de
	djnz .lp
.done:	pop ix
	ld a,(UM_MASK)
	ret
.big:	pop ix
	ld a,80h
	ret

; NEXT_MONSTER_DIR - HL = from block, DE = to block -> A = direction 0..7, FFh
NEXT_MONSTER_DIR:
	ld a,e
	and 1Fh
	ld (UM_C),a		; dest x
	ld a,l
	and 1Fh
	ld (UM_E),a		; cur x
	call BLOCK_Y
	ld b,a			; f = cur y
	ex de,hl
	call BLOCK_Y		; d = dest y
	ld c,a
	ld a,b
	sub c			; s1 = f - d
	ld b,a
	call ABS_A
	ld (UM_D1),a
	ld a,(UM_C)
	ld hl,UM_E
	sub (hl)		; s2 = c - e
	ld c,a
	call ABS_A
	ld (UM_DD2),a
	; s1, s2 doubled; signed compares (values are small)
	sla b
	sla c
	ld e,0
	ld a,(UM_DD2)
	ld d,a
	ld a,b
	call SCMP_GE		; s1 >= d2
	jr c,.n1
	set 3,e
.n1:	ld a,b
	neg
	call SCMP_GE		; -s1 >= d2
	jr c,.n2
	set 2,e
.n2:	ld a,(UM_D1)
	ld d,a
	ld a,c
	call SCMP_GE		; s2 >= d1
	jr c,.n3
	set 1,e
.n3:	ld a,c
	neg
	call SCMP_GE		; -s2 >= d1
	jr c,.n4
	set 0,e
.n4:	ld d,0
	ld hl,MON_DIRCHANGE
	add hl,de
	ld a,(hl)
	ret

; SCMP_GE - signed A >= D (D >= 0)? NC if yes, C if no. Preserves BC, DE.
SCMP_GE:
	bit 7,a
	scf
	ret nz			; negative < D
	cp d
	ret

; BLOCK_Y - HL = block -> A = y (block >> 5)
BLOCK_Y:
	ld a,l
	rlca
	rlca
	rlca
	and 7
	push bc
	ld b,a
	ld a,h
	and 3
	add a,a
	add a,a
	add a,a
	or b
	pop bc
	ret

; ABS_A - A = |A| (signed)
ABS_A:
	or a
	ret p
	neg
	ret

; BLOCK_DISTANCE - HL, DE = blocks -> A = (min >> 1) + max of |dx|, |dy|
BLOCK_DISTANCE:
	ld a,l
	and 1Fh
	ld c,a
	ld a,e
	and 1Fh
	sub c
	call ABS_A
	ld c,a			; dx
	call BLOCK_Y
	ld b,a
	ex de,hl
	call BLOCK_Y
	sub b
	call ABS_A		; dy
	cp c
	jr nc,.ok		; dy >= dx
	ld b,a
	ld a,c
	ld c,b
.ok:	srl c
	add a,c
	ret

; NEW_BLOCK_POS - HL = block, A = direction -> HL = neighbour (& 3FFh)
NEW_BLOCK_POS:
	push de
	add a,a
	ld e,a
	ld d,0
	push hl
	ld hl,DIR_OFFSET
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	pop hl
	add hl,de
	ld a,h
	and 3
	ld h,a
	pop de
	ret

MON_TIMERS:	ds 4
MON_STEPCNT:	db 0
MON_STEPMODE:	db 0
MON_INDEX:	db 0
MON_DIST:	db 0
MON_BL:		dw 0
MON_OBJS:	ds 10
MON_CAPS:	db 0
MON_U30:	db 0
MON_F:		db 0
MON_SUB:	db 0
MON_SID:	dw 0
MON_X:		dw 0
MON_Y:		dw 0
UM_UNIT:	db 0
UM_FRAMES:	db 0
UM_DIST:	db 0
UM_AHEAD:	dw 0
UM_DEST:	dw 0
UM_TABLE:	dw 0
UM_S:		db 0
UM_D:		db 0
UM_D2:		db 0
UM_SDIR:	db 0
UM_NDIR:	db 0
UM_NBLK:	dw 0
UM_OBL:		dw 0
UM_TURN:	db 0
UM_FBLK:	dw 0
UM_NM:		db 0
UM_MASK:	db 0
UM_C:		db 0
UM_E:		db 0
UM_D1:		db 0
UM_DD2:		db 0

; MON_RANGED_INIT - IX = monster, IY = its properties: distance attacks
MON_RANGED_INIT:
	ld (ix+M_RSTEPS),5
	ld a,(iy+MP_REMOTE)
	ld (ix+M_RCOUNT),a
	ret

; ----------------------------------------------------------------------------
; MON_TRY_DISTANCE - IX = monster: a spell, a missile or a mind blast at the
;   party from up to 3 blocks in a clear line (updateMonsterTryDistanceAttack,
;   EOB1) -> C set if it did
; ----------------------------------------------------------------------------
MON_TRY_DISTANCE:
	ld a,(ix+M_RCOUNT)
	or a
	ret z
	call MON_PROPS
	bit 6,(iy+MP_CAPS)
	ret z
	ld a,(ix+M_RSTEPS)
	cp 5
	jr nc,.ready
	inc (ix+M_RSTEPS)
	or a
	ret
.ready:	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(CUR_BLOCK)
	call BLOCK_DISTANCE
	cp 4
	ret nc			; too far (NC)
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(CUR_BLOCK)
	call NEXT_MONSTER_DIR
	ld c,a
	ld a,(ix+M_DIR)
	add a,a
	cp c
	jr z,.line
	or a
	ret
.line:	; nothing in between
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
.lp:	ld a,(ix+M_DIR)
	call NEW_BLOCK_POS
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	add hl,de
	jr z,.clear
	ld a,(ix+M_DIR)
	xor 2
	push hl
	call BLOCK_WALL
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	ld a,(hl)
	pop hl
	and 3
	ret z			; NC
	call BLOCK_HAS_MONSTER
	jr z,.lp
	or a
	ret
.clear:	; what the type does
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld (MC_BLOCK),hl
	ld a,(ix+M_POS)
	ld (MC_POS),a
	ld a,(ix+M_DIR)
	ld (MC_DIR),a
	ld a,(ix+M_TYPE)
	sub 4
	jr z,.bolt
	cp 10
	jr z,.mage
	cp 11
	jr z,.dagger
	cp 12
	jr z,.missile
	cp 13
	jr z,.blast
	cp 17
	jr z,.beholder
	jr .used
.bolt:	ld a,31
	call MC_SOUND
	ld a,9
	jr .cast
.missile:
	ld a,85
	call MC_SOUND
	xor a
	jr .cast
.mage:	ld a,(ix+M_RCOUNT)
	cp 10
	jr c,.ml
	ld a,9
.ml:	ld e,a
	ld d,0
	ld hl,ENEMY_MAGE_SFX
	add hl,de
	ld a,(hl)
	call MC_SOUND
	ld hl,ENEMY_MAGE
	add hl,de
	ld a,(hl)
.cast:	push ix
	call MCALL
	dw MON_CAST
	pop ix
	jr .used
.dagger:
	push ix
	ld hl,60
	call DUPLICATE_ITEM
	ld c,l
	ld b,h
	ld a,h
	or l
	jr z,.dg
	ld a,(MC_DIR)
	ld (FL_DIR),a
	ld a,0FFh
	ld (FL_ATK),a
	ld hl,0
	ld (FL_WEAPON),hl
	ld hl,(MC_BLOCK)
	ld a,(MC_POS)
	and 3
	call LAUNCH
.dg:	pop ix
	jr .used
.blast:	ld a,83
	call MC_SOUND
	push ix
	call MCALL
	dw MIND_BLAST
	pop ix
	jr .used
.beholder:
	push ix
	call MCALL
	dw BEHOLDER_ATTACK
	pop ix
.used:	ld a,(ix+M_RCOUNT)
	inc a
	jr z,.inf
	dec (ix+M_RCOUNT)
.inf:	ld (ix+M_RSTEPS),0
	scf
	ret

MC_BLOCK:	dw 0
MC_POS:		db 0
MC_DIR:		db 0
ENEMY_MAGE:	db 0,0,0,0,0,2,2,5,6,0
ENEMY_MAGE_SFX:	db 0,85,85,85,85,98,98,31,98,2
; MC_SOUND - A = sound: heard from the block of the monster (MC_BLOCK)
MC_SOUND:
	ld hl,(MC_BLOCK)
	jp ENV_SOUND
