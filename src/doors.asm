; ============================================================================
; doors.asm - Doors: switches, opening and closing (processDoorSwitch,
;             openCloseDoor and timerProcessDoors of the original engine)
; Assembler: Sjasm 0.42c
;
; A door block has the door on two opposite walls (c and c ^ 2). Its wall
; type moves one step per door timer tick (5 ticks of 55 ms) between the
; closed state (wall flag 20h) and the open one (flag 10h); flag bit 0 tells
; whether the party may pass.
; DOS uses one active door (block u16, step s8, wall side c).
; ============================================================================

; ----------------------------------------------------------------------------
; DOOR_ACTION - the party presses the switch of the door ahead (if any)
; ----------------------------------------------------------------------------
DOOR_ACTION:
	ld a,(CUR_DIR)
	call BLOCK_AHEAD	; HL = block ahead
	ld (DOOR_BLOCK),hl
	ld a,(CUR_DIR)
	xor 2			; the wall facing the party
	call BLOCK_WALL		; A = wall type
	ld h,(LEVELDAT+D_WSPECIAL)>>8
	ld l,a
	ld a,(hl)
	cp 1			; 1 = door switch
	ret nz
	ld hl,(DOOR_BLOCK)
	; fall through

; PROCESS_DOOR - HL = door block: open it if closed, close it if open
PROCESS_DOOR:
	ld (DOOR_BLOCK),hl
	ld a,(DOOR_TIMER)
	or a
	jr z,.idle
	ld a,(DOOR_SLOT+2)	; toggling the moving door reverses its step
	neg
	jr OPEN_CLOSE
.idle:	ld de,(CUR_BLOCK)	; not under the party
	or a
	sbc hl,de
	add hl,de
	ret z
	call BLOCK_HAS_MONSTER
	ret nz
	call DOOR_SIDE		; C = side with the door, A = its wall type
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	bit 0,(hl)
	ld a,1			; closed: open it
	jr z,OPEN_CLOSE
	ld a,-1			; open: close it

; OPEN_CLOSE - A = +1 open / -1 close, (DOOR_BLOCK) = requested block.
; DOS 14C13/14CA8/14D30: a moving door accepts a change of direction;
; requests for any other door are discarded until the animation finishes.
OPEN_CLOSE:
	ld d,a
	ld a,(DOOR_TIMER)
	or a
	jr z,.idle
	ld hl,(DOOR_BLOCK)
	ld bc,(DOOR_SLOT)
	sbc hl,bc		; OR A cleared carry
	ret nz
	ld a,d
	ld (DOOR_SLOT+2),a
	ret
.idle:	push de			; DOOR_SIDE uses DE for the maze address
	call DOOR_SIDE
	pop de
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	ld b,(hl)		; flags of the current wall
	ld a,d
	inc a
	jr nz,.opening
	bit 0,b
	ret z			; already closed
	jr .start
.opening:
	bit 0,b
	ret nz			; already open
.start:	ld ix,DOOR_SLOT
	ld hl,(DOOR_BLOCK)
	ld (DOOR_SLOT),hl
	ld (ix+2),d
	ld (ix+3),c
	ld a,d
	inc a
	ld c,10h		; closing starts from open (10h)
	jr z,.flg
	ld c,20h		; opening starts from closed (20h)
.flg:	ld a,b
	and c
	call nz,DOOR_STEP
	ld a,DOOR_TICKS
	ld (DOOR_TIMER),a
	ret

; DOOR_STEP - IX = slot: moves both walls one step -> A = new wall flags
DOOR_STEP:
	ld l,(ix+0)
	ld h,(ix+1)
	push hl
	add hl,hl
	add hl,hl
	ld de,LEVELDAT+D_MAZE
	add hl,de		; HL = the 4 walls of the block
	ld a,(ix+3)
	ld e,a
	ld d,0
	push hl
	add hl,de
	ld a,(hl)
	add a,(ix+2)
	ld (hl),a
	ld c,a
	pop hl
	ld a,e
	xor 2
	ld e,a
	add hl,de
	ld a,(hl)
	add a,(ix+2)
	ld (hl),a
	pop hl
	call SCENE_NEEDS_UPDATE
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,c
	ld a,(hl)
	; its sound: 5 closed, 4 closing, 3 opening (updateDoorHandler)
	ld c,5
	bit 5,a
	jr nz,.snd
	ld c,4
	inc (ix+2)
	dec (ix+2)
	jp m,.snd
	dec c
.snd:	push af
	ld a,c
	call SFX_PLAY
	pop af
	ret

; DOORS_TICK - advance the active door every DOOR_TICKS ticks.
DOORS_TICK:
	ld hl,DOOR_TIMER
	ld a,(hl)
	or a
	ret z
	dec (hl)
	ret nz
	ld ix,DOOR_SLOT
	call DOOR_STEP
	and 30h			; fully open or closed
	jr nz,.complete
	ld a,DOOR_TICKS
	ld (DOOR_TIMER),a
	ret
.complete:
	ld hl,0
	ld (DOOR_SLOT),hl
	ret

; DOOR_SIDE - (DOOR_BLOCK) -> C = 0 if wall 0 is the door, else 1; A = its type
DOOR_SIDE:
	ld hl,(DOOR_BLOCK)
	add hl,hl
	add hl,hl
	ld de,LEVELDAT+D_MAZE
	add hl,de
	ld a,(hl)
	push hl
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	bit 3,(hl)
	pop hl
	ld c,0
	ret nz
	inc hl
	ld a,(hl)
	ld c,1
	ret

; ----------------------------------------------------------------------------
; helpers shared with the movement code
; ----------------------------------------------------------------------------

; BLOCK_AHEAD - A = direction -> HL = neighbour of CUR_BLOCK in that direction
BLOCK_AHEAD:
	add a,a
	ld e,a
	ld d,0
	ld hl,DIR_OFFSET
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,(CUR_BLOCK)
	add hl,de
	ld a,h
	and 3
	ld h,a
	ret

; BLOCK_WALL - HL = block, A = side -> A = wall type (preserves HL)
BLOCK_WALL:
	push hl
	add hl,hl
	add hl,hl
	ld e,a
	ld d,0
	add hl,de
	ld de,LEVELDAT+D_MAZE
	add hl,de
	ld a,(hl)
	pop hl
	ret

; BLOCK_HAS_MONSTER - HL = block -> NZ if a monster stands on it (preserves HL)
BLOCK_HAS_MONSTER:
	push hl
	call BLOCKCNT_PTR
	ld a,(hl)
	pop hl
	or a
	ret

; SCENE_NEEDS_UPDATE - HL = block: marks the scene dirty if it is one of the
;   first 15 visible blocks (checkSceneUpdateNeed). Preserves BC.
SCENE_NEEDS_UPDATE:
	push bc
	ex de,hl
	ld hl,VISBLK
	ld b,15
.lp:	ld a,(hl)
	inc hl
	cp e
	jr nz,.n
	ld a,(hl)
	cp d
	jr nz,.n
	ld a,1
	ld (SCENE_DIRTY),a
	jr .done
.n:	inc hl
	djnz .lp
.done:	ex de,hl
	pop bc
	ret

DOOR_TICKS:	equ 5
DOOR_TIMER:	db 0
DOOR_BLOCK:	dw 0
DOOR_SLOT:	ds 4
