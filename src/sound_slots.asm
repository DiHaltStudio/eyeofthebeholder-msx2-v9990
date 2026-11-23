; FX_SFX_INSTALL - DE=stream, BC=channel mask and distance coefficient.
; No sound data is accessed here. SFX_START_DIST has restored page 2.
FX_SFX_INSTALL:
	ld (SP_PTR),de
	ld a,c
	ld (SP_MASK),a
	ld a,b
	and 3
	ld (SP_MASK+1),a
	ld a,(SP_DIST)
	sub 1
	jr nc,.distance
	xor a
.distance:
	ld e,a
	ld a,b
	rrca
	rrca
	and 3Fh
	call MUL8		; HL = (distance - 1) * (63 - original level)
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	ld a,h			; product >> 4
	ld (SP_ATT),a
	call FX_SFX_PRIORITY
	ret c
	; Remove overlapping voices; select a free slot (or the first).
	ld de,SL_SIZE
	ld ix,SFX_SLOT
	ld hl,SFX_SLOT
	ld b,SFX_SLOTS
.sl:	ld a,(ix+SL_ON)
	or a
	jr z,.free
	ld a,(SP_MASK)
	and (ix+SL_MASK)
	ld c,a
	ld a,(SP_MASK+1)
	and (ix+SL_MASK+1)
	or c
	jr z,.nx
	; The original AdLib driver replaces voices, not the entire song.
	; Keep the other music channels when a foreground effect takes one.
	ld a,(SP_MASK)
	cpl
	and (ix+SL_MASK)
	ld (ix+SL_MASK),a
	ld c,a
	ld a,(SP_MASK+1)
	cpl
	and (ix+SL_MASK+1)
	ld (ix+SL_MASK+1),a
	or c
	jr nz,.nx
	ld (ix+SL_ON),0
	ld a,(SFX_ACTIVE)
	dec a
	ld (SFX_ACTIVE),a
.free:	push ix
	pop hl
.nx:	add ix,de
	djnz .sl
	push hl
	pop ix
	ld a,(ix+SL_ON)
	or a
	jr nz,.on
	ld a,(SFX_ACTIVE)
	inc a
	ld (SFX_ACTIVE),a
.on:	ld de,(SP_PTR)
	ld (ix+SL_PTR),e
	ld (ix+SL_PTR+1),d
	ld (ix+SL_WAIT),0
	ld bc,(SP_MASK)
	ld (ix+SL_MASK),c
	ld (ix+SL_MASK+1),b
	ld (ix+SL_ON),1
	ld a,(SP_ATT)
	ld (ix+SL_ATT),a
	ld a,(SP_CHANNEL)
	ld (ix+SL_CHANNEL),a
	ld a,(SP_PRIORITY)
	ld (ix+SL_PRIORITY),a
	ret

; EOB.EXE 1A181h..1A196h sets byte 1 of the positional program to 32
; minus distance. The driver at 6866h keeps the current voice when the
; incoming priority is lower; equality restarts it. Check before displacing
; any channel of a multi-voice stream. Intro and generator use other banks.
FX_SFX_PRIORITY:
	ld a,0FFh
	ld (SP_CHANNEL),a
	ld a,(SP_SET)
	cp 'S'
	jr nz,.allow
	ld a,(SP_TRACK)
	or a
	ret z			; driver initialisation
	add a,a
	ld e,a
	ld d,0
	ld hl,FX_ADLIB_PROGRAMS
	add hl,de
	ld a,(hl)
	cp 9
	jr nc,.allow		; the music control channel has no physical OPL voice
	ld (SP_CHANNEL),a
	ld c,a
	inc hl
	ld a,(SP_DIST)
	or a
	ld a,(hl)		; a local effect uses its original program priority
	jr z,.priority
	ld a,(SP_DIST)
	ld e,a
	ld a,32
	sub e
.priority:
	ld (SP_PRIORITY),a
	ld hl,1
	ld a,c
	or a
	jr z,.scan
.bit:	add hl,hl
	dec a
	jr nz,.bit
.scan:	ld ix,SFX_SLOT
	ld de,SL_SIZE
	ld b,SFX_SLOTS
.voice:	bit 0,(ix+SL_ON)
	jr z,.next
	ld a,c
	cp (ix+SL_CHANNEL)
	jr nz,.next
	ld a,l			; a foreground effect may have taken this voice
	and (ix+SL_MASK)	; while the older stream kept its other channels
	jr nz,.compare
	ld a,h
	and (ix+SL_MASK+1)
	jr z,.next
.compare:
	ld a,(SP_PRIORITY)
	cp (ix+SL_PRIORITY)
	ret c
.next:	add ix,de
	djnz .voice
.allow:	or a
	ret
SP_CHANNEL:	db 0
SP_PRIORITY:	db 0
