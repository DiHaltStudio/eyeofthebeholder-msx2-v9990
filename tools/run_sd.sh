#!/bin/sh
# Use a persistent player disk so reopening openMSX preserves both saves.
set -eu
cd "$(dirname "$0")/.."
sd=$2
case "$1" in
    run-msx2) machine=Philips_NMS_8245; set -- -ext ram1mb ;;
    run-turbor) machine=turbor; set -- ;;
    *) exit 2 ;;
esac
player=${EOB_PLAYER_DIR:-.eob-player}
mkdir -p "$player"
player=$(cd "$player" && pwd)
disk=$player/EOB.HDD
exec 9>"$player/run.lock"
if ! flock -n 9; then
    echo "Close the other player session before opening this disk." >&2
    exit 1
fi
if [ ! -f "$disk" ]; then
    boot=$PWD/third_party/dos
    for f in NEXTOR.SYS COMMAND2.COM; do
        if [ ! -f "$boot/$f" ]; then
            echo "Missing third_party/dos/$f. See docs/BUILDING.md." >&2
            exit 1
        fi
    done
    work=$(mktemp -d "$player/setup.XXXXXX")
    trap 'rm -rf -- "$work"' EXIT
    trap 'exit 1' HUP INT TERM
    printf 'MODE 80\r\nCLS\r\nCD \\EOB\r\nEOB\r\n' > "$work/AUTOEXEC.BAT"
    EOB_SD="$sd" EOB_BOOT="$boot" EOB_SETUP="$work" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
        sh tools/openmsx_upgraded.sh -machine C-BIOS_MSX2 \
        -command 'set renderer none; set mute true' -command 'source tools/import_sd.tcl'
    mv "$work/EOB.HDD" "$disk"
fi
sh tools/openmsx_upgraded.sh -machine "$machine" -ext slotexpander "$@" -ext ide -ext gfx9000 -ext moonsound \
    -hda "$disk" -script tools/gfx9000_autovideo.tcl \
    -command 'plug joyporta mouse; set v9990windows false'
