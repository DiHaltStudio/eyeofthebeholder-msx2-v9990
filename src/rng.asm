; ============================================================================
; rng.asm - Random numbers and dice (rollDice of the original engine)
; Assembler: Sjasm 0.42c
; ============================================================================

; RND16 - HL = next value of a 16-bit xorshift generator (7, 9, 8)
RND16:
	ld hl,(RND_SEED)
	ld a,h
	rra
	ld a,l
	rra
	xor h
	ld h,a
	ld a,l
	rra
	ld a,h
	rra
	xor l
	ld l,a
	xor h
	ld h,a
	ld (RND_SEED),hl
	ret

; RND_RANGE - A = n (1..255) -> A = random 1..n. Preserves BC, DE.
RND_RANGE:
	push bc
	push de
	push af
	call RND16
	pop af
	call DIV16_8		; A = HL mod n
	inc a
	pop de
	pop bc
	ret

; ROLL_DICE - B = times, C = pips, A = increment (signed) -> HL = total
;   (times <= 0 or pips <= 0: just the increment)
ROLL_DICE:
	ld l,a
	rla
	sbc a,a
	ld h,a			; HL = increment, sign extended
	ld a,b
	or a
	ret z
	ret m
	ld a,c
	or a
	ret z
	ret m
.lp:	push hl
	ld a,c
	call RND_RANGE
	pop hl
	ld e,a
	ld d,0
	add hl,de
	djnz .lp
	ret

RND_SEED:	dw 0ACE1h
