; ============================================================================
; exp.asm - Experience and levels (increasePartyExperience,
;           increaseCharacterExperience, levelUp), in the script overlay:
;           SCALL from the resident part, a direct call from the scripts
; Assembler: Sjasm 0.42c
; ============================================================================

; ============================================================================
; Experience and levels
; ============================================================================

; PARTY_EXPERIENCE - HL = points shared by the living characters
;   (increasePartyExperience)
PARTY_EXPERIENCE:
	ld (PE_POINTS),hl
	ld bc,0600h		; B = 6 characters, C = how many alive
	xor a
.cnt:	push af
	call CHAR_PTR
	call CHAR_ALIVE_R
	pop de
	jr z,.nc
	inc c
.nc:	ld a,d
	inc a
	djnz .cnt
	ld a,c
	or a
	ret z
	ld hl,(PE_POINTS)
	call DIV16_8
	ld (PE_POINTS),hl
	xor a
.lp:	ld (PE_CHAR),a
	call CHAR_PTR
	call CHAR_ALIVE_R
	call nz,CHAR_EXPERIENCE
	ld a,(PE_CHAR)
	inc a
	cp 6
	jr c,.lp
	ret

; CHAR_EXPERIENCE - IY = character (PE_CHAR), (PE_POINTS): each of its
;   classes gets its part; a class that reaches the next level gains it
;   (increaseCharacterExperience)
CHAR_EXPERIENCE:
	ld e,(iy+P_CLASS)
	ld d,0
	ld hl,LEVELS_PER_CLASS
	add hl,de
	ld a,(hl)
	ld hl,(PE_POINTS)
	call DIV16_8
	ld (PE_PART),hl
	xor a
.cls:	ld (PE_IDX),a
	call CLASS_TYPE_OF	; A = type or -1
	inc a
	jr z,.next
	dec a
	ld (PE_TYPE),a
	; experience[i] += part (u32)
	push iy
	pop hl
	ld de,P_EXP
	add hl,de
	ld a,(PE_IDX)
	add a,a
	add a,a
	ld e,a
	ld d,0
	add hl,de
	push hl
	ld de,(PE_PART)
	ld a,(hl)
	add a,e
	ld (hl),a
	inc hl
	ld a,(hl)
	adc a,d
	ld (hl),a
	inc hl
	ld a,(hl)
	adc a,0
	ld (hl),a
	inc hl
	ld a,(hl)
	adc a,0
	ld (hl),a
	; the experience the next level needs: EXP_TABLES[type][level]
	ld a,(PE_IDX)
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ld de,P_LEVELS
	add hl,de
	ld a,(hl)
	cp 12
	jr c,.lv
	ld a,11
.lv:	ld e,a
	ld a,(PE_TYPE)
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	ld c,l
	ld b,h
	add hl,hl
	add hl,bc		; type * 12
	ld d,0
	add hl,de
	add hl,hl
	add hl,hl		; * 4 bytes
	ld de,EXP_TABLES
	add hl,de
	ex de,hl		; DE = needed
	pop hl			; HL = experience
	; experience >= needed? (compare from the top byte)
	inc hl
	inc hl
	inc hl
	inc de
	inc de
	inc de
	ld b,4
.cmp:	ld a,(de)
	cp (hl)
	jr c,.gain		; needed < experience
	jr nz,.next		; needed > experience
	dec hl
	dec de
	djnz .cmp
.gain:	call LEVEL_UP
.next:	ld a,(PE_IDX)
	inc a
	cp 3
	jr c,.cls
	ret

; CLASS_TYPE_OF - IY = character, (PE_IDX) = class index -> A = class type
CLASS_TYPE_OF:
	ld a,(iy+P_CLASS)
	ld c,a
	add a,a
	add a,c			; class * 3
	ld hl,PE_IDX
	add a,(hl)
	ld e,a
	ld d,0
	ld hl,EXP_CTYPE
	add hl,de
	ld a,(hl)
	ret

; LEVEL_UP - IY = character, (PE_IDX), (PE_TYPE): one more level and its
;   hit points (increaseCharacterLevel, the original's rules)
LEVEL_UP:
	push iy
	pop hl
	ld a,(PE_IDX)
	ld e,a
	ld d,0
	add hl,de
	ld de,P_LEVELS
	add hl,de
	inc (hl)
	ld b,(hl)		; the new level
	ld a,(iy+P_LEVELS)
	ld (iy+P_LEVEL),a
	; up to some level the hit die rolls, then a fixed bonus
	ld a,(PE_TYPE)
	ld e,a
	ld d,0
	ld hl,HP_INCR+6
	add hl,de
	ld a,(hl)
	cp b
	jr c,.fixed
	ld hl,HP_INCR
	add hl,de
	ld c,(hl)
	ld b,1
	xor a
	push de
	call ROLL_DICE
	pop de
	ld a,l
	jr .con
.fixed:	ld hl,HP_INCR+12
	add hl,de
	ld a,(hl)
.con:	ld (PE_HP),a
	; constitution: above +2 only for fighters
	ld e,(iy+P_CON)
	ld d,0
	ld hl,HP_CON_MOD
	add hl,de
	ld a,(hl)
	cp 3
	jp m,.cm
	push af
	call CLASS_FLAG
	and 31h
	pop bc
	ld a,b
	jr nz,.cm
	ld a,2
.cm:	ld hl,PE_HP
	add a,(hl)		; hp (signed)
	dec a
	jp m,.one		; < 1
	inc a
	ld l,a
	ld h,0
	ld e,(iy+P_CLASS)
	ld d,0
	push hl
	ld hl,LEVELS_PER_CLASS
	add hl,de
	ld a,(hl)
	pop hl
	call DIV16_8
	ld a,l
	or a
	jr nz,.add
.one:	ld a,1
.add:	ld c,a
	call XCALL
	dw FX_LEVEL_HP
	ld a,(PE_CHAR)
	call PANEL_DRAW
	; "<name> ha ganado un nivel de experiencia."
	ld a,(PE_CHAR)
	call CHAR_PTR
	push iy
	pop hl
	inc hl
	ld de,TEXTBUF
	ld bc,10
	ldir
	xor a
	ld (de),a
	ld hl,STR_LEVELGAIN
	call TEXT_APPEND
	ld hl,TEXTBUF
	ld a,C_PURPLE		; VGA colour 1
	jp MSG_PRINT_C

PE_POINTS:	dw 0
PE_PART:	dw 0
PE_CHAR:	db 0
PE_IDX:		db 0
PE_TYPE:	db 0
PE_HP:		db 0
