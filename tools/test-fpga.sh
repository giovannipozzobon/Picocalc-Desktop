#!/usr/bin/env bash
# The FPGA's testbenches, under Icarus Verilog (brew install icarus-verilog).
# The last one, mirror_core, takes about a minute.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fpga/sim/run_sim.sh" "$@"
