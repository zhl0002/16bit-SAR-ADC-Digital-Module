# Run with dc_shell -no_home_init -no_local_init -f <absolute path to this script>.
# SMIC18_DB is an existing typical timing library. SYNTH_OUT must be a new directory.
proc synthesize_cali_logic {} {
    foreach variable {SMIC18_DB SYNTH_OUT} {
        if {![info exists ::env($variable)] || $::env($variable) eq ""} {
            error "Set environment variable $variable before launching DC."
        }
    }
    set project [file dirname [file dirname [file normalize [info script]]]]
    set rtl [file join $project .. 02-RTL-Design rtl cali_logic.v]
    set constraint [file join $project constraints cali_logic_trial_10ns.sdc]
    set db [file normalize $::env(SMIC18_DB)]
    set out [file normalize $::env(SYNTH_OUT)]
    if {![file isfile $db]} { error "Timing library not found: $db" }
    if {[file exists $out]} { error "Choose a new output directory: $out" }

    file mkdir [file join $out work]
    cd $out
    set_app_var target_library [list $db]
    set_app_var link_library [list "*" $db]
    set_svf cali_logic.svf
    define_design_lib WORK -path [file join $out work]
    if {![analyze -format verilog $rtl]} { error "RTL analysis failed" }
    if {![elaborate cali_logic -library WORK]} { error "RTL elaboration failed" }
    if {![link]} { error "Design linking failed" }
    redirect -file check_design_pre.rpt { check_design }
    read_sdc $constraint
    if {[sizeof_collection [get_clocks -quiet cal_clk]] != 1} { error "cal_clk is missing" }
    redirect -file clocks.rpt { report_clock }
    if {![compile -exact_map]} { error "Standard cell mapping failed" }
    set_svf -off

    redirect -file check_design.rpt { check_design }
    redirect -file check_timing.rpt { check_timing }
    redirect -file area.rpt { report_area }
    redirect -file timing_setup_10ns.rpt { report_timing -path full -delay max -max_paths 1 -sort_by group }
    write_file -format verilog -hierarchy -output cali_logic_mapped.v
    write_file -format ddc -hierarchy -output cali_logic.ddc
    write_sdc cali_logic_trial_10ns.sdc
    foreach file {cali_logic_mapped.v cali_logic.ddc cali_logic.svf cali_logic_trial_10ns.sdc} {
        if {![file isfile $file] || [file size $file] == 0} { error "Missing output: $file" }
    }
    puts "SYNTHESIS COMPLETE: $out"
}

if {[catch {synthesize_cali_logic} message]} {
    puts stderr "SYNTHESIS FAILED: $message"
    exit 1
}
exit 0
