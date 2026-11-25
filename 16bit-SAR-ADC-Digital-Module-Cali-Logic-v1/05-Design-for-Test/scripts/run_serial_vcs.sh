#!/usr/bin/env bash
set -euo pipefail

: "${SMIC18_VERILOG:?Set SMIC18_VERILOG to the local SMIC18 Verilog model}"
library=$(realpath -e -- "$SMIC18_VERILOG")
repo_stage=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
patterns=$(realpath -e -- "${1:-$repo_stage/patterns/cali_logic_stuck_serial.stil}")
out=$(mktemp -d "${TMPDIR:-/tmp}/cali_vcs_serial.XXXXXX")

printf 'Simulation directory: %s\n' "$out"
cd "$out"
python3 "$repo_stage/scripts/prepare_cali_scan_vcs.py" "$patterns" tb_cali_logic_stuck.v
vcs -full64 -sverilog +nospecify -top tb_cali_logic_stuck tb_cali_logic_stuck.v \
    "$repo_stage/netlist/cali_logic_scan.v" "$library" -o simv -l vcs_compile.log
./simv -no_save -l vcs_serial.log
grep -q '^ATPG_SERIAL_PASS ' vcs_serial.log
