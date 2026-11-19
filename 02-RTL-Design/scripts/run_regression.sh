#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
vcs=${VCS_BIN:-vcs}
mkdir -p "$root/runs"
out=$(mktemp -d "$root/runs/regression.XXXXXXXX")
printf 'Regression outputs: %s\n' "$out"

for top in tb_cali_logic tb_cali_b6 tb_cali_b6_mismatch tb_cali_full \
           tb_cali_b6_offset tb_cali_full_repeat tb_cali_full_latency; do
    build="$out/build/$top"
    mkdir -p "$build"
    (
        cd "$build"
        "$vcs" -full64 -sverilog -debug_access+all -kdb -timescale=1ns/1ps \
            -top "$top" "$root/rtl/cali_logic.v" "$root/tb/$top.sv" \
            -o simv -l compile.log > compile.console.log 2>&1 && test -x simv
    ) || { tail -n 35 "$build/compile.console.log"; exit 1; }

    case "$top" in
        tb_cali_logic) pass='PASS: control interface tests, 90233 checks' ;;
        tb_cali_b6) pass='PASS: b6 ideal calibration' ;;
        tb_cali_b6_mismatch) pass='PASS: b6 mismatch calibration' ;;
        tb_cali_full) pass='PASS: full-flow reference consistency' ;;
        tb_cali_b6_offset) pass='PASS: b6 offset cancellation' ;;
        tb_cali_full_repeat) pass='PASS: repeated full calibration and reset recovery' ;;
        tb_cali_full_latency) pass='PASS: variable comparator latency and reset recovery' ;;
    esac
    settings=(default)
    if [[ $top == tb_cali_b6_offset ]]; then settings=(0 8 -8); fi
    for setting in "${settings[@]}"; do
        run="$out/runs/$top/$setting"
        mkdir -p "$run"
        options=()
        if [[ $setting != default ]]; then options=("+CMP_OFFSET=$setting"); fi
        (
            cd "$run"
            "$build/simv" -no_save "${options[@]}" -l sim.log > sim.console.log 2>&1 &&
                grep -Fq "$pass" sim.log && grep -Fq '$finish called' sim.log &&
                ! grep -Eq '^(Fatal|Error)(:|-|\[)' sim.log &&
                { [[ $setting == default ]] || grep -Fq "comparator offset = $setting W0" sim.log; }
        ) || { tail -n 40 "$run/sim.console.log"; exit 1; }
        printf 'PASS %s (%s)\n' "$top" "$setting"
    done
done
