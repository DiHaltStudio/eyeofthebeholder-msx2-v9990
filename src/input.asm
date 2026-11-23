; ============================================================================
; input.asm - Keyboard through the PPI matrix (the BIOS is not in page 0
;             under MSX-DOS)
; Assembler: Sjasm 0.42c
;
; Keys: cursors = forward / back / turn left / turn right,
;       Z / X = sidestep left / right, SPACE = use (door switch),
;       1..6 = attack with the main hand of each character, Q W E R T Y =
;       with the other hand; ESC is used by menus.
; ============================================================================

KEY_FWD:	equ 1
KEY_BACK:	equ 2
KEY_TLEFT:	equ 3
KEY_TRIGHT:	equ 4
KEY_SLEFT:	equ 5
KEY_SRIGHT:	equ 6
KEY_ESC:	equ 7
KEY_USE:	equ 8
KEY_ATTACK:	equ 16		; + character * 2 + hand

; KEY_ROW - A = matrix row -> A = row bits (0 = pressed)
KEY_ROW:
	ld b,a
	di
	in a,(0AAh)
	and 0F0h
	ld c,a
	or b
	out (0AAh),a
	in a,(0A9h)
	ld b,a
	ld a,c
	out (0AAh),a
	call MAYBE_EI
	ld a,b
	ret

; MAYBE_EI - interrupts on again, but not while the game runs: the BIOS
;   interrupt (it reads the keyboard 60 times a second) costs the Z80 some
;   6 % for nothing, the game reads keys and mouse itself. Preserves all.
MAYBE_EI:
	push af
	ld a,(INT_OFF)
	or a
	jr nz,.n
	ei
.n:	pop af
	ret
INT_OFF:	db 0

; KEYS_READ -> A = KEY_* code of the first key found, 0 if none
KEYS_READ:
	ld a,7
	call KEY_ROW
	bit 2,a
	ld a,KEY_ESC
	ret z
	ld a,8
	call KEY_ROW
	ld b,a
	ld a,KEY_USE
	bit 0,b
	ret z
	ld a,KEY_FWD
	bit 5,b
	ret z
	ld a,KEY_BACK
	bit 6,b
	ret z
	ld a,KEY_TLEFT
	bit 4,b
	ret z
	ld a,KEY_TRIGHT
	bit 7,b
	ret z
	ld a,5			; row 5: Z is bit 7
	call KEY_ROW
	bit 7,a
	ld a,KEY_SLEFT
	ret z
	; KEY_ROW also returns the sampled row in B; reuse it for X.
	bit 5,b
	ld a,KEY_SRIGHT
	ret z
	; attacks: 1..6 = main hand of characters 1..6, Q W E R T Y = other hand
	ld hl,ATTACK_KEYS
	ld e,KEY_ATTACK
.atk:	ld a,(hl)
	cp 0FFh
	jr z,.none
	push hl
	push de
	call KEY_ROW
	pop de
	pop hl
	inc hl
	and (hl)
	ld a,e
	ret z
	inc hl
	inc e
	jr .atk
.none:	xor a
	ret

; (row, mask) per attack key, in KEY_ATTACK + character * 2 + hand order
ATTACK_KEYS:
	db 0,02h, 4,40h		; 1, Q
	db 0,04h, 5,10h		; 2, W
	db 0,08h, 3,04h		; 3, E
	db 0,10h, 4,80h		; 4, R
	db 0,20h, 5,02h		; 5, T
	db 0,40h, 5,40h		; 6, Y
	db 0FFh
