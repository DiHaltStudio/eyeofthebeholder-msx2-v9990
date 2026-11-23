; ============================================================================
; world.asm - The bridge between the script overlay and the world segment,
;             the level script triggers and the party movement
; Assembler: Sjasm 0.42c
;
; The script interpreter (script.asm) runs from the script segment in page 2,
; so it cannot see LEVELDAT. It calls the resident routines below through
; WCALL, which puts the world segment in page 2 for the call:
;       call WCALL
;       dw   ROUTINE		; registers in and out as ROUTINE wants
; Any resident routine that maps another segment in page 2 puts back the
; one it found (not always the world one), so the overlay may call them.
; ============================================================================

; WCALL - calls the routine whose address follows the call with the world
;   segment in page 2; the previous segment comes back on return.
;   AF, BC, DE, HL pass through in both directions.
; UCALL - the same for the UI overlay (ui.asm)
XCALL:
	push af
	ld a,(FX_SEG)
	jr SEGCALL
AMCALL:
	push af
	ld a,(AM_SEG)
	jr SEGCALL
UCALL:
	push af
	ld a,(UI_SEG)
	jr SEGCALL
WCALL:
	push af
	ld a,(WORLD_SEG)
SEGCALL:
	ld (.new),a
	pop af
	ex (sp),hl
	push de
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (.jp+1),de
	pop de
	ex (sp),hl
	push af
	ld a,(CUR_P2)
	ld (.seg),a
	ld a,(.new)
	call PUT_SEG_P2
	pop af
	push hl			; the previous segment goes on the stack
	ld hl,(.seg)		; (calls may nest)
	ex (sp),hl
.jp:	call 0
	ex (sp),hl		; L = the previous segment
	push af
	ld a,l
	call PUT_SEG_P2
	pop af
	pop hl
	ret
.seg:	dw 0
.new:	db 0

; ----------------------------------------------------------------------------
; RUN_LEVEL_SCRIPT - HL = block, A = event flags (runLevelScript): runs the
;   script attached to the block if its trigger accepts one of the events.
;   Events: 1 the party enters, 2 leaves, 4 an item arrives, 8 an item is
;   taken, 10h an item flies in, 20h timer, 40h the wall is clicked.
;   Callable from anywhere (also from the overlay through WCALL).
; ----------------------------------------------------------------------------
; TRIG_FLAGS - HL = block -> A = the flags of its trigger (0: none)
TRIG_FLAGS:
	ld a,0FFh
	call RUN_LEVEL_SCRIPT.find
	ret nz
	ld a,(hl)
	ret

RUN_LEVEL_SCRIPT:
	call .find
	ret nz
	jr .found
; .find - HL = block -> NZ: no trigger; Z: HL = its flags byte. C = A.
.find:	ld c,a
	ex de,hl		; DE = block
	ld hl,LEVELDAT+D_TRIGGERS
	ld b,(hl)
	inc hl
	inc b
	jr .start
.lp:	ld a,(hl)
	inc hl
	cp e
	jr nz,.n1
	ld a,(hl)
	cp d
	jr z,.fz
.n1:	inc hl
	inc hl
	inc hl
	inc hl
.start:	djnz .lp
	or 1			; none
	ret
.fz:	inc hl
	xor a
	ret
.found:
	; the trigger flags select the events: ((f & F8h) >> 3) | E0h
	ld a,(hl)
	and 0F8h
	rrca
	rrca
	rrca
	or 0E0h
	and c
	ret z
	inc hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ld a,h
	or l
	ret z			; no script
	push de
	ld de,SCRIPT
	add hl,de		; the script start
	pop de
	ld a,(CUR_P2)
	push af
	call SCRIPT_P2
	ld a,c
	call SCR_RUN		; HL = script, DE = block, A = flags
	pop af
	jp PUT_SEG_P2

; ----------------------------------------------------------------------------
; PARTY_TO_BLOCK - HL = block: the party moves there (moveParty): scripts of
;   the block left (2) and of the new one (1), monsters retarget
; ----------------------------------------------------------------------------
PARTY_TO_BLOCK:
	push hl
	call UPDATE_ALL_DESTS
	pop hl
	ld de,(CUR_BLOCK)
	ld (CUR_BLOCK),hl
	push hl
	ex de,hl
	ld a,2
	call RUN_LEVEL_SCRIPT
	; every fourth step the message window moves up a line
	ld hl,MOVE_COUNT
	inc (hl)
	ld a,(hl)
	cp 4
	jr c,.nl
	ld (hl),0
	call MSG_NEWLINE
.nl:	pop hl
	ld a,1
	call RUN_LEVEL_SCRIPT
	call UPDATE_ALL_DESTS
	ld hl,(STEP_COUNT)
	inc hl
	ld (STEP_COUNT),hl
	ld a,1
	ld (SCENE_DIRTY),a
	ret

MOVE_COUNT:	db 0
STEP_COUNT:	dw 0

; SCRIPT_TIMERS_TICK - per tick: the level's script timer and the step
;   counter (updateScriptTimers, EOB1: both run the script of block 0)
SCRIPT_TIMERS_TICK:
	ld a,(LEVELDAT+D_SCRTIMER)
	ld c,a
	bit 1,c
	jr z,.timer
	ld hl,(LEVELDAT+D_SCRTIMER+3)	; steps between calls
	ld a,h
	or l
	jr z,.timer
	ld de,(STEP_COUNT)
	or a
	sbc hl,de
	jr nc,.timer		; stepCounter > steps
	ld hl,0
	ld (STEP_COUNT),hl
	push bc
	ld a,20h
	call RUN_LEVEL_SCRIPT	; block 0
	pop bc
.timer:	bit 0,c
	ret z
	ld hl,(SCR_TIMER)
	dec hl
	ld (SCR_TIMER),hl
	ld a,h
	or l
	ret nz
	ld hl,(LEVELDAT+D_SCRTIMER+1)
	ld (SCR_TIMER),hl
	ld hl,0
	ld a,20h
	call RUN_LEVEL_SCRIPT
	ld a,1
	ld (SCENE_DIRTY),a
	ret

SCR_TIMER:	dw 1

; ----------------------------------------------------------------------------
; Small world accessors for the overlay (call them through WCALL)
; ----------------------------------------------------------------------------

; W_SET_WALL - HL = block, A = side, C = wall type
W_SET_WALL:
	push hl
	add hl,hl
	add hl,hl
	ld e,a
	ld d,0
	add hl,de
	ld de,LEVELDAT+D_MAZE
	add hl,de
	ld (hl),c
	pop hl
	jp SCENE_NEEDS_UPDATE

; W_SET_WALLS4 - HL = block, C = wall type for the four sides
W_SET_WALLS4:
	push hl
	add hl,hl
	add hl,hl
	ld de,LEVELDAT+D_MAZE
	add hl,de
	ld (hl),c
	inc hl
	ld (hl),c
	inc hl
	ld (hl),c
	inc hl
	ld (hl),c
	pop hl
	jp SCENE_NEEDS_UPDATE

; W_BLOCK_MONSTERS - HL = block -> A = monsters on it
W_BLOCK_MONSTERS:
	call BLOCKCNT_PTR
	ld a,(hl)
	ret

; W_OPEN_DOOR / W_CLOSE_DOOR - HL = block (openDoor, closeDoor)
W_OPEN_DOOR:
	ld (DOOR_BLOCK),hl
	ld a,1
	jp OPEN_CLOSE
W_CLOSE_DOOR:
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	add hl,de
	ret z
	call BLOCK_HAS_MONSTER
	ret nz
	ld (DOOR_BLOCK),hl
	ld a,-1
	jp OPEN_CLOSE

; W_MOVE_MONSTERS - HL = from, DE = to: every monster there moves
W_MOVE_MONSTERS:
	ld (WM_FROM),hl
	ld (WM_TO),de
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	push bc
	ld hl,(WM_FROM)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.n
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.n
	ld hl,(WM_TO)
	ld a,(ix+M_DIR)
	call MON_PLACE
.n:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .lp
	ret
WM_FROM:	dw 0
WM_TO:		dw 0

; W_MON_FLAG - A = monster, C = flag bit: set it, the monster hunts
W_MON_FLAG:
	call MON_IX
	ld a,c
	call BIT_MASK
	or (ix+M_FLAGS)
	ld (ix+M_FLAGS),a
	ld (ix+M_MODE),0
	ret

; MON_IX - A = monster number -> IX = its record. Preserves BC.
MON_IX:
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl		; *8
	ld e,l
	ld d,h
	add hl,hl
	add hl,de		; *24
	ld de,LEVELDAT+D_MONSTERS
	add hl,de
	push hl
	pop ix
	ret

; BIT_MASK - A = bit number -> A = 1 << bit
BIT_MASK:
	and 7
	ld b,a
	ld a,1
	ret z
.lp:	add a,a
	djnz .lp
	ret

; W_REPLACE_MONSTER - (WR_*) a new monster in the first free slot unless
;   the block is taken (EoBEngine::replaceMonster, initMonster)
W_REPLACE_MONSTER:
	ld hl,(WR_BLOCK)
	call BLOCK_HAS_MONSTER
	ret nz
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
	ld c,0
.lp:	ld a,(ix+M_HP+1)
	or a
	jp m,.free
	or (ix+M_HP)
	jr z,.free
	ld de,MON_SIZE
	add ix,de
	inc c
	djnz .lp
	ret
.free:	; clear the record
	push ix
	pop hl
	ld b,MON_SIZE
.clr:	ld (hl),0
	inc hl
	djnz .clr
	ld a,(WR_UNIT)
	add a,a
	bit 0,c
	jr z,.u
	inc a
.u:	ld (ix+M_UNIT),a
	ld a,(WR_TYPE)
	ld (ix+M_TYPE),a
	ld a,(WR_POS)
	ld (ix+M_POS),a
	ld a,(WR_SHP)
	ld (ix+M_SHP),a
	ld a,(WR_MODE)
	ld (ix+M_MODE),a
	ld a,(WR_SPELL)
	ld (ix+M_SPELL),a
	ld a,(WR_DIR)
	and 3
	ld (ix+M_DIR),a
	ld hl,(WR_RITEM)
	ld (ix+M_RITEM),l
	ld (ix+M_RITEM+1),h
	ld hl,(WR_FITEM)
	ld (ix+M_FITEM),l
	ld (ix+M_FITEM+1),h
	call MON_PROPS
	call MON_RANGED_INIT
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
	; placeMonster: the block was 0, so only the new one counts
	ld hl,(WR_BLOCK)
	ld (ix+M_BLOCK),l
	ld (ix+M_BLOCK+1),h
	push hl
	call BLOCKCNT_PTR
	inc (hl)
	pop hl
	jp SCENE_NEEDS_UPDATE

WR_UNIT:	db 0
WR_BLOCK:	dw 0
WR_POS:		db 0
WR_DIR:		db 0
WR_TYPE:	db 0
WR_SHP:		db 0
WR_MODE:	db 0
WR_SPELL:	db 0
WR_RITEM:	dw 0
WR_FITEM:	dw 0

; W_MOVE_ITEMS - HL = from, DE = to (same level): every item of the block
;   moves, keeping its position
W_MOVE_ITEMS:
	ld (WM_FROM),hl
	ld (WM_TO),de
.lp:	ld hl,(WM_FROM)
	call DRAWOBJ_PTR
	ld a,(hl)
	inc hl
	or (hl)
	ret z
	dec hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a			; the newest one
	push hl
	call ITEM_IX
	ld a,(ix+I_POS)
	ld (WM_POS),a
	ld hl,(WM_FROM)
	call DRAWOBJ_PTR
	pop de
	call GET_QUEUED_ITEM	; by number
	ld c,l
	ld b,h
	ld hl,(WM_TO)
	ld e,l
	ld d,h
	call DRAWOBJ_PTR
	ld a,(WM_POS)
	call SET_ITEM_POS
	jr .lp
WM_POS:		db 0

; W_DELETE_ITEMS - HL = block, A = item type (FFh: all) (deleteBlockItem)
W_DELETE_ITEMS:
	ld (WD_TYPE),a
	ld (WD_BLOCK),hl
	call DRAWOBJ_PTR
	ld (WD_HEAD),hl
	; take every item out and put back the ones of another type
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or e
	ret z
	ld hl,0
	ld (WD_KEEP),hl
.lp:	ld hl,(WD_HEAD)
	ld a,(hl)
	inc hl
	or (hl)
	jr z,.back
	dec hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	ex de,hl
	ld hl,(WD_HEAD)
	call GET_QUEUED_ITEM
	push hl
	call ITEM_IX
	pop hl
	ld a,(WD_TYPE)
	cp 0FFh
	jr z,.del
	cp (ix+I_TYPE)
	jr z,.del
	; keep: chained in WD_KEEP through I_BLOCK for now
	ld de,(WD_KEEP)
	ld (ix+I_BLOCK),e
	ld (ix+I_BLOCK+1),d
	ld (WD_KEEP),hl
	jr .lp
.del:	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
	ld (ix+I_LEVEL),0
	jr .lp
.back:	ld hl,(WD_KEEP)
	ld a,h
	or l
	ret z
	call ITEM_IX
	ld e,(ix+I_BLOCK)
	ld d,(ix+I_BLOCK+1)
	ld (WD_KEEP),de
	ld c,l
	ld b,h
	ld hl,(WD_BLOCK)
	ld e,l
	ld d,h
	ld a,(ix+I_POS)
	push af
	ld hl,(WD_HEAD)
	pop af
	call SET_ITEM_POS
	jr .back
WD_TYPE:	db 0
WD_BLOCK:	dw 0
WD_HEAD:	dw 0
WD_KEEP:	dw 0

; W_COUNT_ITEMS - HL = block, DE = item number or FFFFh, C = item type or
;   FFh, B = 0: the first match / 1: how many (countQueuedItems, flying ones
;   included) -> HL
W_COUNT_ITEMS:
	call DRAWOBJ_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	ret z
	ld (WC_FIRST),hl
	ld (WC_ID),de
	ld a,c
	ld (WC_TYPE),a
	ld a,b
	ld (WC_MODE),a
	ld de,0
	ld (WC_N),de
.lp:	ld (WC_CUR),hl
	call ITEM_IX
	; a match: the number asked for, or the type asked for, or anything
	ld de,(WC_ID)
	ld a,d
	and e
	inc a
	jr z,.noid
	ld a,e
	cp l
	jr nz,.next
	ld a,d
	cp h
	jr nz,.next
	jr .match
.noid:	ld a,(WC_TYPE)
	cp 0FFh
	jr z,.match
	cp (ix+I_TYPE)
	jr nz,.next
.match:	ld a,(WC_MODE)
	or a
	jr nz,.cnt
	ld hl,(WC_CUR)
	ret
.cnt:	ld hl,(WC_N)
	inc hl
	ld (WC_N),hl
.next:	ld l,(ix+I_PREV)
	ld h,(ix+I_PREV+1)
	ld de,(WC_FIRST)
	or a
	sbc hl,de
	add hl,de
	jr nz,.lp
	ld hl,(WC_N)
	ld a,(WC_MODE)
	or a
	ret nz
	ld hl,0
	ret
WC_FIRST:	dw 0
WC_CUR:		dw 0
WC_ID:		dw 0
WC_TYPE:	db 0
WC_MODE:	db 0
WC_N:		dw 0

; W_IDENTIFY_BLOCK - HL = block: the items lying there get identified
W_IDENTIFY_BLOCK:
	call DRAWOBJ_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	jp IDENTIFY_QUEUE

; IDENTIFY_QUEUE - HL = newest item of a queue (0: none): flag 40h for all
IDENTIFY_QUEUE:
	ld a,h
	or l
	ret z
	ld (WC_FIRST),hl
.lp:	call ITEM_IX
	set 6,(ix+I_FLAGS)
	ld l,(ix+I_PREV)
	ld h,(ix+I_PREV+1)
	ld de,(WC_FIRST)
	or a
	sbc hl,de
	add hl,de
	jr nz,.lp
	ret

; DUPLICATE_ITEM - HL = item -> HL = a copy in the first free record
;   (0 if the original is not in use or there is no room)
DUPLICATE_ITEM:
	call ITEM_IX
	ld a,(ix+I_BLOCK)
	and (ix+I_BLOCK+1)
	inc a
	jr z,.none
	push ix
	ld bc,1
.lp:	ld l,c
	ld h,b
	call ITEM_IX
	ld a,(ix+I_BLOCK)
	and (ix+I_BLOCK+1)
	inc a
	jr z,.free
	inc bc
	ld a,b
	cp ITEM_MAX>>8
	jr nz,.lp
	ld a,c
	cp ITEM_MAX&0FFh
	jr nz,.lp
	pop ix
.none:	ld hl,0
	ret
.free:	pop hl			; the original
	push ix
	pop de
	push bc
	ld bc,I_SIZE
	ldir
	pop hl
	ret

; NPC_EQUIP - IY = a freshly copied NPC record.
NPC_EQUIP:
	; EOB.EXE 3E212h..3E246h: each occupied slot 0..24 gets a distinct
	; item record. Rings (25/26) have no entries in the original presets.
	ld b,25
.items:	ld l,(iy+P_INV)
	ld h,(iy+P_INV+1)
	ld a,h
	or l
	jr z,.next
	push bc
	call DUPLICATE_ITEM
	pop bc
	ld (iy+P_INV),l
	ld (iy+P_INV+1),h
.next:	inc iy
	inc iy
	djnz .items
	ret

; NPC_CLEAR_MAGIC - C = recruit's slot, MAGIC mapped. The original copies
; a whole 243-byte preset with empty prepared spells and character timers.
; Those fields live in separate arrays on the MSX.
NPC_CLEAR_MAGIC:
	ld a,100
	ld e,c
	call MUL8
	ld de,CH_SPELLS
	add hl,de
	xor a
	ld b,100
.spell:	ld (hl),a
	inc hl
	djnz .spell
	ld a,12
	ld e,c
	call MUL8
	ld de,CH_EVENTS
	add hl,de
	ld b,4
.event:	ld a,(hl)
	ld (hl),0
	inc hl
	or (hl)
	ld (hl),0
	inc hl
	ld (hl),0
	inc hl
	jr z,.next
	ld a,(MAGIC_ACTIVE)
	dec a
	ld (MAGIC_ACTIVE),a
.next:	djnz .event
	ret

; MSG_NEWLINE - the message window moves up one line
MSG_NEWLINE:
	call PTR_HIDE
	ld hl,CMD_MSGSCROLL
	ld a,V9_LOG_COPY
	call V9_LMMM
	ld hl,CMD_MSGCLEAR
	ld a,C_BLACK
	jp V9_LMMV

; UPDATE_ALL_DESTS - every monster checks where the party is
UPDATE_ALL_DESTS:
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	push bc
	ld a,(ix+M_BLOCK)
	or (ix+M_BLOCK+1)
	call nz,MON_UPDATE_DEST
	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .lp
	ret

; W_REST_MONSTERS - while resting the monsters of units 0 and 1 go on five
;   times (restParty_updateMonsters) -> NZ if one comes next to the party
W_REST_MONSTERS:
	ld b,5
.lp:	push bc
	xor a
	call UPDATE_MONSTERS
	ld a,1
	call UPDATE_MONSTERS
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.m:	push bc
	ld a,(ix+M_BLOCK)
	or (ix+M_BLOCK+1)
	jr z,.n
	ld a,(ix+M_MODE)
	cp 8
	jr z,.n
	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld de,(CUR_BLOCK)
	call BLOCK_DISTANCE
	cp 2
	jr nc,.n
	pop bc
	pop bc
	or 1
	ret
.n:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .m
	pop bc
	djnz .lp
	xor a
	ret

; MCALL - like WCALL, for the magic overlay (magic.asm)
MCALL:
	push af
	ld a,(MAGIC_SEG)
	jp SEGCALL
; SCALL - the same for the script overlay (script.asm)
SCALL:
	push af
	ld a,(SCRIPT_SEG)
	jp SEGCALL

; ----------------------------------------------------------------------------
; Magic: world parts of the spells
; ----------------------------------------------------------------------------

; FLY_ADD - FLY_NEW becomes a flying object (launchMagicObject)
FLY_ADD:
	ld hl,FLYOBJ
	ld b,10
	ld de,FO_SIZE
.f:	ld a,(hl)
	or a
	jr z,.got
	add hl,de
	djnz .f
	ret
.got:	ex de,hl
	ld hl,FLY_NEW
	ld bc,FO_SIZE
	ldir
	ld hl,FLY_ACTIVE
	inc (hl)
	ld a,1
	ld (SCENE_DIRTY),a
	ret

; W_MAGIC_DAMAGE - a magic flight (FLY_HITREC) hits the monsters of its
;   block: (WD_TIMES) x rolls of (WD_DICE) + (WD_INC) (magicObjectDamageHit)
;   -> A = 1 if something was hit
W_MAGIC_DAMAGE:
	xor a
	ld (WD_HIT),a
	ld hl,(FLY_HITREC+FO_BLOCK)
	call BLOCK_HAS_MONSTER
	jp z,W_MAGIC_PARTY
	ld a,(FLY_HITREC+FO_ATK)
	or a
	jp p,.mon
	ld a,(FLY_HITREC+FO_FLAGS)
	bit 4,a
	jp z,.done
.mon:	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	push bc
	ld hl,(FLY_HITREC+FO_BLOCK)
	ld a,(ix+M_BLOCK)
	cp l
	jp nz,.next
	ld a,(ix+M_BLOCK+1)
	cp h
	jp nz,.next
	; the whole block (flag 2), else its position or the centre
	ld a,(FLY_HITREC+FO_FLAGS)
	bit 1,a
	jr nz,.dmg
	ld a,(ix+M_POS)
	cp 4
	jr z,.dmg
	ld hl,FLY_HITREC+FO_POS
	cp (hl)
	jr nz,.next
.dmg:	; to hit (flag 4)
	ld a,(FLY_HITREC+FO_FLAGS)
	bit 2,a
	jr z,.roll
	ld a,(FLY_HITREC+FO_ATK)
	or a
	jp m,.roll
	ld (CB_CHAR),a
	ld hl,0
	ld (CB_ITEM),hl
	ld a,1
	ld (CB_FLY),a
	push ix
	call HIT_TEST
	pop ix
	ld a,0
	ld (CB_FLY),a
	jr c,.next
.roll:
	call WD_ROLL
	push hl
	call MON_PROPS
	pop hl
	call XCALL
	dw FX_MAGIC_SAVE_MON
.inf:	ld a,h
	or l
	jr z,.hit
	ex de,hl
	push ix
	call INFLICT_MONSTER
	pop ix
.hit:	ld a,1
	ld (WD_HIT),a
	; a single target: done (flags 1 / nothing)
	ld a,(FLY_HITREC+FO_FLAGS)
	bit 1,a
	jr nz,.next
	pop bc
	jr .done
.next:	ld de,MON_SIZE
	add ix,de
	pop bc
	dec b
	jp nz,.lp
.done:	; the lightning bolt goes on through them
	ld a,(FLY_HITREC+FO_ITEM)
	cp 5
	ld a,0
	ret z
	ld a,(WD_HIT)
	ret

; WD_ROLL - base damage only. Target-specific saving throws follow the roll.
WD_ROLL:
	ld a,(WD_TIMES)
	ld b,a
	ld hl,0
.rl:	push bc
	push hl
	ld bc,(WD_DICE)
	ld a,(WD_INC)
	call ROLL_DICE
	pop de
	add hl,de
	pop bc
	djnz .rl
	ret

; W_MAGIC_PARTY - a magic object reaches the party (magicObjectHit): all
;   the characters (flag 2) or the one at its position -> A = 1 if it hit
W_MAGIC_PARTY:
	ld hl,(FLY_HITREC+FO_BLOCK)
	ld de,(CUR_BLOCK)
	or a
	sbc hl,de
	ld a,0
	ret nz
	ld a,(FLY_HITREC+FO_FLAGS)
	bit 1,a
	jr z,.one
	xor a
.all:	push af
	call WP_HIT
	pop af
	inc a
	cp 6
	jr c,.all
	ld a,1
	ret
.one:	; its row: DSC_ITEMPOSINDEX[(dir << 2) + (pos & 3)], then the two sides
	ld a,(CUR_DIR)
	add a,a
	add a,a
	ld c,a
	ld a,(FLY_HITREC+FO_POS)
	and 3
	add a,c
	ld e,a
	ld d,0
	ld hl,DSC_ITEMPOSINDEX
	add hl,de
	ld a,(hl)
	add a,a
	ld (FS_S),a
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
	jp m,.sk
	ld (FS_C),a
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.sk
	pop bc
	ld a,(FS_C)
	call WP_HIT
	ld a,1
	ret
.sk:	pop bc
	djnz .two
	ld a,1
	ret

; WP_HIT - A = character: the magic damage, a shield stops magic missiles
WP_HIT:
	ld (FS_C),a
	call CHAR_PTR
	call CHAR_ALIVE_R
	ret z
	ld a,(FLY_HITREC+FO_CB)
	cp 4
	jr nz,.dmg
	bit 3,(iy+P_EFFECT)
	ret nz
.dmg:
	call WD_ROLL
	ld a,(FS_C)
	call XCALL
	dw FX_MAGIC_SAVE_CHAR
	ld a,h
	or l
	ret z
	ld a,(FS_C)
	jp INFLICT_CHARACTER

; W_LDIR - LDIR with the world segment in page 2 (WCALL W_LDIR): the
;   overlays copy world data through BOUNCE
W_LDIR:
	ldir
	ret

; W_FLY_TURN - DE = block, C = turn: the objects flying there change their
;   direction (oeob_changeDirection -11)
W_FLY_TURN:
	ld hl,FLYOBJ
	ld b,10
.lp:	push hl
	ld a,(hl)
	or a
	jr z,.n
	inc hl
	inc hl
	inc hl
	push hl			; FO_DIR
	inc hl
	inc hl
	ld a,(hl)		; FO_BLOCK
	inc hl
	cp e
	ld a,(hl)
	pop hl
	jr nz,.n
	cp d
	jr nz,.n
	ld a,(hl)
	add a,c
	and 3
	ld (hl),a
.n:	pop hl
	ld a,l
	add a,FO_SIZE
	ld l,a
	djnz .lp
	ret

; W_WAKE_PATROL - the drow patrol attacks (runNpcDialogue, case 3): the
;   waiting monsters (mode 8) wander (mode 5)
W_WAKE_PATROL:
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
	ld de,MON_SIZE
.lp:	ld a,(ix+M_MODE)
	cp 8
	jr nz,.n
	ld (ix+M_MODE),5
.n:	add ix,de
	djnz .lp
	ret

; W_HOLD - C = 1 hold person / 2 hold monster: the monsters of the block
;   of (FLY_HITREC) are paralyzed (magicObjectStatusHit) -> A = 1 if any
W_HOLD:
	ld a,b
	ld (WH_FEAR),a
	ld a,c
	ld (WH_MASK),a
	xor a
	ld (WD_HIT),a
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	push bc
	ld hl,(FLY_HITREC+FO_BLOCK)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.nx
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.nx
	ld a,1
	ld (WD_HIT),a
	call MON_PROPS
	ld a,100		; it evades
	call RND_RANGE
	cp (iy+MP_EVADE)
	jr c,.nx
	ld a,(iy+MP_LEVEL)	; a saving throw against spells
	cp 18
	jr c,.l
	ld a,17
.l:	srl a
	ld e,a
	ld d,0
	ld hl,MON_SAVE4
	add hl,de
	ld c,(hl)
	ld a,20
	call RND_RANGE
	cp c
	jr nc,.nx
	ld a,(WH_MASK)
	and (iy+MP_TFLAGS)
	jr z,.nx
	ld a,(WH_FEAR)
	or a
	jr nz,.fear
	ld (ix+M_MODE),10
	ld (ix+M_SPELL),15
	jr .nx
.fear:	ld a,(ix+M_MODE)	; (magicObjectStatusHit type 6)
	cp 7
	jr z,.nx
	cp 8
	jr z,.nx
	cp 10
	jr z,.nx
	ld (ix+M_MODE),0
	ld (ix+M_SPELL),20
	set 3,(ix+M_FLAGS)
.nx:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .lp
	ld a,(WD_HIT)
	ret
WH_MASK:	db 0
WH_FEAR:	db 0
MON_SAVE4:	db 19,17,16,14,13,11,10,8,7,6

WD_DICE:	dw 0
WD_INC:		db 0
WD_TIMES:	db 1
WD_HIT:		db 0

; W_FRONT_DAMAGE - burning hands: the monsters of the two front positions
;   of the block ahead take (WD_DICE) + (WD_INC)
W_FRONT_DAMAGE:
	ld a,(CUR_DIR)
	call BLOCK_AHEAD
	ld (FD_BLOCK),hl
	ld a,(CUR_DIR)
	add a,a
	ld e,a
	ld d,0
	ld hl,BURNING_DEST
	add hl,de
	ld a,(hl)
	ld (FD_P0),a
	inc hl
	ld a,(hl)
	ld (FD_P1),a
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	push bc
	ld hl,(FD_BLOCK)
	ld a,(ix+M_BLOCK)
	cp l
	jr nz,.n
	ld a,(ix+M_BLOCK+1)
	cp h
	jr nz,.n
	ld a,(ix+M_POS)
	ld hl,FD_P0
	cp (hl)
	jr z,.d
	inc hl
	cp (hl)
	jr nz,.n
.d:	ld bc,(WD_DICE)
	ld a,(WD_INC)
	call ROLL_DICE
	push hl
	call MON_PROPS
	pop hl
	call XCALL
	dw FX_EVADE_MON
	ld a,h
	or l
	jr z,.n
	ex de,hl
	push ix
	call INFLICT_MONSTER
	pop ix
.n:	ld de,MON_SIZE
	add ix,de
	pop bc
	djnz .lp
	jp DIRTY
FD_BLOCK:	dw 0
FD_P0:		db 0
FD_P1:		db 0
BURNING_DEST:	db 2,3, 0,2, 0,1, 1,3

; CAUSE_WOUNDS - (CB_CHAR) touches the monster ahead: (WD_DICE) + (WD_INC)
;   if it hits (causeWounds)
CAUSE_WOUNDS:
	ld hl,(CUR_BLOCK)
	ld a,(CUR_DIR)
	call NEW_BLOCK_POS
	call CLOSEST_MONSTER
	jr c,.none
	ld (CB_MONSTER),ix
	xor a
	ld (CB_FLY),a
	call HIT_TEST
	ret c
	ld bc,(WD_DICE)
	ld a,(WD_INC)
	call ROLL_DICE
	push hl
	call MON_PROPS
	pop hl
	call XCALL
	dw FX_EVADE_MON
	ld a,h
	or l
	ret z
	ex de,hl
	ld ix,(CB_MONSTER)
	jp INFLICT_MONSTER
.none:	ld hl,STR_NOMONSTER
	jp MSG_PRINT

FLY_NEW:	ds FO_SIZE
FLY_HITREC:	ds FO_SIZE

; Automap observation: the same wall id/tables as the view and movement.
; HL=block, A=side -> B=flags, C=visual wall set, A=wall id; HL preserved.
AM_WALL:
 call BLOCK_WALL
 push hl
 ld l,a
 ld h,(LEVELDAT+D_WFLAGS)>>8
 ld b,(hl)
 ld h,(LEVELDAT+D_WVMP)>>8
 ld c,(hl)
 pop hl
 ret
AM_SEG: db 0

FX_SEG: db 0
; Cross-bank copy: caller supplies addresses visible in the selected bank.
MEM_COPY:
 ldir
 ret

F_EFFECTS:	db LANG_C1,LANG_C2,5Ch,"EFFECTS.OVL",0
F_AUTOMAP:	db LANG_C1,LANG_C2,5Ch,"AUTOMAP.OVL",0
