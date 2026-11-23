; ============================================================================
; Native V9938/58 SCREEN 5 automap. User-requested second video output.
; One mapper segment: code 8000..8FFF, twelve 32x32 snapshots 9000..BFFF.
; North stays at top. Reveal occupied cells and directly faced landmarks;
; walls use the neighbour face seen from that cell. No monster/item scan.
; Cell: bit7 seen, bit0..3 N/E/S/W wall, bit4..6 landmark colour (0 none).
; Calls run via AMCALL; WCALL is the only access to live world tables.
; CPU VRAM byte loops are spaced; no unpaced OUTI/OTIR burst is used.
; ============================================================================
 output "../build/AUTOMAP.OVL"
 org 8000h
AM_FRAME:
 di
 ld a,(AM_STARTED)
 or a
 call z,AM_INIT
 ld a,(CUR_LEVEL)
 cp 1
 ret c
 cp 13
 ret nc
 ld hl,AM_ACTUAL
 cp (hl)
 jr z,.actual
 ld (hl),a
 ld (AM_VIEW),a
.actual:
 call AM_SET_BASE              ; observation always updates the live floor
 call AM_OBSERVE
 call AM_KEYS
 ld a,(AM_VIEW)
 call AM_SET_BASE
 ld a,(AM_VIEW)
 ld hl,AM_LEVEL
 cp (hl)
 jr z,.same
 ld (hl),a
 call AM_REDRAW
 ld hl,(CUR_BLOCK)
 ld (AM_OLD),hl
 ld a,1
 ld (AM_CHANGED),a
.same:
 ld a,(AM_VIEW)
 ld hl,CUR_LEVEL
 cp (hl)
 ret nz                        ; no player arrow on an archived floor
.observed:
 ld hl,(AM_OLD)
 ld de,(CUR_BLOCK)
 or a
 sbc hl,de
 jr nz,.changed
 ld a,(CUR_DIR)
 ld hl,AM_DIR
 cp (hl)
 jr nz,.changed
 ld a,(AM_CHANGED)
 or a
 ret z
.changed:
 ld hl,(AM_OLD)
 call AM_DRAW
 ld hl,(CUR_BLOCK)
 ld (AM_OLD),hl
 call AM_DRAW
 ld a,(CUR_DIR)
 ld (AM_DIR),a
 jp AM_ARROW
AM_SET_BASE:
 dec a
 add a,a
 add a,a
 add a,90h
 ld (AM_BASE),a
 ret

; F2 previous, F3 next, F4 live floor. One change per physical press.
AM_KEYS:
 ld a,6
 call KEY_ROW
 cpl
 and 0C0h
 ld d,a
 ld a,7
 push de
 call KEY_ROW
 pop de
 cpl
 and 1
 or d
 ld hl,AM_KEY_LAST
 cp (hl)
 ld (hl),a
 ret z
 or a
 ret z
 bit 0,a
 jr nz,.live
 bit 6,a
 ld a,(AM_VIEW)
 jr z,.next
 dec a
 jr nz,.set
 ld a,12
 jr .set
.next:
 inc a
 cp 13
 jr c,.set
 ld a,1
 jr .set
.live:
 ld a,(CUR_LEVEL)
.set:
 ld (AM_VIEW),a
 ret

; Observe four neighbouring faces and landmarks under the party.
AM_OBSERVE:
 ld a,80h
 ld (AM_CELL),a
 xor a
 ld (AM_SIDE),a
.loop:
 ld a,(AM_SIDE)
 call WCALL
 dw BLOCK_AHEAD
 ld a,(AM_SIDE)
 xor 2
 call WCALL
 dw AM_WALL
 ; A visible wall stays a wall even when it is an undiscovered illusion.
 ; Passability alone must not expose an undiscovered illusion.
 ld a,c
 or a
 jr z,.open
 cp 3
 jr nz,.solid
 bit 0,b
 jr nz,.open
.solid:
 bit 0,b
 jr z,.closed
 ; Only an opening actually recorded here may expose an illusion.
 ; Merely reaching the neighbouring room by another route is insufficient.
 ld hl,(CUR_BLOCK)
 call AM_PTR
 bit 7,(hl)
 jr z,.closed
 ld b,(hl)
 ld a,(AM_SIDE)
 call AM_MASK
 and b
 jr z,.open
.closed:
 ld a,(AM_SIDE)
 ld e,a
 ld d,0
 ld hl,AM_BITS
 add hl,de
 ld a,(AM_CELL)
 or (hl)
 ld (AM_CELL),a
.open:
 ld a,(AM_SIDE)
 ld hl,(CUR_BLOCK)
 call WCALL
 dw AM_WALL
 ; Use the same visible wall ID/set as the dungeon renderer.
 call AM_CLASSIFY
 jr z,.next
.mark:
 ld a,(AM_CELL)
 and 8Fh
 or e
 ld (AM_CELL),a
.next:
 ld hl,AM_SIDE
 inc (hl)
 ld a,(hl)
 cp 4
 jr c,.loop
 ; The movement hook proves the traversed entrance, including illusions.
 ld a,(AM_CROSS_LEVEL)
 ld hl,CUR_LEVEL
 cp (hl)
 jr nz,.store
 ld hl,(AM_TO)
 ld de,(CUR_BLOCK)
 or a
 sbc hl,de
 jr nz,.store
 ld a,(AM_ENTRY)
 cpl
 ld b,a
 ld a,(AM_CELL)
 and b
 ld (AM_CELL),a
.store:
 ld hl,(CUR_BLOCK)
 call AM_PTR
 ld a,(AM_CELL)
 xor (hl)
 ld (AM_CHANGED),a
 ld a,(AM_CELL)
 ld (hl),a
 call AM_LANDMARK
 ret
AM_BITS: db 1,2,4,8

; HL=block -> HL=snapshot byte. Block index is the engine's y*32+x.
AM_PTR:
 ld a,(AM_BASE)
 add a,h
 ld h,a
 ret

; Render a cached cell in a fixed 6x6 square. HL=block (0..1023).
AM_DRAW:
 ld (AM_BLOCK),hl
 call AM_PTR
 ld a,(hl)
 bit 7,a
 ret z
 ld (AM_VALUE),a
 ld hl,AM_TILE
 ld (hl),11h
 ld de,AM_TILE+1
 ld bc,17
 ldir
 ld a,(AM_VALUE)
 bit 0,a
 jr z,.east
 ld hl,AM_TILE
 call .hline
.east:
 ld a,(AM_VALUE)
 bit 1,a
 jr z,.south
 ld hl,AM_TILE+2
 ld b,6
.el:
 ld a,(hl)
 and 0F0h
 or 2
 ld (hl),a
 inc hl
 inc hl
 inc hl
 djnz .el
.south:
 ld a,(AM_VALUE)
 bit 2,a
 jr z,.west
 ld hl,AM_TILE+15
 call .hline
.west:
 ld a,(AM_VALUE)
 bit 3,a
 jr z,.marker
 ld hl,AM_TILE
 ld b,6
.wl:
 ld a,(hl)
 and 0Fh
 or 20h
 ld (hl),a
 inc hl
 inc hl
 inc hl
 djnz .wl
.marker:
 ld a,(AM_VALUE)
 and 70h
 jr z,.send
 ld b,a
 rrca
 rrca
 rrca
 rrca
 or b
 ld (AM_TILE+7),a
 ld (AM_TILE+10),a
.send:
 jp AM_SEND
.hline:
 ld (hl),22h
 inc hl
 ld (hl),22h
 inc hl
 ld (hl),22h
 ret

; Replace centre with a directional arrow, keeping remembered walls.
AM_ARROW:
 ld a,(CUR_DIR)
 ld l,a
 ld h,0
 add hl,hl
 ld e,l
 ld d,h
 add hl,hl
 add hl,hl
 add hl,hl
 add hl,de ; direction*18
 ld de,AM_ARROWS
 add hl,de
 ld de,AM_TILE
 ld b,18
.lp:
 ld a,(de)
 or (hl)
 ld (de),a
 inc hl
 inc de
 djnz .lp
 jp AM_SEND
AM_ARROWS:
 db 0,0,0, 0,0F0h,0, 0Fh,0FFh,0, 0,0F0h,0, 0,0F0h,0, 0,0,0
 db 0,0,0, 0,0Fh,0, 0Fh,0FFh,0F0h, 0,0Fh,0, 0,0,0, 0,0,0
 db 0,0,0, 0,0F0h,0, 0,0F0h,0, 0Fh,0FFh,0, 0,0F0h,0, 0,0,0
 db 0,0,0, 0,0F0h,0, 0Fh,0FFh,0F0h, 0,0F0h,0, 0,0,0, 0,0,0

; A physical, collision-checked step, before any entry script/teleport.
; HL=destination. The resident caller preserves HL across this overlay.
AM_STEP:
 ld (AM_TO),hl
 ld de,(CUR_BLOCK)
 or a
 sbc hl,de
 ld a,h
 and 3
 ld h,a
 ld a,l
 ld c,1 ; east
 cp 1
 jr z,.dir
 ld c,3 ; west
 cp 0FFh
 jr z,.dir
 ld c,2 ; south
 cp 32
 jr z,.dir
 ld c,0 ; north
.dir:
 ld a,c
 call AM_MASK
 cpl
 ld b,a
 ld a,(CUR_LEVEL)
 ld (AM_CROSS_LEVEL),a
 dec a
 add a,a
 add a,a
 add a,90h
 ld (AM_BASE),a
 ld hl,(CUR_BLOCK)
 call AM_PTR
 ld a,(hl)
 and b
 ld (hl),a
 ld a,c
 xor 2
 call AM_MASK
 ld (AM_ENTRY),a
 ret
AM_MASK:
 push hl
 push de
 ld e,a
 ld d,0
 ld hl,AM_BITS
 add hl,de
 ld a,(hl)
 pop de
 pop hl
 ret

; Only the directly faced neighbour may reveal a landmark before entry.
; Use visual wall sets: a closed secret with a normal wall never gets one.
AM_LANDMARK:
 ld a,(CUR_DIR)
 call WCALL
 dw BLOCK_AHEAD
 push hl
 ld a,(CUR_DIR)
 xor 2
 call WCALL
 dw AM_WALL
 call AM_CLASSIFY
 jr nz,.mark
 call AM_PTR
 bit 7,(hl)
 jr z,.none
 ld e,0                        ; an observed closed pit/removed portal clears
 jr .value
.mark:
 call AM_PTR
.value:
 ld a,(hl)
 and 8Fh
 or 80h
 or e
 cp (hl)
 jr z,.none
 ld (hl),a
 pop hl
 ld a,(AM_VIEW)
 ld de,CUR_LEVEL
 ld b,a
 ld a,(de)
 cp b
 ret nz
 jp AM_DRAW
.none:
 pop hl
 ret

 ; Wall 27 is the original visible open floor pit; 26 is a ceiling
; opening and 28 a closed cover. Wall 52 owns DRAW_TELEPORT's sparkles.
AM_CLASSIFY:
 cp TELE_WALL
 ld e,70h
 jr z,.yes
 cp 27
 jr nz,.sets
 ld a,c
 or a
 ld e,60h
 jr z,.yes
.sets:
 ld a,c
 cp 3
 ld e,30h
 jr z,.yes
 cp 4
 ld e,40h
 jr z,.yes
 cp 5
 ld e,50h
 jr z,.yes
 xor a
 ret
.yes:
 or 1
 ret

; Convert block coordinate to byte address: (10+6*y)*128+4+3*x.
AM_SEND:
 ld hl,(AM_BLOCK)
 ld a,l
 and 31
 ld e,a
 add a,a
 add a,e
 add a,4
 ld e,a
 ld d,0
 srl h
 rr l
 srl h
 rr l
 srl h
 rr l
 srl h
 rr l
 srl h
 rr l
 ld a,l
 add a,a
 add a,l
 add a,a
 add a,10
 ld l,0
 ld h,a
 srl h
 rr l
 add hl,de
 ld de,AM_TILE
 ; Fall through: a cell or legend symbol is six rows of three packed bytes.
AM_BLIT:
 ld b,6
.row:
 push bc
 push hl
 call AM_ADDR
 ld b,3
.bytes:
 ld a,(de)
 out (98h),a
 inc de
 djnz .bytes
 pop hl
 ld bc,128
 add hl,bc
 pop bc
 djnz .row
 ret

; Native VDP address (0..3FFF) for CPU writes. Upper VRAM bits in R14.
AM_ADDR:
 ld a,h
 rlca
 rlca
 and 3
 out (99h),a
 ld a,8Eh
 out (99h),a
 ld a,l
 out (99h),a
 ld a,h
 and 3Fh
 or 40h
 out (99h),a
 ret

; Native VDP register write: A=value, C=register. Interrupts disabled.
AM_REG:
 out (99h),a
 ld a,c
 or 80h
 out (99h),a
 ret

AM_INIT:
 ; Do not touch the V9990. Disable native IRQs/sprites and use 212 lines.
 in a,(99h)
 ld hl,AM_REGS
 ld b,10
.regs:
 ld c,(hl)
 inc hl
 ld a,(hl)
 inc hl
 call AM_REG
 djnz .regs
 xor a
 ld c,16
 call AM_REG
 ld hl,AM_PAL
 ld b,32
.pal:
 ld a,(hl)
 out (9Ah),a
 inc hl
 djnz .pal
 ld a,1
 ld (AM_STARTED),a
 xor a
 ld (0F3DBh),a ; no BIOS key click
 ret
AM_REGS:
 db 1,0, 0,6, 2,1Fh, 7,0, 8,10, 9,80h, 18,0, 23,0, 25,0, 27,0
AM_PAL:
 db 00h,0, 12h,1, 66h,6, 70h,4, 07h,7, 70h,7, 70h,0, 77h,0
 db 00h,0, 00h,0, 00h,0, 00h,0, 00h,0, 00h,0, 00h,0, 77h,7

; Floor changes redraw behind a disabled native display, then publish at
; fresh native VBlank. In-floor updates write only the old and current cells.
AM_REDRAW:
 ld a,0FFh
 ld (AM_DIR),a
 xor a
 ld c,1
 call AM_REG
 ld hl,0
 call AM_ADDR
 ld de,128*212
.clear:
 xor a
 out (98h),a
 dec de
 ld a,d
 or e
 jr nz,.clear
 ld hl,0
.all:
 push hl
 call AM_DRAW
 pop hl
 inc hl
 ld a,h
 cp 4
 jr c,.all
 ; Header and compact legend: colour squares match the landmarks.
 ld hl,AM_TITLE
 ld de,4 ; byte x=4, y=0
 call AM_TEXT
 ld a,(AM_VIEW)
 ld b,'0'
 cp 10
 jr c,.units
 sub 10
 inc b
.units:
 add a,'0'
 ld (AM_NUM+1),a
 ld a,b
 ld (AM_NUM),a
 ld hl,AM_NUM
 ld de,46
 call AM_TEXT
 ld hl,AM_NORTH
 ld de,104
 call AM_TEXT
 ld a,3
 ld (AM_INK),a
 ld hl,AM_DOOR_TEXT
 ld de,128*30+104
 call AM_TEXT
 ld a,4
 ld (AM_INK),a
 ld hl,AM_UP_TEXT
 ld de,128*42+104
 call AM_TEXT
 ld a,5
 ld (AM_INK),a
 ld hl,AM_DOWN_TEXT
 ld de,128*54+104
 call AM_TEXT
 ld a,6
 ld (AM_INK),a
 ld hl,AM_PIT_TEXT
 ld de,128*66+104
 call AM_TEXT
 ld a,7
 ld (AM_INK),a
 ld hl,AM_PORTAL_TEXT
 ld de,128*78+104
 call AM_TEXT
 ld a,15
 ld (AM_INK),a
 ld hl,AM_KEYS_TEXT
 ld de,128*102+104
 call AM_TEXT
 ld a,15
 ld (AM_INK),a
 ; The footer has room for whole labels in both languages. Keep it below
 ; the map (last map row is 201) rather than wrapping in the narrow sidebar.
 ld hl,128*204+4
 ld de,AM_UNKNOWN_ICON
 call AM_BLIT
 ld hl,AM_UNKNOWN_TEXT
 ld de,128*204+9
 call AM_TEXT
 ld hl,128*204+56
 ld de,AM_ARROWS ; same north arrow as the player, on the black footer
 call AM_BLIT
 ld hl,AM_POSITION_TEXT
 ld de,128*204+61
 call AM_TEXT
 ld a,2
 ld c,15
 call AM_REG
.endblank:
 in a,(99h)
 bit 6,a
 jr nz,.endblank
.startblank:
 in a,(99h)
 bit 6,a
 jr z,.startblank
 xor a
 ld c,15
 call AM_REG
 ld a,40h
 ld c,1
 jp AM_REG
 if LANG_C2 = 83
AM_TITLE: db "MAPA / PLANTA",0
AM_DOOR_TEXT: db "PUERTA",0
AM_UP_TEXT: db "SUBE",0
AM_DOWN_TEXT: db "BAJA",0
AM_PIT_TEXT: db "HUECO",0
AM_PORTAL_TEXT: db "PORTAL",0
AM_KEYS_TEXT: db "F2 -",10,"F3 +",10,"F4 AQUI",0
AM_UNKNOWN_TEXT: db "SIN EXPLORAR",0
AM_POSITION_TEXT: db "TU POSICION",0
 else
AM_TITLE: db "MAP / LEVEL",0
AM_DOOR_TEXT: db "DOOR",0
AM_UP_TEXT: db "UP",0
AM_DOWN_TEXT: db "DOWN",0
AM_PIT_TEXT: db "PIT",0
AM_PORTAL_TEXT: db "PORTAL",0
AM_KEYS_TEXT: db "F2 -",10,"F3 +",10,"F4 HERE",0
AM_UNKNOWN_TEXT: db "UNEXPLORED",0
AM_POSITION_TEXT: db "YOUR POSITION",0
 endif
AM_NUM: db "00",0
AM_NORTH: db "N ^",0
; Black interior with a grey outline, so the unexplored sample stays visible.
AM_UNKNOWN_ICON: db 22h,22h,22h, 20h,0,2, 20h,0,2, 20h,0,2, 20h,0,2, 22h,22h,22h

; FONT6 text to SC5, HL=ASCIIZ, DE=VRAM byte address. LF advances 12 rows.
AM_TEXT:
 ld (AM_TEXT_XY),de
 ld (AM_LINE_XY),de
.next:
 ld a,(hl)
 inc hl
 or a
 ret z
 cp 10
 jr nz,.glyph
 push hl
 ld hl,(AM_LINE_XY)
 ld de,128*12
 add hl,de
 ld (AM_TEXT_XY),hl
 ld (AM_LINE_XY),hl
 pop hl
 jr .next
.glyph:
 push hl
 sub 32
 ld l,a
 ld h,0
 ld d,h
 ld e,l
 add hl,hl
 add hl,de
 add hl,hl
 ld de,FONT6
 add hl,de
 ex de,hl
 ld hl,(AM_TEXT_XY)
 ld b,6
.row:
 push bc
 push hl
 call AM_ADDR
 ld a,(de)
 inc de
 ld c,a
 ld b,3
.pixel:
 xor a
 sla c
 jr nc,.p2
 ld a,(AM_INK)
 rlca
 rlca
 rlca
 rlca
.p2:
 sla c
 jr nc,.pout
 push hl
 ld hl,AM_INK
 or (hl)
 pop hl
.pout:
 out (98h),a
 djnz .pixel
 pop hl
 ld bc,128
 add hl,bc
 pop bc
 djnz .row
 ld hl,(AM_TEXT_XY)
 inc hl
 inc hl
 inc hl
 ld (AM_TEXT_XY),hl
 pop hl
 jr .next

; Append versioned exploration to the native save, keeping its prefix intact.
; Old saves with EOF here start with no explored cells, never garbage.
AM_SAVE:
 or a
 ret nz ; preserve failure of the preceding native write
 ld de,AM_HEADER
 ld hl,4
 call FILE_WRITE
 ret nz
 ld de,AM_DATA
 ld hl,3000h
 jp FILE_WRITE
AM_LOAD:
 ld de,AM_READHDR
 ld hl,4
 call FILE_READ
 ld a,h
 or a
 jr nz,.clear
 ld a,l
 cp 4
 jr nz,.clear
 ld hl,AM_HEADER
 ld de,AM_READHDR
 ld b,4
.check:
 ld a,(de)
 cp (hl)
 jr nz,.clear
 inc hl
 inc de
 djnz .check
 ld de,AM_DATA
 ld hl,3000h
 call FILE_READ
 ld de,3000h
 or a
 sbc hl,de
 jr z,.done
.clear:
 ld hl,AM_DATA
 ld de,AM_DATA+1
 ld bc,2FFFh
 ld (hl),0
 ldir
.done:
 xor a
 ld (AM_LEVEL),a
 ld (AM_ACTUAL),a
 ld (AM_CROSS_LEVEL),a
 ret
AM_HEADER: db "AM01"
AM_READHDR: ds 4

AM_STOP:
 ld a,(AM_STARTED)
 or a
 ret z
 ; Restore the native DOS text screen through the main BIOS interslot call.
 xor a
 ld ix,005Fh ; CHGMOD, screen 0
 ld iy,(0FCC0h)
 call 001Ch
 di
 xor a
 ld (0F3DBh),a
 ret
; SV_SYNC - the live state into SV_STATE (before SAVE_GAME)
SV_SYNC:
	ld a,(CUR_LEVEL)
	ld (SV_LEVEL),a
	ld hl,(CUR_BLOCK)
	ld (SV_BLOCK),hl
	ld a,(CUR_DIR)
	ld (SV_DIR),a
	ld hl,(HAND)
	ld (SV_HAND),hl
	ld hl,(TEMP_FLAGS)
	ld (SV_TEMPF),hl
	ld hl,(PARTY_EFFECTS)
	ld (SV_EFFECTS),hl
	ld a,(MAGIC_ACTIVE)
	ld (SV_MAGIC),a
	ret
AM_INK: db 15
AM_TO: dw 0FFFFh
AM_CROSS_LEVEL: db 0
AM_ENTRY: db 0
AM_STARTED: db 0
AM_ACTUAL: db 0
AM_VIEW: db 1
AM_KEY_LAST: db 0
AM_LEVEL: db 0
AM_BASE: db 90h
AM_OLD: dw 0
AM_BLOCK: dw 0
AM_VALUE: db 0
AM_CELL: db 0
AM_SIDE: db 0
AM_DIR: db 0FFh
AM_CHANGED: db 0
AM_TILE: ds 18
AM_TEXT_XY: dw 0
AM_LINE_XY: dw 0
 include "panel.asm"
AM_CODE_END:
 assert $ <= 9000h
 ds 9000h-$
AM_DATA: ds 3000h
