# Run with icc2_shell -f from a scratch directory.
# Set PNR_NDM to the final design NDM, PNR_REPORT_DIR to a new directory,
# and optionally PNR_BLOCK to a block label in that library.
foreach name {PNR_NDM PNR_REPORT_DIR} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        error "Set $name before starting ICC2."
    }
}
set ndm [file normalize $::env(PNR_NDM)]
set reports [file normalize $::env(PNR_REPORT_DIR)]
if {![file exists $ndm]} { error "Design library is missing: $ndm" }
if {[file exists $reports]} { error "Choose a new report directory: $reports" }
set block cali_logic/final_routed_10ns
if {[info exists ::env(PNR_BLOCK)] && $::env(PNR_BLOCK) ne ""} {
    set block $::env(PNR_BLOCK)
}
open_lib $ndm
open_block $block
current_block $block
link_block
file mkdir $reports

redirect -file $reports/legality.rpt {check_legality -verbose}
redirect -file $reports/routes.rpt {check_routes}
check_pg_connectivity -check_std_cell_pins one \
    -write_connectivity_file $reports/pg_connectivity.rpt
redirect -file $reports/pg_drc_console.rpt {
    check_pg_drc -output $reports/pg_drc.rpt
}
redirect -file $reports/internal_lvs.rpt {check_lvs -checks all -max_errors 0}
redirect -file $reports/clock_qor.rpt {report_clock_qor -type summary}
redirect -file $reports/setup.rpt {
    report_timing -delay_type max -max_paths 10 -significant_digits 4
}
redirect -file $reports/hold.rpt {
    report_timing -delay_type min -max_paths 10 -significant_digits 4
}
redirect -file $reports/qor.rpt {report_qor}
redirect -file $reports/timing_coverage.rpt {check_timing}
redirect -file $reports/rc.rpt {report_parasitic_parameters}
puts "Inspect the generated reports in $reports."
