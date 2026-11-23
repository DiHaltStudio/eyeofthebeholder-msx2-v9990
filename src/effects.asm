; Additional item/spell effects in their own mapper bank. All world accesses
; use WCALL and resident BOUNCE; no world pointer is dereferenced in this bank.
 output "../build/EFFECTS.OVL"
 org 8000h
 include "itemnames.asm"
 include "rules.asm"
 include "sound_slots.asm"

; C=character, A=53 haste / 54 giant strength; event expiry and dispelling.
FX_EXPIRE:
 push af
 ld a,c
 call CHAR_PTR
 pop af
 cp 53
 jr nz,.strength
 res 4,(iy+P_EFFECT)
 ld a,c
 jp PANEL_DRAW
.strength:
 ld a,(iy+P_EFFECT+2)
 ld (iy+P_STR),a
 ld a,(iy+P_EFFECT+3)
 ld (iy+P_STREXT),a
 ld (iy+P_EFFECT+2),0
 ld (iy+P_EFFECT+3),0
 ld a,c
 jp PANEL_DRAW

; Potion duration: 546 * (1d4+4) original ticks. ADD_EVENT updates an
; existing event or returns carry when all four slots are occupied.
; 120/121 in PARTY (unused high effect word) retain strength during potion.
FX_DURATION:
 ld bc,0104h
 ld a,4
 call ROLL_DICE
 ld e,l
 ld a,273/2 ; multiply by 136, then four = 544 (native timer rounding)
 call MUL8
 add hl,hl
 add hl,hl
 ret
FX_POTION:
 ld a,(CB_VALUE)
 dec a
 cp 8
 jp nc,.full
 ld a,(CB_CHAR)
 call CHAR_PTR
 ld a,(CB_VALUE)
 cp 1
 jr z,.strength
 cp 6
 jr z,.speed
 cp 7
 jr z,.invisible
 ; Existing healing, poison, food and antidote dispatch in the magic bank.
 call MCALL
 dw POTION_BASIC
 jr .ok
.speed:
 call FX_DURATION
 ld a,(CB_CHAR)
 ld c,a
 ld a,53
 call MCALL
 dw ADD_EVENT
 jp c,.full
 ld a,(CB_CHAR)
 call CHAR_PTR
 set 4,(iy+P_EFFECT)
 jr .ok
.invisible:
 set 6,(iy+P_EFFECT)
 jr .ok
.strength:
 ; Do not replace the original strength on repeated drinking.
 ld a,(CB_CHAR)
 ld c,a
 ld a,54
 call MCALL
 dw EVENT_EXISTS
 jr nz,.duration
 ld a,(CB_CHAR)
 call CHAR_PTR
 ld a,(iy+P_STR)
 ld (iy+P_EFFECT+2),a
 ld a,(iy+P_STREXT)
 ld (iy+P_EFFECT+3),a
.duration:
 call FX_DURATION
 ld a,(CB_CHAR)
 ld c,a
 ld a,54
 call MCALL
 dw ADD_EVENT
 jp c,.full
 ld a,(CB_CHAR)
 call CHAR_PTR
 ld (iy+P_STR),22
 ld (iy+P_STREXT),0
.ok:
 ld a,10
 call SFX_PLAY
 ld hl,(CB_ITEM)
 call FX_ITEM_NAME
 ld hl,TEXTBUF
 call MSG_PRINT
 or a
 ret

.full:
 ld hl,FX_FULL_TEXT
 call MSG_PRINT
 scf
 ret
FX_FULL_TEXT:
 if LANG_C2 = 83
 db "No puedes usar esa pocion ahora.",0
 else
 db "You cannot use that potion now.",0
 endif

; A=spell, B=caster level, C=caster, E=target (all passed by SP_EXT).
FX_SPELL:
 ld (FX_KIND),a
 ld a,b
 ld (FX_LEVEL),a
 ld a,c
 ld (FX_CASTER),a
 ld a,(FX_KIND)
 cp 3
 jr z,.detect
 cp 29
 jr z,.detect
 cp 5
 jr z,.read
 cp 9
 jp z,FX_KNOCK
 cp 15
 jp z,FX_HASTE
 jp FX_CLOUD
.detect:
 ld hl,PARTY_EFFECTS
 set 1,(hl)
 ld hl,(HAND)
 ld a,h
 or l
 ret z
 jp SET_HAND_ITEM
.read:
 ld hl,(HAND)
 ld a,h
 or l
 jp z,FX_NOEFFECT
 push hl
 call ITEM_IX
 set 6,(ix+I_FLAGS)
 pop hl
 push hl
 call SET_HAND_ITEM
 pop hl
 call FX_ITEM_NAME
 ld hl,TEXTBUF
 jp MSG_PRINT

FX_HASTE:
 ld a,(FX_LEVEL)
 add a,3
 ld e,a
 ld a,136
 call MUL8
 add hl,hl
 add hl,hl
 ld (FX_DURATION_TMP),hl
 xor a
.loop:
 ld (FX_CHAR),a
 call CHAR_PTR
 call CHAR_ALIVE_R
 jr z,.next
 ld a,(FX_CHAR)
 ld c,a
 ld hl,(FX_DURATION_TMP)
 ld a,53
 call MCALL
 dw ADD_EVENT
 jr c,.next
 ld a,(FX_CHAR)
 call CHAR_PTR
 set 4,(iy+P_EFFECT)
.next:
 ld a,(FX_CHAR)
 inc a
 cp 6
 jr c,.loop
 ret

; Front block and visible wall, with real world mapping restored by WCALL.
FX_FRONT:
 ld a,(CUR_DIR)
 call WCALL
 dw BLOCK_AHEAD
 ld (FX_FRONT_BLOCK),hl
 ld a,(CUR_DIR)
 xor 2
 call WCALL
 dw AM_WALL
 ret
FX_KNOCK:
 call FX_FRONT
 bit 5,b ; fully closed door
 jr z,FX_NOEFFECT
 ld l,a
 ld h,(LEVELDAT+D_WSPECIAL)>>8
 ld de,BOUNCE
 ld bc,1
 call WCALL
 dw MEM_COPY
 ld a,(BOUNCE)
 cp 5 ; forceable doors: remove their mechanical obstruction
 jr z,.force
 cp 1 ; ordinary switch doors; scripted/magical locks stay scripted
 jr nz,FX_NOEFFECT
 ld hl,(FX_FRONT_BLOCK)
 call WCALL
 dw BLOCK_HAS_MONSTER
 jr nz,FX_NOEFFECT
.open:
 ld hl,(FX_FRONT_BLOCK)
 ld (DOOR_BLOCK),hl
 ld a,1
 call WCALL
 dw OPEN_CLOSE
 ld hl,FX_OPEN_TEXT
 jp MSG_PRINT
.force:
 ; Same wall transformation as successful SPC_DOOR_PRY.
 call FX_FRONT
 cp 30
 ld c,18
 jr nz,.wall
 ld c,8
.wall:
 ld hl,(FX_FRONT_BLOCK)
 ld a,(CUR_DIR)
 xor 2
 push bc
 call WCALL
 dw W_SET_WALL
 pop bc
 ld hl,(FX_FRONT_BLOCK)
 ld a,(CUR_DIR)
 call WCALL
 dw W_SET_WALL
 jr .open
FX_NOEFFECT:
 ld hl,FX_NOEFFECT_TEXT
 jp MSG_PRINT

; Silvias follows EOB1: no charge consumed, and no push through a wall or
; into an occupied destination. All monsters on the front tile move together.
FX_PUSH:
 call FX_FRONT
 bit 0,b
 jr z,FX_NOEFFECT
 ld hl,(FX_FRONT_BLOCK)
 ld a,(CUR_DIR)
 call NEW_BLOCK_POS
 ld (FX_DEST),hl
 ld a,(CUR_DIR)
 xor 2
 call WCALL
 dw AM_WALL
 bit 2,b
 jr z,FX_NOEFFECT
 ld hl,(FX_DEST)
 call WCALL
 dw BLOCK_HAS_MONSTER
 jr nz,FX_NOEFFECT
 ld hl,(FX_FRONT_BLOCK)
 call WCALL
 dw BLOCK_HAS_MONSTER
 jr z,FX_NOEFFECT
 ld a,98
 call SFX_PLAY
 call FX_MON_BEGIN
.loop:
 call FX_MON_READ
 ld hl,(FX_FRONT_BLOCK)
 call FX_MATCH
 jr nz,.next
 ld ix,(FX_MON_PTR)
 ld hl,(FX_DEST)
 ld a,0FFh
 call WCALL
 dw MON_PLACE
.next:
 call FX_MON_NEXT
 jr nz,.loop
 jp DIRTY

FX_MON_BEGIN:
 ld hl,LEVELDAT+D_MONSTERS
 ld (FX_MON_PTR),hl
 ld a,30
 ld (FX_MON_LEFT),a
 ret
FX_MON_READ:
 ld hl,(FX_MON_PTR)
 ld de,BOUNCE
 ld bc,MON_SIZE
 call WCALL
 dw MEM_COPY
 ret
FX_MATCH:
 ld de,(BOUNCE+M_BLOCK)
 or a
 sbc hl,de
 ret nz
 ld a,(BOUNCE+M_HP+1)
 bit 7,a
 ret nz
 ld a,(BOUNCE+M_FLAGS)
 and 20h
 ret
FX_MON_NEXT:
 ld hl,(FX_MON_PTR)
 ld de,MON_SIZE
 add hl,de
 ld (FX_MON_PTR),hl
 ld hl,FX_MON_LEFT
 dec (hl)
 ret

; Four stationary poison clouds, six pulses at one-second intervals.
; Records: level, block(2), spell, remaining ticks, pulse countdown.
FX_CLOUD:
 call FX_FRONT
 bit 0,b
 jp z,FX_NOEFFECT
 ld ix,FX_CLOUDS
 ld b,4
.find:
 ld a,(ix+4)
 or a
 jr z,.free
 ld de,6
 add ix,de
 djnz .find
 jp FX_NOEFFECT
.free:
 ld a,(CUR_LEVEL)
 ld (ix+0),a
 ld hl,(FX_FRONT_BLOCK)
 ld (ix+1),l
 ld (ix+2),h
 ld a,(FX_KIND)
 ld (ix+3),a
 ld (ix+4),108
 ld (ix+5),1
 ld hl,FX_CLOUD_TEXT
 call MSG_PRINT
 jp DIRTY
FX_TICK:
 ld ix,FX_CLOUDS
 ld b,4
.loop:
 push bc
 push ix
 ld a,(ix+4)
 or a
 jr z,.next
 dec (ix+4)
 jr nz,.alive
 ld a,1
 ld (SCENE_DIRTY),a
 jr .next
.alive:
 dec (ix+5)
 jr nz,.next
 ld (ix+5),18
 ld a,(CUR_LEVEL)
 cp (ix+0)
 jr nz,.next
 ld l,(ix+1)
 ld h,(ix+2)
 ld (FX_FRONT_BLOCK),hl
 ld a,(ix+3)
 ld (FX_KIND),a
 call FX_CLOUD_PULSE
.next:
 pop ix
 pop bc
 ld de,6
 add ix,de
 djnz .loop
 ret
FX_CLOUD_PULSE:
 call FX_CLOUD_PARTY
 call FX_MON_BEGIN
.loop:
 call FX_MON_READ
 ld hl,(FX_FRONT_BLOCK)
 call FX_MATCH
 jr nz,.next
 ld ix,(FX_MON_PTR)
 call WCALL
 dw MON_PROPS
 bit 2,(iy+MP_TFLAGS) ; undead do not breathe poison
 jr nz,.next
 ; Saving throw against spells (same level table used by W_HOLD).
 ld a,(iy+MP_LEVEL)
 cp 18
 jr c,.level
 ld a,17
.level:
 srl a
 ld e,a
 ld d,0
 ld hl,MON_SAVE4
 add hl,de
 ld c,(hl)
 ld a,20
 call RND_RANGE
 cp c
 jr nc,.next
 ld a,(FX_KIND)
 cp 11
 jr nz,.damage
 ld a,10
 ld (BOUNCE+M_MODE),a
 ld a,2
 ld (BOUNCE+M_SPELL),a
 ld hl,BOUNCE
 ld de,(FX_MON_PTR)
 ld bc,MON_SIZE
 call WCALL
 dw MEM_COPY
 jr .next
.damage:
 ld a,(iy+MP_LEVEL)
 cp 5
 jr nc,.hurt
 ld de,1000                    ; simplified Cloudkill weak-monster death
 jr .inflict
.hurt:
 ld bc,0104h
 xor a
 call ROLL_DICE
 ex de,hl
.inflict:
 ld ix,(FX_MON_PTR)
 call WCALL
 dw INFLICT_MONSTER
.next:
 call FX_MON_NEXT
 jr nz,.loop
 jp DIRTY

 ; Draw the near cloud into the same hidden view buffer as the dungeon.
FX_DRAW_CLOUD:
 call FX_FRONT
 bit 0,b
 ret z
 ld ix,FX_CLOUDS
 ld b,4
.find:
 ld a,(ix+4)
 or a
 jr z,.next
 ld a,(CUR_LEVEL)
 cp (ix+0)
 jr nz,.next
 ld hl,(FX_FRONT_BLOCK)
 ld a,l
 cp (ix+1)
 jr nz,.next
 ld a,h
 cp (ix+2)
 jr z,.draw
.next:
 ld de,6
 add ix,de
 djnz .find
 ret
.draw:
 ld hl,FX_MIST_POINTS
 ld b,24
.dot:
 push bc
 ld a,(hl)
 inc hl
 add a,VIEWBUF_X & 255
 ld (FX_MIST_RECT),a
 ld a,(hl)
 inc hl
 add a,VIEWBUF_Y & 255
 ld (FX_MIST_RECT+2),a
 push hl
 ld hl,FX_MIST_RECT
 ld a,C_LIGHTGREEN
 call V9_LMMV
 pop hl
 pop bc
 djnz .dot
 ret
FX_MIST_RECT: dw VIEWBUF_X,VIEWBUF_Y+38,5,3
FX_MIST_POINTS: db 58,38,76,35,94,37,112,40,52,49,68,47,86,48,104,50
 db 120,52,50,61,66,59,82,62,100,61,118,63,52,74,70,72
 db 88,75,106,73,122,77,58,87,76,85,94,88,110,87,80,97

 ; A=normal keyboard repeat delay. Haste accelerates party movement only
; when every conscious active member is hasted; attacks use individual flags.
FX_REPEAT:
 push af
 ld a,(KEY_LAST)
 cp 1
 jr c,.normal
 cp 7
 jr nc,.normal
 ld b,6
 xor a
.loop:
 push af
 call CHAR_PTR
 call CHAR_ALIVE_R
 jr z,.next
 bit 4,(iy+P_EFFECT)
 jr z,.slow
.next:
 pop af
 inc a
 djnz .loop
 pop af
 srl a
 ret
.slow:
 pop af
.normal:
 pop af
 ret

 ; One original rest hour advances 32760 timer ticks. Poison retains its
; repeating event (RS_HOUR applies rest damage); other timers keep any
; remainder, including temporary paralysis and long book/effect cooldowns.
FX_REST:
 ld hl,FX_CLOUDS
 ld de,FX_CLOUDS+1
 ld bc,23
 ld (hl),0
 ldir
 xor a
 ld (FX_EVENT_I),a
.loop:
 ld a,(FX_EVENT_I)
 ld e,a
 add a,a
 add a,e
 ld e,a
 ld d,0
 ld hl,CH_EVENTS
 add hl,de
 ld (FX_EVENT_PTR),hl
 ld de,BOUNCE
 ld bc,3
 call MCALL
 dw MEM_COPY
 ld hl,(BOUNCE)
 ld a,h
 or l
 jr z,.next
 ld a,(BOUNCE+2)
 bit 7,a
 jr z,.advance
 cp 89h                        ; native temporary paralysis recovery
 jr nz,.next
.advance:
 ld (FX_EVENT_ID),a
 ld hl,(BOUNCE)
 ld de,32760
 or a
 sbc hl,de
 jr c,.expire
 jr z,.expire
 ld (BOUNCE),hl
 ld hl,BOUNCE
 ld de,(FX_EVENT_PTR)
 ld bc,2
 call MCALL
 dw MEM_COPY
 jr .next
.expire:
 xor a
 ld (BOUNCE),a
 ld (BOUNCE+1),a
 ld hl,BOUNCE
 ld de,(FX_EVENT_PTR)
 ld bc,2
 call MCALL
 dw MEM_COPY
 ld a,(FX_EVENT_I)
 srl a
 srl a
 ld c,a
 ld a,(FX_EVENT_ID)
 call MCALL
 dw EVENT_END
 ld hl,MAGIC_ACTIVE
 dec (hl)
.next:
 ld hl,FX_EVENT_I
 inc (hl)
 ld a,(hl)
 cp 24
 jp c,.loop
 jp DIRTY
FX_EVENT_I: db 0
FX_EVENT_ID: db 0
FX_EVENT_PTR: dw 0

FX_SAVE:
 or a
 ret nz
 ld de,FX_HEADER
 ld hl,4
 call FILE_WRITE
 ret nz
 ld de,FX_STATE
 ld hl,FX_STATE_END-FX_STATE
 jp FILE_WRITE
FX_LOAD:
 ld de,FX_READHDR
 ld hl,4
 call FILE_READ
 ld a,l
 cp 4
 jr nz,.clear
 ld hl,FX_HEADER
 ld de,FX_READHDR
 ld b,4
.check:
 ld a,(de)
 cp (hl)
 jr nz,.clear
 inc hl
 inc de
 djnz .check
 ld de,FX_STATE
 ld hl,FX_STATE_END-FX_STATE
 call FILE_READ
 ld de,FX_STATE_END-FX_STATE
 or a
 sbc hl,de
 ret z
.clear:
 ld hl,FX_STATE
 ld de,FX_STATE+1
 ld bc,FX_STATE_END-FX_STATE-1
 ld (hl),0
 ldir
 ret
FX_HEADER: db "FX01"
FX_READHDR: ds 4
FX_STATE:
FX_CLOUDS: ds 24
FX_STATE_END:
FX_KIND: db 0
FX_LEVEL: db 0
FX_CASTER: db 0
FX_CHAR: db 0
FX_FRONT_BLOCK: dw 0
FX_DEST: dw 0
FX_DURATION_TMP: dw 0
FX_MON_PTR: dw 0
FX_MON_LEFT: db 0
 include "../build/effectdata.inc"
; Only a party actually inside this cloud is affected. Brief nausea uses
; the existing timed paralysis recovery and never overwrites real paralysis.
FX_CLOUD_PARTY:
 ld hl,(FX_FRONT_BLOCK)
 ld de,(CUR_BLOCK)
 or a
 sbc hl,de
 ret nz
 xor a
.loop:
 ld (FX_CHAR),a
 call CHAR_PTR
 call CHAR_ALIVE_R
 jr z,.next
 ld a,(FX_KIND)
 cp 11
 jr nz,.save
 bit 2,(iy+P_FLAGS)
 jr nz,.next
.save:
 ld a,(FX_CHAR)
 ld c,4
 call FX_CHAR_SAVE
 jr nc,.next
 ld a,(FX_KIND)
 cp 11
 jr nz,.damage
 ld a,(FX_CHAR)
 ld c,a
 ld hl,36
 ld a,89h
 call MCALL
 dw ADD_EVENT
 jr c,.next
 ld a,(FX_CHAR)
 call CHAR_PTR
 set 2,(iy+P_FLAGS)
 call MCALL
 dw BOOK_CLOSE
 ld a,(FX_CHAR)
 call PANEL_DRAW
 jr .next
.damage:
 ld bc,0104h
 xor a
 call ROLL_DICE
 ld a,(FX_CHAR)
 call WCALL
 dw INFLICT_CHARACTER
.next:
 ld a,(FX_CHAR)
 inc a
 cp 6
 jr c,.loop
 ret
 if LANG_C2 = 83
FX_OPEN_TEXT: db "LA PUERTA SE ABRE.",0
 else
FX_OPEN_TEXT: db "THE DOOR OPENS.",0
 endif
 include "pointer.asm"
FX_END:
 assert FX_END <= 0C000h
