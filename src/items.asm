; ============================================================================
; items.asm - The item table, the item queues of the blocks and the floor
;             items of the 3D view (items_eob.cpp: setItemPosition,
;             getQueuedItem, countQueuedItems; sprites_eob.cpp: drawBlockItems)
; Assembler: Sjasm 0.42c
;
; ITEMS holds ITEM_MAX records of I_SIZE bytes (EoBItem, see
; tools/conv_global.py). The items lying in a block form a circular list
; through I_NEXT / I_PREV; DRAWOBJ (one u16 per block) points to the newest
; one, whose I_NEXT is the oldest. Positions: 0-3 the quarters of the block,
; 4-7 flying, 8 in a wall niche.
; ============================================================================

; ITEM_PTR - HL = item number -> HL = its record. Preserves BC, DE.
ITEM_PTR:
	push de
	add hl,hl
	ld e,l
	ld d,h			; 2n
	add hl,hl
	add hl,hl
	add hl,hl		; 16n
	or a
	sbc hl,de		; 14n
	ld de,ITEMS
	add hl,de
	pop de
	ret

; ITEM_IX - HL = item number -> IX = its record. Preserves BC, DE, HL.
ITEM_IX:
	push hl
	call ITEM_PTR
	push hl
	pop ix
	pop hl
	ret

; DRAWOBJ_PTR - HL = block -> HL = its queue head (DRAWOBJ + block * 2)
DRAWOBJ_PTR:
	ld a,h
	and 3
	ld h,a
	add hl,hl
	push de
	ld de,DRAWOBJ
	add hl,de
	pop de
	ret

; ----------------------------------------------------------------------------
; ITEMS_LINK - builds the queues of the current level (addLevelItems)
; ----------------------------------------------------------------------------
ITEMS_LINK:
	ld hl,DRAWOBJ
	ld de,DRAWOBJ+1
	ld bc,2047
	ld (hl),0
	ldir
	ld bc,0
.lp:	ld l,c
	ld h,b
	call ITEM_IX
	ld a,(CUR_LEVEL)
	cp (ix+I_LEVEL)
	jr nz,.next
	ld e,(ix+I_BLOCK)
	ld d,(ix+I_BLOCK+1)
	ld a,d
	or a
	jp m,.next		; block < 0
	or e
	jr z,.next		; block 0
	push bc
	ex de,hl
	push hl
	call DRAWOBJ_PTR
	pop de
	ld a,(ix+I_POS)
	call SET_ITEM_POS
	pop bc
.next:	inc bc
	ld a,b
	cp ITEM_MAX>>8
	jr nz,.lp
	ld a,c
	cp ITEM_MAX&0FFh
	jr nz,.lp
	ret

; ----------------------------------------------------------------------------
; SET_ITEM_POS - puts an item first in a queue (setItemPosition)
;   HL = queue head address, DE = block (negative: not on the map),
;   BC = item, A = position. Preserves BC.
; ----------------------------------------------------------------------------
SET_ITEM_POS:
	ld (IQ_HEAD),hl
	ld (IQ_POS),a
	ld a,b
	or c
	ret z
	ld l,c
	ld h,b
	call ITEM_IX		; IX = the item
	ld a,(IQ_POS)
	ld (ix+I_POS),a
	ld (ix+I_BLOCK),e
	ld (ix+I_BLOCK+1),d
	ld a,d
	rla
	ld a,0FFh
	jr c,.lv
	ld a,(CUR_LEVEL)
.lv:	ld (ix+I_LEVEL),a
	ld hl,(IQ_HEAD)
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld a,d
	or e
	jr nz,.insert
	; empty queue: the item alone, linked to itself
	ld (hl),b
	dec hl
	ld (hl),c
	ld (ix+I_NEXT),c
	ld (ix+I_NEXT+1),b
	ld (ix+I_PREV),c
	ld (ix+I_PREV+1),b
	ret
.insert:
	; Q = head, QN = Q.next (the oldest):
	; item.prev = QN.prev, item.next = Q.next, then QN.prev = Q.next = head = item
	ex de,hl
	call ITEM_PTR
	push hl
	pop iy			; IY = Q
	ld l,(iy+I_NEXT)
	ld h,(iy+I_NEXT+1)
	ld (ix+I_NEXT),l
	ld (ix+I_NEXT+1),h
	call ITEM_PTR
	ld de,I_PREV
	add hl,de		; HL = &QN.prev
	ld a,(hl)
	ld (ix+I_PREV),a
	ld (hl),c
	inc hl
	ld a,(hl)
	ld (ix+I_PREV+1),a
	ld (hl),b
	ld (iy+I_NEXT),c
	ld (iy+I_NEXT+1),b
	ld hl,(IQ_HEAD)
	ld (hl),c
	inc hl
	ld (hl),b
	ret

; ----------------------------------------------------------------------------
; GET_QUEUED_ITEM - takes an item out of a queue (getQueuedItem)
;   HL = queue head address, DE = item number (FFFFh: the first one found
;   at position A, walking from the newest through I_PREV)
;   -> HL = the item (0 = none); it is left with block 0, level 0
; ----------------------------------------------------------------------------
GET_QUEUED_ITEM:
	ld (IQ_HEAD),hl
	ld (IQ_POS),a
	ld (IQ_ID),de
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	ret z
	ld (IQ_FIRST),hl
.lp:	ld (IQ_CUR),hl
	call ITEM_IX
	; match: id == item, or id == -1 and pos == wanted
	ld de,(IQ_ID)
	ld a,e
	cp l
	jr nz,.byp
	ld a,d
	cp h
	jr z,.found
.byp:	ld a,d
	and e
	inc a
	jr nz,.no		; looking for a given number
	ld a,(IQ_POS)
	cp (ix+I_POS)
	jr z,.found
.no:	ld l,(ix+I_PREV)
	ld h,(ix+I_PREV+1)
	ld de,(IQ_FIRST)
	or a
	sbc hl,de
	add hl,de
	jr nz,.lp
	ld hl,0
	ret
.found:	; unlink: items[next].prev = prev, items[prev].next = next
	ld l,(ix+I_NEXT)
	ld h,(ix+I_NEXT+1)
	ld c,(ix+I_PREV)
	ld b,(ix+I_PREV+1)
	push hl
	call ITEM_PTR
	ld de,I_PREV
	add hl,de
	ld (hl),c
	inc hl
	ld (hl),b
	ld l,c
	ld h,b
	call ITEM_PTR
	ld de,I_NEXT
	add hl,de
	pop de			; DE = next
	ld (hl),e
	inc hl
	ld (hl),d
	xor a
	ld (ix+I_NEXT),a
	ld (ix+I_NEXT+1),a
	ld (ix+I_PREV),a
	ld (ix+I_PREV+1),a
	ld (ix+I_BLOCK),a
	ld (ix+I_BLOCK+1),a
	ld (ix+I_LEVEL),a
	; the head moves to prev; if prev was the item itself the queue is empty
	ld hl,(IQ_HEAD)
	ld de,(IQ_CUR)
	ld a,(hl)
	cp e
	jr nz,.ret
	inc hl
	ld a,(hl)
	dec hl
	cp d
	jr nz,.ret
	ld a,c
	cp e
	jr nz,.newh
	ld a,b
	cp d
	jr nz,.newh
	ld bc,0
.newh:	ld (hl),c
	inc hl
	ld (hl),b
.ret:	ld hl,(IQ_CUR)
	ret

; ----------------------------------------------------------------------------
; DRAW_BLOCK_ITEMS - A = visible block index: the items lying in it
;   (drawBlockItems). Called from the shape pass with the clip window of
;   the block already set (SHAPE_DIM).
; ----------------------------------------------------------------------------
DRAW_BLOCK_ITEMS:
	ld (IT_INDEX),a
	add a,a
	ld l,a
	ld h,0
	ld de,VISBLK
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ex de,hl
	call DRAWOBJ_PTR
	ld a,(hl)
	inc hl
	ld h,(hl)
	ld l,a
	or h
	ret z			; nothing on the floor
	ld (IT_HEAD),hl
	; the wall facing us: a wall without the niche flag hides the items
	ld a,(IT_INDEX)
	ld e,a
	ld d,0
	ld hl,VISWALL
	add hl,de
	ld l,(hl)
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld a,(hl)
	ld b,a
	ld a,(IT_INDEX)
	cp 16
	jr nz,.flg
	ld b,80h		; the party block
.flg:	ld a,b
	ld (IT_FLG),a
	ld h,(LEVELDAT+D_WVMP)>>8
	ld a,(hl)
	or a
	jr z,.vis
	bit 7,b
	ret z
.vis:	; distance class
	ld a,(IT_INDEX)
	ld e,a
	ld d,0
	ld hl,DSC_DIMMAP
	add hl,de
	ld a,(hl)
	ld (IT_DIM),a
	; from the oldest item (head.next) round the circle
	ld hl,(IT_HEAD)
	call ITEM_IX
	ld l,(ix+I_NEXT)
	ld h,(ix+I_NEXT+1)
	ld (IT_FIRST),hl
.lp:	ld (IT_CUR),hl
	call ITEM_IX
	call ITEM_DRAW1
	ld hl,(IT_CUR)
	call ITEM_IX
	ld l,(ix+I_NEXT)
	ld h,(ix+I_NEXT+1)
	ld de,(IT_FIRST)
	or a
	sbc hl,de
	add hl,de
	jr nz,.lp
	ret

; ITEM_DRAW1 - IX = item record, (IT_CUR) = its number
ITEM_DRAW1:
	ld a,(ix+I_POS)
	cp 8
	jr z,.niche
	cp 4
	ret nc			; flying
	; ps = DSC_ITEMPOSINDEX[(dir << 2) + pos]
	ld c,a
	ld a,(CUR_DIR)
	add a,a
	add a,a
	add a,c
	ld e,a
	ld d,0
	ld hl,DSC_ITEMPOSINDEX
	add hl,de
	ld a,(hl)
	ld (IT_PS),a
	; (x, y) = DSC_SHAPECOORDS[index * 5 + ps] + (88, 124)
	ld c,a
	ld a,(IT_INDEX)
	ld b,a
	add a,a
	add a,a
	add a,b
	add a,c
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	ld de,DSC_SHAPECOORDS
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	inc hl
	push hl
	ld hl,88
	add hl,de
	ld (IT_X),hl
	pop hl
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld hl,124
	add hl,de
	ld (IT_Y),hl
	jr .scale
.niche:	; x = DSC_ITEMSHPX[index], y by distance, size of position 0
	ld a,(IT_INDEX)
	add a,a
	ld e,a
	ld d,0
	ld hl,DSC_ITEMSHPX
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)
	ld (IT_X),de
	ld a,(IT_DIM)
	ld e,a
	ld d,0
	ld hl,NICHE_Y
	add hl,de
	ld l,(hl)
	ld h,0
	ld (IT_Y),hl
	xor a
	ld (IT_PS),a
.scale:	; size = DSC_ITEMSCALE[(dim << 2) + ps], negative: not drawn
	ld a,(IT_DIM)
	add a,a
	add a,a
	ld hl,IT_PS
	add a,(hl)
	ld e,a
	ld d,0
	ld hl,DSC_ITEMSCALE
	add hl,de
	ld a,(hl)
	or a
	ret m
	ld (IT_SCALE),a
	; a door ahead clips the far items with the window of another block
	xor a
	ld (IT_TILE2),a
	ld a,(IT_FLG)
	and 8
	jr z,.notile
	ld a,(IT_PS)
	cp 2
	jr nc,.notile
	ld a,(IT_SCALE)
	or a
	jr z,.notile
	ld hl,(IT_Y)
	ld de,-4
	add hl,de
	ld (IT_Y),hl
	ld a,(IT_INDEX)
	ld e,a
	ld d,0
	ld hl,DSC_ITEMTILE
	add hl,de
	ld a,(hl)
	cp 255
	jr z,.notile
	ld (IT_TILE2),a		; non zero: restore the window afterwards
	push ix
	call SHAPE_DIM
	pop ix
.notile:
	; shape: ITEM_SHPMAP[icon]: < 14 large n, 15.. small (n - 1), else none
	ld e,(ix+I_ICON)
	ld d,0
	ld hl,ITEM_SHPMAP
	add hl,de
	ld a,(hl)
	cp ITEM_LARGE_N
	jr c,.shp
	jp z,.done
	cp ITEM_LARGE_N+1+ITEM_SMALL_N
	jp nc,.done
	dec a
.shp:	; entry = n * 4 + size
	add a,a
	add a,a
	ld hl,IT_SCALE
	add a,(hl)
	ld l,a
	ld h,0
	push hl
	ld de,SHP_ITEM0_0
	add hl,de
	ld (IT_SID),hl
	pop hl
	add hl,hl
	add hl,hl
	ld de,ITEMSHP
	add hl,de		; dx, dy, w / 2, h
	; x += (FIN[item & 7] << 1) - w / 2 + dx
	ld a,(IT_CUR)
	and 7
	ld e,a
	ld d,0
	push hl
	ld hl,ITEM_FIN
	add hl,de
	ld a,(hl)
	pop hl
	add a,a
	ld e,a
	rla
	sbc a,a
	ld d,a			; DE = fin * 2
	push hl
	ld hl,(IT_X)
	res 0,l			; the original aligns the shape (x &= ~1)
	add hl,de
	ex de,hl
	pop hl
	ld a,(hl)		; dx
	inc hl
	ld c,(hl)		; dy
	inc hl
	push bc
	add a,e
	ld e,a
	jr nc,.c1
	inc d
.c1:	ld a,e
	sub (hl)		; - w / 2
	ld e,a
	jr nc,.c2
	dec d
.c2:	inc hl
	ld b,(hl)		; h
	; y = y - h + dy (+ FIN[(item >> 1) & 7] when on the floor)
	ld a,(IT_Y)
	sub b
	pop bc
	add a,c
	ld c,a
	ld a,(ix+I_POS)
	cp 8
	jr z,.ny
	ld a,(IT_CUR)
	rrca
	and 7
	push de
	ld e,a
	ld d,0
	ld hl,ITEM_FIN
	add hl,de
	ld a,c
	add a,(hl)
	ld c,a
	pop de
.ny:	ld b,0
	ld hl,(IT_SID)
	push ix
	call DRAW_SHAPE
	pop ix
.done:	ld a,(IT_TILE2)
	or a
	ret z
	ld a,(IT_INDEX)
	push ix
	call SHAPE_DIM
	pop ix
	ret

ITEM_FIN:	db 0, -2, 1, -1, 2, 0, 1, -1
NICHE_Y:	db 25h, 31h, 38h, 0

IQ_HEAD:	dw 0
IQ_POS:		db 0
IQ_ID:		dw 0
IQ_FIRST:	dw 0
IQ_CUR:		dw 0
IT_INDEX:	db 0
IT_HEAD:	dw 0
IT_FIRST:	dw 0
IT_CUR:		dw 0
IT_FLG:		db 0
IT_DIM:		db 0
IT_PS:		db 0
IT_SCALE:	db 0
IT_TILE2:	db 0
IT_X:		dw 0
IT_Y:		dw 0
IT_SID:		dw 0

; ============================================================================
; The item in hand (the mouse pointer shows it)
; ============================================================================

; SET_HAND_ITEM - HL = item (0 = none); a new item prints its name
;   (setHandItem)
SET_HAND_ITEM:
	ld (HAND),hl
	ld a,h
	or l
	ret z
	call ITEM_NAME
	ld hl,STR_TAKEN
	call TEXT_APPEND
	ld hl,TEXTBUF
	jp MSG_PRINT

; ITEM_NAME - HL = item -> TEXTBUF = its name. Scrolls reveal their spell
; on pickup, without casting, identification flags or changes to the item.
ITEM_NAME:
	call XCALL
	dw FX_ITEM_NAME
	ret

; NAME_COPY - A = name number -> TEXTBUF (ITEMNAME.DAT, script segment)
NAME_COPY:
	ld c,a
	ld a,(CUR_P2)
	push af
	call SCRIPT_P2
	ld hl,ITEMNAMES
.skip:	ld a,c
	or a
	jr z,.copy
.s1:	ld a,(hl)
	inc hl
	or a
	jr nz,.s1
	dec c
	jr .skip
.copy:	ld de,TEXTBUF
	ld b,TEXTBUF_LEN-1
.c1:	ld a,(hl)
	ld (de),a
	or a
	jr z,.end
	inc hl
	inc de
	djnz .c1
	xor a
	ld (de),a
.end:	pop af
	jp PUT_SEG_P2

; TEXT_APPEND - HL = text: added at the end of TEXTBUF
TEXT_APPEND:
	ex de,hl
	ld hl,TEXTBUF
	ld b,TEXTBUF_LEN-1
.end:	ld a,(hl)
	or a
	jr z,.cp
	inc hl
	djnz .end
	ret
.cp:	ld a,(de)
	ld (hl),a
	or a
	ret z
	inc de
	inc hl
	djnz .cp
	ld (hl),0
	ret

TEXTBUF_LEN:	equ 96
TEXTBUF:	ds TEXTBUF_LEN
HAND:		dw 0

; SLOT_PTR - IY = character, A = inventory slot -> HL = its address
SLOT_PTR:
	add a,a
	add a,P_INV
	ld e,a
	ld d,0
	push iy
	pop hl
	add hl,de
	ret

; ----------------------------------------------------------------------------
; CLK_DROP_PICKUP - A = 0..3, the quarter clicked (clickedSceneDropPickupItem):
;   0, 1 the near half of the party block, 2, 3 the block ahead
; ----------------------------------------------------------------------------
CLK_DROP_PICKUP:
	ld (DP_ARG),a
	ld hl,(CUR_BLOCK)
	cp 2
	jr c,.blk
	ld a,(CUR_DIR)
	call BLOCK_AHEAD
	; only through an open or passable wall (flags 0Bh)
	push hl
	ld a,(SIDE_D)
	call BLOCK_WALL
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	ld a,(hl)
	pop hl
	and 0Bh
	ld a,1
	ret z
.blk:	ld (DP_BLOCK),hl
	ld a,(CUR_DIR)
	add a,a
	add a,a
	ld hl,DP_ARG
	add a,(hl)
	ld e,a
	ld d,0
	ld hl,DROP_DIR
	add hl,de
	ld a,(hl)
	ld (DP_POS),a
	ld hl,(HAND)
	ld a,h
	or l
	jr z,.pick
	; drop the hand item there
	ld c,l
	ld b,h
	ld hl,(DP_BLOCK)
	ld e,l
	ld d,h
	call DRAWOBJ_PTR
	ld a,(DP_POS)
	call SET_ITEM_POS
	ld hl,0
	call SET_HAND_ITEM
	ld hl,(DP_BLOCK)
	ld a,4
	call RUN_LEVEL_SCRIPT
	jr .upd
.pick:	ld hl,(DP_BLOCK)
	call DRAWOBJ_PTR
	ld de,0FFFFh
	ld a,(DP_POS)
	call GET_QUEUED_ITEM
	ld a,h
	or l
	ld a,1
	ret z
	call SET_HAND_ITEM
	ld hl,(DP_BLOCK)
	ld a,8
	call RUN_LEVEL_SCRIPT
.upd:	ld a,1
	ld (SCENE_DIRTY),a
	ret

DROP_DIR:	db 0,1,2,3, 1,3,0,2, 3,2,1,0, 2,0,3,1
DP_ARG:		db 0
DP_POS:		db 0
DP_BLOCK:	dw 0

; CLASS_FLAG - IY = character -> A = its class flags
CLASS_FLAG:
	ld e,(iy+P_CLASS)
	ld d,0
	ld hl,CLASS_FLAGS
	add hl,de
	ld a,(hl)
	ret

; ITEM_USABLE - IY = character, HL = item -> NZ if its class may use it
;   (item 0: yes)
ITEM_USABLE:
	ld a,h
	or l
	jr z,.yes
	call ITEM_IX
	ld a,(ix+I_TYPE)
	call ITEMTYPE_PTR
	ld de,IT_CLASSES
	add hl,de
	push hl
	call CLASS_FLAG
	pop hl
	and (hl)
	ret
.yes:	or 1
	ret

; ----------------------------------------------------------------------------
; CLK_SCENE_SPECIAL - a click on the wall ahead (specialWallAction with the
;   mouse flag 40h): door switches, niches, doors nobody can force
; ----------------------------------------------------------------------------
CLK_SCENE_SPECIAL:
	ld a,(CUR_DIR)
	call BLOCK_AHEAD
	ld a,(CUR_DIR)
	ld c,40h
	; fall through

; SPECIAL_WALL - HL = block, A = direction towards its wall, C = 40h (the
;   mouse) or 10h (a flying object) (specialWallAction) -> A = 0 if nothing
SPECIAL_WALL:
	ld (SPC_BLOCK),hl
	xor 2
	ld (SPC_DIR),a
	ld a,c
	ld (SPC_FLAG),a
	ld a,(SPC_DIR)
	call BLOCK_WALL
	ld (SPC_WALL),a
	ld h,(LEVELDAT+D_WSPECIAL)>>8
	ld l,a
	ld a,(hl)
	or a
	ret z
	ld (SPC_TYPE),a
	; the trigger of the block must take this kind of event
	ld hl,(SPC_BLOCK)
	call TRIG_FLAGS
	and 0F8h
	rrca
	rrca
	rrca
	or 0E0h
	ld hl,SPC_FLAG
	and (hl)
	ret z
	ld a,(SPC_TYPE)
	call SPC_ACTION
	push af
	ld a,1
	ld (SCENE_DIRTY),a
	pop af
	ret

SPC_ACTION:
	cp 1
	jp z,SPC_DOOR_SWITCH
	cp 6
	jp z,SPC_DOOR_NOPRY
	cp 10
	jp z,SPC_NICHE
	cp 5
	jp z,SPC_DOOR_PRY
	cp 7
	jr z,SPC_SCRIPT
	cp 9
	jr z,SPC_SCRIPT
	; 2, 8: a wall shape; 3, 4: a lever (up / down): the click must hit it
	cp 11
	jr nc,SPC_NO
	ld a,(SPC_WALL)
	call CLICKED_SHAPE
	ret z
	ld a,(SPC_TYPE)
	cp 3
	jr z,.on
	cp 4
	jr nz,SPC_SCRIPT
	ld c,-1
	jr .lever
.on:	ld c,1
.lever:	ld a,29			; the lever goes down (29) / up (30)
	bit 7,c
	jr nz,.ls
	inc a
.ls:	call SFX_PLAY
	ld a,(SPC_WALL)
	add a,c
	ld c,a
	ld hl,(SPC_BLOCK)
	ld a,(SPC_DIR)
	call W_SET_WALL
SPC_SCRIPT:
	ld hl,(SPC_BLOCK)
	ld a,(SPC_FLAG)
	call RUN_LEVEL_SCRIPT
	ld a,1
	ret
SPC_NO:	xor a
	ret

; CLICKED_SHAPE - A = wall type -> NZ if the mouse is on one of its
;   decorations, as drawn on the wall right ahead (clickedShape: slot 1)
CLICKED_SHAPE:
	ld c,a
	ld a,(SPC_FLAG)		; only the mouse needs to hit it
	cp 40h
	jr z,.mouse
	or a
	ret
.mouse:	ld a,c
	ld h,(LEVELDAT+D_WSHAPE)>>8
	ld l,a
	ld a,(hl)
	cp 0FFh
	jp z,.no
.lp:	or a
	ret z
	dec a
	ld l,a
	ld h,0
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl
	add hl,hl		; *64
	ld de,LEVELDAT+D_DECOS
	add hl,de
	push hl
	pop iy
	ld l,(iy+10)		; slot 1: shape, x, y
	ld h,(iy+11)
	ld a,h
	and l
	inc a
	jr z,.next
	call SHAPE_ENTRY
	jr c,.next
	ld a,(ix+4)
	ld (CS_W),a
	ld a,(ix+5)
	ld (CS_H),a
	ld l,(iy+12)
	ld h,(iy+13)
	bit 0,(iy+0)
	jr z,.x
	; mirrored: x = 176 - x - w
	ex de,hl
	ld hl,176
	or a
	sbc hl,de
	ld a,(CS_W)
	ld e,a
	ld d,0
	or a
	sbc hl,de
.x:	; DOS 14B30-14BC1: inclusive (x-3, y-3)..(x+w+3, y+h+3)
	ld de,-3
	add hl,de
	ex de,hl		; DE = x1
	ld hl,(MOUSE_X)
	or a
	sbc hl,de
	jp m,.next
	ld a,(CS_W)
	add a,6
	ld e,a
	ld d,0
	sbc hl,de
	jr z,.xin
	jp p,.next
.xin:	ld l,(iy+14)
	ld h,(iy+15)
	ld de,-3
	add hl,de
	ex de,hl
	ld a,(MOUSE_Y)
	ld l,a
	ld h,0
	or a
	sbc hl,de
	jp m,.next
	ld a,(CS_H)
	add a,6
	ld e,a
	ld d,0
	sbc hl,de
	jr z,.yes
	jp m,.yes
.next:	ld a,(iy+1)
	jp .lp
.yes:	or 1
	ret
.no:	xor a
	ret
CS_W:	db 0
CS_H:	db 0

; SPC_DOOR_PRY - a door the strongest character may force (clickedDoorPry)
SPC_DOOR_PRY:
	call IN_DOOR_RECT
	ret z
	; the strongest of those able to act
	ld a,0FFh
	ld (PRY_CHAR),a
	xor a
.lp:	ld (PRY_I),a
	call CHAR_PTR
	call CHAR_ALIVE_R
	jr z,.n
	ld a,(iy+P_HP)
	dec a
	jp m,.n			; hp <= 0
	ld a,(iy+P_FLAGS)
	and 0Ch
	jr nz,.n
	ld a,(iy+P_STR)
	add a,(iy+P_STREXT)
	ld c,a
	ld a,(PRY_CHAR)
	inc a
	jr z,.take
	ld a,(PRY_BEST)
	cp c
	jr z,.take
	jr nc,.n
.take:	ld a,c
	ld (PRY_BEST),a
	ld a,(PRY_I)
	ld (PRY_CHAR),a
.n:	ld a,(PRY_I)
	inc a
	cp 6
	jr c,.lp
	ld a,(PRY_CHAR)
	inc a
	ld hl,STR_PRY0
	jr z,.msg
	dec a
	call CHAR_PTR
	ld a,(iy+P_STR)
	cp 19
	jr c,.s
	ld a,18
.s:	ld e,a
	ld d,0
	ld hl,PRY_CHANCE
	add hl,de
	ld c,(hl)
	ld b,1
	push bc
	ld c,20
	xor a
	call ROLL_DICE		; 1d20
	pop bc
	ld a,l
	cp c
	ld hl,STR_PRY3
	jr nc,.msg
	; forced: both sides become an openable door
	ld a,(SPC_WALL)
	cp 30
	ld c,18
	jr nz,.w
	ld c,8
.w:	ld hl,(SPC_BLOCK)
	ld a,(SPC_DIR)
	push bc
	call W_SET_WALL
	pop bc
	ld a,(SPC_DIR)
	xor 2
	call W_SET_WALL
	ld hl,(SPC_BLOCK)
	call W_OPEN_DOOR
	ld hl,STR_PRY1
.msg:	call MSG_PRINT
	ld a,1
	ret

PRY_CHANCE:	db 1,1,2,3,3,4,4,5,5,6,6,7,7,8,8,9,10,11,12,13
PRY_CHAR:	db 0
PRY_BEST:	db 0
PRY_I:		db 0

; IN_DOOR_RECT - NZ if the mouse is inside (40, 16)-(136, 88)
IN_DOOR_RECT:
	ld a,(SPC_FLAG)
	cp 40h
	jr z,.mouse
	or a
	ret
.mouse:	ld a,(MOUSE_X+1)
	or a
	jr nz,.no
	ld a,(MOUSE_X)
	cp 40
	jr c,.no
	cp 137
	jr nc,.no
	ld a,(MOUSE_Y)
	cp 16
	jr c,.no
	cp 89
	jr nc,.no
	or 1
	ret
.no:	xor a
	ret

; the switch of the door ahead: inside its rectangle (4 pixels around)
SPC_DOOR_SWITCH:
	ld a,(SPC_FLAG)
	cp 40h
	jp nz,.press
	ld a,(SPC_WALL)
	cp 32
	jp nc,SPC_DOOR_NOPRY
	ld e,a
	ld d,0
	ld hl,DSC_DOORSHPINDEX
	add hl,de
	ld a,(hl)		; door slot (block 13: distance 2)
	ld l,a
	ld h,0
	ld e,l
	ld d,h
	add hl,hl
	add hl,de
	add hl,hl		; *6
	ld de,LEVELDAT+D_DOORS+2
	add hl,de
	ld e,(hl)
	inc hl
	ld d,(hl)		; switch shape
	inc hl
	ld a,(hl)
	sub 4
	ld (SPC_X),a		; x1 = switch x - 4 (block 13: centre x 0)
	inc hl
	ld a,(hl)
	sub 4
	ld (SPC_Y),a
	ex de,hl
	call SHAPE_ENTRY
	jr c,SPC_DOOR_NOPRY
	ld a,(MOUSE_X+1)
	or a
	jr nz,SPC_DOOR_NOPRY
	; The switch on the right half of a dwarven door slides with it.
	; DOS 15009h, against the nearest door (distance class 2).
	ld b,0
	ld a,(CUR_LEVEL)
	sub 4
	cp 3
	jr nc,.mouse_x
	ld a,(SPC_WALL)
	ld b,4
	cp 30
	jr nc,.mouse_x
	ld e,a
	ld d,0
	ld hl,DSC_DOORSCALEOFFS
	add hl,de
	sub (hl)
	ld e,a
	add a,a
	add a,a
	add a,a
	add a,e			; nine pixels per step
	ld b,a
.mouse_x:
	ld a,(SPC_X)
	add a,b
	ld b,a
	ld a,(MOUSE_X)
	sub b
	jr c,SPC_DOOR_NOPRY
	ld e,a
	ld a,(ix+4)
	add a,8
	cp e
	jr c,SPC_DOOR_NOPRY
	ld a,(SPC_Y)
	ld b,a
	ld a,(MOUSE_Y)
	sub b
	jr c,SPC_DOOR_NOPRY
	ld e,a
	ld a,(ix+5)
	add a,8
	cp e
	jr c,SPC_DOOR_NOPRY
.press:	ld hl,(SPC_BLOCK)
	ld a,6			; the switch clicks
	call SFX_PLAY
	call PROCESS_DOOR
	ld a,1
	ret

; a door that cannot be forced: inside (40, 16)-(136, 88), wall flag 20h
SPC_DOOR_NOPRY:
	call IN_DOOR_RECT
	jr z,.no
	ld a,(SPC_WALL)
	ld h,(LEVELDAT+D_WFLAGS)>>8
	ld l,a
	bit 5,(hl)
	jr z,.no
	ld hl,STR_NOPRY
	call MSG_PRINT
	ld a,1
	ret
.no:	xor a
	ret

; a niche: put the hand item in it (small items only) or take one
SPC_NICHE:
	ld a,(SPC_FLAG)
	cp 40h
	ld a,0
	ret nz
	ld a,(SPC_WALL)
	call CLICKED_SHAPE
	ret z
	ld hl,(HAND)
	ld a,h
	or l
	jr z,.take
	call ITEM_IX
	ld e,(ix+I_ICON)
	ld d,0
	ld hl,ITEM_SHPMAP
	add hl,de
	ld a,(hl)
	cp ITEM_LARGE_N+1
	jr nc,.small
	ld hl,STR_TOOBIG
	call MSG_PRINT
	ld a,1
	ret
.small:	ld bc,(HAND)
	ld hl,(SPC_BLOCK)
	ld e,l
	ld d,h
	call DRAWOBJ_PTR
	ld a,8
	call SET_ITEM_POS
	ld hl,(SPC_BLOCK)
	ld a,4
	call RUN_LEVEL_SCRIPT
	ld hl,0
	call SET_HAND_ITEM
	jr .upd
.take:	ld hl,(SPC_BLOCK)
	call DRAWOBJ_PTR
	ld de,0FFFFh
	ld a,8
	call GET_QUEUED_ITEM
	ld a,h
	or l
	ld a,1
	ret z
	push hl
	ld hl,(SPC_BLOCK)
	ld a,8
	call RUN_LEVEL_SCRIPT
	pop hl
	call SET_HAND_ITEM
.upd:	ld a,1
	ld (SCENE_DIRTY),a
	ret

SPC_BLOCK:	dw 0
SPC_DIR:	db 0
SPC_WALL:	db 0
SPC_X:		db 0
SPC_Y:		db 0
SPC_TYPE:	db 0
SPC_FLAG:	db 0
