; ============================================================================
; eob.asm - Eye of the Beholder for MSX-DOS2/Nextor + V9990 (GFX9000)
;           B2 (384x240) / BP6 mode, 320x200 game image at (32, 20)
; Assembler: Sjasm 0.42c        Target: EOB.COM
;
; Memory
;   0100h-7FFFh  code, tables, the party and the item table (ITEMS)
;   8000h-BFFFh  page 2, normally the world segment (WORLD_P2):
;                  LEVELDAT  LEVELn.DAT (maze, shapes, monsters, triggers)
;                  BLOCKCNT  monsters per block (256-aligned)
;                  DRAWOBJ   item queue head per block
;                other segments come in only for a moment: the RAM shapes
;                (GLOBAL.SHP, LEVELn.SHP) while uploading one to VRAM, the
;                script segment (LEVELn.INF at 8000h, ITEMNAME.DAT at
;                A000h) while reading a byte, the DOS segment (FILEBUF)
;                while loading a .V9 file
;   C000h-...    DOS stack
;
; Files (build/): UI.V9 (playfield frame), LEVELn.V9 (level store),
;   LEVELn.PAL (64 colours), LEVELn.DAT (maze and tables), LEVELn.INF (the
;   level script); see tools/conv_level.py and tools/conv_global.py.
; ============================================================================

	org 0100h

	include "../build/vram.inc"
	include "../build/lang.inc"

START:
	call CHECK_DOS2
	ld de,F_INIT		; the start-up runs in page 3 (src/init.asm)
	ld hl,INIT
	ld bc,ROWBUF-INIT
	call LOAD_RAM
	jp INIT
; INIT_DONE - A = choice of the title menu (0 the last game, 1 start): the
;   play field, the game
INIT_DONE:
	ld hl,INT_OFF		; no BIOS interrupt from now on (MAYBE_EI)
	ld (hl),1
	push af
	ld de,F_UI
	call LOAD_V9
	call SCENE_DRAW
	call PANEL_DRAW_ALL
	pop af
	or a
	jr nz,.new
	call WCALL		; the last game (none: the new party stays)
	dw LOAD_GAME
.new:
	call MCALL
	dw AMB_RESET
	ld a,80h
	call MCALL
	dw TT_DISPLAY

; ----------------------------------------------------------------------------
; Main loop, once per frame (60 Hz V9990 vblank):
;   - the game clock: a tick every 55 ms (18.2 Hz, the PC timer) drives the
;     timers of the original (doors for now);
;   - keys: one action per press, auto-repeat while held;
;   - the scene is redrawn when something visible changed (SCENE_DIRTY).
; ----------------------------------------------------------------------------
MAIN:
	di			; (DOS calls turn them on again)
	call V9_WAIT_VBLANK
	call MOUSE_UPDATE
	call CLOCK_FRAME
	call KEYS_READ		; A = KEY_* code, 0 = nothing
	ld hl,KEY_LAST
	cp (hl)
	ld (hl),a
	jr nz,.new
	or a
	jr z,.draw
	ld hl,KEY_DELAY
	dec (hl)
	jr nz,.draw
	push af
	ld a,REPEAT_FRAMES
	call XCALL
	dw FX_REPEAT
	ld (KEY_DELAY),a
	pop af
	jr .act
.new:	or a
	jr z,.draw
	ld hl,KEY_DELAY
	push af
	ld a,FIRST_REPEAT
	call XCALL
	dw FX_REPEAT
	ld (KEY_DELAY),a
	pop af
.act:	cp KEY_ESC
	jr z,.draw		; ESC is handled by menus, not by dungeon movement
	call PARTY_ACTION
.draw:	ld a,(CLICK)
	or a
	call nz,CLICK_PROCESS
	ld a,(LEVEL_REQ)
	or a
	call nz,LEVEL_CHANGE
	ld a,(QUIT_REQ)
	or a
	jp nz,QUIT
	ld a,(SCENE_DIRTY)
	or a
	jr z,MAIN_PTR
	xor a
	ld (SCENE_DIRTY),a
	call SCENE_DRAW
SCENE_DONE:			; (profiling label, see tools/perf_scene.tcl)
MAIN_PTR:	call AMCALL
	dw AM_FRAME
	call PTR_SHOW
	jr MAIN

; CLOCK_FRAME - 60 frames make 18.2 ticks: adds 10 per frame, a tick each 33
CLOCK_FRAME:
	ld hl,CLOCK_ACC
	ld a,(hl)
	add a,10
	ld (hl),a
	cp 33
	ret c
	sub 33
	ld (hl),a
	; --- one tick ---
	call DOORS_TICK
	call CHAR_TIMERS_TICK
	call XCALL
	dw FX_TICK
	call SCRIPT_TIMERS_TICK
	call FLY_TICK
	call TELE_TICK		; (page 3)
	ld hl,(FOOD_TIMER)	; food: every 1080 ticks
	dec hl
	ld (FOOD_TIMER),hl
	ld a,h
	or l
	jr nz,.nofood
	ld hl,1080
	ld (FOOD_TIMER),hl
	call UCALL
	dw FOOD_TICK
.nofood:
	ld a,(MAGIC_ACTIVE)
	or a
	jr z,.nomagic
	call MCALL
	dw MAGIC_TICK
.nomagic:
	call MCALL		; everybody down: the end of this game
	dw PARTY_CHECK
	call MCALL		; the sewer sound deadline ages on all floors
	dw LEVEL_TICK
	jp MONSTERS_TICK

CLOCK_ACC:	db 0
QUIT_REQ:	db 0
FOOD_TIMER:	dw 1080
KEY_LAST:	db 0
KEY_DELAY:	db 0
SCENE_DIRTY:	db 0
REPEAT_FRAMES:	equ 8
FIRST_REPEAT:	equ 14

QUIT:
	call AMCALL
	dw AM_STOP
	call RESTORE_P2
	ld a,42h
	call V9_DISPLAY
	ld de,MSG_BYE
	call PRINT
	ld c,0
	jp BDOS

; ----------------------------------------------------------------------------
; PARTY_ACTION - A = key code: move or turn, redraw if something changed
; ----------------------------------------------------------------------------
PARTY_ACTION:
	cp KEY_ATTACK
	jr c,.notatk
	sub KEY_ATTACK
	jp PARTY_ATTACK
.notatk:
	cp KEY_USE
	jp z,DOOR_ACTION
	cp KEY_FWD
	jr z,.fwd
	cp KEY_BACK
	jr z,.back
	cp KEY_SLEFT
	jr z,.sleft
	cp KEY_SRIGHT
	jr z,.sright
	cp KEY_TLEFT
	jr z,.tleft
	cp KEY_TRIGHT
	ret nz
	ld a,(CUR_DIR)
	inc a
	jr .turn
.tleft:	ld a,(CUR_DIR)
	dec a
.turn:	and 3
	ld (CUR_DIR),a
	jr DIRTY
.fwd:	xor a
	jr .move
.back:	ld a,2
	jr .move
.sleft:	ld a,3
	jr .move
.sright: ld a,1
.move:	ld hl,CUR_DIR
	add a,(hl)
	and 3
	call MOVE_PARTY
	jr nz,DIRTY
	ld a,29			; notifyBlockNotPassable
	call SFX_PLAY
	ld hl,STR_CANTGO
	jp MSG_PRINT
DIRTY:	ld a,1
	ld (SCENE_DIRTY),a
	ret

; MOVE_PARTY - A = absolute direction of the step -> NZ if the party moved
;   The wall of the destination block facing the party must be passable
;   (flag bit 0), as calcNewBlockPositionAndTestPassability does.
MOVE_PARTY:
	ld c,a
	call BLOCK_AHEAD	; HL = new block
	ld a,c
	xor 2			; its wall facing us
	call BLOCK_WALL
	ld e,l
	ld d,h
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	ld a,(hl)
	and 1
	ret z
	ex de,hl
	call BLOCK_HAS_MONSTER
	jr nz,.no
	push hl
	call AMCALL
	dw AM_STEP
	pop hl
	call PARTY_TO_BLOCK
	or 1
	ret
.no:	xor a
	ret

DIR_OFFSET:	dw -32, 1, 32, -1


MSG_BYE:	db 13,10,"$"
F_UI:		db "UI.V9",0
F_INIT:		db LANG_C1,LANG_C2,5Ch,"INIT.BIN",0

CUR_BLOCK:	dw 0
CUR_DIR:	db 0
CUR_LEVEL:	db 1
PARTY:		ds 6*P_SIZE
GLOBALDAT:	ds 2+GLOBAL_N*8

	include "v9990.asm"
	include "dos2.asm"
	include "input.asm"
	include "mouse.asm"
	include "scene.asm"
	include "shapes.asm"
	include "monsters.asm"
	include "cache.asm"
	include "doors.asm"
	include "world.asm"
	include "level.asm"
	include "rng.asm"
	include "sound.asm"
	include "items.asm"
	include "fly.asm"
	include "combat.asm"
	include "../build/itemtypes.inc"
	include "gui.asm"
	include "../build/gui.inc"
	include "../build/strings.inc"
	include "../build/tables.inc"
	include "../build/drawlist.inc"
	include "../build/doortab.inc"	; (DRAW_DOOR is in page 3)

ITEMS:		ds ITEM_MAX*I_SIZE
END_OF_PROGRAM:
	assert END_OF_PROGRAM <= 8000h	; pages 0-1 full

; the world segment (page 2); 256-aligned so the 256-entry tables of
; LEVELDAT are indexed with L
LEVELDAT:	equ 8000h
BLOCKCNT:	equ LEVELDAT + ((D_SIZE + 255) & 0FF00h)	; monsters per block
DRAWOBJ:	equ BLOCKCNT + 1024				; item queue per block
FLYOBJ:		equ DRAWOBJ + 2048				; flying objects
WORLD_END:	equ FLYOBJ + 10*FO_SIZE
	assert WORLD_END <= 0C000h	; world segment full
	assert (FLYOBJ & 0FFh) + 10*FO_SIZE <= 100h	; W_FLY_TURN steps with L
; the script segment
SCRIPT:		equ 8000h	; LEVELn.INF (offsets as in the original)
ITEMNAMES:	equ 0A000h	; ITEMNAME.DAT
OVL_BASE:	equ 0A600h	; SCRIPT.OVL, the interpreter
; page 3 (the TPA top is checked at start)
BOUNCE:		equ 0C000h	; buffers to copy between two page-2 segments
BOUNCE_CHUNK:	equ 0C300h
ROWBUF:		equ BOUNCE_CHUNK	; one shape row while uploading it
BOUNCE_LEN:	equ 400h
PAGE3:		equ BOUNCE+BOUNCE_LEN

	include "script.asm"
UI_BASE:	equ 8000h	; UI.OVL, in the UI segment
	include "ui.asm"
MAGIC_BASE:	equ 8000h	; MAGIC.OVL, in the magic segment
	include "magic.asm"
INTRO_BASE:	equ 8000h	; INTRO.OVL, in the text segment before TEXT.DAT
	include "intro.asm"
CG_BASE:	equ 8000h	; CHARGEN.OVL, in a segment of its own (SEG_RUN)
	include "chargen.asm"
	include "automap.asm"
	include "effects.asm"
	include "init.asm"

; ----------------------------------------------------------------------------
; Page 3 (C400h on, after BOUNCE): tables read from any page-2 mapping,
; loaded from PAGE3.DAT at start, and some buffers
; ----------------------------------------------------------------------------
	output "../build/PAGE3.DAT"
	org PAGE3
	include "../build/font.inc"
	include "../build/itemshp.inc"
	include "doordraw.asm"
	include "teleport.asm"
; Read from any sound/world mapping; keep the small resident area below 8000h.
SFX_OP_CHANNEL:
	db 0,1,2,0,1,2,9,9,3,4,5,3,4,5,9,9,6,7,8,6,7,8
BOOK_STAGE_COORDS:
	ld hl,(LEVELDAT+D_BOOK_STAGE)
	ld de,(LEVELDAT+D_BOOK_STAGE+2)
	ret
PAGE3_FILE_END:
PALBUF:		equ PAGE3_FILE_END		; 192: the level palette
CACHE_TAB:	equ PALBUF+192			; the shape cache
PAGE3_END:	equ CACHE_TAB+CACHE_MAX*6
	assert PAGE3_END <= 0D400h	; page 3 too big (the TPA of Nextor: D606h; INIT checks it)
