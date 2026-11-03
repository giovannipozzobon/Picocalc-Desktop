#!/usr/bin/env bash
# Esegue tutti i testbench (Icarus Verilog: brew install icarus-verilog).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT="$(mktemp -d)"
rc=0
run() { # nome tb sorgenti...
    local n="$1"; shift
    iverilog -g2012 -o "$OUT/$n.vvp" "$@" && vvp "$OUT/$n.vvp" | grep -E "PASS|FAIL|ERR" || rc=1
}
run qspi_rx     qspi_rx_tb.v     ../rtl/link/qspi_rx.v
run qspi_glitch qspi_glitch_tb.v ../rtl/link/qspi_rx.v
run scroll_map  scroll_map_tb.v  ../rtl/lcd/scroll_map.v
run cmd_decoder cmd_decoder_tb.v ../rtl/lcd/cmd_decoder.v
run vtiming     vtiming_tb.v     ../rtl/video/j20k_vtiming.v
run link_test   link_test_tb.v   ../rtl/link/qspi_rx.v ../rtl/link/lfsr_check.v
run mirror_core mirror_core_tb.v sdram_model.v ../rtl/top/pm_mirror_core.v ../rtl/link/qspi_rx.v ../rtl/lcd/cmd_decoder.v ../rtl/lcd/scroll_map.v ../rtl/mem/*.v ../rtl/video/j20k_vtiming.v ../rtl/video/mirror_video.v   # ~1 min
exit $rc
