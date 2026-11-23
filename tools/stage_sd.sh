#!/bin/sh
# Stage the bilingual game directory for MSX-DOS2 or Nextor.
set -eu
cd "$(dirname "$0")/.."

INITIAL_SAVE=assets/saves/initial/EOBSAVE.DAT
LEVELS=${LEVELS:-1}
LANGLVL=""
for l in $LEVELS; do
    if [ -f build/pc_en/LEVEL$l.INF ] || [ -f "${EOB_PC_DIR}/LEVEL$l.DRO" ]; then LANGLVL="$LANGLVL LEVEL$l.LVL"; fi
done
LANGFILES="EOB.BIN INIT.BIN PAGE3.DAT SCRIPT.OVL UI.OVL MAGIC.OVL AUTOMAP.OVL EFFECTS.OVL INTRO.OVL TEXT.DAT ITEMNAME.DAT
CHARGEN.OVL CHARGEN.V9 CHARGEN.PAL
$(cd build && ls INSEQ*.BIN)$LANGLVL"

# The order is the order of the directory, and MSX-DOS looks for a name entry
# by entry (slow on a Z80): the language folders first, then what the game
# opens while playing, what only the start-up opens after it, the intro last.
SHARED=""
for l in $LEVELS; do
    case " $LANGLVL " in *" LEVEL$l.LVL "*) ;; *) SHARED="$SHARED LEVEL$l.LVL" ;; esac
    SHARED="$SHARED LEVEL$l.V9"
done
SHARED="$SHARED UI.V9"
for l in $LEVELS; do
    [ -f build/NPC$l.V9 ] && SHARED="$SHARED NPC$l.V9"
    [ -f build/PORTAL$l.V9 ] && SHARED="$SHARED PORTAL$l.V9"
done
[ -f build/XDEATH.V9 ] && SHARED="$SHARED XDEATH.V9"
SHARED="$SHARED GLOBAL.SHP GLOBAL.DAT PARTY.DAT ITEMS.DAT SFX.DAT TITLE.V9 TITLE.PAL CGSND.DAT
$(cd build && ls IN[0-9][0-9]_*.V9 INSND*.DAT)"

for f in $SHARED; do
    [ -f "build/en/$f" ] && ! cmp -s "build/$f" "build/en/$f" && {
        echo "error: $f differs between the languages" >&2; exit 1; }
done


work=$(mktemp -d build/sd.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$work/EOB/ES" "$work/EOB/EN"
for f in $SHARED EOB.COM LOGO.BIN COVER.BIN; do
    cp "build/$f" "$work/EOB/"
done
for f in $LANGFILES; do
    cp "build/$f" "$work/EOB/ES/"
    cp "build/en/$f" "$work/EOB/EN/"
done
cp "$INITIAL_SAVE" "$work/EOB/ES/"
cp "$INITIAL_SAVE" "$work/EOB/EN/"
mkdir -p build/SD
if [ -e build/SD/EOB ]; then
    mv build/SD/EOB "$work/previous"
fi
if ! mv "$work/EOB" build/SD/EOB; then
    if [ -d "$work/previous" ]; then mv "$work/previous" build/SD/EOB; fi
    exit 1
fi
