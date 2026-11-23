; Item names in the effects overlay; TEXTBUF remains resident.
FX_ITEM_NAME:
 call .name
 ld a,(PARTY_EFFECTS)
 bit 1,a
 ret z
 bit 7,(ix+I_FLAGS)
 ret z
 ld hl,FX_MAGIC_TEXT
 jp TEXT_APPEND
.name:
	call ITEM_IX
	ld a,(ix+I_TYPE)
	cp 34
	jr z,.mage
	cp 35
	jp nz,.ordinary
	ld a,(ix+I_VALUE)
	dec a
	cp 24
	jp nc,.ordinary
	add a,26		; divine values 1..24 -> spell IDs 26..49
	jr .scroll
.mage:	ld a,(ix+I_VALUE)
	dec a
	cp 25
	jp nc,.ordinary
	inc a
.scroll:
	push ix
	call MCALL
	dw SPELL_NAME_TB
	pop ix
	ld a,(TEXTBUF)
	or a
	jp z,.ordinary		; reserved spell IDs have no display name
	; Keep the spell in resident RAM while NAME_COPY maps the script bank.
	ld hl,TEXTBUF
	ld de,SCROLL_NAME
	ld bc,TEXTBUF_LEN
	ldir
	ld a,(ix+I_NAMEUNID)
	call NAME_COPY
	ld hl,SCROLL_COLON
	call TEXT_APPEND
	ld hl,SCROLL_NAME
	jp TEXT_APPEND
.ordinary:
	bit 6,(ix+I_FLAGS)
	jp z,.unid
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld a,(hl)
	cp 14
	jr z,.potion
	cp 18
	jr z,.wand
	cp 16
	jr z,.ring
	jr .normal
.potion:
	ld a,(ix+I_VALUE)
	dec a
	cp FX_POT_NAMES_COUNT
	jr nc,.normal
	ld hl,FX_POT_NAMES
	jr .suffix
.wand:
	ld a,(ix+I_VALUE)
	cp FX_WAND_NAMES_COUNT
	jr nc,.normal
	ld hl,FX_WAND_NAMES
	jr .suffix
.ring:
	ld a,(ix+I_VALUE)
	cp FX_RING_NAMES_COUNT
	jr nc,.normal
	ld hl,FX_RING_NAMES
.suffix:
	add a,a
	ld e,a
	ld d,0
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	push de
	ld a,(ix+I_NAMEUNID)
	call NAME_COPY
	ld hl,SCROLL_COLON
	call TEXT_APPEND
	pop hl
	jp TEXT_APPEND
.normal:
	bit 6,(ix+I_FLAGS)
	jp z,.unid
	ld a,(ix+I_NAMEID)
	call NAME_COPY
	ld a,(TEXTBUF)
	or a
	jp z,.unid		; identified, but no special name
	ret
.unid:	ld a,(ix+I_NAMEUNID)
	call NAME_COPY
	; identified weapons and armour show their bonus: "name +n"
	bit 6,(ix+I_FLAGS)
	ret z
	ld a,(ix+I_VALUE)
	dec a
	ret m			; value <= 0
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld a,(hl)		; extra properties
	cp 4
	ret nc
	ld hl,STR_PLUS
	call TEXT_APPEND
	ld a,(ix+I_VALUE)
	call NUM_STR		; HL = digits
	jp TEXT_APPEND
STR_PLUS:	db " +",0
SCROLL_COLON:	db ": ",0
SCROLL_NAME:	ds TEXTBUF_LEN
