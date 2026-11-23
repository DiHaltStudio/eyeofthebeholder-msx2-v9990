; ============================================================================
; level.asm - Loading a level and moving between levels (loadLevel,
;             loadNewLevelOrMonsters, the temporary data of visited levels)
; Assembler: Sjasm 0.42c
;
; Files of level n: LEVELn.V9 (level store in VRAM) and LEVELn.LVL: the
; maze and tables (LEVELDAT, D_SIZE), the palette (192), the script
; (SCRIPT_MAX) and the RAM shapes (16 KB per segment), read in one go.
; A level the party leaves keeps its maze and monsters in a temp segment
; (three levels per segment) and gets them back when the party returns.
; ============================================================================

TEMP_LEN:	equ 1360	; 12 levels in a segment

; ----------------------------------------------------------------------------
; LEVEL_CHANGE - the script asked for another level (LEVEL_REQ, its block
;   and direction): the party goes there
; ----------------------------------------------------------------------------
LEVEL_CHANGE:
	call FLY_ALL_END
	call DOORS_COMPLETE
	call TEMP_SAVE
	ld a,(LEVEL_REQ)
	push af
	xor a
	ld (LEVEL_REQ),a
	pop af
	call LOAD_LEVEL
	ld hl,(LEVEL_REQ_BLOCK)
	ld (CUR_BLOCK),hl
	ld a,(LEVEL_REQ_DIR)
	cp 0FFh
	jr z,.dir
	and 3
	ld (CUR_DIR),a
.dir:	ld hl,(CUR_BLOCK)
	call PARTY_TO_BLOCK
	ld a,1
	ld (SCENE_DIRTY),a
	jp PANEL_DRAW_ALL

LEVEL_REQ:	db 0
LEVEL_REQ_BLOCK: dw 0
LEVEL_REQ_DIR:	db 0

; ----------------------------------------------------------------------------
; LOAD_LEVEL - A = level number: all its data (the party position is left
;   to the caller)
; ----------------------------------------------------------------------------
LOAD_LEVEL:
	ld (CUR_LEVEL),a
	; the old view goes black first: the palette changes
	call PTR_HIDE
	ld hl,CMD_VIEWCLR
	ld a,C_BLACK
	call V9_LMMV
	call V9_WAIT_CE
	; LEVELn.LVL: maze and tables, palette, script, RAM shapes
	call LEVEL_LVL
	call FILE_OPEN
	ld de,LEVELDAT
	ld hl,D_SIZE
	call FILE_READ
	ld de,PALBUF
	ld hl,192
	call FILE_READ
	call SCRIPT_P2
	ld de,SCRIPT
	ld hl,SCRIPT_MAX
	call FILE_READ
	call WORLD_P2
	di			; only foreground owns V9990; keep palette within blank
	ld hl,PALBUF
	call MCALL
	dw TT_VBLANK
	xor a
	ld b,192
	call V9_SETPAL
	call MAYBE_EI
	; RAM shapes: more segments if this level needs them
	ld a,(LEVELDAT+D_NSEGS)
	ld hl,LVL_SEGS
	sub (hl)
	jr c,.segs
	jr z,.segs
	ld b,a
	ld a,(hl)
	add a,b
	ld (hl),a
	sub b
	add a,GLOBAL_SEGS
	ld e,a
	ld d,0
	ld hl,SEGTAB
	add hl,de
	call MAP_ALLOC
.segs:	ld a,(LEVELDAT+D_NSEGS)
	ld b,a
	ld c,GLOBAL_SEGS
.sg:	push bc
	ld a,c
	call SEG_P2
	ld de,8000h
	ld hl,4000h
	call FILE_READ
	pop bc
	inc c
	djnz .sg		; (every level has shapes)
	call WORLD_P2
	call FILE_CLOSE
	; the level store in VRAM
	ld hl,EXT_V9
	call LEVEL_FILE
	call LOAD_V9
	; the state of the level
	ld hl,FLYOBJ
	ld de,FLYOBJ+1
	ld bc,10*FO_SIZE-1
	ld (hl),0
	ldir
	xor a
	ld (FLY_ACTIVE),a
	ld hl,(LEVELDAT+D_CACHEY)	; (CACHE_RESET may run with another
	ld (CACHE_Y0),hl		; segment in page 2)
	call CACHE_RESET
	call MONSTERS_INIT
	call TEMP_RESTORE
	call ITEMS_LINK
	xor a
	ld (DOOR_TIMER),a
	ld hl,0
	ld (DOOR_SLOT),hl
	ld hl,(LEVELDAT+D_SCRTIMER+1)
	ld a,h
	or l
	jr nz,.tm
	inc hl
.tm:	ld (SCR_TIMER),hl
	ld hl,0
	ld (STEP_COUNT),hl
	ret

LVL_SEGS:	db 0		; segments allocated for level shapes
CMD_VIEWCLR:	dw SCREEN_X, SCREEN_Y, VIEW_W, VIEW_H

; LEVEL_LVL - DE = "LEVELn.LVL" for CUR_LEVEL, in the language folder for
;   the levels whose texts depend on the language (bit n-1 of LVL_LANG)
LEVEL_LVL:
	ld hl,EXT_LVL
	call LEVEL_FILE
	ld a,(CUR_LEVEL)
	ld b,a
	ld hl,LVL_LANG
.bit:	srl h
	rr l
	djnz .bit
	ret nc
	ld de,FNAME_L
	ret

; LEVEL_FILE - HL = extension -> DE = "LEVELn.ext" for CUR_LEVEL
LEVEL_FILE:
	push hl
	ld de,FNAME+5
	ld a,(CUR_LEVEL)
	cp 10
	jr c,.one
	sub 10
	ld c,a
	ld a,'1'
	ld (de),a
	inc de
	ld a,c
.one:	add a,'0'
	ld (de),a
	inc de
	ld a,'.'
	ld (de),a
	inc de
	pop hl
.cp:	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	or a
	jr nz,.cp
	ld de,FNAME
	ret

FNAME_L:	db LANG_C1,LANG_C2,5Ch	; the language folder, for LEVEL_LVL
FNAME:		db "LEVEL"
		ds 10
EXT_V9:		db "V9",0
EXT_LVL:	db "LVL",0

; DOORS_COMPLETE - the doors in motion reach their end (completeDoorOperations)
DOORS_COMPLETE:
	ld a,(DOOR_TIMER)
	or a
	ret z
	ld a,1
	ld (DOOR_TIMER),a
	call DOORS_TICK
	jr DOORS_COMPLETE

; ----------------------------------------------------------------------------
; Temporary data of the visited levels: one segment, TEMP_LEN bytes per
; level: the walls that differ from LEVELn.DAT (u8 count, then u16 index,
; u8 value; at most TEMP_DIFFS) and the 30 monsters.
; ----------------------------------------------------------------------------
TEMP_DIFFS:	equ 200
TEMP_MON:	equ 1+TEMP_DIFFS*3	; offset of the monsters

; TEMP_PLACE - CUR_LEVEL -> TS_ADDR = its area in the temp segment
;   (allocated on first use)
TEMP_PLACE:
	ld a,(CUR_LEVEL)
	dec a
	ld hl,8000h
	ld de,TEMP_LEN
	or a
	jr z,.addr
	ld b,a
.mul:	add hl,de
	djnz .mul
.addr:	ld (TS_ADDR),hl
	ld a,(TEMP_SEG)
	or a
	ret nz
	ld hl,TEMP_SEG
	ld b,1
	jp MAP_ALLOC

; TEMP_FLAG - CUR_LEVEL -> HL = byte of TEMP_FLAGS, A = its bit mask
TEMP_FLAG:
	ld a,(CUR_LEVEL)
	dec a
	ld hl,TEMP_FLAGS
	cp 8
	jr c,.lo
	inc hl
	sub 8
.lo:	jp BIT_MASK

; TEMP_SAVE - the changed walls and the monsters of the current level
TEMP_SAVE:
	call TEMP_PLACE
	call TEMP_FLAG
	or (hl)
	ld (hl),a
	; the original maze, read again into the script segment (its script
	; is not needed any more)
	call LEVEL_LVL
	call SCRIPT_P2
	ld hl,SCRIPT
	ld bc,4096
	call LOAD_RAM
	; compare, 256 bytes at a time: the list grows in BOUNCE
	xor a
	ld (BOUNCE),a
	ld hl,BOUNCE+1
	ld (TS_LIST),hl
	ld hl,0
	ld (TS_INDEX),hl
.chunk:	call WORLD_P2
	ld hl,(TS_INDEX)
	ld de,LEVELDAT+D_MAZE
	add hl,de
	ld de,BOUNCE_CHUNK
	ld bc,256
	ldir
	call SCRIPT_P2
	ld hl,(TS_INDEX)
	ld de,SCRIPT
	add hl,de
	ld de,BOUNCE_CHUNK
	ld b,0
.cmp:	ld a,(de)
	cp (hl)
	jr z,.same
	ld c,a
	ld a,(BOUNCE)
	cp TEMP_DIFFS
	jr nc,.same		; full: the rest is lost
	inc a
	ld (BOUNCE),a
	push hl
	ld hl,(TS_INDEX)
	ld a,l
	add a,b
	push de
	ld de,(TS_LIST)
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
	ld a,c
	ld (de),a
	inc de
	ld (TS_LIST),de
	pop de
	pop hl
.same:	inc hl
	inc de
	inc b
	jr nz,.cmp
	ld hl,(TS_INDEX)
	inc h
	ld (TS_INDEX),hl
	ld a,h
	cp 4096>>8
	jr c,.chunk
	; the list to the temp segment
	ld a,(TEMP_SEG)
	call PUT_SEG_P2
	ld hl,BOUNCE
	ld de,(TS_ADDR)
	ld bc,TEMP_MON
	ldir
	; the monsters
	ld a,(WORLD_SEG)
	ld (SC_SRCSEG),a
	ld a,(TEMP_SEG)
	ld (SC_DSTSEG),a
	ld hl,(TS_ADDR)
	ld de,TEMP_MON
	add hl,de
	ex de,hl
	ld hl,LEVELDAT+D_MONSTERS
	ld bc,30*MON_SIZE
	jp SEG_COPY

; TEMP_RESTORE - after loading a level: its walls and monsters as the party
;   left them, if it was there before (the monster counters are rebuilt)
TEMP_RESTORE:
	call TEMP_FLAG
	and (hl)
	ret z
	call TEMP_PLACE
	ld a,(TEMP_SEG)
	call PUT_SEG_P2
	ld hl,(TS_ADDR)
	ld de,BOUNCE
	ld bc,TEMP_MON
	ldir
	call WORLD_P2
	ld hl,BOUNCE
	ld b,(hl)
	inc hl
	inc b
	jr .next
.wall:	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld a,(hl)
	inc hl
	push hl
	ld hl,LEVELDAT+D_MAZE
	add hl,de
	ld (hl),a
	pop hl
.next:	djnz .wall
	ld a,(TEMP_SEG)
	ld (SC_SRCSEG),a
	ld a,(WORLD_SEG)
	ld (SC_DSTSEG),a
	ld hl,(TS_ADDR)
	ld de,TEMP_MON
	add hl,de
	ld de,LEVELDAT+D_MONSTERS
	ld bc,30*MON_SIZE
	call SEG_COPY
	; monsters per block, again
	ld hl,BLOCKCNT
	ld de,BLOCKCNT+1
	ld bc,1023
	ld (hl),0
	ldir
	ld ix,LEVELDAT+D_MONSTERS
	ld b,30
.lp:	ld l,(ix+M_BLOCK)
	ld h,(ix+M_BLOCK+1)
	ld a,h
	or l
	jr z,.n
	ld (ix+M_ATTFRM),0
	push bc
	call BLOCKCNT_PTR
	inc (hl)
	pop bc
.n:	ld de,MON_SIZE
	add ix,de
	djnz .lp
	ret

; SEG_COPY - copies BC bytes from (SC_SRCSEG):HL to (SC_DSTSEG):DE, both in
;   page 2, through BOUNCE_CHUNK; the world segment is mapped at the end
SEG_COPY:
	ld a,b
	or c
	jp z,WORLD_P2
	push bc
	ld a,b
	or a
	jr z,.part
	ld bc,256
.part:	; BC = this chunk
	push bc
	push de
	ld a,(SC_SRCSEG)
	call PUT_SEG_P2
	ld de,BOUNCE_CHUNK
	ldir
	pop de
	pop bc
	push bc
	push hl
	ld hl,BOUNCE_CHUNK
	ld a,(SC_DSTSEG)
	call PUT_SEG_P2
	ldir
	pop hl
	pop bc
	ex (sp),hl		; HL = remaining
	or a
	sbc hl,bc
	ld c,l
	ld b,h
	pop hl
	jr SEG_COPY

TEMP_SEG:	db 0
TEMP_FLAGS:	dw 0
TS_ADDR:	dw 0
TS_LIST:	dw 0
TS_INDEX:	dw 0
SC_SRCSEG:	db 0
SC_DSTSEG:	db 0

; ----------------------------------------------------------------------------
; SAVE_GAME / LOAD_GAME - the game in EOBSAVE.DAT (one slot, as the
;   original): position, hand, party, items, script flags, the visited
;   levels (the current one goes there first) -> NZ on error
; ----------------------------------------------------------------------------
SAVE_GAME:
	call DOORS_COMPLETE
	call TEMP_SAVE		; (it reads LEVELn.DAT over the script)
	call AMCALL
	dw SV_SYNC
	ld de,F_SAVE
	call FILE_CREATE
	jr nz,.err
	ld de,SV_STATE
	ld hl,SV_STATE_LEN
	call FILE_WRITE
	ld de,PARTY
	ld hl,6*P_SIZE
	call FILE_WRITE
	ld de,ITEMS
	ld hl,ITEM_MAX*I_SIZE
	call FILE_WRITE
	call SCRIPT_P2
	ld de,SC_FLAGTAB
	ld hl,18*4
	call FILE_WRITE
	ld a,(MAGIC_SEG)
	call PUT_SEG_P2
	ld de,CH_SPELLS
	ld hl,600
	call FILE_WRITE
	ld de,CH_EVENTS
	ld hl,6*12
	call FILE_WRITE
	ld a,(TEMP_SEG)
	call PUT_SEG_P2
	ld de,8000h
	ld hl,4000h
	call FILE_WRITE
	call AMCALL
	dw AM_SAVE
	call XCALL
	dw FX_SAVE
	push af
	call WORLD_P2
	call FILE_CLOSE
	pop af
	jr nz,.err
	call RELOAD_SCRIPT
	xor a
	ret
.err:	call WORLD_P2
	call RELOAD_SCRIPT
	or 1
	ret

LOAD_GAME:
	ld de,F_SAVE
	ld a,1
	ld c,_OPEN
	call BDOS
	or a
	ret nz
	ld a,b
	ld (FILE_H),a
	xor a
	call MCALL
	dw TT_DISPLAY		; hide before any loader writes the visible frame
	call PTR_HIDE
	call FLY_ALL_END
	ld a,0FFh		; no exchange of characters going on
	ld (SWAP_CHAR),a
	ld de,SV_STATE
	ld hl,SV_STATE_LEN
	call FILE_READ
	ld de,PARTY
	ld hl,6*P_SIZE
	call FILE_READ
	ld de,ITEMS
	ld hl,ITEM_MAX*I_SIZE
	call FILE_READ
	call SCRIPT_P2
	ld de,SC_FLAGTAB
	ld hl,18*4
	call FILE_READ
	ld a,(MAGIC_SEG)
	call PUT_SEG_P2
	ld de,CH_SPELLS
	ld hl,600
	call FILE_READ
	ld de,CH_EVENTS
	ld hl,6*12
	call FILE_READ
	call TEMP_PLACE		; (allocates the segment)
	ld a,(TEMP_SEG)
	call PUT_SEG_P2
	ld de,8000h
	ld hl,4000h
	call FILE_READ
	call AMCALL
	dw AM_LOAD
	call XCALL
	dw FX_LOAD
	call WORLD_P2
	call FILE_CLOSE
	ld hl,(SV_TEMPF)
	ld (TEMP_FLAGS),hl
	ld hl,(SV_EFFECTS)
	ld (PARTY_EFFECTS),hl
	ld a,(SV_MAGIC)
	ld (MAGIC_ACTIVE),a
	xor a
	ld (BOOK_ON),a
	ld (CONTROL_MODE),a
	ld a,(SV_LEVEL)
	call LOAD_LEVEL
	ld hl,(SV_BLOCK)
	ld (CUR_BLOCK),hl
	ld a,(SV_DIR)
	ld (CUR_DIR),a
	ld hl,(SV_HAND)
	ld (HAND),hl
	; the whole frame again (the level store overwrote what the camp kept)
	ld de,F_UI
	call LOAD_V9
.frame_loaded:
	call TEXT_FONT6
	di			; DOS may have enabled BIOS interrupts
	call SCENE_DRAW
	call PANEL_DRAW_ALL
.frame_built:
	ld a,80h
	call MCALL
	dw TT_DISPLAY		; drains commands and reveals at a fresh VBlank
	xor a
	ld (SCENE_DIRTY),a
	ret

; RELOAD_SCRIPT - the script of LEVELn.LVL again into the script segment
RELOAD_SCRIPT:
	call LEVEL_LVL
	call FILE_OPEN
	ld a,(FILE_H)
	ld b,a
	xor a			; from the start of the file
	ld de,0
	ld hl,D_SIZE+192
	ld c,_SEEK
	call BDOS
	call SCRIPT_P2
	ld de,SCRIPT
	ld hl,SCRIPT_MAX
	call FILE_READ
	call FILE_CLOSE
	jp WORLD_P2

; the state block of the save file; SV_SYNC copies the live values in
SV_STATE:
SV_LEVEL:	db 0
SV_BLOCK:	dw 0
SV_DIR:		db 0
SV_HAND:	dw 0
SV_TEMPF:	dw 0
SV_EFFECTS:	dw 0
SV_MAGIC:	db 0
SV_STATE_LEN:	equ $-SV_STATE


F_SAVE:		db LANG_C1,LANG_C2,5Ch,"EOBSAVE.DAT",0
