; ============================================================================
; rust.asm - The rust monster eats metal items (script overlay, SCALL)
; Assembler: Sjasm 0.42c
; ============================================================================

; RUST_ATTACK - A = character: 3 times of 4 the first metal item (item
;   type extra properties 80h) of its inventory from a random slot on is
;   gone, "<name> has lost his <item>." (monsterCloseAttack, capsFlags 80h)
RUST_ATTACK:
	ld (RU_CHAR),a
	ld a,4
	call RND_RANGE
	cp 4
	ret z
	ld a,27
	call RND_RANGE
	dec a
	ld c,a			; the slot
	ld b,27
.lp:	push bc
	ld a,(RU_CHAR)
	call CHAR_PTR
	ld a,c
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld (RU_SLOT),hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or e
	jr z,.next
	ld (RU_ITEM),de
	ex de,hl
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld de,IT_METAL
	add hl,de
	bit 7,(hl)
	jr nz,.got
.next:	pop bc
	inc c
	ld a,c
	cp 27
	jr c,.n
	ld c,0
.n:	djnz .lp
	ret
.got:	pop bc
	ld hl,(RU_SLOT)
	xor a
	ld (hl),a
	inc hl
	ld (hl),a
	ld (ix+I_BLOCK),0FFh	; the record is free
	ld (ix+I_BLOCK+1),0FFh
	ld hl,(RU_ITEM)
	call ITEM_NAME
	ld hl,TEXTBUF
	ld de,RU_NAME
	ld bc,RU_NAME_LEN
	ldir
	xor a
	ld (RU_NAME+RU_NAME_LEN-1),a
	ld (TEXTBUF),a
	ld a,(RU_CHAR)
	call CHAR_PTR
	call RU_NAME_APP
	ld hl,STR_RIP_F		; raceSex bit 0: her / his
	bit 0,(iy+P_RACE)
	jr nz,.s
	ld hl,STR_RIP_M
.s:	call TEXT_APPEND
	ld hl,RU_NAME
	call TEXT_APPEND
	ld hl,STR_RIP_END
	call TEXT_APPEND
	ld hl,TEXTBUF
	call MSG_PRINT
	ld a,(RU_CHAR)
	jp PANEL_DRAW
RU_CHAR:	db 0
RU_SLOT:	dw 0
RU_ITEM:	dw 0
RU_NAME_LEN:	equ 40
RU_NAME:	ds RU_NAME_LEN
; RU_NAME_APP - IY = character: its name (10 characters at most) at the
;   end of TEXTBUF (NAME_APPEND of the magic overlay)
RU_NAME_APP:
	push iy
	pop hl
	inc hl
	ld de,RU_CNAME
	ld bc,10
	ldir
	xor a
	ld (de),a
	ld hl,RU_CNAME
	jp TEXT_APPEND
RU_CNAME:	ds 11
