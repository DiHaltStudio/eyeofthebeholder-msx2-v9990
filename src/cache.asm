; ============================================================================
; cache.asm - VRAM cache of the RAM shapes (decorations and monsters)
; Assembler: Sjasm 0.42c
;
; The RAM shapes of the level (LEVELn.SHP, in mapper segments) are uploaded
; to the VRAM rows CACHE_Y0..1022 when a scene needs them, mirrored on the
; fly if asked. The cache is filled in shelves (left to right, top to bottom)
; and flushed when full; the flush waits for every LMMM, queued or running,
; that may read the old contents (CACHE_RESET). Uploads to fresh rows do not
; wait: the blitter goes on meanwhile (see the command queue in v9990.asm).
;
; Entry: key (shape id | 8000h if mirrored), vx, vy   (6 bytes)
; ============================================================================

CACHE_MAX:	equ 64
CACHE_END:	equ PTR_SAVE_Y	; first row not used (below: the pointer save area)

; CACHE_RESET - empties the cache (after loading a level, or when it is full);
;   what was queued or runs may read the old shapes: it finishes first.
;   The first row is CACHE_Y0, not LEVELDAT+D_CACHEY: a full cache also
;   empties while an overlay is in page 2 (the inventory drawing its items),
;   and the row read there sent the next shapes into the screen.
CACHE_RESET:
	call V9_WAIT_CE
	xor a
	ld (CACHE_CNT),a
	ld (CACHE_SH),a
	ld hl,0
	ld (CACHE_X),hl
	ld hl,(CACHE_Y0)
	ld (CACHE_Y),hl
	ret

; CACHE_RESERVE - HL = rows: the cache empties and starts that far below
;   its first row (NPC figures, the death of Xanathar are there)
CACHE_RESERVE:
	push hl
	call CACHE_RESET
	pop de
	ld hl,(CACHE_Y)
	add hl,de
	ld (CACHE_Y),hl
	ret

; ----------------------------------------------------------------------------
; MCACHE_GET - IX = RAM shape entry, (SHP_ID) = its id, B = 1 mirrored
;   -> IX = SHP_TMP, an entry with the VRAM vx, vy of the cached copy
;   Preserves B. The entry is copied first: the level shape table is in the
;   world segment, which leaves page 2 while the shape is uploaded.
; ----------------------------------------------------------------------------
MCACHE_GET:
	push bc
	push ix
	pop hl
	ld de,CK_ENT
	ld bc,8
	ldir
	ld ix,CK_ENT
	pop bc
	push bc
	ld hl,(SHP_ID)
	ld a,b
	or a
	jr z,.key
	set 7,h
.key:	ld (CK_KEY),hl
	ld a,(ix+4)
	ld (SHP_TMP+4),a
	ld a,(ix+5)
	ld (SHP_TMP+5),a
	; --- search ---
	ld a,(CACHE_CNT)
	or a
	jr z,.miss
	ld b,a
	ld hl,CACHE_TAB
	ld de,(CK_KEY)
.find:	ld a,(hl)
	cp e
	jr nz,.nf
	inc hl
	ld a,(hl)
	dec hl
	cp d
	jr z,.hit
.nf:	ld a,6
	add a,l
	ld l,a
	jr nc,.nc
	inc h
.nc:	djnz .find
.miss:	call CACHE_ALLOC	; -> (CK_X), (CK_Y)
	call CACHE_UPLOAD
	; new entry
	ld a,(CACHE_CNT)
	ld l,a
	inc a
	ld (CACHE_CNT),a
	ld h,0
	ld e,l
	ld d,h
	add hl,hl
	add hl,de
	add hl,hl		; *6
	ld de,CACHE_TAB
	add hl,de
	ld de,(CK_KEY)
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld de,(CK_X)
	ld (hl),e
	inc hl
	ld (hl),d
	inc hl
	ld de,(CK_Y)
	ld (hl),e
	inc hl
	ld (hl),d
	jr .done
.hit:	inc hl
	inc hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld (CK_X),de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (CK_Y),de
.done:	ld hl,(CK_X)
	ld (SHP_TMP),hl
	ld hl,(CK_Y)
	ld (SHP_TMP+2),hl
	ld ix,SHP_TMP
	pop bc
	ret

; CACHE_ALLOC - room for (ix+4) x (ix+5) -> (CK_X), (CK_Y); flushes if full
CACHE_ALLOC:
	ld a,(CACHE_CNT)
	cp CACHE_MAX
	call z,CACHE_RESET
.retry:	ld hl,(CACHE_X)
	ld e,(ix+4)
	ld d,0
	add hl,de
	ld de,512+1
	or a
	sbc hl,de
	jr c,.fitx		; x + w <= 512
	; new shelf
	ld hl,(CACHE_Y)
	ld a,(CACHE_SH)
	ld e,a
	ld d,0
	add hl,de
	ld (CACHE_Y),hl
	ld hl,0
	ld (CACHE_X),hl
	xor a
	ld (CACHE_SH),a
.fitx:	ld hl,(CACHE_Y)
	ld e,(ix+5)
	ld d,0
	add hl,de
	ld de,CACHE_END+1
	or a
	sbc hl,de
	jr c,.fity
	call CACHE_RESET	; full: start again
	jr .retry
.fity:	ld hl,(CACHE_X)
	ld (CK_X),hl
	ld e,(ix+4)
	ld d,0
	add hl,de
	ld (CACHE_X),hl
	ld hl,(CACHE_Y)
	ld (CK_Y),hl
	ld a,(CACHE_SH)
	cp (ix+5)
	ret nc
	ld a,(ix+5)
	ld (CACHE_SH),a
	ret

; CACHE_UPLOAD - copies the RAM shape IX to VRAM (CK_X, CK_Y), mirrored if
;   the key has bit 15 set. Source: segment (ix+6), address (ix+0..1).
;   IX must not point to page 2; the segment page 2 had comes back at the end.
CACHE_UPLOAD:
	ld a,(CUR_P2)
	ld (CK_PREV),a
	ld a,(ix+6)
	call SEG_P2
	ld l,(ix+0)
	ld h,(ix+1)
	ld (CK_SRC),hl
	ld hl,(CK_Y)
	ld (CK_ROW),hl
	ld b,(ix+5)
.row:	call Q_PUMP		; (the blitter goes on with the scene)
	push bc
	; VRAM address = row * 512 + x
	ld hl,(CK_ROW)
	ld a,l
	add a,a			; bit 7 of the row -> carry
	ld c,h
	rl c			; C = row >> 7
	ld h,a			; H = (row & 7Fh) << 1
	ld de,(CK_X)
	ld a,d
	or h
	ld h,a			; + x bit 8
	ld l,e
	call V9_SETWADDR
	; the row is RLE (n < 80h: n bytes; 80h + n: n times one byte):
	; forwards straight to the port, mirrored through ROWBUF backwards
	ld hl,(CK_SRC)
	ld e,(ix+4)		; pixels left
	ld c,V9_VRAM
	ld a,(CK_KEY+1)
	rla
	jr c,.mirror
.fw:	ld a,(hl)
	inc hl
	bit 7,a
	jr nz,.frun
	ld b,a
	ld d,a
	otir
	jr .fnext
.frun:	and 7Fh
	ld b,a
	ld d,a
	ld a,(hl)
	inc hl
.fr:	out (c),a
	djnz .fr
.fnext:	ld a,e
	sub d
	ld e,a
	jr nz,.fw
	ld (CK_SRC),hl
	jr .next
.mirror:
	; the address of every token goes to ROWBUF (a row of w pixels has at
	; most w / 2 + 1), then the tokens go out from the last one, each
	; backwards: literals with otdr, runs with out
	ld de,ROWBUF
	ld b,(ix+4)		; pixels left
.tk:	ld a,l
	ld (de),a
	inc de
	ld a,h
	ld (de),a
	inc de
	ld a,(hl)
	inc hl
	bit 7,a
	jr nz,.tr
	ld c,a			; literal: n bytes
	add a,l
	ld l,a
	jr nc,.tl
	inc h
.tl:	ld a,b
	sub c
	ld b,a
	jr nz,.tk
	jr .emit
.tr:	and 7Fh			; run: n times one byte
	ld c,a
	inc hl
	ld a,b
	sub c
	ld b,a
	jr nz,.tk
.emit:	ld (CK_SRC),hl
	ld c,V9_VRAM
.em:	dec de
	ld a,(de)
	ld h,a
	dec de
	ld a,(de)
	ld l,a			; HL = the token
	ld a,(hl)
	bit 7,a
	jr nz,.er
	ld b,a
	add a,l
	ld l,a
	jr nc,.el
	inc h			; HL = its last byte
.el:	otdr
	ld a,e
	or a
	jr nz,.em
	jr .next
.er:	and 7Fh
	ld b,a
	inc hl
	ld a,(hl)
.erl:	out (c),a
	djnz .erl
	ld a,e
	or a			; (ROWBUF is 256-aligned)
	jr nz,.em
.next:	ld hl,(CK_ROW)
	inc hl
	ld (CK_ROW),hl
	pop bc
	dec b
	jp nz,.row
	ld a,(CK_PREV)		; back to what page 2 had (world or an overlay)
	jp PUT_SEG_P2

	assert (ROWBUF & 0FFh) == 0
CK_PREV:	db 0
CACHE_CNT:	db 0
CACHE_SH:	db 0
CACHE_X:	dw 0
CACHE_Y:	dw 0
CACHE_Y0:	dw 0		; the first row of the cache in this level (LOAD_LEVEL)
CK_KEY:		dw 0
CK_X:		dw 0
CK_Y:		dw 0
CK_SRC:		dw 0
CK_ROW:		dw 0
SHP_ID:		dw 0
SHP_TMP:	ds 8
CK_ENT:		ds 8
;  CACHE_TAB (CACHE_MAX * 6 bytes) is in page 3, see eob.asm
