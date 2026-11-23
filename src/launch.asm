; ============================================================================
; launch.asm - EOB.COM: the DiHalt Studio logo and PSG fanfare (9.42 s, cannot be
;   skipped), the cover of the game with the choice of language, and then the
;   game in that language: ES\EOB.BIN or EN\EOB.BIN (src/eob.asm assembled
;   for each language) is read to 0100h and run as if MSX-DOS had loaded it.
;   The pictures come from tools/conv_opening.py: LOGO.BIN (B1 mode, 4 bpp)
;   and COVER.BIN (B3 mode, 512x424 interlaced, BD8 colours).
; ============================================================================
	output "../build/EOB.COM"
	org 0100h

BDOS:		equ 5
RDSLT:		equ 000Ch
CALSLT:		equ 001Ch
CHGCPU:		equ 0180h
EXPTBL:		equ 0FCC1h	; main BIOS slot ID
_INNOE:		equ 08h
_STROUT:	equ 09h
_CONST:		equ 0Bh
_OPEN:		equ 43h
_CLOSE:		equ 45h
_READ:		equ 48h
_TERM:		equ 62h
_DOSVER:	equ 6Fh

V9_VRAM:	equ 60h
V9_PAL:		equ 61h
V9_REGDAT:	equ 63h
V9_REGSEL:	equ 64h
V9_STATUS:	equ 65h
V9_INTFLAG:	equ 66h
V9_SYSCTL:	equ 67h

BUF:		equ 8000h	; file reads, 16 KB (page 2: the disk ROM is not
				; in the way, the sectors go straight in)
CHUNK:		equ 4000h
BLOCK:		equ 1024	; COVER.BIN: RLE blocks (tools/conv_opening.py)
LOGO_VRAM:	equ 60000h	; B1: 128 bytes a line, so line 3072
COVER_W:	equ 512
COVER_H:	equ 424
BAND_Y:		equ 380		; the language band (tools/conv_opening.py)
BAND_H:		equ 44
STUB_AT:	equ 0B000h	; the loader of the game, out of its way

START:
	ld c,_DOSVER
	call BDOS
	or a
	jr nz,.nodos2		; on DOS1 function 6Fh does not exist
	ld a,b
	cp 2
	jr nc,.dos2
.nodos2:
	ld de,MSG_DOS2
	ld c,_STROUT
	call BDOS
	ld c,0
	jp BDOS
.dos2:	call CPU_INIT
	ld de,MSG_TITLE
	call PRINT
	call V9_PROBE
	jr z,.v9
	ld de,MSG_NOV9
	jp FATAL
.v9:	ld de,MSG_V9
	call PRINT
	call LOGO_SHOW
.wait:	call TICK		; keep the logo until the complete fanfare ends
	ld hl,(LOGO_PTR)
	ld a,h
	or l
	jr nz,.wait
	call RELEASE
	call COVER_SHOW
	call CHOOSE
	call DISP_OFF
	call BLANK_PALETTE
.flush:	ld c,_CONST		; the keys of the choice stay in the buffer
	call BDOS		; of MSX-DOS: they would end the intro
	or a
	jr z,.empty
	ld c,_INNOE
	call BDOS
	jr .flush
.empty:
	ld hl,STUB
	ld de,STUB_AT
	ld bc,STUB_END-STUB
	ldir
	ld a,(LANG)
	or a
	ld hl,NAME_ES
	jr z,.go
	ld hl,NAME_EN
.go:	ld de,STUB_AT+STUB_NAME-STUB
	ld bc,NAME_LEN
	ldir
	jp STUB_AT

; CPU_INIT - Read the machine generation from the BIOS slot: DOS maps RAM
; at 002Dh, so a direct read would not identify the machine. RDSLT leaves
; interrupts off; this launcher runs with BIOS/DOS interrupts enabled.
CPU_INIT:
	xor a
	ld (0F3DBh),a		; CLIKSW: keep BIOS keyboard clicks silent
	ld a,(EXPTBL)
	ld hl,002Dh
	call RDSLT
	ei
	cp 3			; only MSX turbo R has CHGCPU
	ret nz
	ld a,1
	ld (CPU_CAN_Z80),a
	jp CPU_KEY

; CPU_KEY - Hold R at launch, or press it during the logo, to select Z80.
; One-shot, turbo R only. Use the BIOS interslot entry because this COM
; itself occupies 0180h. CHGCPU A=80h selects Z80 and updates the turbo LED.
; The selected CPU persists through DOS loads and into the game.
CPU_KEY:
	ld a,(CPU_CAN_Z80)
	or a
	ret z
	ld a,4
	call KEY_ROW
	bit 7,a			; keyboard row 4, bit 7 = R (active low)
	ret nz
	xor a
	ld (CPU_CAN_Z80),a
	push ix
	push iy
	ld ix,CHGCPU
	ld iy,(EXPTBL-1)		; IY high = main BIOS slot
	ld a,80h
	call CALSLT
	ei
	pop iy
	pop ix
	ret

; ----------------------------------------------------------------------------
; LOGO_SHOW - B1 mode (256x212, 4 bpp) showing LOGO.BIN from LOGO_VRAM;
;   the PSG fanfare starts when it appears
; ----------------------------------------------------------------------------
LOGO_SHOW:
	ld a,2			; reset: nothing old shows
	out (V9_SYSCTL),a
	xor a			; MCS = 0: the crystal clock of B1 and B3
	out (V9_SYSCTL),a
	ld hl,MODE_B1
	call SET_REGS
	ld de,F_LOGO
	call OPEN
	ld hl,48		; the 16 colours
	call READ
	xor a
	ld hl,BUF
	ld b,48
	call PALETTE_UPLOAD
	ld a,LOGO_VRAM>>16	; the pixels
	ld hl,LOGO_VRAM&0FFFFh
	call VRAM_ADDR
	call STREAM
	call COVER_LOAD		; preload before music: DOS disk stalls cannot slow it
	call DISP_ON
	ld a,1			; the frames from now
	out (V9_INTFLAG),a
	xor a
	ld (LOGO_WAIT),a
	ld (LOGO_ACC),a
	ld hl,LOGO_MUSIC
	ld (LOGO_PTR),hl
	jp LOGO_TICK

; TICK - advance the 50 Hz PSG stream from the 60 Hz V9990, independently
;   of the MSX's own 50/60 Hz VDP. All disk reads finish before playback.
TICK:
	in a,(V9_INTFLAG)
	rrca
	ret nc
	ld a,1
	out (V9_INTFLAG),a
	ld a,(LOGO_ACC)
	add a,50
	cp 60
	jr c,.save
	sub 60
	ld (LOGO_ACC),a
	push bc
	push de
	push hl
	call CPU_KEY
	call LOGO_TICK
	pop hl
	pop de
	pop bc
	ret
.save:	ld (LOGO_ACC),a
	ret

; One-shot stream from HeroQuest / Mad Mix 2. Waits count 50 Hz ticks;
; FF ends playback. No BIOS hook, so disk reads cannot leave a hook behind.
LOGO_TICK:
	ld hl,(LOGO_PTR)
	ld a,h
	or l
	ret z
	ld a,(LOGO_WAIT)
	or a
	jr z,.read
	dec a
	ld (LOGO_WAIT),a
	ret
.read:	ld a,(hl)
	cp 0FFh
	jp z,LOGO_STOP
	inc hl
	bit 7,a
	jr nz,.wait
	ld e,(hl)
	inc hl
	call LOGO_PSG
	jr .read
.wait:	and 7Fh
	dec a
	ld (LOGO_WAIT),a
	ld (LOGO_PTR),hl
	ret

LOGO_STOP:
	ld hl,(LOGO_PTR)
	ld a,h
	or l
	ret z
	ld hl,0
	ld (LOGO_PTR),hl
	ld e,0
	ld a,8
	call LOGO_PSG
	ld a,9
	call LOGO_PSG
	ld a,10
	call LOGO_PSG
	ld e,3Fh
	ld a,7
	jp LOGO_PSG

; A = sound register, E = value. Preserve live joystick I/O directions in
; R7. Keep each select/write atomic against BIOS PSG access, restoring IFF.
LOGO_PSG:
	ld d,a
	ld a,i
	push af
	di
	ld a,d
	out (PSG_SEL),a
	cp 7
	ld a,e
	jr nz,.write
	in a,(PSG_RD)
	and 0C0h
	ld b,a
	ld a,e
	and 3Fh
	or b
.write:	out (PSG_WR),a
	pop af
	ret po
	ei
	ret

; ----------------------------------------------------------------------------
; COVER_LOAD - COVER.BIN to VRAM 0 (the screen, then the two bands): RLE
;   blocks of BLOCK bytes. Loaded with the display off before the fanfare.
; ----------------------------------------------------------------------------
COVER_LOAD:
	ld de,F_COVER
	call OPEN
	xor a
	ld h,a
	ld l,a
	call VRAM_ADDR
.blk:	ld hl,BLOCK
	call READ
	ld a,h
	or l
	jp z,CLOSE
	ld hl,BUF
.tok:	ld a,(hl)
	inc hl
	cp 80h
	jr z,.blk		; the end of the block
	jr c,.lit
	and 7Fh			; a run
	ld b,a
	ld a,(hl)
	inc hl
.run:	out (V9_VRAM),a
	djnz .run
	jr .tok
.lit:	ld b,a			; so many bytes
	ld c,V9_VRAM
	otir
	jr .tok

; STREAM - the rest of the open file to the VRAM write address, then closed
STREAM:
.lp:	ld hl,CHUNK
	call READ
	ld a,h
	or l
	jr z,.end
	ex de,hl
	ld hl,BUF
	call VRAM_OUT
	jr .lp
.end:	jp CLOSE

; ----------------------------------------------------------------------------
; COVER_SHOW - B3 mode (512x424 interlaced, BD8): the cover and its band
; ----------------------------------------------------------------------------
COVER_SHOW:
	call DISP_OFF
	ld hl,MODE_B3
	call SET_REGS
	xor a			; colour 0 (the border) black
	ld hl,BORDER_RGB
	ld b,3
	call PALETTE_UPLOAD
	call MOUSE_CHECK
	jr nz,.missing
	call BAND_DRAW
	jp DISP_ON		; copy complete before publishing the cover
.missing:
	ld a,2			; bilingual mouse prompt
	call BAND_DRAW_A
	call DISP_ON
WAIT_MOUSE:
	ld a,7
	call KEY_ROW
	bit 2,a
	jp z,QUIT		; ESC can still leave the launcher
	call MOUSE_CHECK
	jr nz,WAIT_MOUSE
	call BAND_DRAW
	jp RELEASE
BORDER_RGB:	db 0,0,0

; BAND_DRAW / BAND_DRAW_A - copy the language band or mouse prompt (LMMM)
BAND_DRAW:
	ld a,(LANG)
BAND_DRAW_A:
	ld hl,COVER_H
	ld de,BAND_H
	or a
	jr z,.sy
	add hl,de
	dec a
	jr z,.sy
	add hl,de
.sy:	ld (CMD_BAND+2),hl
.ce:	in a,(V9_STATUS)
	rrca			; CE: a command still running
	jr c,.ce
	ld a,32
	out (V9_REGSEL),a
	ld hl,CMD_BAND
	ld bc,21*256+V9_REGDAT
	otir
	ret

; ----------------------------------------------------------------------------
; CHOOSE - cursor keys or mouse: ESPAÑOL / ENGLISH in (LANG); SPACE, RETURN
;   or a mouse button take it; ESC goes back to MSX-DOS
; ----------------------------------------------------------------------------
CHOOSE:
	xor a
	ld (MS_ACC),a
.loop:	call FRAME
	ld a,7
	call KEY_ROW
	bit 2,a			; ESC
	jp z,QUIT
	bit 7,a			; RETURN
	jr z,.take
	ld a,8
	call KEY_ROW
	bit 0,a			; SPACE
	jr z,.take
	ld c,0
	bit 4,a			; left
	jr z,.set
	bit 5,a			; up
	jr z,.set
	inc c
	bit 7,a			; right
	jr z,.set
	bit 6,a			; down
	jr z,.set
	call MOUSE_READ
	and 30h			; a button (0 = pressed)
	cp 30h
	jr nz,.take
	ld a,h
	and l
	inc a
	jr z,.loop		; FFh, FFh: no mouse
	ld a,(MS_ACC)		; to the right, dx < 0
	sub h
	ld (MS_ACC),a
	ld c,0
	bit 7,a
	jr nz,.left
	cp 12			; 12 to the right: ENGLISH
	jr c,.loop
	inc c
	jr .set
.left:	cp -11			; 12 to the left: ESPAÑOL
	jr nc,.loop
.set:	xor a
	ld (MS_ACC),a
	ld a,(LANG)
	cp c
	jr z,.loop
	ld a,c
	ld (LANG),a
	call BAND_DRAW
	jr .loop
.take:	jp RELEASE

; RELEASE - waits until no key or button is held (half a second at most)
RELEASE:
	ld b,30
.lp:	push bc
	call FRAME
	ld a,7
	call KEY_ROW
	and 84h			; RETURN, ESC
	cp 84h
	jr nz,.held
	ld a,8
	call KEY_ROW
	and 0F1h		; arrows, SPACE
	cp 0F1h
	jr nz,.held
	call MOUSE_READ
	and 30h
	cp 30h
	jr nz,.held
	pop bc
	ret
.held:	pop bc
	djnz .lp
	ret

QUIT:	call DISP_OFF
	ld b,0
	ld c,_TERM
	jp BDOS

; ----------------------------------------------------------------------------
; the V9990
; ----------------------------------------------------------------------------
; V9_PROBE - Z if a V9990 answers (the backdrop register keeps a value)
V9_PROBE:
	ld a,15
	out (V9_REGSEL),a
	ld a,2Ah
	out (V9_REGDAT),a
	ld a,15 | 40h
	out (V9_REGSEL),a
	in a,(V9_REGDAT)
	and 3Fh
	cp 2Ah
	ret nz
	ld a,15
	out (V9_REGSEL),a
	ld a,15h
	out (V9_REGDAT),a
	ld a,15 | 40h
	out (V9_REGSEL),a
	in a,(V9_REGDAT)
	and 3Fh
	cp 15h
	ret

; Visibility owns only R8 bit7. No BIOS/input calls inside the transaction;
; both paths preserve incoming IFF and all other R8 controls, including010.
DISP_ON:
	push bc
	ld b,80h
	jr DISP_CHANGE
DISP_OFF:
	push bc
	ld b,0
DISP_CHANGE:
	ld a,i
	ld a,i			; audited NMOS Z80 IFF sampling
	push af
	di
.idle:	in a,(V9_STATUS)
	rrca
	jr c,.idle
	call FRAME		; leave this VBlank and enter the next
	ld a,0C8h		; both register auto-increments disabled
	out (V9_REGSEL),a
	in a,(V9_REGDAT)
	and 7Fh
	or b
.write:
	out (V9_REGDAT),a
	bit 7,b
	jr nz,.done
	; The blanked output uses palette entry 0. Clear it in the same retrace.
	xor a
	call PAL_ADDR
	out (V9_PAL),a
	out (V9_PAL),a
	out (V9_PAL),a
.done:
	pop af
	pop bc
	ret po
	ei
	ret

; A=first palette entry, HL=RGB bytes, B=count. The short transfer is the
; sole V9990 writer and fits in a fresh VBlank. Preserve the caller's IFF;
; FRAME/PAL_ADDR do not enable interrupts or call BIOS/DOS.
PALETTE_UPLOAD:
	push de
	ld e,a
	ld a,i
	ld a,i
	push af
	di
	call FRAME
	ld a,e
	call PAL_ADDR
	ld c,V9_PAL
	otir
	pop af
	pop de
	ret po
	ei
	ret

; Clear all 64 colours after the language choice. The black backdrop has
; already been published by DISP_OFF; each half fits in a fresh retrace.
BLANK_PALETTE:
	xor a
	ld hl,.zero
	ld b,96
	call PALETTE_UPLOAD
	ld a,32
	ld hl,.zero
	ld b,96
	jp PALETTE_UPLOAD
.zero:	ds 96,0

; SET_REGS - HL = (register, value) pairs until FFh
SET_REGS:
	ld a,(hl)
	inc a
	ret z
	dec a
	out (V9_REGSEL),a
	inc hl
	ld a,(hl)
	out (V9_REGDAT),a
	inc hl
	jr SET_REGS

; VRAM_ADDR - AHL = VRAM write address
VRAM_ADDR:
	ld c,a
	xor a
	out (V9_REGSEL),a
	ld a,l
	out (V9_REGDAT),a
	ld a,h
	out (V9_REGDAT),a
	ld a,c
	out (V9_REGDAT),a
	ret

; PAL_ADDR - A = first colour
PAL_ADDR:
	add a,a
	add a,a
	ld c,a
	ld a,14
	out (V9_REGSEL),a
	ld a,c
	out (V9_REGDAT),a
	ret

; VRAM_OUT - HL = data, DE = bytes (a multiple of 256, or less than 256 left
;   at the end: the rest goes too)
VRAM_OUT:
	ld c,V9_VRAM
	ld a,e
	or a
	jr z,.full
	ld b,a
	otir
.full:	ld a,d
	or a
	ret z
	ld b,0
.lp:	otir
	dec a
	jr nz,.lp
	ret

; FRAME - waits for the start of the next frame of the V9990
FRAME:
.vis:	in a,(V9_STATUS)
	bit 6,a			; VR: vertical retrace
	jr nz,.vis
.vr:	in a,(V9_STATUS)
	bit 6,a
	jr z,.vr
	ret

; ----------------------------------------------------------------------------
; input
; ----------------------------------------------------------------------------
; KEY_ROW - A = keyboard row -> A = its keys (0 = pressed)
KEY_ROW:
	ld b,a
	di
	in a,(0AAh)
	and 0F0h
	or b
	out (0AAh),a
	in a,(0A9h)
	ei
	ret

PSG_SEL:	equ 0A0h
PSG_WR:		equ 0A1h
PSG_RD:		equ 0A2h
MS_WAIT1:	equ 10
MS_WAIT2:	equ 30

; Require two mouse packets on different frames. A stationary mouse sends
; 0000h; an open port or typical joystick repeats the same nonzero nibble.
MOUSE_CHECK:
	call FRAME
	call MOUSE_PACKET
	ret nz
	call FRAME
MOUSE_PACKET:
	call MOUSE_READ
	ld a,h
	or l
	ret z
	ld a,h
	cp l
	jr nz,.ok
	rlca
	rlca
	rlca
	rlca
	cp h
	jr nz,.ok
	or 1
	ret
.ok:	xor a
	ret

; MOUSE_READ - mouse in port 1 -> H = dx, L = dy, A bits 4-5 = buttons
;   (0 = pressed); as MOUSE_READ of src/mouse.asm
MOUSE_READ:
	ld de,1310h
	ld b,MS_WAIT2
	call .ofs2
	add a,a
	add a,a
	add a,a
	add a,a
	ld c,a
	call .ofs
	and 0Fh
	or c
	ld h,a
	call .ofs
	add a,a
	add a,a
	add a,a
	add a,a
	ld c,a
	call .ofs
	push af
	and 0Fh
	or c
	ld l,a
	pop af
	ei			; (not between the nibbles, as in src/mouse.asm)
	ret
.ofs:	ld b,MS_WAIT1
.ofs2:	ld a,15
	di
	out (PSG_SEL),a
	in a,(PSG_RD)
	and 80h
	or d
	out (PSG_WR),a
	xor e
	ld d,a
	call .wait
	ld a,14
	out (PSG_SEL),a
	in a,(PSG_RD)
	ret
.wait:	ld a,b
.w1:	djnz .w1
	db 0EDh,55h		; RETN on a Z80, a NOP on the R800
	rlca
	rlca
	ld b,a
.w2:	djnz .w2
	ld b,a
.w3:	djnz .w3
	ret

; ----------------------------------------------------------------------------
; files
; ----------------------------------------------------------------------------
; OPEN - DE = name (read only); on error the program ends
OPEN:
	ld (FNAME),de
	ld a,1
	ld c,_OPEN
	call BDOS
	or a
	jr nz,FILE_ERR
	ld a,b
	ld (FH),a
	ret

; READ - HL = bytes -> HL = bytes read, at BUF
READ:
	ld de,BUF
	ld a,(FH)
	ld b,a
	ld c,_READ
	call BDOS
	or a
	ret z
	cp 0C7h			; .EOF
	jr nz,FILE_ERR
	ld hl,0
	ret

CLOSE:
	ld a,(FH)
	ld b,a
	ld c,_CLOSE
	jp BDOS

FILE_ERR:
	call LOGO_STOP
	call DISP_OFF
	ld de,MSG_FILE
	call PRINT
	ld de,(FNAME)
	call PRINT
	ld de,MSG_CRLF
FATAL:	call PRINT
	ld b,1
	ld c,_TERM
	jp BDOS

; PRINT - DE = text ending in 0 or "$"
PRINT:
	ld a,(de)
	or a
	ret z
	cp "$"
	ret z
	push de
	ld e,a
	ld c,2			; _CONOUT
	call BDOS
	pop de
	inc de
	jr PRINT

; ----------------------------------------------------------------------------
; STUB - copied to STUB_AT: clears the memory of the game, reads it to 0100h
;   and runs it (only relative jumps: it runs away from where it is assembled)
; ----------------------------------------------------------------------------
STUB:
	ld hl,0100h
	ld de,0101h
	ld bc,STUB_AT-0101h
	ld (hl),l
	ldir
	ld de,STUB_AT+STUB_NAME-STUB
	ld a,1
	ld c,_OPEN
	call BDOS
	or a
	jr nz,.err
	push bc
	ld de,0100h
	ld hl,STUB_AT-0100h
	ld c,_READ
	call BDOS
	pop bc
	ld c,_CLOSE
	call BDOS
	jp 0100h
.err:	ld b,a
	ld c,_TERM
	jp BDOS
STUB_NAME:	ds 12
STUB_END:

NAME_ES:	db "ES",5Ch,"EOB.BIN",0
NAME_LEN:	equ $-NAME_ES
NAME_EN:	db "EN",5Ch,"EOB.BIN",0

F_LOGO:		db "LOGO.BIN",0
F_COVER:	db "COVER.BIN",0
MSG_TITLE:	db "Eye of the Beholder",13,10
		db "Westwood Associates / SSI 1991",13,10
		db "DiHalt 2026",13,10,13,10,0
MSG_DOS2:	db "MSX-DOS2 or Nextor required.",13,10,"$"
MSG_V9:		db "V9990 found!",13,10,0
MSG_NOV9:	db "V9990 NOT found!",13,10,0
MSG_FILE:	db "Cannot read ",0
MSG_CRLF:	db 13,10,0

; R#6 mode, R#7, R#8 display off, R#9 no interrupts, R#13 colours,
; R#15 border, R#17-18 Y scroll
MODE_B1:	db 6,81h, 7,0, 8,42h, 9,0, 13,0, 15,0
		db 17,(LOGO_VRAM/128)&0FFh, 18,(LOGO_VRAM/128)>>8, 0FFh
MODE_B3:	db 6,96h, 7,06h, 9,0, 13,40h, 15,0, 17,0, 18,0, 0FFh

; LMMM: the band of a language (SY) to the screen
CMD_BAND:	dw 0, COVER_H, 0, BAND_Y, COVER_W, BAND_H
		db 0, 0Ch	; ARG, LOP: copy
		dw 0FFFFh, 0, 0	; WM, FC, BC
		db 40h		; LMMM

LANG:		db 0		; 0 Spanish, 1 English
MS_ACC:		db 0
LOGO_PTR:	dw 0
LOGO_WAIT:	db 0
LOGO_ACC:	db 0
CPU_CAN_Z80:	db 0		; turbo R detected, R shortcut still available
FH:		db 0
FNAME:		dw 0

LOGO_MUSIC:	incbin "../build/logo_psg.bin"

	assert $ < BUF
	assert STUB_END-STUB < 100h
