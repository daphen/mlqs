#!/usr/bin/env bash
# Refresh the vendored QsLib snapshot from the live design system.
# The snapshot ships in the repo so outside installs work standalone;
# a local ~/.local/share/qml/QsLib always takes precedence at runtime.
set -euo pipefail
SRC="$HOME/nixos/dotfiles/qslib/.local/share/qml/QsLib"
DST="$(dirname "$0")/ui/vendor/QsLib"
mkdir -p "$DST"
rsync -a --delete "$SRC/" "$DST/"
echo "vendored $(ls "$DST" | wc -l) entries ($(ls "$DST/icons" | wc -l) icons)"
