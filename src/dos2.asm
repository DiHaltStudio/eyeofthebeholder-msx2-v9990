; ============================================================================
; dos2.asm - File access with MSX-DOS2 / Nextor and console utilities
; Assembler: Sjasm 0.42c
;
; BDOS calls (CALL 0005h, function in C):
;   02h _CONOUT  E = character
;   09h _STROUT  DE = text terminated by '$'
;   43h _OPEN    DE = ASCIIZ name, A = mode (1 = read-only) -> B = handle
;   45h _CLOSE   B = handle
;   48h _READ    B = handle, DE = buffer, HL = bytes -> HL = bytes read
;   62h _TERM    B = error code (ends the program)
;   6Fh _DOSVER  -> B = kernel version (2 or higher on DOS2/Nextor)
; All return A = error code (0 = OK).
; ============================================================================

BDOS:		equ 0005h
_CONOUT:	equ 02h
_STROUT:	equ 09h
_OPEN:		equ 43h
_CLOSE:		equ 45h
_READ:		equ 48h
_SEEK:		equ 4Ah
_CREATE:	equ 44h
_WRITE:		equ 49h
_TERM:		equ 62h
_DOSVER:	equ 6Fh

FILEBUF:	equ 8000h	; file read buffer
FILEBUF_LEN:	equ 4000h	; 16 KB

; ----------------------------------------------------------------------------
; PRINT - writes a text terminated by '$'
;   input: DE = text
; ----------------------------------------------------------------------------
PRINT:
	ld c,_STROUT
	jp BDOS

; ----------------------------------------------------------------------------
; CHECK_DOS2 - ends with a message if there is no MSX-DOS2 or Nextor
; ----------------------------------------------------------------------------
CHECK_DOS2:
	ld c,_DOSVER
	call BDOS
	or a
	jr nz,.no	; on DOS1 function 6Fh does not exist
	ld a,b
	cp 2
	ret nc
.no:	ld de,.msg
	call PRINT
	ld c,0		; _TERM0 (also valid on DOS1)
	jp BDOS
.msg:	db "MSX-DOS2 or Nextor required.",13,10,"$"

; ----------------------------------------------------------------------------
; FILE_OPEN - opens a file for reading. DE = ASCIIZ name -> (FILE_H)
;   On error, ends the program showing the file name.
; ----------------------------------------------------------------------------
FILE_OPEN:
	ld (FILE_NAME),de
	ld a,1			; mode: read-only
	ld c,_OPEN
	call BDOS
	or a
	jp nz,FILE_ERROR
	ld a,b
	ld (FILE_H),a
	ret

; FILE_READ - reads HL bytes into DE from the open file -> HL = bytes read
FILE_READ:
	ld a,(FILE_H)
	ld b,a
	ld c,_READ
	jp BDOS

; FILE_CREATE - DE = ASCIIZ name: a new (or emptied) file for writing
;   -> NZ on error
FILE_CREATE:
	xor a			; open mode: read and write
	ld b,0			; attributes
	ld c,_CREATE
	call BDOS
	or a
	ret nz
	ld a,b
	ld (FILE_H),a
	xor a
	ret

; FILE_WRITE - writes HL bytes from DE -> NZ on error
FILE_WRITE:
	ld a,(FILE_H)
	ld b,a
	ld c,_WRITE
	call BDOS
	or a
	ret

FILE_CLOSE:
	ld a,(FILE_H)
	ld b,a
	ld c,_CLOSE
	jp BDOS

FILE_H:		db 0
FILE_NAME:	dw 0

; ----------------------------------------------------------------------------
; LOAD_V9 - loads a VRAM file (.V9, format in write_v9 of conv_level.py):
;   RLE chunks, each with its VRAM address, and rectangles to clear; read
;   16 KB at a time into FILEBUF (the DOS segment of page 2), no item
;   crosses a block. The world segment comes back at the end.
;   input: DE = ASCIIZ name
; ----------------------------------------------------------------------------
LOAD_V9:
	call V9_WAIT_CE		; no command may be writing VRAM meanwhile
	call FILE_OPEN
	call RESTORE_P2
	call .fill
.hdr:	ld e,(hl)		; header: VRAM address (FExxxxh clear, FFxxxxh end)
	inc hl
	ld d,(hl)
	inc hl
	ld a,(hl)
	inc hl
	cp 0FEh
	jr c,.addr
	jr nz,.eof
	xor a			; clear: dx, dy, nx, ny
	call V9_LMMV
	call V9_WAIT_CE
	jr .hdr
.addr:	ld c,a
	ex de,hl
	call V9_SETWADDR
	ex de,hl
	ld c,V9_VRAM
.tok:	call SFX_POLL		; sound continues while pixels are decompressed
	ld a,(hl)
	inc hl
	or a
	jp m,.run
	jr z,.next
	ld b,a			; n bytes
	otir
	jr .tok
.run:	and 7Fh			; 80h: the end of the chunk
	jr z,.hdr
	ld b,a			; n times one byte
	ld a,(hl)
	inc hl
.r:	out (c),a
	djnz .r
	jr .tok
.next:	call .fill		; the rest of the block is padding
	jr .tok
.fill:	ld de,FILEBUF
	ld hl,FILEBUF_LEN
	call FILE_READ
	ld hl,FILEBUF
	ld c,V9_VRAM
	ret
.eof:	call FILE_CLOSE
	jp WORLD_P2

; ----------------------------------------------------------------------------
; LOAD_RAM - loads a file into RAM
;   input: DE = ASCIIZ name, HL = destination, BC = maximum size
;   output: HL = bytes read
; ----------------------------------------------------------------------------
LOAD_RAM:
	push bc
	push hl
	call FILE_OPEN
	pop de			; DE = destination
	pop hl			; HL = size
	call FILE_READ
	push hl
	call FILE_CLOSE
	pop hl
	ret

; ----------------------------------------------------------------------------
; FILE_ERROR - shows "Error reading <file>" and ends
; ----------------------------------------------------------------------------
FILE_ERROR:
	ld a,42h
	call V9_DISPLAY		; so the message shows on the MSX screen
	ld de,.msg
	call PRINT
	ld hl,(FILE_NAME)
.lp:	ld a,(hl)
	or a
	jr z,.end
	push hl
	ld e,a
	ld c,_CONOUT
	call BDOS
	pop hl
	inc hl
	jr .lp
.end:	ld b,1
	ld c,_TERM
	jp BDOS
.msg:	db 13,10,"Error reading $"

; FATAL - shows the text (DE, terminated by '$') and ends
FATAL:
	push de
	ld a,42h
	call V9_DISPLAY
	pop de
	call PRINT
	ld b,1
	ld c,_TERM
	jp BDOS

; ============================================================================
; Memory mapper (MSX-DOS2 support routines)
;   EXTBIO (0FFCAh) with D=4, E=2 returns the jump table in HL:
;     +00h ALL_SEG  (A=0 user segment, B=0 primary mapper -> A=segment)
;     +24h PUT_P2   (A=segment in page 2)
;     +27h GET_P2   (-> A=segment of page 2)
;   On exit the original page 2 segment is restored with PUT_P2.
; ============================================================================
EXTBIO:		equ 0FFCAh
HOKVLD:		equ 0FB20h

ALL_SEG:	jp 0		; patched in MAP_INIT
PUT_P2:		jp 0
GET_P2:		jp 0
ORIG_P2:	db 0
CUR_P2:		db 0FFh		; segment now in page 2 (FFh = unknown)

; MAP_ALLOC - allocates B segments and stores their numbers at (HL)
MAP_ALLOC:
	ld a,b
	or a
	ret z
.lp:	push bc
	push hl
	xor a
	ld b,a
	call ALL_SEG
	pop hl
	pop bc
	jr c,.err
	ld (hl),a
	inc hl
	djnz .lp
	ret
.err:	ld de,.msg
	jp FATAL
.msg:	db 13,10,"Not enough memory: a RAM mapper of 512 KB is needed.",13,10,"$"

; SEG_P2 - A = index in SEGTAB: puts that segment in page 2 (if not there)
SEG_P2:
	ld e,a
	ld d,0
	ld hl,SEGTAB
	add hl,de
	ld a,(hl)
	ld hl,CUR_P2
	cp (hl)
	ret z
	ld (hl),a
	jp PUT_P2

; WORLD_P2 - the world segment (level data, see eob.asm) in page 2: the
;   normal state while the game runs. Preserves all but AF.
WORLD_P2:
	ld a,(WORLD_SEG)
	; fall through
; PUT_SEG_P2 - A = segment number: in page 2 (if not there)
PUT_SEG_P2:
	push hl
	ld hl,CUR_P2
	cp (hl)
	pop hl
	ret z
	ld (CUR_P2),a
	jp PUT_P2

; SEG_RUN - A = segment, DE = file name (not in page 2): the file is loaded
;   at 8000h of that segment and run there; the page-2 segment comes back
;   (an overlay that runs once: the character generation)
SEG_RUN:
	ld hl,CUR_P2
	ld c,(hl)
	push bc
	call PUT_SEG_P2
	ld hl,8000h
	ld bc,4000h
	call LOAD_RAM
	call 8000h
	pop bc
	ld a,c
	jr PUT_SEG_P2

; SCRIPT_P2 - the script segment (level script, item names) in page 2
SCRIPT_P2:
	ld a,(SCRIPT_SEG)
	jr PUT_SEG_P2

WORLD_SEG:	db 0
SCRIPT_SEG:	db 0
UI_SEG:		db 0
MAGIC_SEG:	db 0
TEXT_SEG:	db 0

; RESTORE_P2 - puts the original DOS segment back in page 2
RESTORE_P2:
	ld a,(ORIG_P2)
	ld (CUR_P2),a
	jp PUT_P2

SEGTAB:		ds 32
