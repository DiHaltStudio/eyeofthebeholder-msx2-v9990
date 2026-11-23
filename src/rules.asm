; Character rule helpers in EFFECTS.OVL. Party/items are resident. UI tables
; are read through UCALL, never through an address under the wrong bank.
P_STONESKIN: equ 55              ; unused saved party byte after P_LEVELS[3]

; Memorize/Pray hit tests in the roomier effects bank. Return tab 0..4,
; add=5, remove=6, clear=7, exit=8, or FF for a gap/outside/unused row.
; The UI already highlights the row under the pointer before calling us.
FX_MZ_CLICK:
 ld a,(MOUSE_X+1)
 or a
 jr nz,.none
 ld a,(MOUSE_X)
 sub 8
 jr c,.none
 cp 160
 jr nc,.none
 ld c,a
 ld a,(MOUSE_Y)
 cp 16
 jr c,.none
 cp 37
 jr c,.tab
 sub 50
 jr c,.none
 cp 72
 jr c,.row
 ld a,(MOUSE_Y)
 sub 126
 cp 14
 jr nc,.none
 ld a,(CLICK)
 cp 1
 jr nz,.none
 ld a,c
 cp 48
 ld a,7
 ret c
 ld a,c
 sub 56
 cp 24
 ld a,6
 ret c
 ld a,c
 sub 88
 cp 24
 ld a,5
 ret c
 ld a,c
 cp 120
 ld a,8
 ret nc
.none:
 ld a,0FFh
 ret
.tab:
 ld a,(CLICK)
 cp 1
 jr nz,.none
 ld a,c
 and 31
 cp 24
 jr nc,.none
 ld a,c
 rrca
 rrca
 rrca
 rrca
 rrca
 and 7
 ret
.row:
 ld c,0
.divide:
 sub 9
 jr c,.check
 inc c
 jr .divide
.check:
 push bc
 call UCALL
 dw MZ_ROWS
 pop bc
 cp c
 jr c,.none
 jr z,.none
 ld a,(CLICK)
 cp 2
 ld a,6
 ret z
 ld a,5
 ret

; A=recipient, C=caster level. Separate from Armor's damage allowance.
FX_STONESKIN:
 call CHAR_PTR
 ld a,c
 srl a
 push af
 ld a,4
 call RND_RANGE
 pop bc
 add a,b
 ld (iy+P_STONESKIN),a
 ret

; Called only on a successful physical monster strike, before damage dice.
; NZ=one protected blow consumed. Spell/projectile damage bypasses this hook.
FX_STONE_HIT:
 push iy
 ld a,(CB_TARGET)
 call CHAR_PTR
 ld a,(iy+P_STONESKIN)
 or a
 jr z,.done
 dec (iy+P_STONESKIN)
 jr nz,.remaining
 res 2,(iy+P_EFFECT)
.remaining:
 ld a,1
.done:
 pop iy
 or a
 ret

; A=character -> NZ when a Wizardry ring is worn on either finger.
FX_WIZARDRY:
 call CHAR_PTR
 ld a,25
 call .ring
 ret nz
 ld a,26
.ring:
 call HAND_ITEM
 ld a,h
 or l
 ret z
 call ITEM_IX
 ld a,(ix+I_TYPE)
 cp 47
 jr nz,.no
 ld a,(ix+I_VALUE)
 cp 1
 jr nz,.no
 or 1
 ret
.no:
 xor a
 ret

; A=character, C=class type -> A=class level or zero; IY=character.
FX_CLASS_LEVEL:
 call CHAR_PTR
 push bc
 ld a,(iy+P_CLASS)
 ld e,a
 add a,a
 add a,e
 ld e,a
 ld d,0
 ld hl,CLASS_TYPE
 add hl,de
 ld de,BOUNCE
 ld bc,3
 call UCALL
 dw MEM_COPY
 pop bc
 ld hl,BOUNCE
 ld b,0
.find:
 ld a,(hl)
 cp c
 jr z,.found
 inc hl
 inc b
 ld a,b
 cp 3
 jr c,.find
 xor a
 ret
.found:
 push iy
 pop hl
 ld e,b
 ld d,0
 add hl,de
 ld de,P_LEVELS
 add hl,de
 ld a,(hl)
 ret

; A=character, C=book type, B=nonzero item cast. Caster wrapper preserves
; BC/DE/HL: callers use them to accumulate duration and damage parameters.
FX_CASTER_LEVEL:
 ld d,a
 ld a,b
 or a
 ld a,9
 ret nz
 ld a,c
 inc a
 ld c,a                        ; mage=1, cleric=2
 ld a,d
 push af
 push bc
 call FX_CLASS_LEVEL
 pop bc
 pop de                        ; D=character
 or a
 ret nz
 ld a,c
 cp 2
 jr nz,.minimum
 ld a,d
 ld c,4
 call FX_CLASS_LEVEL
 sub 8
 jr c,.minimum
 or a
 ret nz
.minimum:
 ld a,1
 ret

; A=character, C=positive healing. Use a signed 16-bit sum before clamping.
FX_HEAL:
 push af
 call CHAR_PTR
 call CHAR_ALIVE_R
 jr z,.done
 ld a,(iy+P_HP)
 ld l,a
 rla
 sbc a,a
 ld h,a
 ld b,0
 add hl,bc
 bit 7,h
 jr nz,.store
 ld e,(iy+P_HPMAX)
 ld d,0
 or a
 sbc hl,de
 add hl,de
 jr c,.store
 ex de,hl
.store:
 ld (iy+P_HP),l
.done:
 pop af
 jp PANEL_DRAW

; IY=character, A=temporary HP gained. Never wrap the signed HP byte.
; Return actual increment in L so Aid only removes points actually granted.
FX_TEMP_HP:
 ld e,a
 ld d,0
 ld c,(iy+P_HP)
 ld l,c
 ld a,c
 rla
 sbc a,a
 ld h,a
 add hl,de
 bit 7,h
 jr nz,.store
 ld a,h
 or a
 jr nz,.cap
 ld a,l
 cp 128
 jr c,.store
.cap:
 ld l,127
.store:
 ld a,l
 ld (iy+P_HP),a
 sub c
 ld l,a
 ret
FX_AID_ADD:
 ; Refresh replaces the unused bonus; repeated casts must not stack HP.
 ld a,(iy+P_HP)
 sub (iy+P_AID)
 ld (iy+P_HP),a
 ld a,l
 call FX_TEMP_HP
 ld (iy+P_AID),l
 ret

; The native HP field is signed eight-bit; level gains must not wrap it.
FX_LEVEL_HP:
 ld a,c
 push bc
 call FX_TEMP_HP
 pop bc
 ld a,(iy+P_HPMAX)
 add a,c
 jr c,.cap
 cp 128
 jr c,.store
.cap:
 ld a,127
.store:
 ld (iy+P_HPMAX),a
 ret

; Script HP changes use a signed delta, unlike healing spells/potions.
FX_MOD_HP:
 push af
 call CHAR_PTR
 call CHAR_ALIVE_R
 jr z,.done
 ld a,(iy+P_HP)
 ld l,a
 rla
 sbc a,a
 ld h,a
 ld a,c
 ld e,a
 rla
 sbc a,a
 ld d,a
 add hl,de
 bit 7,h
 jr nz,.negative
 ld e,(iy+P_HPMAX)
 ld d,0
 or a
 sbc hl,de
 add hl,de
 jr c,.store
 ex de,hl
 jr .store
.negative:
 ld de,-10
 or a
 sbc hl,de
 add hl,de
 jr nc,.store
 ex de,hl
.store:
 ld (iy+P_HP),l
.done:
 pop af
 jp PANEL_DRAW

; Reject illegal active weapons before any action, cooldown or invisibility
; change. NZ=legal; IY remains the attacking character.
FX_WEAPON_VALID:
 ld a,(CB_SLOT)
 or a
 jr z,.first
 call UCALL
 dw VALIDATE_SLOT1
 ret
.first:
 call HAND_ITEM
 jp ITEM_USABLE

; IY=recipient, L=damage. Preserve all the damage routine's inputs.
FX_DAMAGE_REMAINDERS:
 push af
 push bc
 push de
 push hl
 push ix
 push iy
 ld c,l
 ld a,(iy+P_AID)
 sub c
 jr nc,.aid
 xor a
.aid:
 ld (iy+P_AID),a
 ld a,(iy+P_EFFREM)
 or a
 jr z,.done
 sub c
 jr nc,.armor
 xor a
.armor:
 ld (iy+P_EFFREM),a
 or a
 jr nz,.done
 res 0,(iy+P_EFFECT)
 ld a,(CB_TARGET)
 call UCALL
 dw RECALC_AC
.done:
 pop iy
 pop ix
 pop hl
 pop de
 pop bc
 pop af
 ret

; Timed callbacks have already restored strength/removed temporary weapons.
; Status flags and their recovery timers are deliberately retained.
FX_CLEAR_UNTIMED:
 push af
 call CHAR_PTR
 ld a,(iy+P_HP)
 cp -10
 jr z,.dead
 sub (iy+P_AID)
 ld (iy+P_HP),a
.dead:
 xor a
 ld (iy+P_AID),a
 ld (iy+P_EFFREM),a
 ld (iy+P_STONESKIN),a
 ld (iy+P_EFFECT),a
 ld (iy+P_EFFECT+1),a
 pop af
 push af
 call UCALL
 dw RECALC_AC
 pop af
 jp PANEL_DRAW

FX_MAGIC_HIT:
	ld a,(FLY_HITREC+FO_CB)
	cp 4
	jp z,.missile
	cp 10
	jp z,.melf
	cp 13
	jp z,.fireball
	cp 14
	jp z,.flamearrow
	cp 18
	jp z,.lightning
	cp 21
	jp z,.ice
	cp 47
	jp z,.strike
	cp 50
	jp z,.mbolt
	cp 51
	jp z,.death
	cp 52
	jp z,.disintegrate
	ld c,1
	cp 16
	jp z,.hold
	cp 33
	jp z,.hold
	inc c
	cp 25
	jp z,.hold
	xor a
	ret
.hold:	ld b,0
	call WCALL
	dw W_HOLD
	ret
.mbolt:	ld bc,0
	ld e,12
	ld a,1
	jp .hit
.missile:			; 1d4 + 1, times (level - 1) / 2 (at least 1)
	ld bc,0104h
	ld e,1
	ld a,(FLY_HITREC+FO_LEVEL)
	dec a
	srl a
	jr .hit
.melf:
	ld a,(FLY_HITREC+FO_LEVEL)
	ld c,0
.divide3:
	sub 3
	jr c,.melflevel
	inc c
	jr .divide3
.melflevel:
	ld a,c
	ld bc,0204h
	ld e,0
	jr .hit
.flamearrow:
	; SSI rulebook: 3d10, doubled at mage level 10.
	ld a,(FLY_HITREC+FO_LEVEL)
	cp 10
	ld a,1
	jr c,.flamedice
	inc a
.flamedice:
	ld bc,030Ah
	ld e,0
	jr .hit
.fireball:
	ld a,35			; it explodes
	call SFX_PLAY
	ld a,(FLY_HITREC+FO_LEVEL)
	ld bc,0106h
	ld e,0
	jr .hit
.lightning:
	ld a,(FLY_HITREC+FO_LEVEL)
	ld bc,0106h
	ld e,0
	jr .hit
.ice:	ld a,35
	call SFX_PLAY
	ld bc,030Ah
	ld e,0
	ld a,1
	ld (WD_TIMES),a
	ld (WD_DICE),bc
	ld a,e
	ld (WD_INC),a
	jp FX_ICE_AREA
.strike:
	ld bc,0608h
	ld e,0
	ld a,1
.hit:	or a
	jr nz,.lv
	inc a
.lv:	ld (WD_TIMES),a
	ld (WD_DICE),bc
	ld a,e
	ld (WD_INC),a
	call WCALL
	dw W_MAGIC_DAMAGE
	ret

.death:
 call MCALL
 dw DEATH_SPELL
 ret
.disintegrate:
 call MCALL
 dw DISINTEGRATE
 ret

; Impact and four orthogonal neighbors; preserve the flight's real block.
; As in EOB1 the cross expands only when the centre actually hits a target.
FX_ICE_AREA:
 ld hl,(FLY_HITREC+FO_BLOCK)
 ld (FX_ICE_CENTRE),hl
 call WCALL
 dw W_MAGIC_DAMAGE
 or a
 ret z
 ld hl,FX_ICE_OFFSETS
 ld b,4
.loop:
 push bc
 push hl
 ld e,(hl)
 inc hl
 ld d,(hl)
 ld hl,(FX_ICE_CENTRE)
 add hl,de
 ld a,h
 and 3
 ld h,a
 ld (FLY_HITREC+FO_BLOCK),hl
 call WCALL
 dw W_MAGIC_DAMAGE
 pop hl
 inc hl
 inc hl
 pop bc
 djnz .loop
 ld hl,(FX_ICE_CENTRE)
 ld (FLY_HITREC+FO_BLOCK),hl
 ld a,1
 ret
FX_ICE_CENTRE: dw 0
FX_ICE_OFFSETS: dw -32,32,-1,1

; A=level, B=class save group, C=save category -> A=threshold.
; Preserve BC so character-specific racial adjustment can inspect category.
FX_SAVE_THRESHOLD:
 push bc
 cp 32
 jr c,.level
 ld a,31
.level:
 push af
 ld a,b
 ld e,160
 call MUL8
 pop af
 ld e,a
 ld d,0
 add hl,de
 ld a,c
 ld e,32
 push hl
 call MUL8
 pop de
 add hl,de
 ld de,FX_SAVE_TABLE
 add hl,de
 ld a,(hl)
 pop bc
 ret

; A=character, C=save category -> A=threshold, IY=character.
FX_CHAR_THRESHOLD:
 call CHAR_PTR
 ld e,(iy+P_CLASS)
 ld d,0
 ld hl,CLASS_MODIFIER
 add hl,de
 ld b,(hl)
 ld a,(iy+P_LEVEL)
 call FX_SAVE_THRESHOLD
 ld d,a
 ld a,(iy+P_RACE)
 srl a
 cp 3
 jr z,.short
 cp 5
 jr z,.short
 cp 4
 jr nz,.done
 ld a,c
 or a
 jr z,.done                    ; gnomes: no poison adjustment
.short:
 ld a,c
 cp 2
 jr z,.done
 cp 3
 jr z,.done
 ld a,(iy+P_CON)
 cp 20
 jr c,.constitution
 ld a,19
.constitution:
 ld e,a
 ld a,d
 ld d,0
 ld hl,FX_CON_SAVE
 add hl,de
 sub (hl)
 ret
.done:
 ld a,d
 ret

; A=character C=category -> NC=successful save, C=failed.
FX_CHAR_SAVE:
 call FX_CHAR_THRESHOLD
 ld c,a
 ld a,20
 call RND_RANGE
 cp c
 ret

; HL=damage, IY=resident monster properties; preserve live IX/loop counters.
FX_MAGIC_SAVE_MON:
 push bc
 push de
 push iy
 ld a,(FLY_HITREC+FO_CB)
 cp 50                         ; special monster rays have no damage flag 1
 call c,FX_EVADE_MON
 push hl
 ld a,(FLY_HITREC+FO_FLAGS)
 bit 3,a
 jr z,FX_MAGIC_SAVE_KEEP
 ld a,(iy+MP_LEVEL)
 ld bc,4                      ; class group 0, spell save category 4
 call FX_SAVE_THRESHOLD
 ld c,a
 ld a,20
 call RND_RANGE
 cp c
 jr FX_MAGIC_SAVE_RESULT

; A=character, HL=damage; shield immunity is handled by WP_HIT first.
FX_MAGIC_SAVE_CHAR:
 push bc
 push de
 push iy
 push hl
 ld c,a
 ld a,(FLY_HITREC+FO_FLAGS)
 bit 3,a
 jr z,FX_MAGIC_SAVE_KEEP
 ld a,c
 ld c,4
 call FX_CHAR_SAVE
FX_MAGIC_SAVE_RESULT:
 pop hl
 jr c,FX_MAGIC_SAVE_DONE
 srl h
 rr l
 jr FX_MAGIC_SAVE_DONE
FX_MAGIC_SAVE_KEEP:
 pop hl
FX_MAGIC_SAVE_DONE:
 pop iy
 pop de
 pop bc
 ret
FX_CON_SAVE: db 0,0,0,0,1,1,1,2,2,2,2,3,3,3,4,4,4,4,5,5

; EOB1 spell damage flag 1: target's magical attack evasion percentage.
; Elemental immunityFlags are EOB2 data; EOB1 initializes that field to zero.
FX_EVADE_MON:
 push hl
 ld a,100
 call RND_RANGE
 pop hl
 cp (iy+MP_EVADE)
 ret nc
 ld hl,0
 ret
 include "../build/rules.inc"

; Native saved byte 56 is unused in the 128-byte party record. Bits 0/1
; mark the initial result phase for each hand; timers remain independent of
; spell-event capacity, and native saves/reordering carry both phases.
P_RECOVERY: equ 56
FX_ATTACK_PHASE:
 ld a,(CB_SLOT)
 or a
 ld a,1
 jr z,.mask
 inc a
.mask:
 ld e,a
 cpl
 and (iy+P_RECOVERY)
 ld (iy+P_RECOVERY),a
 ld a,(CB_RESULT)
 cp 0FDh                       ; -3 reach / -4 ammo: only the initial 18
 ret z
 cp 0FCh
 ret z
 ld a,(iy+P_RECOVERY)
 or e
 ld (iy+P_RECOVERY),a
 ret

; IY=character, A=hand. Preserve the character-timer loop registers.
FX_SLOT_PHASE:
 push bc
 push de
 push hl
 push iy
 ld c,a
 ld e,1
 or a
 jr z,.mask
 inc e
.mask:
 ld a,(iy+P_RECOVERY)
 and e
 ld b,a
 ld a,e
 cpl
 and (iy+P_RECOVERY)
 ld (iy+P_RECOVERY),a
 push iy
 pop hl
 ld a,c
 add a,P_STATUS0
 ld e,a
 ld d,0
 add hl,de
 ld (hl),0
 ld a,b
 or a
 jr z,.ready
 ld b,36
 bit 4,(iy+P_EFFECT)
 jr z,.timer
 ld b,9
.timer:
 inc hl
 inc hl
 ld (hl),b
 jr .done
.ready:
 ld a,c
 or a
 jr nz,.second
 res 0,(iy+P_DISABLED)
 jr .done
.second:
 res 1,(iy+P_DISABLED)
.done:
 pop iy
 pop hl
 pop de
 pop bc
 ret

; Shape choice is shared by inventory, party hands and item cursor. Inputs
; refer only to resident items; caller coordinates and character survive.
FX_ITEM_ICON:
 push bc
 push de
 push ix
 call ITEM_IX
 call FX_ICON_IX
 pop ix
 pop de
 pop bc
 ret
FX_ICON_IX:
 push bc
 push de
 ld e,(ix+I_ICON)
 ld d,0
 ld hl,SHP_ICON0
 ld a,(PARTY_EFFECTS)
 bit 1,a
 jr z,.normal
 bit 7,(ix+I_FLAGS)
 jr z,.normal
 ld hl,SHP_BLUEICON0
.normal:
 add hl,de
 pop de
 pop bc
 ret
FX_HAND_SHAPE:
 push af
 call HAND_ITEM
 ld a,h
 or l
 jr z,.empty
 pop af
 jp FX_ITEM_ICON
.empty:
 pop af
 add a,85
 ld l,a
 ld h,0
 ld de,SHP_ICON0
 add hl,de
 ret

; Nonstacking corrected printed intent: AC5 through level5, AC4 at6,
; AC3 at9, then one better each three levels. Level10 matches SSI's AC3.
; Use the casting level saved at spell start, not the wearer's class.
P_VEST_AC: equ 57
FX_VEST_START:
 ld b,a
 ld a,5
 ld c,a
 ld a,b
 sub 3
 jr c,.store
.loop:
 sub 3
 jr c,.store
 dec c
 jr .loop
.store:
 ld a,c
 add a,11                       ; encoded so zero still means legacy/default
 ld b,a
 ld a,e                        ; recipient supplied while MAGIC was mapped
 call CHAR_PTR
 ld (iy+P_VEST_AC),b
 ret
FX_VEST_AC:
 ld b,a                        ; incoming AC, UI variable is banked out here
 ld a,(iy+P_VEST_AC)
 or a
 jr z,.legacy
 sub 11
 jr .known
.legacy:
 ld a,5                        ; legacy saves had no recorded strength
.known:
 ld c,a
 ld a,b
 cp c
 ret m
 ret z
 ld a,c
 ret

FX_BLUE_ENTRY:
 ld a,h
 or a
 scf
 ret nz
 ld a,l
 cp 89
 ccf
 ret c
 add hl,hl
 add hl,hl
 add hl,hl
 ld de,FX_BLUE_SHAPES
 add hl,de
 ld de,SHP_TMP
 ld bc,8
 ldir
 ld ix,SHP_TMP
 or a
 ret
 include "../build/blueicons.inc"
