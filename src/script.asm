; ============================================================================
; script.asm - The level script interpreter (EoBInfProcessor with the EOB1
;              opcodes, ScummVM script_eob.cpp)
; Assembler: Sjasm 0.42c
;
; An overlay: it is assembled to build/SCRIPT.OVL and lives in the script
; segment at OVL_BASE, next to the script itself (LEVELn.INF at SCRIPT,
; offsets as in the file) and the item names. It runs with that segment in
; page 2, so everything in the world segment is reached through WCALL
; (world.asm). Tools: tools/inf_disasm.py lists the scripts.
;
; Opcodes are the bytes -1 .. -26; anything else is skipped. HL is the
; script pointer while an opcode runs.
; ============================================================================

	output "../build/SCRIPT.OVL"
	org OVL_BASE

; SCR_RUN - HL = script, DE = block (the trigger), A = event flags
SCR_RUN:
	ld (SC_FLAGS),a
	ld (SC_FUNC),de
	xor a
	ld (SC_ABORT),a
	ld (SC_ABORTSUB),a
	ld (SC_DLG),a
	ld a,0FFh
	ld (SC_ACTIVE),a
SCR_LOOP:
	ld a,(hl)
	inc hl
	cp 0E6h			; -26 .. -1
	jr c,SCR_NEXT
	cpl			; index 0..25
	add a,a
	ld e,a
	ld d,0
	push hl
	ld hl,SC_OPS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	ex (sp),hl
	ret			; to the opcode, HL = its operands
SCR_NEXT:
	ld a,(SC_ABORT)
	ld c,a
	ld a,(SC_ABORTSUB)
	or c
	jr z,SCR_LOOP
	ret

SC_OPS:	dw OP_SETWALL, OP_TOGGLEWALL, OP_OPENDOOR, OP_CLOSEDOOR, OP_REPLACEMON
	dw OP_MOVE, OP_INVTOBLOCK, OP_PRINT, OP_SETFLAGS, OP_SOUND
	dw OP_CLEARFLAGS, OP_MODHP, OP_DAMAGE, OP_JUMP, OP_END
	dw OP_RETURN, OP_CALL, OP_EVAL, OP_DELETEITEM, OP_NEWLEVEL
	dw OP_EXPERIENCE, OP_CREATEITEM, OP_LAUNCH, OP_CHANGEDIR, OP_IDENTIFY
	dw OP_SEQUENCE

; GETW - (HL) -> DE, HL += 2
GETW:	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ret

; ----------------------------------------------------------------------------
; walls and doors
; ----------------------------------------------------------------------------
OP_SETWALL:
	ld a,(hl)
	inc hl
	cp 0E9h
	jr z,.side
	cp 0EDh
	jr z,.dir
	cp 0F7h
	jp nz,SCR_NEXT
	call GETW		; block, type -> the four sides
	ld c,(hl)
	inc hl
	push hl
	ex de,hl
	call WCALL
	dw W_SET_WALLS4
	pop hl
	jp SCR_NEXT
.dir:	ld a,(hl)
	inc hl
	and 3
	ld (CUR_DIR),a
	jp SC_DIRTY
.side:	call GETW		; block, side, type
	ld a,(hl)
	inc hl
	ld c,(hl)
	inc hl
	push hl
	ex de,hl
	call WCALL
	dw W_SET_WALL
	pop hl
	jp SCR_NEXT

OP_TOGGLEWALL:
	ld a,(hl)
	inc hl
	cp 0E9h
	jr z,.side
	cp 0EAh
	jr z,.door
	cp 0F7h
	jp nz,SCR_NEXT
	; block, a, b: side 0 decides, the four sides change
	call GETW
	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	push hl
	ex de,hl
	xor a
	push bc
	call WCALL
	dw BLOCK_WALL
	pop bc
	cp b
	jr z,.t4
	ld c,b
.t4:	call WCALL
	dw W_SET_WALLS4
	pop hl
	jp SCR_NEXT
.side:	call GETW		; block, side, a, b
	ld a,(hl)
	inc hl
	ld (SC_TMP),a
	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	push hl
	ex de,hl
	push bc
	call WCALL
	dw BLOCK_WALL
	pop bc
	cp b
	jr z,.t1
	ld c,b
.t1:	ld a,(SC_TMP)
	call WCALL
	dw W_SET_WALL
	pop hl
	jp SCR_NEXT
.door:	call GETW
	push hl
	ex de,hl
	call WCALL
	dw PROCESS_DOOR
	pop hl
	jp SCR_NEXT

OP_OPENDOOR:
	call GETW
	push hl
	ex de,hl
	call WCALL
	dw W_OPEN_DOOR
	pop hl
	jp SCR_NEXT

OP_CLOSEDOOR:
	call GETW
	push hl
	ex de,hl
	call WCALL
	dw W_CLOSE_DOOR
	pop hl
	jp SCR_NEXT

; ----------------------------------------------------------------------------
; monsters, party, items on the map
; ----------------------------------------------------------------------------
OP_REPLACEMON:
	inc hl
	ld a,(hl)
	inc hl
	ld (WR_UNIT),a
	call GETW
	ld (WR_BLOCK),de
	ld a,(hl)
	inc hl
	ld (WR_POS),a
	ld a,(hl)
	inc hl
	ld (WR_DIR),a
	ld a,(hl)
	inc hl
	ld (WR_TYPE),a
	ld a,(hl)
	inc hl
	ld (WR_SHP),a
	ld a,(hl)
	inc hl
	ld (WR_MODE),a
	ld a,(hl)
	inc hl
	ld (WR_SPELL),a
	call GETW
	ld (WR_RITEM),de
	call GETW
	ld (WR_FITEM),de
	push hl
	call WCALL
	dw W_REPLACE_MONSTER
	pop hl
	jp SC_DIRTY

OP_MOVE:
	ld a,(hl)
	inc hl
	ld (SC_TMP),a
	ld de,0
	cp 0F1h
	call nz,GETW		; c (not for -15)
	ld (SC_FROM),de
	call GETW		; d
	ld (SC_TO),de
	push hl
	ld a,(SC_TMP)
	cp 0F3h
	jr z,.mon
	cp 0E8h
	jr z,.party
	cp 0F5h
	jr nz,.done
	ld hl,(SC_FROM)
	ld de,(SC_TO)
	call WCALL
	dw W_MOVE_ITEMS
	jr .done
.mon:	ld hl,(SC_FROM)
	ld de,(SC_TO)
	call WCALL
	dw W_MOVE_MONSTERS
	jr .done
.party:	; the party moves: a nested script run may happen, keep our state
	ld hl,(SC_DLG)		; SC_DLG, SC_ACTIVE
	push hl
	ld hl,(SC_FUNC)
	push hl
	ld hl,(SC_FLAGS)	; SC_FLAGS, SC_ABORT
	push hl
	ld a,(SC_SUBPOS)
	push af
	ld hl,(SC_TO)
	call WCALL
	dw PARTY_TO_BLOCK
	pop af
	ld c,a
	ld a,(SC_ABORTSUB)
	or a
	jr nz,.keep
	ld a,c
	ld (SC_SUBPOS),a
.keep:	pop hl
	ld (SC_FLAGS),hl
	pop hl
	ld (SC_FUNC),hl
	pop hl
	ld (SC_DLG),hl
.done:	pop hl
	jp SC_DIRTY

OP_INVTOBLOCK:
	ld a,(hl)		; character (-1: random)
	inc hl
	ld c,a
	call GETW
	ld (SC_TO),de
	ld a,(hl)
	inc hl
	ld (SC_TMP),a
	push hl
	ld a,c
	cp 0FFh
	jr nz,.ch
	ld bc,0106h		; 1d6 - 1
	ld a,-1
	call ROLL_DICE
	ld a,l
.ch:	; DOS scans all six character slots, including a recruit in slot 5
	ld (SC_CHAR),a
	call CHAR_PTR
	ld a,(iy+P_FLAGS)
	or a
	jr nz,.got
	ld a,(SC_CHAR)
	inc a
	cp 6
	jr c,.ch
	xor a
	jr .ch
.got:	ld a,(CONTROL_MODE)
	or a
	jr z,.roll
	ld a,(SC_CHAR)
	ld c,a
	ld a,(UPDATE_CHAR)
	cp c
	jr z,.done		; the character whose inventory is open is protected
.roll:	ld bc,011Bh
	xor a
	call ROLL_DICE
	ld c,l			; initial 1d27, then advance cyclically
	ld b,27
.slot:	ld a,c
	cp 27			; no inventory item exists beyond slot 26
	jr nc,.next
	cp 16			; quiver
	jr z,.next
	cp 2
	jr nc,.inspect
	ld a,(CONTROL_MODE)	; both hands are safe with the party panel open
	or a
	jr z,.next
.inspect:
	ld a,c
	call SLOT_PTR
	ld (SC_PTR),hl
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.next
	ld (SC_ITEM),hl
	call ITEM_IX
	ld e,(ix+I_ICON)
	ld d,0
	ld hl,ITEM_SHPMAP
	add hl,de
	ld a,(hl)
	bit 7,a			; signed DOS shape index, -1 has no shape
	jr nz,.next
	cp ITEM_LARGE_N+1
	jr c,.next		; large items stay
	ld hl,(SC_PTR)
	xor a
	ld (hl),a
	inc hl
	ld (hl),a
	ld bc,(SC_ITEM)
	ld hl,(SC_TO)
	ld e,l
	ld d,h
	call WCALL
	dw DRAWOBJ_PTR
	ld a,(SC_TMP)
	call WCALL
	dw SET_ITEM_POS
	ld a,(SC_CHAR)
	call PANEL_DRAW
	jr .done
.next:	inc c
	ld a,c
	cp 27
	jr c,.count
	ld c,0
.count:	djnz .slot
.done:	pop hl
	jp SC_DIRTY

OP_DELETEITEM:
	ld a,(hl)
	inc hl
	cp 0FFh
	jr nz,.block
	; the hand item disappears
	push hl
	ld hl,(HAND)
	call ITEM_IX
	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
	ld hl,0
	call SET_HAND_ITEM
	pop hl
	jp SCR_NEXT
.block:	cp 0FEh
	jr nz,.t
	ld a,0FFh		; -2: any type
.t:	call GETW
	push hl
	ex de,hl
	call WCALL
	dw W_DELETE_ITEMS
	pop hl
	jp SC_DIRTY

OP_CREATEITEM:
	call GETW		; item to copy
	ld (SC_ITEM),de
	call GETW		; block
	ld (SC_TO),de
	ld a,(hl)
	inc hl
	ld (SC_TMP),a
	push hl
	ld hl,(SC_ITEM)
	call DUPLICATE_ITEM
	ld a,h
	or l
	jr z,.done
	ld (SC_ITEM),hl
	ld de,(SC_TO)
	ld a,d
	and e
	inc a
	jr nz,.map
	ld de,(HAND)		; FFFFh: into the hand if it is empty
	ld a,d
	or e
	jr nz,.done
	call SET_HAND_ITEM
	jr .done
.map:	ld bc,(SC_ITEM)
	ld hl,(SC_TO)
	ld e,l
	ld d,h
	call WCALL
	dw DRAWOBJ_PTR
	ld a,(SC_TMP)
	call WCALL
	dw SET_ITEM_POS
.done:	pop hl
	jp SC_DIRTY

OP_IDENTIFY:
	; the original reads the block and consumes no operand bytes
	push hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,(CUR_BLOCK)
	or a
	sbc hl,de
	jr nz,.blk
	; the party stands there: everything it carries
	xor a
.ch:	ld (SC_CHAR),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.nc
	ld b,27
	ld c,0
.slot:	push bc
	ld a,c
	call SLOT_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	jr z,.ns
	call ITEM_IX
	set 6,(ix+I_FLAGS)
.ns:	pop bc
	inc c
	djnz .slot
.nc:	ld a,(SC_CHAR)
	inc a
	cp 6
	jr c,.ch
.blk:	pop hl
	push hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	call WCALL
	dw W_IDENTIFY_BLOCK
	pop hl
	jp SCR_NEXT

; OP_LAUNCH - a trap shoots: -33 (a spell) or else (a copy of an item),
;   item / flight type, block, direction, side (oeob_launchObject). Nobody
;   throws it (FFh), as a monster's missile.
OP_LAUNCH:
	ld a,(hl)
	inc hl
	ld (SC_TMP),a
	call GETW
	ld (SC_ITEM),de
	call GETW
	ld (MC_BLOCK),de
	ld a,(hl)		; direction
	inc hl
	ld (MC_DIR),a
	ld (FL_DIR),a
	add a,a
	add a,(hl)		; + side: LAUNCH_POS[dir * 2 + side]
	inc hl
	push hl
	ld e,a
	ld d,0
	ld hl,LAUNCH_POS
	add hl,de
	ld a,(hl)
	ld (MC_POS),a
	ld a,(SC_TMP)
	cp 0DFh
	jr nz,.item
	ld a,(SC_ITEM)
	call MCALL
	dw MON_CAST
	jr .done
.item:	ld hl,(SC_ITEM)
	call DUPLICATE_ITEM
	ld a,h
	or l
	jr z,.done
	push hl
	ld c,l
	ld b,h
	ld a,0FFh
	ld (FL_ATK),a
	ld hl,0
	ld (FL_WEAPON),hl
	ld hl,(MC_BLOCK)
	ld a,(MC_POS)
	call WCALL
	dw LAUNCH
	pop hl
	jr nz,.done
	call ITEM_IX		; no free record: the copy is dropped
	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
.done:	pop hl
	jp SC_DIRTY
LAUNCH_POS:	db 2, 3, 0, 2, 1, 0, 3, 1

OP_CHANGEDIR:
	ld a,(hl)
	inc hl
	ld c,(hl)
	inc hl
	cp 0F5h			; -11: the objects flying in the trigger block
	jr nz,.party
.fly:	push hl			; keep the next INF opcode across the world helper
	ld de,(SC_FUNC)
	call WCALL
	dw W_FLY_TURN
.fly_resume:
	pop hl			; W_FLY_TURN traverses FLYOBJ in HL
	jp SCR_NEXT
.party:	cp 0F1h			; -15: the party
	jp nz,SCR_NEXT
	ld a,(CUR_DIR)
	add a,c
	and 3
	ld (CUR_DIR),a
	jp SC_DIRTY

; ----------------------------------------------------------------------------
; messages, sounds, flags
; ----------------------------------------------------------------------------
OP_PRINT:
	push hl
.end:	ld a,(hl)
	inc hl
	or a
	jr nz,.end
	ld e,(hl)		; colour (VGA index)
	inc hl
	inc hl
	ex (sp),hl		; the text
	ld d,0
	push hl
	ld hl,VGA_LUT
	add hl,de
	ld a,(hl)
	pop hl
	call MSG_WRAP
	pop hl
	jp SCR_NEXT

OP_SOUND:			; sound, block (0: the party hears it as is)
	ld c,(hl)
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ex de,hl
	ld a,h
	or l
	ld a,c
	jr z,.now
	call ENV_SOUND
	jr .done
.now:	call SFX_PLAY
.done:	pop hl
	jp SCR_NEXT

OP_SETFLAGS:
	ld a,(hl)
	inc hl
	cp 0D1h
	jr z,.rest
	cp 0E4h
	jr z,.dlg
	cp 0EFh
	jr z,.level
	cp 0F0h
	jr z,.global
	cp 0F3h
	jp nz,SCR_NEXT
	ld a,(hl)		; monster, bit
	inc hl
	ld c,(hl)
	inc hl
	push hl
	call WCALL
	dw W_MON_FLAG
	pop hl
	jp SCR_NEXT
.rest:	xor a
	ld (SC_NOREST),a
	jp SCR_NEXT
.dlg:	ld a,1
	ld (SC_DLG),a
	jp SCR_NEXT
.level:	call LEVEL_FLAG_PTR
	jr .set
.global: call GLOBAL_FLAG_PTR
.set:	or (hl)
	ld (hl),a
	pop hl
	jp SCR_NEXT

OP_CLEARFLAGS:
	ld a,(hl)
	inc hl
	cp 0D1h
	jr z,.rest
	cp 0E4h
	jr z,.dlg
	cp 0EFh
	jr z,.level
	cp 0F0h
	jp nz,SCR_NEXT
	call GLOBAL_FLAG_PTR
	jr .clr
.level:	call LEVEL_FLAG_PTR
.clr:	cpl
	and (hl)
	ld (hl),a
	pop hl
	jp SCR_NEXT
.rest:	ld a,1
	ld (SC_NOREST),a
	jp SCR_NEXT
.dlg:	xor a
	ld (SC_DLG),a
	jp SCR_NEXT

; LEVEL_FLAG_PTR / GLOBAL_FLAG_PTR - (HL) = bit number, HL += 1
;   -> (SP) = the script pointer (pushed), HL = byte of the flag, A = mask
LEVEL_FLAG_PTR:
	ld a,(CUR_LEVEL)
	jr FLAG_PTR
GLOBAL_FLAG_PTR:
	ld a,17
FLAG_PTR:
	add a,a
	add a,a			; 4 bytes per table
	ld e,a
	ld a,(hl)
	inc hl
	pop bc			; return address
	push hl			; the script pointer for the caller
	push bc
	ld c,a
	srl a
	srl a
	srl a			; byte of the 32
	add a,e
	ld e,a
	ld d,0
	ld hl,SC_FLAGTAB
	add hl,de
	ld a,c
	push hl
	call BIT_MASK
	pop hl
	ret

; FLAG_TEST - A = table (level or 17), (HL) = bit -> pushes 0 / 1, HL += 1
FLAG_TEST:
	add a,a
	add a,a
	ld e,a
	ld a,(hl)
	inc hl
	push hl
	ld c,a
	srl a
	srl a
	srl a
	add a,e
	ld e,a
	ld d,0
	ld hl,SC_FLAGTAB
	add hl,de
	push hl
	ld a,c
	call BIT_MASK
	pop hl
	and (hl)
	ld l,0
	jr z,.p
	inc l
.p:	ld h,0
	call PUSH_HL
	pop hl
	ret

; ----------------------------------------------------------------------------
; characters
; ----------------------------------------------------------------------------
OP_MODHP:
	ld a,(hl)		; character (-1: all), points
	inc hl
	ld c,(hl)
	inc hl
	push hl
	ld (SC_TMP),a
	inc a
	jr z,.all
	ld a,(SC_TMP)
	call MOD_HP
	jr .done
.all:	xor a
.lp:	push af
	call MOD_HP
	pop af
	inc a
	cp 6
	jr c,.lp
.done:	pop hl
	jp SCR_NEXT

; MOD_HP - A = character, C = points (modifyCharacterHitpoints). Keeps C.
MOD_HP:
 push bc
 call XCALL
 dw FX_MOD_HP
 pop bc
 ret

OP_DAMAGE:
	ld a,(hl)		; character (-1: all), times, pips, base
	inc hl
	ld (SC_CHAR),a
	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld a,(hl)
	inc hl
	push hl
	ld (SC_DBASE),a
	ld a,c
	or a
	jr nz,.d
	ld a,b			; no pips: the times are the damage
	ld (SC_DBASE),a
	ld b,0
.d:	ld (SC_DICE),bc
	ld a,(SC_CHAR)
	inc a
	jr z,.all
	ld a,(SC_CHAR)
	ld c,0
	call DAMAGE1
	jr .done
.all:	xor a
.lp:	push af
	ld c,4			; ring of protection 3 saves them
	call DAMAGE1
	pop af
	inc a
	cp 6
	jr c,.lp
.done:	pop hl
	jp SCR_NEXT

; DAMAGE1 - A = character, C = flags (4: the ring helps)
DAMAGE1:
	ld (SC_TMP),a
	call CHAR_PTR
	call CHAR_ALIVE_R
	ret z
	push bc
	ld bc,(SC_DICE)
	ld a,(SC_DBASE)
	call ROLL_DICE
	pop bc
	bit 2,c
	jr z,.hit
	push hl
	ld a,25
	call RING3
	jr z,.no
	ld a,26
	call RING3
.no:	pop hl
	ret z
.hit:	ld a,h
	or l
	ret z
	ld a,(SC_TMP)
	jp INFLICT_CHARACTER

; RING3 - IY = character, A = slot -> Z if a ring of type 47 value 3 is there
RING3:
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
	cp 3
	ret
.no:	or 1
	ret

OP_EXPERIENCE:
	ld a,(hl)
	inc hl
	cp 0E2h
	jp nz,SCR_NEXT
	call GETW
	push hl
	ex de,hl
	call PARTY_EXPERIENCE	; (exp.asm, here)
	pop hl
	jp SCR_NEXT

; ----------------------------------------------------------------------------
; flow
; ----------------------------------------------------------------------------
OP_JUMP:
	call GETW
	ld hl,SCRIPT
	add hl,de
	jp SCR_NEXT

OP_END:
	ld a,1
	ld (SC_ABORT),a
	xor a
	ld (SC_SUBPOS),a
	jp SCR_NEXT

OP_RETURN:
	ld a,(SC_SUBPOS)
	or a
	jr z,OP_END_ONLY
	dec a
	ld (SC_SUBPOS),a
	add a,a
	ld e,a
	ld d,0
	ld hl,SC_SUBSTACK
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	jp SCR_NEXT
OP_END_ONLY:
	ld a,1
	ld (SC_ABORT),a
	jp SCR_NEXT

OP_CALL:
	call GETW
	ld a,(SC_SUBPOS)
	cp 10
	jp nc,SCR_NEXT
	inc a
	ld (SC_SUBPOS),a
	dec a
	add a,a
	ld c,a
	ld b,0
	push hl
	ld hl,SC_SUBSTACK
	add hl,bc
	pop bc
	ld (hl),c
	inc hl
	ld (hl),b
	ld hl,SCRIPT
	add hl,de
	jp SCR_NEXT

OP_NEWLEVEL:
	inc hl			; sub level (EOB2)
	ld a,(hl)		; level
	inc hl
	ld (LEVEL_REQ),a
	call GETW
	ld (LEVEL_REQ_BLOCK),de
	ld a,(hl)
	ld (LEVEL_REQ_DIR),a
	; the main loop loads it (this segment gets the new script)
	ld a,1
	ld (SC_ABORT),a
	ld (SC_ABORTSUB),a
	xor a
	ld (SC_SUBPOS),a
	jp SCR_NEXT

; sequence: the NPC dialogues (0..7); 8 the portal, 9 the death of
;   Xanathar, 10 the password check of the original (nothing here)
OP_SEQUENCE:
	ld a,(hl)
	inc hl
	push hl
	cp 9
	jr z,.xdeath
	cp 8
	jr z,.portal
	call c,NPC_RUN
	jr .done
.portal:
	ld hl,(8000h+1FF0h)
	call MCALL
	dw SEQ_PORTAL
.done:	pop hl
	jp SC_DIRTY
.xdeath:			; Xanathar dies: the end of the game
	call BOSS_DEATH
	pop hl
	jp SCR_NEXT

; Called either by sequence 9 or by KILL_MONSTER (the original EOB1
; killMonsterExtra hook). Give the quest its flag before the bonus check.
BOSS_DEATH_IF_BOSS:
	; The monster record lives in the world segment, not in this overlay.
	; MON_PROPS reads its type into A while WCALL maps that segment.
	call WCALL
	dw MON_PROPS
	cp 21
	ret nz
	; fall through
BOSS_DEATH:
	ld a,(QUIT_REQ)
	or a
	ret nz			; the ending can only run once
	ld a,(SC_FLAGTAB+17*4+1)
	or 10h			; global flag 12: Xanathar defeated
	ld (SC_FLAGTAB+17*4+1),a
	ld hl,(8000h+1FF2h)
	call MCALL
	dw XDEATH
	ld a,(SC_FLAGTAB+17*4)	; the twelve special quests: global flags 1..12
	and 0FEh
	cp 0FEh
	ld a,0
	jr nz,.nb
	ld a,(SC_FLAGTAB+17*4+1)
	and 1Fh
	cp 1Fh
	ld a,0
	jr nz,.nb
	inc a
.nb:	call MCALL
	dw FINALE
	ld a,1
	ld (QUIT_REQ),a
	ld (SC_ABORT),a
	ret

; ----------------------------------------------------------------------------
; NPC_RUN - A = NPC: its dialogue (EoBEngine::npcSequence / runNpcDialogue)
; ----------------------------------------------------------------------------
NPC_TABLE:	equ 8000h+1F00h	; the scene table, at the end of LEVELn.INF
KEIRGAR_FACE:	equ 52		; portrait -9

NPC_RUN:
	ld (NR_NPC),a
	call WCALL		; the view where the party stands now
	dw SCENE_DRAW
	ld a,(NR_NPC)
	ld c,1
	call NPC_SCENE
	ld a,(NR_NPC)
	add a,a
	ld e,a
	ld d,0
	ld hl,NR_CASES
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	call NR_JP
	call MCALL
	dw DLG_END
	ret
NR_JP:	jp (hl)
NR_CASES:	dw NR0, NR1, NR2, NR3, NR4, NR5, NR6, NR7
NR_NPC:		db 0
NR_R:		db 0
NR_A:		db 0

; NPC_SCENE - A = scene, C = 1: NPCn.V9 first -> the figures and an empty box
NPC_SCENE:
	push bc
	ld e,a
	ld d,0
	ld hl,NPC_TABLE
	add hl,de
	ld a,(hl)
	ld hl,BOUNCE
	ld (hl),0
	or a
	jr z,.go
	ld e,a
	ld hl,NPC_TABLE
	add hl,de
	ld de,BOUNCE
	ld bc,25
	ldir
.go:	pop bc
	ld a,c
	call MCALL
	dw DLG_START
	ret

; the dialogue calls: SAYW A = text (then MAS), ASK A = text, C = buttons,
; JOIN A = NPC, B, C, D = texts, DEL_ITEMS B = type, C = value -> NZ
SAYW:	ld c,1
	call MCALL
	dw DLG_SAY
	ret
ASK:	call MCALL
	dw DLG_ASK
	ret
JOIN:	call MCALL
	dw DLG_JOIN
	ret
DEL_ITEMS:
	call MCALL
	dw DEL_PARTY_ITEMS
	ret

; GFLAG_TEST / GFLAG_SET - A = bit of the global flags (checkScriptFlags)
GFLAG_TEST:
	call GFLAG_BIT
	and (hl)
	ret
GFLAG_SET:
	call GFLAG_BIT
	or (hl)
	ld (hl),a
	ret
GFLAG_BIT:
	ld c,a
	srl a
	srl a
	srl a
	ld e,a
	ld d,0
	ld hl,SC_FLAGTAB+17*4
	add hl,de
	ld a,c
	and 7
	ld b,a
	ld a,1
	ret z
.s:	add a,a
	djnz .s
	ret

; CREATE_HERE - HL = item to copy: the copy lies where the party stands
;   (createItemOnCurrentBlock)
CREATE_HERE:
	call DUPLICATE_ITEM
	ld a,h
	or l
	ret z
; PLACE_HERE - HL = item: on the floor of the party block
PLACE_HERE:
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
	ld (SC_TMP),a
	pop bc
	ld hl,(CUR_BLOCK)
	ld e,l
	ld d,h
	call WCALL
	dw DRAWOBJ_PTR
	ld a,(SC_TMP)
	call WCALL
	dw SET_ITEM_POS
	ld a,1
	ld (SCENE_DIRTY),a
	ret

; 0: Taghor, the wounded dwarf (level 4)
NR0:	ld a,13
	call GFLAG_TEST
	jr z,.three
	ld a,8
	ld c,2			; heal / leave
	call ASK
	or a
	jr z,.r
	ld a,2
	jr .r
.three:	ld a,8
	ld c,1			; heal / talk / leave
	call ASK
.r:	cp 1
	jr nz,.n1
	ld a,1
	call SAYW
	ld a,13
	call GFLAG_SET
	jr NR0
.n1:	or a
	ret nz
	ld a,6
	ld b,12
	ld c,23
	ld d,2
	call JOIN
	ld a,14
	jp GFLAG_SET

; 1: Armun, the speaker of the dwarves (level 5)
NR1:	xor a
	ld (NR_R),a
	ld a,16
	call GFLAG_TEST
	jr nz,.keir
	ld a,15
	call GFLAG_TEST
	ld a,13
	jr nz,.a
	ld a,15
	call GFLAG_SET
	ld a,3
	ld c,3
	call ASK
	ld (NR_R),a
	ld a,4
.a:	ld (NR_A),a
	ld a,(NR_R)
	or a
	jr nz,.no
	ld a,(NR_A)
	ld c,4
	call ASK
	or a
	jr nz,.no
	ld b,6			; the help is welcome: six of item 55 and item 62
.it:	push bc
	ld hl,55
	call CREATE_HERE
	pop bc
	djnz .it
	ld hl,62
	call CREATE_HERE
	ld a,16
	call GFLAG_SET
	ld a,6
	call SAYW
	ld a,7
	ld b,7
	ld c,29
	ld d,30
	call JOIN
	jr .r1
.no:	ld a,5
	call SAYW
.r1:	ld a,1
	ld (NR_R),a
.keir:	; the prince back with his people
	ld a,19
	call GFLAG_TEST
	jr nz,.pot
	ld c,0
.kl:	ld a,c
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.kn
	ld a,(iy+P_FACE)
	cp KEIRGAR_FACE
	jr z,.kf
.kn:	inc c
	ld a,c
	cp 6
	jr c,.kl
	jr .pot
.kf:	ld a,25
	call SAYW
	ld a,26
	call SAYW
	ld a,19
	call GFLAG_SET
	ld a,1
	ld (NR_R),a
.pot:	; the potion that wakes the king
	ld a,20
	call GFLAG_TEST
	jr nz,.end
	ld b,6
	ld c,0FFh
	call DEL_ITEMS
	jr z,.end
	ld a,8
	ld c,0
	call NPC_SCENE
	ld a,28
	call SAYW
	ld hl,32
	call CREATE_HERE
	ld a,20
	call GFLAG_SET
	ld a,1
	ld (NR_R),a
.end:	ld a,(NR_R)
	or a
	ret nz
	xor a			; "Te deseo suerte en tus viajes."
	jp SAYW

; 2: the dwarven cleric (level 5)
NR2:	ld a,16
	call GFLAG_TEST
	ld a,24
	jp z,SAYW
	ld a,17
	call GFLAG_TEST
	ld a,11
	jp nz,SAYW
	call MCALL
	dw RAISE_COUNT
	or a
	jr nz,.three
	ld a,9
	ld c,5			; heal / leave
	call ASK
	or a
	jr z,.r
	ld a,2
	jr .r
.three:	ld a,9
	ld c,6			; heal / raise / leave
	call ASK
.r:	cp 2
	ret nc
	or a
	jr nz,.raise
	call MCALL
	dw HEAL_PARTY
	jr .set
.raise:	call MCALL
	dw RAISE_DLG
	bit 7,a
	jr z,.set
	and 7Fh
	ld (NR_A),a
	add a,9			; the cleric with that NPC
	ld c,0
	call NPC_SCENE
	ld a,(NR_A)
	add a,a
	add a,32
	ld b,a
	inc a
	ld d,a
	ld c,0
	ld a,(NR_A)
	call JOIN
.set:	ld a,17
	jp GFLAG_SET

; 3: the drow patrol (level 7)
NR3:	ld a,18
	ld c,7			; attack / bribe
	call ASK
	or a
	jr nz,.bribe
	ld a,22
	call GFLAG_SET
	ld a,27
	call GFLAG_SET
	call WCALL
	dw W_WAKE_PATROL
	ret
.bribe:	ld b,49			; the kenku egg
	ld c,0FFh
	call DEL_ITEMS
	ld a,19
	jp z,SAYW
	ld a,20
	call SAYW
	ld a,22
	jp GFLAG_SET

; 4: Shindia (level 10)
NR4:	ld a,14
	ld c,8			; kill / listen / let go
	call ASK
	or a
	jr nz,.n0
	ld a,21
	call GFLAG_SET
	jr .end
.n0:	dec a
	ld a,15
	call z,SAYW
.end:	ld a,23
	jp GFLAG_SET

; 5: the dark elves of Xanathar (level 12)
NR5:	ld a,16
	ld c,9			; surrender / attack
	call ASK
	or a
	jr nz,.end
	ld a,17
	call SAYW
	; the hands lose everything but the magic weapons (types 51..56)
	ld c,0
.ch:	ld a,c
	call CHAR_PTR
	push bc
	ld b,2
	push iy
	pop hl
	ld de,P_INV
	add hl,de
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
	sub 51
	cp 6
	jr c,.ns
	ex de,hl
	ld (hl),0
	dec hl
	ld (hl),0
	ex de,hl
	call PLACE_HERE
.ns:	pop hl
	pop bc
	inc hl
	inc hl
	djnz .sl
	pop bc
	ld a,c
	push bc
	call PANEL_DRAW
	pop bc
	inc c
	ld a,c
	cp 6
	jr c,.ch
.end:	ld a,25
	jp GFLAG_SET

; 6: the figure in the black robe (level 6)
NR6:	ld a,21
	call SAYW
	ld a,24
	jp GFLAG_SET

; 7: prince Keirgar (level 10)
NR7:	ld a,22
	ld c,10			; free / kill / leave
	call ASK
	cp 2
	jr nc,.end
	or a
	jr nz,.kill
	ld a,8
	ld b,27
	ld c,44
	ld d,45
	call JOIN
	jr .end
.kill:	ld a,31
	call SAYW
.end:	ld a,26
	jp GFLAG_SET

SC_DIRTY:
	ld a,1
	ld (SCENE_DIRTY),a
	jp SCR_NEXT

; ----------------------------------------------------------------------------
; eval: a little stack machine; the result decides a conditional jump
; ----------------------------------------------------------------------------
OP_EVAL:
	ld a,(hl)
	inc hl
	cp 0EEh			; -18: end of the expression
	jr z,.end
	cp 80h
	jr c,.value
	sub 0DAh		; -38 -> 0
	jr c,OP_EVAL		; unknown: ignored
	cp 38
	jr nc,OP_EVAL
	add a,a
	ld e,a
	ld d,0
	push hl
	ld hl,EV_OPS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	ex (sp),hl
	ret
.value:	push hl
	ld l,a
	ld h,0
	call PUSH_HL
	pop hl
	jr OP_EVAL
.end:	push hl
	call POP_HL
	ld a,h
	or l
	pop hl
	jr z,.jump
	inc hl
	inc hl
	jp SCR_NEXT
.jump:	jp OP_JUMP

EV_NEXT:	equ OP_EVAL

EV_OPS:	dw EV_INVISIBLE, EV_DICE, EV_CLASS, EV_RACE, EV_NOP, EV_NOP, EV_FLAGS, EV_NOP
	dw EV_NOP, EV_NOP, EV_NOP, EV_NOP, EV_NOP, EV_HAND, EV_NOP, EV_WALL
	dw EV_NOP, EV_NOP, EV_NOP, EV_DIR, EV_NOP, EV_LFLAG, EV_GFLAG, EV_ATBLOCK
	dw EV_ITEM, EV_MONSTER, EV_NOP, EV_COUNT, EV_NOP, EV_WALL0, EV_OR, EV_AND
	dw EV_LE, EV_LT, EV_GE, EV_GT, EV_NE, EV_EQ

EV_NOP:	jp EV_NEXT

EV_INVISIBLE:			; 1 if every character is invisible (40h)
	push hl
	ld ix,PARTY
	ld de,P_SIZE
	ld b,6
.lp:	bit 0,(ix+P_FLAGS)
	jr z,.n
	bit 6,(ix+P_EFFECT)
	jr z,.no
.n:	add ix,de
	djnz .lp
	ld hl,1
	jr .push
.no:	ld hl,0
.push:	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_DICE:
	ld b,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld a,(hl)
	inc hl
	push hl
	call ROLL_DICE
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_CLASS:			; a character of these classes is in the party
	ld a,(hl)
	inc hl
	push hl
	ld (SC_TMP),a
	ld c,0
	xor a
.lp:	push af
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.n
	call CLASS_FLAG
	ld hl,SC_TMP
	and (hl)
	jr z,.n
	ld c,1
.n:	pop af
	inc a
	cp 6
	jr c,.lp
	ld l,c
	ld h,0
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_RACE:			; a character of this race is in the party
	ld a,(hl)
	inc hl
	push hl
	ld (SC_TMP),a
	ld c,0
	xor a
.lp:	push af
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	jr z,.n
	ld a,(iy+P_RACE)
	srl a
	ld hl,SC_TMP
	cp (hl)
	jr nz,.n
	ld c,1
.n:	pop af
	inc a
	cp 6
	jr c,.lp
	ld l,c
	ld h,0
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_FLAGS:
	push hl
	ld a,(SC_FLAGS)
	ld l,a
	ld h,0
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_HAND:			; the hand item: type (-31), number (-11), value
	ld a,(hl)
	inc hl
	push hl
	ld c,a
	ld hl,(HAND)
	cp 0F5h
	jr z,.push
	call ITEM_IX
	ld a,c
	cp 0E1h
	ld a,(ix+I_TYPE)
	jr z,.sx
	ld a,(ix+I_VALUE)
.sx:	ld l,a
	rla
	sbc a,a
	ld h,a
.push:	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_WALL:			; side, block -> wall type
	ld a,(hl)
	inc hl
	call GETW
	push hl
	ex de,hl
	call WCALL
	dw BLOCK_WALL
	ld l,a
	ld h,0
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_WALL0:			; block -> wall type of side 0
	call GETW
	push hl
	ex de,hl
	xor a
	call WCALL
	dw BLOCK_WALL
	ld l,a
	ld h,0
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_DIR:
	push hl
	ld a,(CUR_DIR)
	ld l,a
	ld h,0
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_LFLAG:
	ld a,(CUR_LEVEL)
	call FLAG_TEST
	jp EV_NEXT

EV_GFLAG:
	ld a,17
	call FLAG_TEST
	jp EV_NEXT

EV_ATBLOCK:
	call GETW
	push hl
	ld hl,(CUR_BLOCK)
	or a
	sbc hl,de
	ld hl,0
	jr nz,.p
	inc l
.p:	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_ITEM:			; item number, block -> it lies there (its number) or 0
	call GETW
	push de
	call GETW
	ex (sp),hl		; HL = item, (SP) = script
	ex de,hl		; HL = block, DE = item
	ld bc,00FFh		; any type, the first match
	call WCALL
	dw W_COUNT_ITEMS
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_MONSTER:			; block -> monsters & 1
	call GETW
	push hl
	ex de,hl
	call WCALL
	dw W_BLOCK_MONSTERS
	and 1
	ld l,a
	ld h,0
	call PUSH_HL
	pop hl
	jp EV_NEXT

EV_COUNT:			; type, block -> how many items of the type
	ld c,(hl)
	inc hl
	call GETW
	push hl
	ex de,hl
	ld de,0FFFFh
	ld b,1
	call WCALL
	dw W_COUNT_ITEMS
	call PUSH_HL
	pop hl
	jp EV_NEXT

; binary operators: a = pop, b = pop, push (a op b)
EV_OR:	call EV_POP2
	ld a,h
	or l
	or d
	or e
	jr EV_BOOL
EV_AND:	call EV_POP2
	ld a,h
	or l
	jr z,EV_BOOL
	ld a,d
	or e
	jr EV_BOOL
EV_LE:	call EV_CMP		; a <= b: not (a > b)
	jr z,EV_TRUE
	jr c,EV_TRUE
	jr EV_FALSE
EV_LT:	call EV_CMP
	jr c,EV_TRUE
	jr EV_FALSE
EV_GE:	call EV_CMP
	jr nc,EV_TRUE
	jr EV_FALSE
EV_GT:	call EV_CMP
	jr z,EV_FALSE
	jr nc,EV_TRUE
	jr EV_FALSE
EV_NE:	call EV_CMP
	jr nz,EV_TRUE
	jr EV_FALSE
EV_EQ:	call EV_CMP
	jr z,EV_TRUE
EV_FALSE:
	xor a
	jr EV_BOOL
EV_TRUE:
	ld a,1
EV_BOOL:
	or a
	ld hl,0
	jr z,.p
	inc l
.p:	call PUSH_HL
	pop hl			; the script pointer (pushed by EV_POP2)
	jp EV_NEXT

; EV_POP2 - pushes the script pointer, HL = a (top), DE = b
EV_POP2:
	pop bc			; return address
	push hl
	push bc
	call POP_HL
	push hl
	call POP_HL
	ex de,hl
	pop hl
	ret

; EV_CMP - like EV_POP2, then compares a with b (signed): Z equal, C a < b
EV_CMP:
	pop bc
	push hl
	push bc
	call POP_HL
	push hl
	call POP_HL
	ex de,hl
	pop hl
	ld a,h
	xor d
	jp m,.sign		; different signs
	or a
	sbc hl,de
	ret
.sign:	ld a,h			; a negative (C) or b negative (NC, NZ)
	rla
	ret c
	or 1
	ret

; PUSH_HL / POP_HL - the expression stack (30 words). Keep BC, DE.
PUSH_HL:
	push de
	ex de,hl
	ld a,(SC_SP)
	cp 30
	jr nc,.full
	inc a
	ld (SC_SP),a
	dec a
	add a,a
	ld l,a
	ld h,0
	push bc
	ld bc,SC_STACK
	add hl,bc
	pop bc
	ld (hl),e
	inc hl
	ld (hl),d
.full:	pop de
	ret
POP_HL:
	push de
	ld a,(SC_SP)
	or a
	jr z,.empty
	dec a
	ld (SC_SP),a
	add a,a
	ld l,a
	ld h,0
	ld de,SC_STACK
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	pop de
	ret
.empty:	ld hl,0
	pop de
	ret

; ----------------------------------------------------------------------------
; interpreter state (kept here, in the script segment)
; ----------------------------------------------------------------------------
SC_FLAGS:	db 0		; the event flags of this run
SC_ABORT:	db 0		; (after SC_FLAGS: saved together)
SC_ABORTSUB:	db 0
SC_DLG:		db 0
SC_ACTIVE:	db 0		; (after SC_DLG: saved together)
SC_FUNC:	dw 0
SC_SUBPOS:	db 0
SC_NOREST:	db 0
SC_TMP:		db 0
SC_CHAR:	db 0
SC_FROM:	dw 0
SC_TO:		dw 0
SC_ITEM:	dw 0
SC_PTR:		dw 0
SC_DICE:	dw 0
SC_DBASE:	db 0
SC_SP:		db 0
SC_SUBSTACK:	ds 20
SC_STACK:	ds 60
SC_FLAGTAB:	ds 18*4		; level flags 1..12, global flags at 17

	include "../build/vgalut.inc"

	; (here for room: called with SCALL)
	include "stats.asm"
	include "../build/statsdata.inc"
	include "facetint.asm"
	include "rust.asm"
	include "exp.asm"
	include "../build/expdata.inc"

OVL_SCRIPT_END:
	assert OVL_SCRIPT_END <= 0C000h	; script overlay too big
