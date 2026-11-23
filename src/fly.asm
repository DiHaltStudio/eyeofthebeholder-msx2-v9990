; ============================================================================
; fly.asm - Flying objects: thrown items and missiles (launchObject,
;           timerProcessFlyingObjects, updateObjectFlight,
;           updateFlyingObjectHitTest, endObjectFlight, drawFlyingObjects)
; Assembler: Sjasm 0.42c
;
; Ten records of FO_SIZE bytes at FLYOBJ (world segment, they end with the
; level). A flying item stays in the item queue of its block with position
; 4..7; every 3 ticks it moves half a block. Spells have enable 2 and no
; item. Thrown by the party, by monsters or by the traps of the level scripts
; (OP_LAUNCH).
; ============================================================================

FO_EN:		equ 0		; 0 free, 1 item
FO_START:	equ 1		; 1 until it leaves the first block
FO_FLAGS:	equ 2
FO_DIR:		equ 3
FO_DIST:	equ 4		; half blocks left
FO_BLOCK:	equ 5		; u16
FO_POS:		equ 7
FO_ITEM:	equ 8		; u16
FO_TYPE:	equ 10
FO_ATK:		equ 11		; thrower (character) or FFh
FO_WEAPON:	equ 12		; u16, the launcher (bow, sling)
FO_CB:		equ 14		; magic: the spell whose end routine hits
FO_LEVEL:	equ 15		; magic: the level of the caster
FO_SIZE:	equ 16
FLY_TICKS:	equ 3

; ----------------------------------------------------------------------------
; LAUNCH - BC = item, HL = start block, A = start position, (FL_DIR),
;   (FL_ATK), (FL_WEAPON) -> NZ if it flies (launchObject)
; ----------------------------------------------------------------------------
LAUNCH:
	ld (FL_POS),a
	ld (FL_BLOCK),hl
	ld (FL_ITEM),bc
	ld ix,FLYOBJ
	ld b,10
.free:	ld a,(ix+FO_EN)
	or a
	jr z,.got
	ld de,FO_SIZE
	add ix,de
	djnz .free
	xor a
	ret
.got:	push ix
	ld hl,(FL_BLOCK)
	ld e,l
	ld d,h
	call DRAWOBJ_PTR
	ld bc,(FL_ITEM)
	ld a,(FL_POS)
	or 4
	call SET_ITEM_POS
	pop ix
	ld (ix+FO_EN),1
	ld (ix+FO_START),1
	ld (ix+FO_FLAGS),0
	ld a,(FL_DIR)
	ld (ix+FO_DIR),a
	ld (ix+FO_DIST),12
	ld hl,(FL_BLOCK)
	ld (ix+FO_BLOCK),l
	ld (ix+FO_BLOCK+1),h
	ld a,(FL_POS)
	ld (ix+FO_POS),a
	ld hl,(FL_ITEM)
	ld (ix+FO_ITEM),l
	ld (ix+FO_ITEM+1),h
	ld a,(FL_ATK)
	ld (ix+FO_ATK),a
	ld hl,(FL_WEAPON)
	ld (ix+FO_WEAPON),l
	ld (ix+FO_WEAPON+1),h
	ld hl,FLY_ACTIVE
	inc (hl)
	ld a,1
	ld (SCENE_DIRTY),a
	ld hl,(FL_ITEM)		; arrows whistle, the rest is thrown
	call ITEM_IX
	ld a,(ix+I_TYPE)
	cp 7
	ld a,26
	jr z,.snd
	ld a,11
.snd:	call SFX_PLAY
	or 1
	ret

FL_POS:		db 0
FL_BLOCK:	dw 0
FL_ITEM:	dw 0
FL_DIR:		db 0
FL_ATK:		db 0
FL_WEAPON:	dw 0
FLY_ACTIVE:	db 0
FLY_TIMER:	db FLY_TICKS

; CLK_THROW - A = 0 / 1 (the half of the view): the hand item flies
;   (clickedSceneThrowItem), thrown by the selected character
CLK_THROW:
	ld hl,(HAND)
	ld c,l
	ld b,h
	ld e,a
	ld a,h
	or l
	ld a,1
	ret z
	ld a,e
	call THROW_START	; A = position index -> HL = block, A = position
	ld a,(SEL_CHAR)
	ld (FL_ATK),a
	ld de,0
	ld (FL_WEAPON),de
	ld a,(TS_POS)
	call LAUNCH
	ld a,1
	ret z
	ld hl,0
	call SET_HAND_ITEM
	ld a,1
	ret

; THROW_START - A = 0..3 -> HL = party block, (TS_POS) = drop position for
;   the facing, (FL_DIR) = facing. Keeps BC.
THROW_START:
	ld e,a
	ld a,(CUR_DIR)
	ld (FL_DIR),a
	add a,a
	add a,a
	add a,e
	ld e,a
	ld d,0
	ld hl,DROP_DIR
	add hl,de
	ld a,(hl)
	ld (TS_POS),a
	ld hl,(CUR_BLOCK)
	ret
TS_POS:		db 0

; ----------------------------------------------------------------------------
; FLY_TICK - per game tick: every FLY_TICKS ticks the objects move
; ----------------------------------------------------------------------------
FLY_TICK:
	ld a,(FLY_ACTIVE)
	or a
	ret z
	ld hl,FLY_TIMER
	dec (hl)
	ret nz
	ld (hl),FLY_TICKS
	ld ix,FLYOBJ
	ld b,10
.lp:	push bc
	ld a,(ix+FO_EN)
	or a
	jr z,.n
	ld (FS_FO),ix
	call FLY_STEP
	ld ix,(FS_FO)
.n:	ld de,FO_SIZE
	add ix,de
	pop bc
	djnz .lp
	ld a,1
	ld (SCENE_DIRTY),a
	ret

; FLY_STEP - (FS_FO) = IX = the object: half a block on
FLY_STEP:
	xor a
	ld (FS_END),a
	ld a,(ix+FO_DIST)
	or a
	jr nz,.d
	inc a
	ld (FS_END),a		; this is its last move
.d:	; next position: FLY_DIRPOS[(dir << 2) + (pos & 3)], bit 7: next block
	ld a,(ix+FO_DIR)
	add a,a
	add a,a
	ld c,a
	ld a,(ix+FO_POS)
	and 3
	add a,c
	ld e,a
	ld d,0
	ld hl,FLY_DIRPOS
	add hl,de
	ld a,(hl)
	ld (FS_NEWBL),a
	and 3
	ld (FS_POS),a
	ld l,(ix+FO_BLOCK)
	ld h,(ix+FO_BLOCK+1)
	ld a,(FS_NEWBL)
	rla
	jr nc,.same
	ld a,(ix+FO_DIR)
	call NEW_BLOCK_POS
	ld ix,(FS_FO)
	ld (ix+FO_START),0
.same:	ld (FS_BLOCK),hl
	call FLY_MOVE
	jr nz,.moved
	ld ix,(FS_FO)
	bit 5,(ix+FO_FLAGS)
	jr z,.stop
	ld l,(ix+FO_BLOCK)
	ld h,(ix+FO_BLOCK+1)
	ld (FS_BLOCK),hl
	ld a,(ix+FO_POS)
	ld (FS_POS),a
	call FLY_HITTEST
	jr .stop
.moved:
	ld a,(FS_NEWBL)
	rla
	jr nc,.hit
	ld hl,(FS_BLOCK)
	ld a,10h
	call RUN_LEVEL_SCRIPT
.hit:	ld ix,(FS_FO)
	ld a,(ix+FO_EN)		; a script may have ended it
	or a
	ret z
	call FLY_HITTEST
	jr z,.end
.stop:	ld a,1
	ld (FS_END),a
.end:	ld a,(FS_END)
	or a
	ret z
	ld ix,(FS_FO)
	; fall through

; FLY_END - IX = object: it lands (endObjectFlight)
FLY_END:
	ld a,(ix+FO_EN)
	or a
	ret z
	cp 2
	jr nz,.item
	push ix
	pop hl
	ld e,l
	ld d,h
	inc de
	ld (hl),0
	ld bc,FO_SIZE-1
	ldir
	ld hl,FLY_ACTIVE
	dec (hl)
	ret
.item:	ld a,18			; it falls (endObjectFlight)
	call SFX_PLAY
	ld l,(ix+FO_ITEM)
	ld h,(ix+FO_ITEM+1)
	push ix
	call ITEM_IX
	ld a,(ix+I_POS)
	and 3
	ld (ix+I_POS),a
	pop ix
	ld l,(ix+FO_BLOCK)
	ld h,(ix+FO_BLOCK+1)
	push ix
	pop de
	push hl
	ld l,e
	ld h,d
	inc de
	ld (hl),0
	ld bc,FO_SIZE-1
	ldir
	ld hl,FLY_ACTIVE
	dec (hl)
	pop hl
	ld a,4
	jp RUN_LEVEL_SCRIPT

; FLY_MOVE - (FS_BLOCK), (FS_POS): the object enters there if the wall it
;   meets lets it (updateObjectFlight) -> NZ; else the wall reacts (a switch
;   gets pressed) -> Z
FLY_MOVE:
	ld ix,(FS_FO)
	ld hl,(FS_BLOCK)
	ld a,(ix+FO_DIR)
	xor 2
	call BLOCK_WALL
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	ld a,(hl)
	ld c,a
	ld a,(ix+FO_EN)
	cp 2
	jr nz,.itm
	; magic: stops at a closed wall of another block
	bit 0,c
	jr nz,.mgo
	ld l,(ix+FO_BLOCK)
	ld h,(ix+FO_BLOCK+1)
	ld de,(FS_BLOCK)
	or a
	sbc hl,de
	jr z,.mgo
	xor a			; blocked: Z
	ret
.mgo:	ld hl,(FS_BLOCK)
	ld (ix+FO_BLOCK),l
	ld (ix+FO_BLOCK+1),h
	ld a,(FS_POS)
	ld (ix+FO_POS),a
	ld a,(ix+FO_DIST)
	inc a
	jr z,.inf
	dec (ix+FO_DIST)
.inf:	or 1
	ret
.itm:	ld a,c
	bit 0,a
	jr nz,.go
	ld c,a
	ld a,(ix+FO_START)
	or a
	jr nz,.go
	bit 1,c			; small items pass flag 2 walls
	jr z,.wall
	ld l,(ix+FO_ITEM)
	ld h,(ix+FO_ITEM+1)
	call ITEM_IX
	ld e,(ix+I_ICON)
	ld d,0
	ld hl,ITEM_SHPMAP
	add hl,de
	ld a,(hl)
	cp ITEM_LARGE_N+1
	jr nc,.go
.wall:	ld ix,(FS_FO)
	ld hl,(FS_BLOCK)
	ld a,(ix+FO_DIR)
	ld c,10h
	call SPECIAL_WALL
	xor a
	ret
.go:	ld ix,(FS_FO)
	ld l,(ix+FO_BLOCK)
	ld h,(ix+FO_BLOCK+1)
	call DRAWOBJ_PTR
	ld e,(ix+FO_ITEM)
	ld d,(ix+FO_ITEM+1)
	call GET_QUEUED_ITEM
	ld ix,(FS_FO)
	ld c,(ix+FO_ITEM)
	ld b,(ix+FO_ITEM+1)
	ld hl,(FS_BLOCK)
	ld e,l
	ld d,h
	call DRAWOBJ_PTR
	ld a,(FS_POS)
	or 4
	call SET_ITEM_POS
	ld ix,(FS_FO)
	ld hl,(FS_BLOCK)
	ld (ix+FO_BLOCK),l
	ld (ix+FO_BLOCK+1),h
	ld a,(FS_POS)
	ld (ix+FO_POS),a
	dec (ix+FO_DIST)
	or 1
	ret

; FLY_HITTEST - (FS_BLOCK), (FS_POS): a monster or the party there gets
;   hit (updateFlyingObjectHitTest) -> NZ
FLY_HITTEST:
	ld ix,(FS_FO)
	ld a,(ix+FO_START)
	or a
	jr z,.go
	; still in the first block: thrown by the party only into monsters
	ld l,(ix+FO_BLOCK)
	ld h,(ix+FO_BLOCK+1)
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	jr nz,.st
	ld a,(ix+FO_ATK)
	or a
	jp m,.go
.st:	ld a,(ix+FO_ATK)
	or a
	jp m,.no
	ld l,(ix+FO_BLOCK)
	ld h,(ix+FO_BLOCK+1)
	call BLOCK_HAS_MONSTER
	jr z,.no
.go:	ld ix,(FS_FO)
	ld a,(ix+FO_EN)
	cp 2
	jr nz,.items
	ld a,(ix+FO_CB)
	or a
	ret z
	push ix
	pop hl
	ld de,FLY_HITREC
	ld bc,FO_SIZE
	ldir
	call MCALL
	dw MAGIC_HIT
	or a
	ret
.items:	ld hl,(FS_BLOCK)
	call BLOCK_HAS_MONSTER
	jr z,.party
	; the monsters at that position (or in the centre)
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.mon:	push bc
	ld hl,(FS_BLOCK)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.nm
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.nm
	ld a,(ix+M_POS)
	cp 4
	jr z,.on
	ld hl,FS_POS
	cp (hl)
	jr nz,.nm
.on:	push ix
	call FLY_MON_HIT
	pop ix
	jr z,.nm
	pop bc
	or 1
	ret
.nm:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .mon
.no:	xor a
	ret
.party:	ld hl,(FS_BLOCK)
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	jr nz,.no
	jp FLY_PARTY_HIT

; FLY_MON_HIT - IX = monster (flyingObjectMonsterHit) -> NZ if hit
FLY_MON_HIT:
	ld (CB_MONSTER),ix
	ld iy,(FS_FO)
	ld l,(iy+FO_ITEM)
	ld h,(iy+FO_ITEM+1)
	ld (CB_ITEM),hl
	push ix
	call ITEM_IX
	ld a,(ix+I_TYPE)
	ld (CB_TYPE),a
	ld a,(ix+I_VALUE)
	ld (CB_VALUE),a
	pop ix
	ld a,1
	ld (CB_FLY),a
	ld iy,(FS_FO)
	ld a,(iy+FO_ATK)
	ld (CB_CHAR),a
	or a
	jp m,.dmg		; nobody threw it: it always hits
	call HIT_TEST
	jr nc,.dmg
	xor a
	ld (CB_FLY),a
	ret
.dmg:	call CALC_MONSTER_DAMAGE
	push af
	xor a
	ld (CB_FLY),a
	pop af
	or a
	jr z,.hit
	ld ix,(CB_MONSTER)
	ld e,a
	ld d,0
	call INFLICT_MONSTER
.hit:	or 1
	ret

; FLY_PARTY_HIT - the object reaches the party (flyingObjectPartyHit)
FLY_PARTY_HIT:
	ld ix,(FS_FO)
	ld l,(ix+FO_ITEM)
	ld h,(ix+FO_ITEM+1)
	ld (CB_ITEM),hl
	ld a,(ix+FO_DIR)
	ld (FS_ODIR),a
	call ITEM_IX
	ld a,(ix+I_TYPE)
	ld (CB_TYPE),a
	ld a,(ix+I_VALUE)
	ld (CB_VALUE),a
	; ps = DSC_ITEMPOSINDEX[(dir << 2) + (pos & 3)]
	ld a,(CUR_DIR)
	add a,a
	add a,a
	ld c,a
	ld a,(ix+I_POS)
	and 3
	add a,c
	ld e,a
	ld d,0
	ld hl,DSC_ITEMPOSINDEX
	add hl,de
	ld a,(hl)
	ld (FS_PS),a
	; both characters of the row when it comes straight on
	ld c,0
	cp 3
	jr c,.b
	ld a,(CUR_DIR)
	ld hl,FS_ODIR
	cp (hl)
	jr z,.b1
	xor 2
	cp (hl)
	jr nz,.b
.b1:	inc c
.b:	ld a,c
	ld (FS_BOTH),a
	ld a,(FS_PS)
	add a,a
	ld (FS_S),a
	ld a,(FS_PS)
	cp 3
	jr c,.s
	ld bc,0102h
	ld a,-1
	call ROLL_DICE
	ld a,(FS_S)
	add a,l
	ld (FS_S),a
.s:	xor a
	ld (FS_HIT),a
	ld b,2
.two:	push bc
	ld a,(FS_S)
	ld e,a
	xor 1
	ld (FS_S),a
	ld d,0
	ld hl,FLY_CHARID
	add hl,de
	ld a,(hl)
	or a
	jp m,.skip
	ld (FS_C),a
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.skip
	; damage: the dice of the item (small), + its value; 1 if not ammunition
	ld a,(CB_TYPE)
	call ITEMTYPE_PTR
	ld a,(hl)
	ld (FS_EP),a
	inc hl
	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld a,(hl)
	call ROLL_DICE
	ld a,(CB_VALUE)
	ld e,a
	rla
	sbc a,a
	ld d,a
	add hl,de
	ld a,(FS_EP)
	cp 2
	jr z,.dm
	cp 3
	jr z,.dm
	ld hl,1
.dm:	bit 7,h
	jr nz,.inf0
	ld a,h
	or l
	jr z,.inf0
	ld a,(FS_C)
	call INFLICT_CHARACTER
.inf0:	ld a,1
	ld (FS_HIT),a
	ld a,(FS_PS)
	cp 2
	jr c,.out
	ld a,(FS_BOTH)
	or a
	jr z,.out
.skip:	pop bc
	djnz .two
	jr .ret
.out:	pop bc
.ret:	ld a,(FS_HIT)
	or a
	ret

FLY_CHARID:	db 0, -1, 1, -1, 2, 4, 3, 5
FLY_DIRPOS:	db 82h,83h,00h,01h, 01h,80h,03h,82h, 02h,03h,80h,81h, 81h,00h,83h,02h
FS_FO:		dw 0
FS_END:		db 0
FS_NEWBL:	db 0
FS_POS:		db 0
FS_BLOCK:	dw 0
FS_ODIR:	db 0
FS_PS:		db 0
FS_BOTH:	db 0
FS_S:		db 0
FS_C:		db 0
FS_HIT:		db 0
FS_EP:		db 0

; FLY_ALL_END - every object lands (a level change)
FLY_ALL_END:
	ld ix,FLYOBJ
	ld b,10
.lp:	push bc
	push ix
	call FLY_END
	pop ix
	ld de,FO_SIZE
	add ix,de
	pop bc
	djnz .lp
	xor a
	ld (FLY_ACTIVE),a
	ret

; ----------------------------------------------------------------------------
; DRAW_FLYING - A = visible block index: its flying objects (drawFlyingObjects)
; ----------------------------------------------------------------------------
DRAW_FLYING:
	ld c,a
	ld a,(FLY_ACTIVE)
	or a
	ret z
	ld a,c
	ld (DF_INDEX),a
	; hidden behind a wall without the niche flag
	ld e,a
	ld d,0
	ld hl,VISWALL
	add hl,de
	ld l,(hl)
	ld h,(LEVELDAT+D_WVMP)>>8
	ld a,(hl)
	or a
	jr z,.vis
	ld h,(LEVELDAT+D_WFLAGS)>>8
	bit 7,(hl)
	ret z
.vis:	ld a,(DF_INDEX)
	add a,a
	ld e,a
	ld d,0
	ld hl,VISBLK
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (DF_BLOCK),de
	; by draw position
	ld hl,DF_OBJS
	ld b,10
	xor a
.clr:	ld (hl),a
	inc hl
	djnz .clr
	ld ix,FLYOBJ
	ld b,10
.scan:	ld a,(ix+FO_EN)
	or a
	jr z,.ns
	ld hl,(DF_BLOCK)
	ld a,(ix+FO_BLOCK)
	cp l
	jr nz,.ns
	ld a,(ix+FO_BLOCK+1)
	cp h
	jr nz,.ns
	ld a,(CUR_DIR)
	ld c,a
	add a,a
	add a,a
	add a,c
	ld c,a
	ld a,(ix+FO_POS)
	and 3
	add a,c
	ld e,a
	ld d,0
	ld hl,DSC_OBJPOSINDEX
	add hl,de
	ld a,(hl)
	add a,a
	ld e,a
	ld hl,DF_OBJS
	add hl,de
	push ix
	pop de
	ld (hl),e
	inc hl
	ld (hl),d
.ns:	ld de,FO_SIZE
	add ix,de
	djnz .scan
	ld hl,DF_OBJS
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
	call DRAW_FLYING1
	pop bc
	pop hl
.nd:	djnz .draw
	ret

; DRAW_FLYING1 - IX = object
DRAW_FLYING1:
	; p = DSC_ITEMPOSINDEX[(dir << 2) + (pos & 3)]
	ld a,(CUR_DIR)
	add a,a
	add a,a
	ld c,a
	ld a,(ix+FO_POS)
	and 3
	add a,c
	ld e,a
	ld d,0
	ld hl,DSC_ITEMPOSINDEX
	add hl,de
	ld a,(hl)
	ld (DF_P),a
	; size FLIGHT_SCL[(index << 2) + p]
	ld c,a
	ld a,(DF_INDEX)
	add a,a
	add a,a
	add a,c
	ld e,a
	ld hl,FLIGHT_SCL
	add hl,de
	ld a,(hl)
	or a
	ret m
	ld (DF_SCL),a
	; x = DSC_SHAPECOORDS[(index * 5 + p) * 2] + 88
	ld a,(DF_INDEX)
	ld c,a
	add a,a
	add a,a
	add a,c
	ld hl,DF_P
	add a,(hl)
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	ld de,DSC_SHAPECOORDS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,88
	add hl,de
	ld (DF_X),hl
	xor a
	ld (DF_MID),a
	ld a,(ix+FO_EN)
	cp 2
	jr nz,.thing
	; magic: its own thrown shape; flag 40h: in the middle of the block
	ld a,(ix+FO_TYPE)
	add a,ITEM_THROWN0
	ld (DF_N),a
	bit 6,(ix+FO_FLAGS)
	jr z,.flipt
	ld a,1
	ld (DF_MID),a
	ld a,(DF_INDEX)
	ld c,a
	add a,a
	add a,a
	add a,c
	add a,4
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	ld de,DSC_SHAPECOORDS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,88
	add hl,de
	ld (DF_X),hl
	jr .flipt
.thing:	; the shape: a thrown shape seen from behind (0) or from the front (1),
	; else the item itself, mirrored when it crosses to the right
	ld l,(ix+FO_ITEM)
	ld h,(ix+FO_ITEM+1)
	push ix
	call ITEM_IX
	ld e,(ix+I_ICON)
	pop ix
	ld d,0
	ld hl,ITEM_SHPMAP
	add hl,de
	ld a,(hl)
	ld (DF_SHP),a
	ld c,0			; direction offset
	ld a,(CUR_DIR)
	cp (ix+FO_DIR)
	jr z,.dofs
	inc c
	xor 2
	cp (ix+FO_DIR)
	jr z,.dofs
	ld c,0FFh
.dofs:	ld a,c
	inc a
	jr z,.item
	ld a,(DF_SHP)
	ld e,a
	ld d,0
	ld hl,FLIGHT_SHPMAP
	add hl,de
	ld a,(hl)
	or a
	jp m,.item
	add a,c
	add a,ITEM_THROWN0	; shape number
	ld (DF_N),a
.flipt:	ld a,(ix+FO_DIR)
	add a,a
	add a,a
	ld c,a
	ld a,(ix+FO_POS)
	and 3
	add a,c
	ld e,a
	ld d,0
	ld hl,FLIGHT_FLIP
	add hl,de
	ld a,(hl)
	ld (DF_FLIP),a
	jr .shape
.item:	ld a,(DF_SHP)		; item shape: < 14 large, 15.. small
	cp ITEM_LARGE_N
	jr c,.n
	ret z
	cp ITEM_LARGE_N+1+ITEM_SMALL_N
	ret nc
	dec a
.n:	ld (DF_N),a
	ld a,(CUR_DIR)
	inc a
	and 3
	cp (ix+FO_DIR)
	ld a,0
	jr nz,.f
	inc a
.f:	ld (DF_FLIP),a
.shape:	; entry = n * 4 + size: dx, dy, w / 2, h
	ld a,(DF_N)
	add a,a
	add a,a
	ld hl,DF_SCL
	add a,(hl)
	ld l,a
	ld h,0
	push hl
	ld de,SHP_ITEM0_0
	add hl,de
	ld (DF_SID),hl
	pop hl
	add hl,hl
	add hl,hl
	ld de,ITEMSHP
	add hl,de
	ld a,(hl)
	ld (DF_DX),a
	inc hl
	ld a,(hl)
	ld (DF_DY),a
	inc hl
	ld a,(hl)
	ld (DF_HW),a
	inc hl
	ld a,(hl)
	ld (DF_H),a
	; mirrored: the crop offset from the other side
	ld a,(DF_FLIP)
	or a
	jr z,.x
	push ix
	ld hl,(DF_SID)
	call SHAPE_ENTRY
	ld c,(ix+4)
	pop ix
	jr c,.x
	ld a,(DF_HW)
	add a,a
	ld hl,DF_DX
	sub (hl)
	sub c
	ld (hl),a
.x:	; x - w / 2 + dx, y = 39 - h + dy
	ld hl,(DF_X)
	res 0,l
	ld a,(DF_HW)
	ld e,a
	ld d,0
	or a
	sbc hl,de
	ld a,(DF_DX)
	ld e,a
	add hl,de
	ex de,hl
	ld a,(DF_H)
	ld c,a
	ld a,(DF_MID)
	or a
	ld a,39
	jr z,.y
	srl c			; centred: 44 - h / 2
	ld a,44
.y:	sub c
	ld hl,DF_DY
	add a,(hl)
	ld c,a
	ld a,(DF_FLIP)
	ld b,a
	ld hl,(DF_SID)
	push ix
	call DRAW_SHAPE
	pop ix
	ret

DF_INDEX:	db 0
DF_BLOCK:	dw 0
DF_OBJS:	ds 10
DF_P:		db 0
DF_SCL:		db 0
DF_X:		dw 0
DF_SHP:		db 0
DF_N:		db 0
DF_FLIP:	db 0
DF_SID:		dw 0
DF_DX:		db 0
DF_DY:		db 0
DF_HW:		db 0
DF_H:		db 0
DF_MID:		db 0
