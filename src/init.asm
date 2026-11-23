; ============================================================================
; init.asm - INIT.BIN: the start-up, loaded at C000h (BOUNCE, free until the
;   game runs) by START and run once there: checks, the files, the segments,
;   the intro, the first level, the title menu; then INIT_DONE (resident).
;   The routines and texts used only here are here too, so that the
;   resident code keeps its room.
; ============================================================================
	output "../build/INIT.BIN"
	org BOUNCE

INIT:
	call V9_DETECT
	jr z,.v9ok
	ld de,MSG_NOV9
	jp FATAL
.v9ok:	; page 3 from C000h holds buffers and tables: the TPA must go beyond
	ld a,(0007h)
	cp (PAGE3_END+200h)>>8
	jr nc,.tpa
	ld de,MSG_TPA
	jp FATAL
.tpa:	ld de,F_PAGE3
	ld hl,PAGE3
	ld bc,PAGE3_END-PAGE3
	call LOAD_RAM
	call MAP_INIT
	ld hl,WORLD_SEG
	ld b,2			; WORLD_SEG, SCRIPT_SEG
	call MAP_ALLOC
	call WORLD_P2
	ld de,MSG_LOAD
	call PRINT
	call V9_INIT_B2
	call V9_CURSORS_OFF

	; black screen area (rows 0..239)
	ld hl,CMD_CLS
	ld a,1
	call V9_LMMV
	ld de,F_UI
	call LOAD_V9
	; interface shapes (portraits, icons, floor items) in mapper segments
	ld hl,SEGTAB
	ld b,GLOBAL_SEGS
	call MAP_ALLOC
	ld de,F_GLOBAL_SHP
	xor a
	ld b,GLOBAL_SEGS
	call LOAD_SEGS
	ld de,F_GLOBAL_DAT
	ld hl,GLOBALDAT
	ld bc,2+GLOBAL_N*8
	call LOAD_RAM
	ld de,F_PARTY
	ld hl,PARTY
	ld bc,6*P_SIZE
	call LOAD_RAM
	ld de,F_ITEMS
	ld hl,ITEMS
	ld bc,ITEM_MAX*I_SIZE
	call LOAD_RAM
	; the script segment: item names and the interpreter (the level script
	; comes with each level)
	call SCRIPT_P2
	ld de,F_ITEMNAME
	ld hl,ITEMNAMES
	ld bc,OVL_BASE-ITEMNAMES
	call LOAD_RAM
	ld de,F_SCRIPT_OVL
	ld hl,OVL_BASE
	ld bc,0C000h-OVL_BASE
	call LOAD_RAM
	; the UI overlay (the inventory)
	ld hl,UI_SEG
	ld de,F_UI_OVL
	call INIT_OVERLAY
	; the magic overlay
	ld hl,MAGIC_SEG
	ld de,F_MAGIC_OVL
	call INIT_OVERLAY
	; Native MSX2 automap: code plus exploration for all twelve floors.
	ld hl,AM_SEG
	ld de,F_AUTOMAP
	call INIT_OVERLAY
	ld hl,FX_SEG
	ld de,F_EFFECTS
	call INIT_OVERLAY
	; the sound effects (an OPL4 is needed)
	call SOUND_INIT
	; the texts of the dialogues; the intro runs first in that segment
	ld hl,TEXT_SEG
	ld b,1
	call MAP_ALLOC
	ld a,(TEXT_SEG)
	call PUT_SEG_P2
	ld de,F_INTRO
	ld hl,INTRO_BASE
	ld bc,IN_BUF-INTRO_BASE
	call LOAD_RAM
	call INTRO_RUN
	ld a,(TEXT_SEG)
	call PUT_SEG_P2
	ld de,F_TEXT
	ld hl,8000h
	ld bc,4000h
	call LOAD_RAM
	call WORLD_P2

	ld a,1
	call LOAD_LEVEL
	ld hl,(LEVELDAT+D_START)
	ld (CUR_BLOCK),hl
	ld a,(LEVELDAT+D_START+2)
	ld (CUR_DIR),a

	; the title and its menu: load the last game, start, back to DOS
	call MCALL
	dw TITLE_MENU
	cp 2
	jp z,QUIT
	jp INIT_DONE

INIT_OVERLAY:
 push de
 ld b,1
 call MAP_ALLOC
 dec hl
 ld a,(hl)
 call PUT_SEG_P2
 pop de
 ld hl,8000h
 ld bc,4000h
 jp LOAD_RAM

; ----------------------------------------------------------------------------
; V9_DETECT - Z set if a V9990 answers (R#15 write and read-back test)
; ----------------------------------------------------------------------------
V9_DETECT:
	ld a,V9R_BACKDROP | 40h		; read-only increment inhibited
	out (V9_REGSEL),a
	in a,(V9_REGDAT)
	ld e,a
	cpl
	and 3Fh
	ld d,a
	ld a,V9R_BACKDROP
	out (V9_REGSEL),a
	ld a,d
	out (V9_REGDAT),a
	ld a,V9R_BACKDROP | 40h
	out (V9_REGSEL),a
	in a,(V9_REGDAT)
	and 3Fh
	cp d
	ld a,V9R_BACKDROP
	out (V9_REGSEL),a
	ld a,e
	out (V9_REGDAT),a
	ret

; ----------------------------------------------------------------------------
; V9_INIT_B2 - B2 mode (384x240) BP6, 512 px image, display off
; ----------------------------------------------------------------------------
V9_INIT_B2:
	ld a,2			; P#7: SRS = reset
	out (V9_SYSCTL),a
	ld a,1			; P#7 = MCS: MCKIN clock (overscan B0/B2/B4)
	out (V9_SYSCTL),a
	ld hl,.regs
	jp V9_BOOT_REGTABLE

.regs:	db V9R_CTRL,	02h	; display off; cursor attributes are disabled separately
	db V9R_MODE0,	96h	; DSPM=10 (bitmap) DCKM=01 XIMM=01 (512) CLRM=10 (8 bpp)
	db V9R_MODE1,	00h	; NTSC 60 Hz, no interlace
	db V9R_INTEN,	00h
	db V9R_PALCTL,	00h	; PLTM = 0: BP6, 64-colour palette
	db V9R_BACKDROP, 0
	db V9R_ADJUST,	00h
	db V9R_SCAY+1,	0, V9R_SCAY, 0
	db V9R_SCAX,	0, V9R_SCAX+1, 0
	db 0FFh

; ----------------------------------------------------------------------------
; V9_CURSORS_OFF - disables both cursors (bit D of their attributes)
; ----------------------------------------------------------------------------
V9_CURSORS_OFF:
	ld c,VRAM_CURATR >> 16
	ld hl,VRAM_CURATR & 0FFFFh
	call V9_SETWADDR
	ld b,16
.lp:	ld a,10h
	out (V9_VRAM),a
	djnz .lp
	ret

MAP_INIT:
	ld a,(HOKVLD)
	rrca
	jr nc,.err
	xor a
	ld de,0402h
	call EXTBIO
	ld a,h
	or l
	jr z,.err
	ld (ALL_SEG+1),hl
	ld de,24h
	add hl,de
	ld (PUT_P2+1),hl
	inc hl
	inc hl
	inc hl
	ld (GET_P2+1),hl
	call GET_P2
	ld (ORIG_P2),a
	ret
.err:	ld de,.msg
	jp FATAL
.msg:	db "No DOS2 mapper routines.$"


; LOAD_SEGS - loads a file into B segments of SEGTAB from index A (via page 2)
;   input: DE = ASCIIZ name, A = first index, B = number of segments
LOAD_SEGS:
	ld (.idx),a
	ld a,b
	or a
	ret z
	ld (.cnt),a
	call FILE_OPEN
.lp:	ld a,(.idx)
	call SEG_P2
	ld de,8000h
	ld hl,4000h
	call FILE_READ
	ld hl,.idx
	inc (hl)
	ld a,(.cnt)
	dec a
	ld (.cnt),a
	jr nz,.lp
	call WORLD_P2
	jp FILE_CLOSE
.cnt:	db 0
.idx:	db 0


; SOUND_INIT - an OPL4 there? SFX.DAT in a segment of its own, then the
;   writes of the driver set-up (track 0)
SOUND_INIT:
	in a,(OPL_ADDR)
	inc a
	ret z			; FFh: no MoonSound
	xor a
	ld b,a
	call ALL_SEG
	ret c			; no memory left: no sound
	ld (SFX_SEG),a
	ld a,1
	ld (SFX_ON),a
	ld (SFX_HW),a
	ld de,F_SFX
	jp SFX_LOADSET

CMD_CLS:	dw 0, 0, 512, 240
MSG_NOV9:	db "V9990 (GFX9000) not found.",13,10,"$"
MSG_TPA:	db "Not enough TPA memory.",13,10,"$"
MSG_LOAD:	db "Eye of the Beholder - loading...",13,10,"$"
F_SCRIPT_OVL:	db LANG_C1,LANG_C2,5Ch,"SCRIPT.OVL",0
F_UI_OVL:	db LANG_C1,LANG_C2,5Ch,"UI.OVL",0
F_MAGIC_OVL:	db LANG_C1,LANG_C2,5Ch,"MAGIC.OVL",0
F_TEXT:		db LANG_C1,LANG_C2,5Ch,"TEXT.DAT",0
F_INTRO:	db LANG_C1,LANG_C2,5Ch,"INTRO.OVL",0
F_PAGE3:	db LANG_C1,LANG_C2,5Ch,"PAGE3.DAT",0
F_GLOBAL_SHP:	db "GLOBAL.SHP",0
F_GLOBAL_DAT:	db "GLOBAL.DAT",0
F_PARTY:	db "PARTY.DAT",0
F_ITEMS:	db "ITEMS.DAT",0
F_ITEMNAME:	db LANG_C1,LANG_C2,5Ch,"ITEMNAME.DAT",0

	assert $ <= ROWBUF	; the start-up overflows into ROWBUF
