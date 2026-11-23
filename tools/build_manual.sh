#!/bin/sh
# Build both editable LaTeX manuals, twice for the contents. Use the local
# toolchain or the already installed DiHalt LaTeX image; never pull an image.
set -eu
cd "$(dirname "$0")/.."
[ "$#" -gt 0 ] || set -- es en
for lang in "$@"; do
    case "$lang" in es|en) ;; *) echo "Unsupported manual language: $lang" >&2; exit 2;; esac
done
mkdir -p build/texmf-var
if command -v pdflatex >/dev/null 2>&1; then
    cd docs/manual
    for lang in "$@"; do
        for pass in 1 2; do
            pdflatex -halt-on-error -interaction=nonstopmode -jobname="manual-$lang" \
                "\def\manlang{$lang}\input{manual}" > "../../build/manual-$lang-build.log"
        done
    done
elif command -v podman >/dev/null 2>&1 && podman image exists localhost/heroquest-manual-latex:bookworm; then
    podman run --rm --userns=keep-id -e TEXMFVAR=/work/build/texmf-var \
        -v "$PWD:/work:rw" -w /work/docs/manual localhost/heroquest-manual-latex:bookworm \
        sh -c 'for lang do for pass in 1 2; do
            pdflatex -halt-on-error -interaction=nonstopmode -jobname="manual-$lang" \
                "\def\manlang{$lang}\input{manual}" > "/work/build/manual-$lang-build.log" || exit 1
        done; done' sh "$@"
else
    echo "Install pdflatex (Helvetica, longtable, geometry, microtype, graphics and hyperref)." >&2
    exit 1
fi
