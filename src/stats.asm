; ============================================================================
; stats.asm - the statistics page of the inventory (part of the SCRIPT
;   overlay): EoBCoreEngine::gui_drawCharacterStatsPage
; ============================================================================

; STATS_DRAW - A = character: its page over the inventory slots
STATS_DRAW:
	ld (ST_CHAR),a
	ld hl,ST_FILLS
	ld b,3
.fill:	push bc
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	ld c,(hl)
	inc hl
	ld b,(hl)
	inc hl
	ld a,(hl)
	inc hl
	push hl
	ld l,a
	ld a,C_INACTFILL
	call FILL_RECT
	pop hl
	pop bc
	djnz .fill
	ld hl,(ST_GUI)		; "CARACTERISTICAS" (the text out of page 2:
	ld de,TEXTBUF		; SHADED_TEXT is in the UI overlay)
	ld bc,TEXTBUF_LEN
	ldir
	ld hl,TEXTBUF
	ld de,183
	ld c,42
	ld a,C_WHITE
	call UCALL
	dw SHADED_TEXT
	ld a,(ST_CHAR)
	call CHAR_PTR
	ld a,(iy+P_CLASS)
	ld hl,ST_CLASS
	ld c,55
	call ST_LISTED
	ld a,(iy+P_ALIGN)
	ld hl,ST_ALIGN
	ld c,62
	call ST_LISTED
	ld a,(iy+P_RACE)
	ld hl,ST_RACE
	ld c,69
	call ST_LISTED
	; the six abilities
	ld b,0
.ab:	push bc
	ld a,b
	add a,6
	ld hl,ST_STAT
	call ST_PTR
	ld a,b
	add a,a
	add a,a
	add a,a
	sub b			; * 7
	add a,82
	ld c,a
	push bc
	ld de,183
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	pop bc
	pop de
	push de
	push bc
	ld a,d
	call ST_ABILITY		; -> HL = its value as text
	pop bc
	ld de,275
	ld a,C_WHITE
	ld b,0
	call TEXT_PRINT
	pop bc
	inc b
	ld a,b
	cp 6
	jr c,.ab
	; armour class
	ld hl,(ST_GUI+2)
	ld de,183
	ld c,124
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	ld a,(ST_CHAR)
	call CHAR_PTR
	ld a,(iy+P_AC)
	call ST_SNUM
	ld de,275
	ld c,124
	ld a,C_WHITE
	ld b,0
	call TEXT_PRINT
	ld hl,(ST_GUI+4)	; EXP
	ld de,239
	ld c,138
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	ld hl,(ST_GUI+6)	; NIV
	ld de,278
	ld c,138
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	; the classes: name, experience, level
	ld b,0
.cl:	push bc
	ld a,(ST_CHAR)
	call CHAR_PTR
	ld a,(iy+P_CLASS)
	ld c,a
	add a,a
	add a,c
	add a,b
	ld e,a
	ld d,0
	ld hl,ST_CTYPE
	add hl,de
	ld a,(hl)
	cp 0FFh
	jr z,.nx
	add a,15
	ld hl,ST_CLASS
	call ST_PTR
	ld a,b
	add a,a
	add a,a
	add a,a
	sub b
	add a,145
	ld (ST_Y),a
	ld c,a
	ld de,180
	ld a,C_BLACK
	ld b,0
	call TEXT_PRINT
	pop bc
	push bc
	ld a,b			; experience: 4 bytes
	add a,a
	add a,a
	add a,P_EXP
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	call ST_U32		; -> HL = text, B = length
	ld de,251
	call ST_CENTRE
	pop bc
	push bc
	ld e,b
	ld d,0
	push iy
	pop hl
	add hl,de
	ld de,P_LEVELS
	add hl,de
	ld a,(hl)
	call ST_SNUM
	ld de,286
	call ST_CENTRE
.nx:	pop bc
	inc b
	ld a,b
	cp 3
	jr c,.cl
	ret

; ST_CENTRE - HL = text, DE = centre x: at (ST_Y), white
ST_CENTRE:
	push hl
	call STR_LEN
	ld a,b
	add a,a
	add a,b			; half the width
	ld c,a
	ld b,0
	ex de,hl
	or a
	sbc hl,bc
	ex de,hl
	pop hl
	ld a,(ST_Y)
	ld c,a
	ld a,C_WHITE
	ld b,0
	jp TEXT_PRINT

; ST_LISTED - A = index into the list HL, C = y: at x 183, black
ST_LISTED:
	call ST_PTR
	ld de,183
	ld a,C_BLACK
	ld b,0
	jp TEXT_PRINT

; ST_PTR - A = index, HL = list of words -> HL = that entry
ST_PTR:
	push de
	add a,a
	ld e,a
	ld d,0
	add hl,de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	pop de
	ret

; ST_ABILITY - A = 0..5 (str, int, wis, dex, con, cha) -> HL = text
ST_ABILITY:
	ld a,(ST_CHAR)
	push de
	call CHAR_PTR
	pop de
	ld a,d
	or a
	jr nz,.o
	; strength: 18/xx with the exceptional strength (100: 00)
	ld a,(iy+P_STR)
	call ST_SNUM
	ld a,(iy+P_STREXT)
	or a
	ret z
	ld de,ST_BUF
	call ST_CPY
	ld a,'/'
	ld (de),a
	inc de
	ld a,(iy+P_STREXT)
	cp 100
	jr c,.e
	xor a
.e:	ld c,'0'-1
.t:	inc c
	sub 10
	jr nc,.t
	add a,'0'+10
	ex de,hl
	ld (hl),c
	inc hl
	ld (hl),a
	inc hl
	ld (hl),0
	ld hl,ST_BUF
	ret
.o:	ld e,a
	ld d,0
	ld hl,ST_ABOFS-1
	add hl,de
	ld e,(hl)
	push iy
	pop hl
	add hl,de
	ld a,(hl)
	; fall through
; ST_SNUM - A = signed number -> HL = text
ST_SNUM:
	bit 7,a
	jr z,.p
	neg
	call NUM_STR
	dec hl
	ld (hl),'-'
	ret
.p:	jp NUM_STR

ST_CPY:	ld a,(hl)
	or a
	ret z
	ld (de),a
	inc hl
	inc de
	jr ST_CPY

; ST_U32 - HL = a 32-bit number -> HL = decimal text, B = length
ST_U32:
	ld de,ST_N
	ld bc,4
	ldir
	ld hl,ST_BUF+11
	ld (hl),0
.dig:	push hl
	ld hl,ST_N+3		; divide by 10, from the top byte
	ld b,4
	xor a
.dv:	ld c,(hl)
	push bc
	ld b,8
	ld e,a			; remainder
	ld a,c
.bit:	rla
	rl e
	ld c,a
	ld a,e
	sub 10
	jr c,.no
	ld e,a
.no:	ccf
	ld a,c
	djnz .bit
	rla
	ld (hl),a
	ld a,e
	pop bc
	dec hl
	djnz .dv
	pop hl
	dec hl
	add a,'0'
	ld (hl),a
	ld a,(ST_N)
	ld b,a
	ld a,(ST_N+1)
	or b
	ld b,a
	ld a,(ST_N+2)
	or b
	ld b,a
	ld a,(ST_N+3)
	or b
	jr nz,.dig
	push hl
	call STR_LEN
	pop hl
	ret

ST_FILLS:	; x, y, w, h: the slots go under
	dw 179
	db 36, 93, 130
	dw 272
	db 51, 29, 115
	dw 301
	db 51, 18, 97
ST_ABOFS:	db P_INT, P_WIS, P_DEX, P_CON, P_CHA
ST_CHAR:	db 0
ST_Y:		db 0
ST_N:		ds 4
ST_BUF:		ds 12
