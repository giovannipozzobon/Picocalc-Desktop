#!/usr/bin/env bash
#
# The Tang Nano 20K's bitstream, built with Gowin EDA (design.md §3.11,
# docs/fpga/).
#
# Usage:  tools/build-fpga.sh [mirror|linktest|bars480|bars720] [--program | --flash]
#   mirror     the HDMI mirror the shell's `hdmi` talks to (the default)
#   linktest   the QSPI link's test, for checking wiring and speed
#   bars480, bars720   colour bars, to check the HDMI output
# --program loads it into the FPGA's SRAM (lost at power-off), --flash into
# its SPI flash (kept); both need openFPGALoader. Gowin EDA is found under
# /Applications, or set GOWIN_HOME. The bitstream is copied to
# build/fpga/<target>.fs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET=mirror
ARGS=()
for a in "$@"; do
    case "$a" in
        mirror|linktest|bars480|bars720) TARGET="$a" ;;
        *) ARGS+=("$a") ;;
    esac
done

"$ROOT/fpga/gowin/run_synth.sh" "$TARGET" ${ARGS[@]+"${ARGS[@]}"}
FS="$(find "$ROOT/fpga/gowin/work/$TARGET/impl" -name '*.fs' | head -n1)"
mkdir -p "$ROOT/build/fpga"
cp -f "$FS" "$ROOT/build/fpga/$TARGET.fs"
echo "build-fpga.sh: build/fpga/$TARGET.fs"
