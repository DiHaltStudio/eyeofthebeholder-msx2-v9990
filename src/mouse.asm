; ============================================================================
; mouse.asm - Mouse (joystick port 1), the pointer and the click
;             areas of the play screen (the original's button list 1)
; Assembler: Sjasm 0.42c
;
; The empty-hand arrow uses the bitmap cursors. A held item uses its full
; colour icon and saves the 16x16 pixels below it to PTR_SAVE (VRAM).
;
; MOUSE_X / MOUSE_Y are game coordinates (0-319, 0-199). Tests may poke them
; and set MOUSE_FAKE to 1 (left click) or 2 (right click).
; ============================================================================

PTR_SAVE_X:	equ 0		; VRAM: below the shape cache (CACHE_END)
PTR_SAVE_Y:	equ 1000

; ----------------------------------------------------------------------------
; MOUSE_READ - the mouse of port 1 -> H = x offset, L = y offset (positive:
;   left / up; FFh, FFh with nothing connected), A = R#14 (buttons in
;   bits 4 and 5, 0 = pressed). Timing for Z80 and R800 (the RETN trick
;   ends the delay early on a Z80). The interrupts stay off for the whole
;   read: a BIOS interrupt between two nibbles (the title menu runs with
;   them) lasts longer than the mouse waits for the next strobe, and the
;   rest of the read comes wrong (the pointer jumped 15-16 pixels).
; ----------------------------------------------------------------------------
MS_WAIT1:	equ 10
MS_WAIT2:	equ 30

MOUSE_READ:
	ld de,1310h		; port 1: R#15 = x0010011b, pin 8 toggled with 10h
	ld b,MS_WAIT2
	call .ofs2
	add a,a
	add a,a
	add a,a
	add a,a
	ld c,a
	call .ofs
	and 0Fh
	or c
	ld h,a
	call .ofs
	add a,a
	add a,a
	add a,a
	add a,a
	ld c,a
	call .ofs
	push af
	and 0Fh
	or c
	ld l,a
	pop af
	jp MAYBE_EI		; (not between the nibbles: see above)
.ofs:	ld b,MS_WAIT1
.ofs2:	ld a,15
	di
	out (PSG_SEL),a
	in a,(PSG_RD)
	and 80h			; keep the kana led
	or d
	out (PSG_WR),a
	xor e
	ld d,a
	call .wait
	ld a,14
	out (PSG_SEL),a
	in a,(PSG_RD)
	ret
.wait:	ld a,b
.w1:	djnz .w1
	db 0EDh,55h		; RETN on a Z80, a NOP on the R800
	rlca
	rlca
	ld b,a
.w2:	djnz .w2
	ld b,a
.w3:	djnz .w3
	ret

PSG_SEL:	equ 0A0h
PSG_WR:		equ 0A1h
PSG_RD:		equ 0A2h

; ----------------------------------------------------------------------------
; MOUSE_UPDATE - once per frame: moves the pointer position, sets CLICK to
;   1 (left) or 2 (right) when a button goes down
; ----------------------------------------------------------------------------
MOUSE_UPDATE:
	call MOUSE_READ
	cpl
	rrca
	rrca
	rrca
	rrca
	and 3			; bit 0 left, bit 1 right (1 = pressed)
	ld c,a
	ld a,h
	and l
	inc a
	jr z,.clk		; FFh, FFh: no mouse
	; x -= dx (0..319)
	push hl
	ld a,h
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld hl,(MOUSE_X)
	or a
	sbc hl,de
	jp p,.x0
	ld hl,0
.x0:	ld de,320
	or a
	sbc hl,de
	add hl,de
	jr c,.x1
	ld hl,319
.x1:	ld (MOUSE_X),hl
	pop hl
	; y -= dy (0..199)
	ld a,l
	ld e,a
	rla
	sbc a,a
	ld d,a
	ld a,(MOUSE_Y)
	ld l,a
	ld h,0
	or a
	sbc hl,de
	jp p,.y0
	ld hl,0
.y0:	ld de,200
	or a
	sbc hl,de
	add hl,de
	jr c,.y1
	ld hl,199
.y1:	ld a,l
	ld (MOUSE_Y),a
.clk:	; new presses
	ld a,(MS_BUT)
	cpl
	and c
	ld b,a
	ld a,c
	ld (MS_BUT),a
	bit 0,b
	ld a,1
	jr nz,.set
	bit 1,b
	ld a,2
	jr nz,.set
	xor a
.set:	ld (CLICK),a
	ld a,(MOUSE_FAKE)
	or a
	ret z
	ld (CLICK),a
	xor a
	ld (MOUSE_FAKE),a
	ret

MOUSE_X:	dw 160
MOUSE_Y:	db 100
MOUSE_FAKE:	db 0
MS_BUT:		db 0
CLICK:		db 0

; ----------------------------------------------------------------------------
; PTR_KEEP_ARROW leaves the hardware arrow visible across view redraws.
; PTR_HIDE also disables the arrow. Both preserve all registers.
; ----------------------------------------------------------------------------
PTR_KEEP_ARROW:
	push af
	ld a,(PTR_HARD)
	or a
	jr z,PTR_HIDE.check
	pop af
	ret
PTR_HIDE:
	push af
.check:	ld a,(PTR_ON)
	or a
	jr nz,.hide
	pop af
	ret
.hide:	pop af
	call XCALL
	dw FX_PTR_HIDE
	ret
PTR_SHOW:
	call XCALL
	dw FX_PTR_SHOW
	ret

PTR_HARD:	db 0
PTR_ON:		db 0
PTR_X:		dw 0
PTR_Y:		dw 0
PTR_ID:		dw 0
PTR_NX:		dw 0
PTR_NY:		dw 0
PTR_NID:	dw 0
PTR_CMD:	dw 0, 0, 0, 0, 16, 16

; ============================================================================
; Click areas (gui_initButton with the button list of the play screen):
; checked in order; a handler returning A = 0 lets the next areas try.
; Entry: x (u16), y, w, h, buttons (1 left, 2 right), handler (u16), arg
; The rectangles include their right and bottom edges, as in the original.
; ============================================================================
CLICK_PROCESS:
	ld a,(SWAP_CHAR)	; two characters change places: only the names
	inc a			; and the panel take clicks
	jr z,.noswap
	call MCALL
	dw SWAP_CLICKS
	ret
.noswap:
	ld a,(BOOK_ON)
	or a
	jr z,.nobook
	call MCALL		; the spellbook below the view takes its clicks
	dw BOOK_CLICKS
	or a
	ret nz
.nobook:
	ld a,(CONTROL_MODE)
	or a
	jr z,.play
	call UCALL		; the inventory has its own areas
	dw INV_CLICKS
	ret
.play:	ld ix,CLICK_AREAS
.lp:	ld a,(ix+0)
	and (ix+1)
	inc a
	ret z			; FFFFh: end
	; x inside?
	ld hl,(MOUSE_X)
	ld e,(ix+0)
	ld d,(ix+1)
	or a
	sbc hl,de
	jr c,.next
	ld e,(ix+3)
	ld d,0
	sbc hl,de
	jr z,.xin
	jr nc,.next
.xin:	; y inside?
	ld a,(MOUSE_Y)
	sub (ix+2)
	jr c,.next
	cp (ix+4)
	jr z,.yin
	jr nc,.next
.yin:	ld a,(CLICK)
	and (ix+5)
	jr z,.next
	push ix
	ld l,(ix+6)
	ld h,(ix+7)
	ld a,(ix+8)
	call .jp
	pop ix
	or a
	ret nz
.next:	ld de,9
	add ix,de
	jr .lp
.jp:	jp (hl)

CLICK_AREAS:
	dw 24
	db 8, 128, 96, 3
	dw CLK_SCENE_SPECIAL
	db 1
	dw 184
	db 2, 63, 50, 3
	dw CLK_CHAR_BOX
	db 0
	dw 256
	db 2, 63, 50, 3
	dw CLK_CHAR_BOX
	db 1
	dw 184
	db 54, 63, 50, 3
	dw CLK_CHAR_BOX
	db 2
	dw 256
	db 54, 63, 50, 3
	dw CLK_CHAR_BOX
	db 3
	dw 184
	db 106, 63, 50, 3
	dw CLK_CHAR_BOX
	db 4
	dw 256
	db 106, 63, 50, 3
	dw CLK_CHAR_BOX
	db 5
	dw 289
	db 177, 31, 21, 3
	dw CLK_CAMP
	db 0
	dw 0
	db 102, 88, 18, 3
	dw CLK_DROP_PICKUP
	db 0
	dw 89
	db 102, 88, 18, 3
	dw CLK_DROP_PICKUP
	db 1
	dw 0
	db 72, 88, 29, 3
	dw CLK_DROP_PICKUP
	db 2
	dw 89
	db 72, 88, 29, 3
	dw CLK_DROP_PICKUP
	db 3
	dw 184
	db 10, 33, 33, 3
	dw CLK_PORTRAIT
	db 0
	dw 256
	db 10, 33, 33, 3
	dw CLK_PORTRAIT
	db 1
	dw 184
	db 62, 33, 33, 3
	dw CLK_PORTRAIT
	db 2
	dw 256
	db 62, 33, 33, 3
	dw CLK_PORTRAIT
	db 3
	dw 184
	db 114, 33, 33, 3
	dw CLK_PORTRAIT
	db 4
	dw 256
	db 114, 33, 33, 3
	dw CLK_PORTRAIT
	db 5
	dw 216
	db 10, 31, 33, 3
	dw CLK_WEAPON_SLOT
	db 0
	dw 288
	db 10, 31, 33, 3
	dw CLK_WEAPON_SLOT
	db 1
	dw 216
	db 62, 31, 33, 3
	dw CLK_WEAPON_SLOT
	db 2
	dw 288
	db 62, 31, 33, 3
	dw CLK_WEAPON_SLOT
	db 3
	dw 216
	db 114, 31, 33, 3
	dw CLK_WEAPON_SLOT
	db 4
	dw 288
	db 114, 31, 33, 3
	dw CLK_WEAPON_SLOT
	db 5
	dw 24
	db 128, 21, 16, 3
	dw CLK_ARROW
	db KEY_FWD
	dw 24
	db 144, 21, 16, 3
	dw CLK_ARROW
	db KEY_BACK
	dw 3
	db 144, 21, 16, 3
	dw CLK_ARROW
	db KEY_SLEFT
	dw 45
	db 144, 21, 16, 3
	dw CLK_ARROW
	db KEY_SRIGHT
	dw 3
	db 128, 21, 16, 3
	dw CLK_ARROW
	db KEY_TLEFT
	dw 45
	db 128, 21, 16, 3
	dw CLK_ARROW
	db KEY_TRIGHT
	dw 0
	db 8, 88, 48, 3
	dw CLK_THROW
	db 0
	dw 88
	db 8, 88, 48, 3
	dw CLK_THROW
	db 1
	dw 0FFFFh

; ----------------------------------------------------------------------------
; Handlers: A = arg -> A = 0 to go on with the next areas
; ----------------------------------------------------------------------------

; CLK_CHAR_BOX - clickedCharPortraitDefault: the character becomes the
;   selected one (no visible effect yet); an empty box ends the search. A
;   right click on its name starts an exchange (clickedCharNameLabelRight).
CLK_CHAR_BOX:
	ld (SEL_CHAR_TRY),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	ld a,1
	ret z
	ld a,(SEL_CHAR_TRY)
	ld (SEL_CHAR),a
	ld a,(CLICK)
	cp 2
	ld a,0
	ret nz
	ld a,(SEL_CHAR_TRY)
	call MCALL
	dw SWAP_LABEL		; A = 0 if not on the name
	ret

; CLK_PORTRAIT - A = character: its inventory
CLK_PORTRAIT:
	ld (SEL_CHAR_TRY),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	ld a,1
	ret z
	ld a,(SEL_CHAR_TRY)
	call UCALL
	dw INV_OPEN
	ld a,1
	ret

CLK_CAMP:
	call UCALL
	dw CAMP
	ld a,1
	ret

; CLK_ARROW - the movement arrows, A = key code
CLK_ARROW:
	call PARTY_ACTION
	ld a,1
	ret

; CLK_WEAPON_SLOT - left: take / put the hand item; right: use it
CLK_WEAPON_SLOT:
	ld (CK_CHAR),a
	call CHAR_PTR
	bit 0,(iy+P_FLAGS)
	ld a,1
	ret z
	; the slot: above the second slot row = the first hand
	ld a,(CK_CHAR)
	srl a
	ld e,a
	ld d,0
	ld hl,PANEL_BOXY
	add hl,de
	ld a,(hl)
	add a,25
	ld c,a
	ld a,(MOUSE_Y)
	cp c
	ld a,0
	jr c,.slot
	inc a
.slot:	ld (CK_SLOT),a
	ld a,(CLICK)
	cp 2
	jr z,.right
	ld a,(CK_CHAR)
	ld c,a
	ld a,(CK_SLOT)
	call UCALL
	dw SWAP_HAND_SLOT
	ld a,1
	ret
.right:	ld a,(CK_CHAR)
	add a,a
	ld hl,CK_SLOT
	add a,(hl)
	call PARTY_ATTACK
	ld a,1
	ret

CK_CHAR:	db 0
CK_SLOT:	db 0
SEL_CHAR:	db 0
SWAP_CHAR:	db 0FFh		; the first character of an exchange (FFh none)
CONTROL_MODE:	db 0		; 0 party panel, 1 inventory
BOOK_ON:	db 0		; the spellbook is open
MAGIC_ACTIVE:	db 0		; timed spell events running
PARTY_EFFECTS:	dw 0		; spell effects on the whole party
UPDATE_CHAR:	db 0		; the character of the inventory
SEL_CHAR_TRY:	db 0
