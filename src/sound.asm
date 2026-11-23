; ============================================================================
; sound.asm - The sound effects on the FM part of the OPL4 (MoonSound): the
;   AdLib register streams of SFX.DAT (tools/conv_sfx.py, made with the AdLib
;   driver of the original), up to SFX_SLOTS at a time, at the 72 Hz of that
;   driver from the 60 Hz frame (SFX_FRAME runs in V9_WAIT_VBLANK, so the
;   menus and dialogues go on sounding). No OPL4: nothing is played.
; ============================================================================

OPL_ADDR:	equ 0C4h	; FM, register bank 0 (OPL2 compatible)
OPL_DATA:	equ 0C5h
SFX_SLOTS:	equ 4
SL_PTR:		equ 0		; slot: stream pointer (u16)
SL_WAIT:	equ 2		;       ticks left without writes
SL_MASK:	equ 3		;       OPL channels (u16)
SL_ON:		equ 5
SL_ATT:		equ 6		; extra attenuation for this stream
SL_CHANNEL:	equ 7		; primary DOS AdLib program channel (FFh: untracked)
SL_PRIORITY:	equ 8
SL_SIZE:	equ 9

; SFX_LOADSET - DE = name (not in page 2): a set of sounds in the sound
;   segment (what plays stops), then the driver set-up
SFX_LOADSET:
	ld a,(de)
	ld (SP_SET),a		; SFX.DAT / INSNDn.DAT / CGSND.DAT
	ld a,(SFX_HW)
	or a
	ret z
	push de
	call SFX_STOP
	pop de
	ld a,(CUR_P2)
	push af
	ld a,(SFX_SEG)
	call PUT_SEG_P2
	ld hl,8000h
	ld bc,4000h
	call LOAD_RAM
	pop af
	call PUT_SEG_P2
	xor a
	call SFX_START
	jp SFX_TICK

; SFX_PLAY - A = track (snd_playSoundEffect): it starts, replacing the
;   overlapping voices of older streams. Preserves BC, DE, HL, IX.
SFX_PLAY:
	or a			; (0: the driver set-up, not a sound)
	ret z
SFX_START:
	push de
	ld e,0
SFX_START_DIST:
	ld (SP_TRACK),a
	push hl
	push bc
	push ix
	ld c,a
	ld a,e
	ld (SP_DIST),a
	ld a,(SFX_ON)
	or a
	jp z,.ret
	ld a,(CUR_P2)
	push af
	ld a,(SFX_SEG)
	call PUT_SEG_P2
	ld l,c
	ld h,0
	add hl,hl
	set 7,h			; 8000h + 2 * track: the stream
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld bc,239		; 8000h + 240 + 2 * track: its channels
	add hl,bc
	ld c,(hl)
	inc hl
	ld b,(hl)
	pop af
	call PUT_SEG_P2
	ld a,d
	or e
	jp z,.ret
	call XCALL
	dw FX_SFX_INSTALL
.ret:	pop ix
	pop bc
	pop hl
	pop de
	ret

; ENV_SOUND - A = track, HL = block: heard up to 15 blocks away
;   (snd_processEnvironmentalSoundEffect with the AdLib)
ENV_SOUND:
	or a
	ret z
	push de
	push af
	ld de,(CUR_BLOCK)
	call BLOCK_DISTANCE
	cp 16
	jr nc,.far
	ld e,a
	pop af
	jp SFX_START_DIST
.far:	pop af
	pop de
	ret

; SFX_FRAME - once per frame: 72 ticks a second. Preserves all.
SFX_FRAME:
	push af
	ld a,(SFX_ACTIVE)
	or a
	jr z,.ret
	ld a,(SFX_ACC)
	add a,72
.lp:	cp 60
	jr c,.st
	sub 60
	push af
	call SFX_TICK
	pop af
	jr .lp
.st:	ld (SFX_ACC),a
.ret:	pop af
	ret

; SFX_TICK - one tick of every stream playing. Preserves all but AF.
SFX_TICK:
	push bc
	push de
	push hl
	push ix
	ld a,(CUR_P2)
	push af
	ld a,(SFX_SEG)
	call PUT_SEG_P2
	ld ix,SFX_SLOT
	ld b,SFX_SLOTS
.sl:	ld a,(ix+SL_ON)
	or a
	jr z,.nx
	ld a,(ix+SL_WAIT)
	or a
	jr z,.rd
	dec (ix+SL_WAIT)
	jr .nx
.rd:	ld l,(ix+SL_PTR)
	ld h,(ix+SL_PTR+1)
	ld a,(hl)
	inc hl
	or a
	jr z,.end
	jp m,.wait
	ld c,a
.w:	ld d,(hl)
	inc hl
	ld e,(hl)
	inc hl
	call SFX_WRITE
	dec c
	jr nz,.w
	jr .st
.wait:	and 7Fh			; this tick and k more
	ld (ix+SL_WAIT),a
.st:	ld (ix+SL_PTR),l
	ld (ix+SL_PTR+1),h
	jr .nx
.end:	ld (ix+SL_ON),0
	ld a,(SFX_ACTIVE)
	dec a
	ld (SFX_ACTIVE),a
.nx:	ld de,SL_SIZE
	add ix,de
	djnz .sl
	pop af
	call PUT_SEG_P2
	pop ix
	pop hl
	pop de
	pop bc
	ret

; D=register,E=value: an interrupted voice must not overwrite its new owner.
; A zero mask is the unfiltered driver-init stream. Preserve BC/DE/HL/IX.
SFX_WRITE:
	ld a,d
	sub 0C9h
	cp 22
	jr nc,SFX_WRITE_REAL
	; Marker for a level affected by the original DOS distance transform.
	push de
	add a,40h
	ld d,a
	ld a,e
	and 3Fh
	add a,(ix+SL_ATT)
	cp 64
	jr c,.level
	ld a,63
.level:	xor e
	and 3Fh
	xor e			; preserve the operator's key scaling bits
	ld e,a
	call SFX_WRITE_REAL
	pop de
	ret
SFX_WRITE_REAL:
	ld a,(ix+SL_MASK)
	or (ix+SL_MASK+1)
	jp z,OPL_W
	push bc
	push hl
	ld a,d
	cp 20h
	jr c,.global
	cp 96h
	jr c,.operator
	cp 0E0h
	jr nc,.operator
	cp 0A0h
	jr c,.global
	cp 0C9h
	jr nc,.global
	and 0Fh
	cp 9
	jr c,.channel
.global:
	ld a,9
	jr .channel
.operator:
	and 1Fh
	cp 22
	jr nc,.global
	ld l,a
	ld h,0
	ld bc,SFX_OP_CHANNEL
	add hl,bc
	ld a,(hl)
.channel:
	ld bc,1
	inc a
.shift:	dec a
	jr z,.mask
	sla c
	rl b
	jr .shift
.mask:	ld a,c
	and (ix+SL_MASK)
	ld c,a
	ld a,b
	and (ix+SL_MASK+1)
	or c
	pop hl
	pop bc
	ret z
	jp OPL_W
; OPL_W - D = register, E = value (FM bank 0), the busy bit respected
OPL_W:
	in a,(OPL_ADDR)
	rrca
	jr c,OPL_W
	ld a,d
	out (OPL_ADDR),a
.b:	in a,(OPL_ADDR)
	rrca
	jr c,.b
	ld a,e
	out (OPL_DATA),a
	ret

; SFX_STOP - every stream stops, every note is off
SFX_STOP:
	ld hl,SFX_SLOT
	ld b,SFX_SLOTS*SL_SIZE
.c:	ld (hl),0
	inc hl
	djnz .c
	xor a
	ld (SFX_ACTIVE),a
	ld a,(SFX_HW)
	or a
	ret z
	ld de,0B000h
.k:	call OPL_W
	inc d
	ld a,d
	cp 0B9h
	jr c,.k
	ret

SFX_ON:		db 0		; the effects are heard (preferences)
SFX_HW:		db 0		; there is an OPL4
SFX_SEG:	db 0
SFX_ACTIVE:	db 0
SFX_ACC:	db 0
SP_MASK:	dw 0
SP_PTR:		dw 0
SP_SET:		db 0
SP_TRACK:	db 0
SP_DIST:	db 0
SP_ATT:		db 0
SFX_SLOT:	ds SFX_SLOTS*SL_SIZE
F_SFX:		db "SFX.DAT",0

; Cooperative audio during long graphics uploads/commands. No VRAM or
; register-selector writes; callers own their ongoing V9990 transaction.
SFX_POLL:
	ld a,(SFX_ACTIVE)
	or a
	ret z
	in a,(V9_INTFLAG)
	and 1
	ret z
	out (V9_INTFLAG),a
	jp SFX_FRAME
