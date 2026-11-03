#!/usr/bin/env bash
#
# PicoCalc HDMI Mirror - sintesi con Gowin EDA su macOS (adattato da J20K)
#
# Uso:  fpga/gowin/run_synth.sh <target> [--program | --flash]
#   target:  bars720 | bars480 | linktest | mirror
#
# Il bitstream finisce in fpga/gowin/work/<target>/impl/pnr/<top>.fs
# --program carica nella SRAM (volatile), --flash nella flash SPI (persistente).
# Gowin EDA e' cercato in /Applications; per forzarlo: export GOWIN_HOME=...

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # .../fpga
WORK="$ROOT/gowin/work"
DEVICE_NAME="GW2AR-18C"
DEVICE="GW2AR-LV18QN88C8/I7"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m  XX\033[0m %s\n' "$*" >&2; }

TARGET=""; PROGRAM=0; FLASH=0
while [ $# -gt 0 ]; do
    case "$1" in
        --program) PROGRAM=1; shift ;;
        --flash)   PROGRAM=1; FLASH=1; shift ;;
        bars720|bars480|linktest|mirror) TARGET="$1"; shift ;;
        *) fail "argomento sconosciuto: $1"; exit 1 ;;
    esac
done
[ -n "$TARGET" ] || { fail "specifica un target: bars720 | bars480 | linktest | mirror"; exit 1; }

case "$TARGET" in
    bars720) TOP="pm_bars_720p"; CSTS="base_hdmi.cst" ; SRCS=(rtl/video/pm_bars.v rtl/video/j20k_*.v rtl/top/pm_bars_top.v) ;;
    bars480) TOP="pm_bars_480p"; CSTS="base_hdmi.cst" ; SRCS=(rtl/video/pm_bars.v rtl/video/j20k_*.v rtl/top/pm_bars_top.v) ;;
    mirror) TOP="pm_mirror_top"; CSTS="base_hdmi.cst link_qspi.cst uart_tx.cst"
            SRCS=(rtl/common/pm_pll_sdram.v rtl/common/uart_tx.v rtl/common/pm_report.v rtl/link/qspi_rx.v rtl/lcd/cmd_decoder.v rtl/lcd/scroll_map.v "rtl/mem/*.v" "rtl/video/j20k_*.v" rtl/video/mirror_video.v rtl/top/pm_mirror_core.v rtl/top/pm_mirror_top.v) ;;
    linktest) TOP="pm_link_test_top"; CSTS="base_min.cst link_qspi.cst"
              SRCS=(rtl/common/pm_pll_sys.v rtl/common/uart_tx.v rtl/common/pm_report.v rtl/link/qspi_rx.v rtl/link/lfsr_check.v rtl/top/pm_link_test_top.v) ;;
esac

find_gw_sh() {
    if [ -n "${GOWIN_HOME:-}" ] && [ -x "$GOWIN_HOME/IDE/bin/gw_sh" ]; then echo "$GOWIN_HOME/IDE/bin/gw_sh"; return; fi
    command -v gw_sh 2>/dev/null && return
    find /Applications ~/Applications -maxdepth 7 -type f -name gw_sh -perm -u+x 2>/dev/null | head -n1
}
GW_SH="$(find_gw_sh || true)"
[ -n "$GW_SH" ] || { fail "gw_sh non trovato (imposta GOWIN_HOME)"; exit 1; }
info "gw_sh: $GW_SH"

# Le librerie di Gowin stanno una directory sopra bin/: senza queste variabili
# gw_sh carica le Qt di sistema e va in errore.
GOWIN_LIB="$(dirname "$(dirname "$GW_SH")")/lib"
if [ -d "$GOWIN_LIB" ]; then
    export DYLD_LIBRARY_PATH="$GOWIN_LIB${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    export DYLD_FRAMEWORK_PATH="$GOWIN_LIB${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
fi

DIR="$WORK/$TARGET"; rm -rf "$DIR"; mkdir -p "$DIR"
# Gowin legge un solo .cst: i vincoli del target vengono uniti in un file
: > "$DIR/pins.cst"
for c in $CSTS; do cat "$ROOT/constraints/$c" >> "$DIR/pins.cst"; echo >> "$DIR/pins.cst"; done
# FILT=n ./run_synth.sh linktest: lunghezza del filtro anti-glitch (default 3)
if [ -n "${FILT:-}" ] && [ "$TARGET" = linktest ]; then
    sed "s/\\.FILT(3)/.FILT($FILT)/" "$ROOT/rtl/top/pm_link_test_top.v" > "$DIR/pm_link_test_top.v"
    for i in "${!SRCS[@]}"; do
        [ "${SRCS[$i]}" = rtl/top/pm_link_test_top.v ] && SRCS[$i]="gowin/work/linktest/pm_link_test_top.v"
    done
    info "filtro anti-glitch FILT=$FILT"
fi
{
    echo "set_device -name $DEVICE_NAME $DEVICE"
    echo "add_file $DIR/pins.cst"
    echo "add_file $ROOT/constraints/pico_tang20k.sdc"
    for g in "${SRCS[@]}"; do for f in $ROOT/$g; do echo "add_file $f"; done; done
    echo "set_option -top_module $TOP"
    echo "set_option -output_base_name $TOP"
    echo "set_option -synthesis_tool gowinsynthesis"
    echo "set_option -verilog_std sysv2017"
    echo "set_option -use_mspi_as_gpio 1"
    echo "set_option -use_sspi_as_gpio 1"
    echo "set_option -use_ready_as_gpio 1"
    echo "set_option -use_done_as_gpio 1"
    echo "set_option -gen_text_timing_rpt 1"
    echo "run all"
} > "$DIR/run.tcl"

info "sintesi $TARGET (top $TOP)"
( cd "$DIR" && "$GW_SH" run.tcl ) > "$DIR/gw_sh.log" 2>&1 || {
    fail "gw_sh in errore, ultime righe di $DIR/gw_sh.log:"; tail -n 30 "$DIR/gw_sh.log" >&2; exit 1; }
ok "sintesi e place&route completati"

FS="$(find "$DIR/impl" -name '*.fs' | head -n1)"
[ -n "$FS" ] && ok "bitstream: ${FS#$ROOT/}" || { fail "bitstream non trovato"; exit 1; }

if [ "$PROGRAM" -eq 1 ]; then
    command -v openFPGALoader >/dev/null || { fail "brew install openfpgaloader"; exit 1; }
    if [ "$FLASH" -eq 1 ]; then openFPGALoader -b tangnano20k -f "$FS"
    else                        openFPGALoader -b tangnano20k    "$FS"; fi
fi
