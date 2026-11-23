# Run with fm_shell -f from a scratch directory.
# Set SMIC18_DB, PNR_SCAN_NETLIST, PNR_ROUTED_NETLIST and PNR_LEC_DIR.
proc required_path {name} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        error "Set $name before starting Formality."
    }
    return [file normalize $::env($name)]
}
set library [required_path SMIC18_DB]
set scan [required_path PNR_SCAN_NETLIST]
set routed [required_path PNR_ROUTED_NETLIST]
set reports [required_path PNR_LEC_DIR]
foreach path [list $library $scan $routed] {
    if {![file isfile $path] || ![file readable $path]} {
        error "Missing or unreadable input: $path"
    }
}
if {$scan eq $routed} { error "Provide two different netlists." }
if {[file exists $reports]} { error "Choose a new report directory: $reports" }
file mkdir $reports

set synopsys_auto_setup true
read_db $library
read_verilog -container r -libname WORK -05 $scan
set_top r:/WORK/cali_logic
read_verilog -container i -libname WORK -05 $routed
set_top i:/WORK/cali_logic
match
set passed [verify]
report_status > $reports/equivalence.rpt
report_unmatched_points > $reports/equivalence_unmatched.rpt
report_failing_points > $reports/equivalence_failed.rpt
report_black_boxes > $reports/equivalence_blackboxes.rpt
if {!$passed} { exit 1 }
exit 0
