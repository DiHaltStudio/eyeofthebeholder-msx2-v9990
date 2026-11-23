#!/bin/sh
# Delegate environment setup and execution to the upgraded run.sh. It changes
# directory, so restore it with the first startup script. openMSX executes
# startup scripts before -command arguments, regardless of their CLI order.
set -eu
EOB_PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
export EOB_PROJECT_DIR
launcher=${OPENMSX_RUN:-$EOB_PROJECT_DIR/../openmsx_v9990_upgraded/run.sh}
if [ ! -x "$launcher" ]; then
    echo "Upgraded openMSX launcher is missing or not executable: $launcher" >&2
    exit 1
fi
exec "$launcher" -script "$EOB_PROJECT_DIR/tools/openmsx_project_dir.tcl" "$@"
