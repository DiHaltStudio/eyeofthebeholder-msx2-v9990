; ============================================================================
; useitem.asm - using what a hand holds, besides weapons and books (part of
;   the MAGIC overlay): scrolls, potions, wands, letters (clickedWeaponSlot,
;   useMagicScroll, usePotion, useWand, displayParchment)
; ============================================================================

; USE_ITEM - A = extra properties of the hand item (CB_CHAR, CB_SLOT,
;   CB_ITEM, CB_VALUE set by PARTY_ATTACK)
USE_ITEM:
	cp 7
	ret z			; food: eaten in the inventory
	cp 9
	jr z,.mscroll
	cp 10
	jr z,.cscroll
	cp 11
	jr z,.letter
	cp 14
	jp z,USE_POTION
	cp 18
	jp z,USE_WAND
	ld hl,STR_MISUSE1	; worn: used when needed
	or a
	jp z,MSG_PRINT
	cp 16
	jp z,MSG_PRINT
	ld hl,STR_MISUSE2	; not used that way
	jp MSG_PRINT
.cscroll:
	ld a,(CB_VALUE)
	add a,CLERIC_OFS
	jr .scroll
.mscroll:
	ld a,(CB_VALUE)
.scroll:
	call US_BEGIN
	ret nz
	call US_DELETE		; the scroll is gone
	jp US_CAST
.letter:
	ld a,(CB_VALUE)
	jp LETTER

; US_BEGIN - A = spell: cast by the hand of CB_CHAR (the book state kept)
;   -> NZ if it needs a free hand and has none
US_BEGIN:
	push af
	ld a,1
	ld (US_ITEMCAST),a
	ld a,(CB_SLOT)
	ld (US_SLOT),a
	pop af
	ld (ACTIVE_SPELL),a
	ld a,(BOOK_CHAR)
	ld (US_BOOKCHAR),a
	ld a,(BOOK_TYPE)
	ld (US_BOOKTYPE),a
	ld a,(CB_CHAR)
	ld (BOOK_CHAR),a
	ld a,(ACTIVE_SPELL)
	cp CLERIC_OFS+1
	ld a,0
	jr c,.t
	inc a
.t:	ld (BOOK_TYPE),a
	call CS_FREEHAND
	ret z
	jr US_END

; US_CAST - the spell of US_BEGIN starts (on the caster itself)
US_CAST:
	call CS_ANNOUNCE
	ld a,(CAST_WHO)		; a target to choose: the caster
	or a
	jr z,.recovery
	xor a
	ld (CAST_WHO),a
	ld hl,STR_DOT+1		; (the question goes)
	ld a,(BOOK_CHAR)
	ld (ACTIVE_CHAR),a
	call START_SPELL
.recovery:
	call US_HAND_RECOVERY
US_END:	push af
	xor a
	ld (US_ITEMCAST),a
	ld a,(US_BOOKCHAR)
	ld (BOOK_CHAR),a
	ld a,(US_BOOKTYPE)
	ld (BOOK_TYPE),a
	pop af
	ret
US_BOOKCHAR:	db 0
US_BOOKTYPE:	db 0
US_ITEMCAST:	db 0
US_SLOT:	db 0

; gui_updateSlotAfterScrollUse: exactly18 hand ticks, independent of the
; four spell events. Preserve another hand's recovery and any book timer.
; Failed free-hand checks return through US_END without entering this path.
US_HAND_RECOVERY:
	ld a,(BOOK_CHAR)
	call CHAR_PTR
	ld a,(US_SLOT)
	or a
	jr nz,.second
	ld (iy+P_STATUS0),0
	ld (iy+P_TIMER0),18
	res 0,(iy+P_RECOVERY)
	set 0,(iy+P_DISABLED)
	jr .draw
.second:
	ld (iy+P_STATUS1),0
	ld (iy+P_TIMER1),18
	res 1,(iy+P_RECOVERY)
	set 1,(iy+P_DISABLED)
.draw:	ld a,(BOOK_CHAR)
	jp PANEL_DRAW

; US_DELETE - the hand item of CB_CHAR / CB_SLOT is gone (deleteInventoryItem)
US_DELETE:
	ld a,(CB_CHAR)
	call CHAR_PTR
	ld a,(CB_SLOT)
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	push hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	call ITEM_IX
	ld (ix+I_BLOCK),0FFh
	ld (ix+I_BLOCK+1),0FFh
	pop hl
	ld (hl),0
	inc hl
	ld (hl),0
	ld a,(CB_CHAR)
	jp PANEL_DRAW

; USE_POTION - drunk: its effect, then "<name> esta <effect>!"
USE_POTION:
	ld a,(CB_CHAR)
	ld (ACTIVE_CHAR),a
	call XCALL
	dw FX_POTION
	ret c
	jp US_DELETE

; USE_WAND - its spell while it has charges (useWand)
USE_WAND:
	ld a,(CB_VALUE)
	or a
	ld hl,STR_WAND0
	jp z,MSG_PRINT
	cp 5
	jr nz,.spell
	call XCALL
	dw FX_PUSH
	ret
.spell:	ld e,a
	ld d,0
	ld hl,WAND_TYPES
	add hl,de
	ld a,(hl)
	call US_BEGIN
	ret nz
	; a charge less: none left, the wand is gone (updateUsedCharacterHandItem)
	ld hl,(CB_ITEM)
	call ITEM_IX
	ld a,(ix+I_FLAGS)
	and 3Fh
	dec a
	jr z,.gone
	dec (ix+I_FLAGS)
	jp US_CAST
.gone:	call US_DELETE
	jp US_CAST

; LETTER - A = text: a letter, a note, a map in a box over the view
LETTER:
	push af
	call FIN_MODE
	pop af
	call TXT_FETCH
	call DLG_TEXT
	call DLG_MORE
	call DLG_MODE
	jp DLG_END

POTION_BASIC:
 ld a,(CB_CHAR)
 ld (ACTIVE_CHAR),a
 call CHAR_PTR
 ld a,(CB_VALUE)
 cp 2
 jr z,.heal
 cp 3
 jr z,.extra
 cp 4
 jr z,.poison
 cp 5
 jr z,.food
 jp SP_NEUTRALIZE
.heal:
 ld bc,0204h
 ld a,2
 jr .roll
.extra:
 ld bc,0308h
 ld a,3
.roll:
 call ROLL_DICE
 ld c,l
 ld a,(CB_CHAR)
 jp HEAL_CHAR
.poison:
 ld a,(CB_CHAR)
 ld c,2
 jp STATUS_ATTACK
.food:
 ld (iy+P_FOOD),100
 ret
