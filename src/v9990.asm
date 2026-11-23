; ============================================================================
; v9990.asm - V9990 (GFX9000) routines for the B2 / BP6 mode
; Assembler: Sjasm 0.42c
;
; B2 mode: 384x240 pixels (NTSC overscan), 8 bits per pixel through a
; 64-colour palette (BP6). The image space is 512 pixels wide (XIMM = 01):
; VRAM address = y * 512 + x, 1024 rows in the 512 KB. The hardware cursors
; use 7FE00h-7FFFFh (rows 1023, x 0..511: keep that row free).
;
; Ports (base 60h, standard GFX9000):
;   P#0 60h  VRAM data           P#4 64h  register select
;   P#1 61h  palette data        P#5 65h  status (bit 0 CE = command running)
;   P#2 62h  command data        P#6 66h  interrupt flags
;   P#3 63h  register data       P#7 67h  system control (bit 0 MCS)
;
; Writing a register: OUT (64h),no. and OUT (63h),value; the register number
; auto-increments after each write to 63h.
; ============================================================================

V9_VRAM:	equ 60h
V9_PAL:		equ 61h
V9_CMD:		equ 62h
V9_REGDAT:	equ 63h
V9_REGSEL:	equ 64h
V9_STATUS:	equ 65h
V9_INTFLAG:	equ 66h
V9_SYSCTL:	equ 67h

V9R_WADDR:	equ 0		; R#0-2  VRAM write address (19 bits)
V9R_MODE0:	equ 6		; R#6    DSPM DCKM XIMM CLRM
V9R_MODE1:	equ 7		; R#7    C25M SM1 SM PAL EO IL HSCN
V9R_CTRL:	equ 8		; R#8    bit7 DISP, bit6 SPD (1 = no cursors)
V9R_INTEN:	equ 9		; R#9    interrupt enable
V9R_PALCTL:	equ 13		; R#13   PLTM (bits 7-6): 0 = palette (BP6)
V9R_PALPTR:	equ 14		; R#14   palette pointer (colour no. << 2)
V9R_BACKDROP:	equ 15		; R#15   backdrop colour (0..63)
V9R_ADJUST:	equ 16
V9R_SCAY:	equ 17		; R#17-18 Y scroll
V9R_SCAX:	equ 19		; R#19-20 X scroll
V9R_CSPO:	equ 28		; R#28   cursor palette group (palette bits 5-2)
V9R_CMD_SX:	equ 32		; R#32-43 SX,SY,DX,DY,NX,NY (16 bits each)
V9R_CMD_ARG:	equ 44
V9R_CMD_LOG:	equ 45
V9R_CMD_WM:	equ 46
V9R_CMD_FC:	equ 48
V9R_CMD_OP:	equ 52

V9_OP_LMMM:	equ 40h		; VRAM -> VRAM copy
V9_OP_LMMV:	equ 20h		; rectangle fill (colour FC)
V9_LOG_COPY:	equ 0Ch		; WC = SC
V9_LOG_TCOPY:	equ 1Ch		; WC = SC, except SC = 0 (transparent)

VRAM_CURATR:	equ 7FE00h	; attributes of the 2 cursors (16 bytes)

; ----------------------------------------------------------------------------
; V9_SETREG - writes a register. A = reg. no., E = value. Only modifies A.
; ----------------------------------------------------------------------------
V9_SETREG:
	out (V9_REGSEL),a
	ld a,e
	out (V9_REGDAT),a
	ret

; ----------------------------------------------------------------------------
; V9_REGTABLE - writes (register, value) pairs until a register 0FFh
; ----------------------------------------------------------------------------
V9_REGTABLE:
	ld a,(hl)
	cp 0FFh
	ret z
	out (V9_REGSEL),a
	inc hl
	ld a,(hl)
	out (V9_REGDAT),a
	inc hl
	jr V9_REGTABLE

; ----------------------------------------------------------------------------
; V9_SETWADDR - VRAM write address with auto-increment
;   input: C = bits 18-16, HL = bits 15-0. Modifies A.
; ----------------------------------------------------------------------------
V9_SETWADDR:
	xor a
	out (V9_REGSEL),a
	ld a,l
	out (V9_REGDAT),a
	ld a,h
	out (V9_REGDAT),a
	ld a,c
	and 07h
	out (V9_REGDAT),a
	ret

; ----------------------------------------------------------------------------
; V9_SETPAL - HL = R,G,B data (0..31), A = first colour, B = number of bytes
; ----------------------------------------------------------------------------
V9_SETPAL:
	add a,a
	add a,a
	ld e,a
	ld a,V9R_PALPTR
	call V9_SETREG
	ld c,V9_PAL
	otir
	ret

; ----------------------------------------------------------------------------
; V9_DISPLAY - A = R#8 value (82h = on with cursors, 42h = off)
; ----------------------------------------------------------------------------
V9_DISPLAY:
	ld e,a
	ld a,V9R_CTRL
	jp V9_SETREG

; V9_DISPLAY_SYNC - A = 00h off / 80h on. Drain the blitter, wait for a fresh
; VBlank and change only DISP in R#8 (C8h disables both auto-increments).
; BIOS interrupts never write the V9990; only this foreground owns it.
; The short register transaction preserves IFF. Clobbers AF, DE.
V9_DISPLAY_SYNC:
TT_DISPLAY:
	ld d,a
	call V9_WAIT_CE
	ld a,i
	ld a,i
	push af
	di
	call TT_VBLANK
	ld a,V9R_CTRL | 0C0h
	out (V9_REGSEL),a
	in a,(V9_REGDAT)
	and 7Fh
	or d
.write:	out (V9_REGDAT),a
	pop af
	ret po
	ei
	ret

; Wait until any current retrace ends, then the next one begins. No sound
; tick or other work between the wait and the register/palette transaction.
TT_VBLANK:
.vis:	in a,(V9_STATUS)
	bit 6,a
	jr nz,.vis
.vr:	in a,(V9_STATUS)
	bit 6,a
	jr z,.vr
	ret

; A = palette index, B = bytes, HL = RGB stream. Preserve IFF.
V9_PALETTE_SYNC:
	ld d,a
	ld a,i
	ld a,i
	push af
	di
	call TT_VBLANK
	ld a,d
	call V9_SETPAL
	pop af
	ret po
	ei
	ret

; Initialise the hidden mode. Reset can leave other palette entries live.
V9_BOOT_REGTABLE:
	call V9_REGTABLE
	ld hl,ROWBUF
	ld de,ROWBUF+1
	ld bc,95
	ld (hl),0
	ldir
	xor a
	ld hl,ROWBUF
	ld b,96
	call V9_PALETTE_SYNC
	ld a,32
	ld hl,ROWBUF
	ld b,96
	jp V9_PALETTE_SYNC

; ----------------------------------------------------------------------------
; V9_WAIT_CE - waits for the queued commands and the running one to finish.
;   Preserves all but AF.
; ----------------------------------------------------------------------------
V9_WAIT_CE:
	ld a,(Q_CNT)
	or a
	call nz,Q_FLUSH
.w:	call SFX_POLL		; OPL only; keep the caller's VRAM ownership
	in a,(V9_STATUS)
	rrca
	jr c,.w
	ret

; ----------------------------------------------------------------------------
; V9_WAIT_VBLANK - waits for the next vertical blank (interrupt flag bit 0)
; ----------------------------------------------------------------------------
V9_WAIT_VBLANK:
	ld a,1
	out (V9_INTFLAG),a		; clear the pending flag
.lp:	in a,(V9_INTFLAG)
	rrca
	jr nc,.lp
	ld a,1
	out (V9_INTFLAG),a		; SFX_POLL must not count this frame again
	jp SFX_FRAME			; the sound effects go on

; ----------------------------------------------------------------------------
; V9_LMMM - copies a VRAM -> VRAM rectangle
;   input: HL = 12-byte block: sx, sy, dx, dy, nx, ny (16 bits, LE)
;          A  = logical operation (V9_LOG_COPY or V9_LOG_TCOPY)
;   Waits for the previous command to finish; does not wait for its own.
; ----------------------------------------------------------------------------
V9_LMMM:
	ld e,a
	ld a,(Q_ON)
	or a
	jr nz,Q_ADD
	call V9_WAIT_CE
; V9_ISSUE - HL = the 12-byte block, E = logical operation: the LMMM starts
;   now (no command running) -> HL = the block + 12
V9_ISSUE:
	ld a,V9R_CMD_SX
	out (V9_REGSEL),a
	ld bc,12*256+V9_REGDAT
	otir				; R#32..R#43
	xor a
	out (V9_REGDAT),a		; R#44 ARG = 0 (toward +x, +y)
	ld a,e
	out (V9_REGDAT),a		; R#45 LOG
	ld a,0FFh
	out (V9_REGDAT),a		; R#46-47 write mask
	out (V9_REGDAT),a
	ld a,V9R_CMD_OP
	out (V9_REGSEL),a
	ld a,V9_OP_LMMM
	out (V9_REGDAT),a
	ret

; ----------------------------------------------------------------------------
; The command queue: while Q_ON (the scene composition) the LMMMs wait in
;   Q_BUF and start as soon as the V9990 is free (Q_PUMP is called from the
;   CPU-heavy loops), so the Z80 works while the blitter copies. Writing
;   VRAM with the CPU is safe meanwhile as long as no queued LMMM reads that
;   area (the cache only overwrites shapes after CACHE_RESET, which waits).
; ----------------------------------------------------------------------------
Q_N:		equ 14
Q_ESIZE:	equ 13		; the 12-byte block + LOG

; Q_ADD - HL = block, E = LOG: queued (or started now if all is idle)
Q_ADD:
	ld a,(Q_CNT)
	or a
	jr nz,.full
	in a,(V9_STATUS)
	rrca
	jr nc,V9_ISSUE		; idle: no need to queue it
.full:	ld a,(Q_CNT)
	cp Q_N
	jr c,.room
	call Q_PUMP
	jr .full
.room:	push de
	ld de,(Q_TAIL)
	ld bc,12
	ldir			; HL = block + 12, as V9_ISSUE leaves it
	pop bc
	ld a,c
	ld (de),a
	inc de
	push hl
	ld hl,Q_BUF+Q_N*Q_ESIZE
	or a
	sbc hl,de
	jr nz,.nw
	ld de,Q_BUF
.nw:	ld (Q_TAIL),de
	ld hl,Q_CNT
	inc (hl)
	pop hl
	ld d,b			; (DE kept, like V9_LMMM did)
	ld e,c
	; (falls into Q_PUMP)

; Q_PUMP - the next queued LMMM starts if the V9990 is free.
;   Preserves BC, DE, HL, IX.
Q_PUMP:
	ld a,(Q_CNT)
	or a
	ret z
	in a,(V9_STATUS)
	rrca
	ret c
	push bc
	push de
	push hl
	ld hl,(Q_HEAD)
	ld bc,12
	add hl,bc
	ld e,(hl)
	sbc hl,bc		; (no carry from the add)
	call V9_ISSUE
	inc hl
	ex de,hl
	ld hl,Q_BUF+Q_N*Q_ESIZE
	or a
	sbc hl,de
	jr nz,.nw
	ld de,Q_BUF
.nw:	ld (Q_HEAD),de
	ld hl,Q_CNT
	dec (hl)
	pop hl
	pop de
	pop bc
	ret

; Q_FLUSH - every queued LMMM started (the last one may still run).
;   Preserves BC, DE, HL, IX.
Q_FLUSH:
	call Q_PUMP
	ld a,(Q_CNT)
	or a
	jr nz,Q_FLUSH
	ret

Q_ON:		db 0
Q_CNT:		db 0
Q_HEAD:		dw Q_BUF
Q_TAIL:		dw Q_BUF
Q_BUF:		ds Q_N*Q_ESIZE

; ----------------------------------------------------------------------------
; V9_LMMV - fills a rectangle with a colour
;   input: HL = block: dx, dy, nx, ny (16 bits), A = colour
; ----------------------------------------------------------------------------
V9_LMMV:
	ld e,a
	call V9_WAIT_CE
	ld a,V9R_CMD_SX+4
	out (V9_REGSEL),a
	ld bc,8*256+V9_REGDAT
	otir				; R#36..R#43
	xor a
	out (V9_REGDAT),a		; ARG
	ld a,V9_LOG_COPY
	out (V9_REGDAT),a		; LOG
	ld a,0FFh
	out (V9_REGDAT),a		; WM
	out (V9_REGDAT),a
	ld a,e
	out (V9_REGDAT),a		; FC (8 bpp: same value in both bytes)
	out (V9_REGDAT),a
	ld a,V9R_CMD_OP
	out (V9_REGSEL),a
	ld a,V9_OP_LMMV
	out (V9_REGDAT),a
	ret
