; ============================================================================
; intro.asm - INTRO.OVL: the animated intro (EoBIntroPlayer), run once at
;   start in the text segment, before TEXT.DAT goes there. It plays the
;   commands made by tools/conv_intro.py (INSEQnn.BIN, loaded part by part
;   in IN_BUF): VRAM copies, fills, images, palettes, texts, sounds. A key
;   or a click ends it.
; ============================================================================
	output "../build/INTRO.OVL"
	org INTRO_BASE

IN_BUF:		equ 8C00h	; the part of the commands being played

INTRO_RUN:
	ld hl,IN_CLS
	xor a
	call V9_LMMV
	call TEXT_FONT8
	xor a
	ld (IN_PART),a
	ld (CLICK),a
	ld (IN_VISIBLE),a
	call IN_LOAD
.lp:	ld a,(hl)
	inc hl
	cp 12
	jr nc,IN_END
	push hl
	add a,a
	ld e,a
	ld d,0
	ld hl,IN_OPS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	ex (sp),hl
	ret			; HL = the operands
IN_NEXT:
	jr INTRO_RUN.lp

IN_OPS:	dw IN_END, IN_WAIT, IN_COPY, IN_TCOPY, IN_FILL, IN_V9, IN_PAL, IN_SFX
	dw IN_SNDSET, IN_TEXT, IN_WHIRL, IN_PARTNEXT

; IN_END - the end (or a key): silence, the sounds of the game, the font
IN_END:
.fl:	ld c,0Bh		; the keys pressed go
	call BDOS
	or a
	jr z,.cls
	ld c,08h
	call BDOS
	jr .fl
.cls:	ld hl,IN_CLS
	xor a
	call V9_LMMV
	ld de,F_SFX
	call SFX_LOADSET
	jp TEXT_FONT6

IN_WAIT:
	ld a,(IN_VISIBLE)
	or a
	jr nz,.ready
	; Publish only after the scene's drawing commands have been submitted.
	inc a
	ld (IN_VISIBLE),a
	ld a,80h
	call V9_DISPLAY_SYNC
.ready:
	ld b,(hl)
	inc hl
.f:	push bc
	push hl
	call V9_WAIT_VBLANK
	call MOUSE_UPDATE
	call KEYS_READ
	ld hl,CLICK
	or (hl)
	jr nz,.k
	push af
	ld c,0Bh		; a key pressed meanwhile (loading): DOS has it
	call BDOS
	pop bc
	or b
.k:
	pop hl
	pop bc
	jr nz,IN_END		; skipped
	djnz .f
	jr IN_NEXT

IN_COPY:
	ld a,V9_LOG_COPY
	jr IN_LMMM
IN_TCOPY:
	ld a,V9_LOG_TCOPY
IN_LMMM:
	ld de,IN_CMD
	ld bc,12
	ldir
	push hl
	ld hl,IN_CMD
	call V9_LMMM
	pop hl
	jp IN_NEXT

IN_FILL:
	ld de,IN_CMD
	ld bc,8
	ldir
	ld a,(hl)
	inc hl
	push hl
	ld hl,IN_CMD
	call V9_LMMV
	pop hl
	jp IN_NEXT

IN_V9:	ex de,hl		; an image
	call IN_SKIPZ
	push hl
	call LOAD_V9_KEEP
	pop hl
	jp IN_NEXT

IN_PAL:	ld a,(IN_VISIBLE)
	or a
	jr z,.upload
	xor a
	ld (IN_VISIBLE),a
	call V9_DISPLAY_SYNC
.upload:
	; A full 192-byte OTIR can overrun B2 retrace on the Z80.
	; Keep the picture hidden across both halves.
	xor a
	ld b,96
	call V9_PALETTE_SYNC
	ld a,32
	ld b,96
	call V9_PALETTE_SYNC
	jp IN_NEXT

IN_VISIBLE: db 0

IN_SFX:	ld a,(hl)
	inc hl
	call SFX_PLAY
	jp IN_NEXT

IN_SNDSET:			; the name goes to page 3 first
	ld de,ROWBUF
.c:	ld a,(hl)
	ld (de),a
	inc hl
	inc de
	or a
	jr nz,.c
	push hl
	ld de,ROWBUF
	call SFX_LOADSET
	pop hl
	jp IN_NEXT

IN_TEXT:
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld a,(hl)
	inc hl
	ld b,0
	push hl
	call TEXT_PRINT
	pop hl
	call IN_SKIPZ0
	jp IN_NEXT

; IN_WHIRL - lines of colour c every 8 pixels, alternately down and across,
;   16 frames (whirlTransition)
IN_WHIRL:
	ld a,(hl)
	inc hl
	push hl
	ld (IN_WCOL),a
	ld c,0			; offset 0..15 (i * 8 + ii)
.st:	push bc
	ld a,c
	and 7
	ld b,a			; ii
	ld a,c
	rrca
	rrca
	rrca
	and 1
	add a,b			; i + ii
	ld e,a
	ld d,0
	bit 0,b
	jr z,.h
	; vertical lines: x = i + ii + 8 k
.v:	ld hl,IN_CMD
	push de
	ld bc,SCREEN_X
	ex de,hl
	add hl,bc
	ex de,hl
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld (hl),SCREEN_Y
	inc hl
	ld (hl),0
	inc hl
	ld (hl),1
	inc hl
	ld (hl),0
	inc hl
	ld (hl),200
	inc hl
	ld (hl),0
	ld hl,IN_CMD
	ld a,(IN_WCOL)
	call V9_LMMV
	pop de
	ld hl,8
	add hl,de
	ex de,hl
	ld hl,320
	or a
	sbc hl,de
	jr z,.next
	jr nc,.v
	jr .next
.h:	; horizontal lines: y = i + ii + 8 k
	ld hl,IN_CMD
	ld (hl),SCREEN_X
	inc hl
	ld (hl),0
	inc hl
	ld a,e
	add a,SCREEN_Y
	ld (hl),a
	inc hl
	ld (hl),0
	inc hl
	ld (hl),320 & 255
	inc hl
	ld (hl),320 >> 8
	inc hl
	ld (hl),1
	inc hl
	ld (hl),0
	push de
	ld hl,IN_CMD
	ld a,(IN_WCOL)
	call V9_LMMV
	pop de
	ld a,e
	add a,8
	ld e,a
	cp 200
	jr c,.h
.next:	call V9_WAIT_VBLANK
	pop bc
	inc c
	ld a,c
	cp 16
	jp c,.st
	pop hl
	jp IN_NEXT

; IN_PARTNEXT - the next part of the commands
IN_PARTNEXT:
	ld hl,IN_PART
	inc (hl)
	call IN_LOAD
	jp IN_NEXT

; IN_LOAD - INSEQ<IN_PART>.BIN into IN_BUF -> HL = IN_BUF
IN_LOAD:
	ld a,(IN_PART)
	ld c,'0'-1
.t:	inc c
	sub 10
	jr nc,.t
	add a,'0'+10
	ld hl,IN_NAME+5
	ld (hl),c
	inc hl
	ld (hl),a
	ld de,IN_NAME_L
	ld hl,IN_BUF
	ld bc,0C000h-IN_BUF
	call LOAD_RAM
	ld hl,IN_BUF
	ret

; IN_SKIPZ - DE = text in the commands: HL after its end
IN_SKIPZ:
	ld l,e
	ld h,d
IN_SKIPZ0:
	ld a,(hl)
	inc hl
	or a
	jr nz,IN_SKIPZ0
	ret

IN_CLS:		dw 0, 0, 512, 240
IN_CMD:		ds 12
IN_WCOL:	db 0
IN_PART:	db 0
IN_NAME_L:	db LANG_C1,LANG_C2,5Ch	; in the language folder
IN_NAME:	db "INSEQ00.BIN",0

	assert $ <= IN_BUF	; the intro code reaches its buffer
