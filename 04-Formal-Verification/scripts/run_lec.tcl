# Run in a clean working directory with fm_shell -f <absolute path to this script>.
# SMIC18_DB points to the synthesis library. LEC_OUT must be a new directory.
proc verify_cali_logic {} {
    foreach name {SMIC18_DB LEC_OUT} {
        if {![info exists ::env($name)] || $::env($name) eq ""} {
            error "Set environment variable $name before launching Formality."
        }
    }

    set stage [file dirname [file dirname [file normalize [info script]]]]
    set root [file dirname $stage]
    set rtl [file join $root 02-RTL-Design rtl cali_logic.v]
    set netlist [file join $root 03-Logic-Synthesis netlist cali_logic_mapped.v]
    set svf [file join $root 03-Logic-Synthesis formality cali_logic.svf]
    set db [file normalize $::env(SMIC18_DB)]
    set out [file normalize $::env(LEC_OUT)]

    foreach input [list $rtl $netlist $svf $db] {
        if {![file isfile $input]} { error "Input file not found: $input" }
    }
    if {[file exists $out]} { error "Choose a new output directory: $out" }

    file mkdir $out
    cd $out
    set ::synopsys_auto_setup true
    if {![set_svf $svf]} { error "Could not read the synthesis guidance." }

    if {![read_verilog -r $rtl] || ![set_top r:/WORK/cali_logic]} {
        error "Could not read and link the reference RTL."
    }
    if {![read_db -technology_library $db]} {
        error "Could not read the technology library."
    }
    if {![read_verilog -i $netlist] || ![set_top i:/WORK/cali_logic]} {
        error "Could not read and link the mapped implementation."
    }
    if {![match]} { error "Compare point matching failed." }

    set equivalent [verify]
    report_status > verification.rpt
    if {![save_session cali_logic.fss]} { error "Could not save the Formality session." }
    if {!$equivalent} { error "Equivalence was not proved. See $out/verification.rpt." }
    puts "EQUIVALENCE VERIFIED: $out/verification.rpt"
}

if {[catch {verify_cali_logic} message]} {
    puts stderr "LEC FAILED: $message"
    exit 1
}
exit 0
