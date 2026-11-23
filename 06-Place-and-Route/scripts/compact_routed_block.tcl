# Compact the routed SMIC18 cali_logic block in a new local working directory.
# Run via icc2_shell -f. Existing reference NDMs must remain resolvable.
# See reports/area_optimization.md for input parameters and validation.
proc required_env {name} {
    if {![info exists ::env($name)] || $::env($name) eq ""} {
        error "Set $name before starting ICC2."
    }
    return $::env($name)
}

proc prepare_working_copy {} {
    set source [file normalize [required_env AREA_SOURCE_NDM]]
    set run [file normalize [required_env AREA_RUN_DIR]]
    set util [required_env AREA_UTIL]
    set margin [required_env AREA_OFFSET]
    set cores [required_env AREA_CORES]
    if {![file isdirectory $source]} {error "Source NDM directory is missing: $source"}
    if {[file exists $run]} {error "Choose a new run directory: $run"}
    if {![string is double -strict $util] || $util <= 0 || $util >= 1} {
        error "AREA_UTIL must be a fraction between 0 and 1."
    }
    if {![string is double -strict $margin] || $margin < 7.5} {
        error "Use at least 7.5 um with this power-ring geometry."
    }
    if {![string is integer -strict $cores] || $cores < 1} {
        error "AREA_CORES must be a positive integer."
    }
    foreach name {AREA_TLU AREA_LAYER_MAP} {
        set ::env($name) [file normalize [required_env $name]]
        if {![file isfile $::env($name)] || ![file readable $::env($name)]} {
            error "Missing or unreadable input: $::env($name)"
        }
    }
    file mkdir $run
    file copy -- $source $run/compact.ndm
    cd $run
}

proc snapshot {stage} {
    save_block -as cali_logic/$stage
    save_lib
    puts "MILESTONE $stage"
    flush stdout
}

proc make_power {core_bbox} {
    foreach {net type} {VDD power VSS ground} {
        if {[sizeof_collection [get_nets -quiet $net]] == 0} {
            if {$type eq "power"} {create_net $net -power} else {create_net $net -ground}
        }
        if {[sizeof_collection [get_ports -quiet $net]] == 0} {
            create_port $net -direction inout -port_type $type
        }
        connect_pg_net -net $net [get_ports $net]
        connect_pg_net -net $net [get_flat_pins -all */$net]
    }
    create_pg_ring_pattern -horizontal_width 2 -vertical_width 2 -horizontal_layer METAL3 -vertical_layer METAL4 -horizontal_spacing 1 -vertical_spacing 1 core_ring
    set_pg_strategy ring_strategy -core -pattern {{name: core_ring} {nets: {VDD VSS}} {offset: {2 2}}}
    compile_pg -strategies ring_strategy
    create_pg_std_cell_conn_pattern std_rail -layers METAL1 -mark_as_follow_pin true
    set_pg_strategy rail_strategy -core -pattern {{name: std_rail} {nets: {VDD VSS}}}
    create_pg_mesh_pattern upper_mesh -layers {
        {{vertical_layer: METAL4} {width: 1.2} {spacing: 3.0} {pitch: 40.0} {offset: 10.0}}
        {{horizontal_layer: METAL5} {width: 1.2} {spacing: 3.0} {pitch: 40.0} {offset: 10.0}}
    }
    set_pg_strategy mesh_strategy -core -pattern {{name: upper_mesh} {nets: {VDD VSS}}} -extension {stop: innermost_ring}
    compile_pg -strategies {rail_strategy mesh_strategy}

    lassign [lindex $core_bbox 0] x_min y_min
    lassign [lindex $core_bbox 1] x_max y_max
    foreach {net portion lower upper} {VDD 0.30 2.0 4.0 VSS 0.70 5.0 7.0} {
        set x [expr {floor($x_min + ($x_max - $x_min) * $portion)}]
        set boundary [list [list $x [expr {$y_max + $lower}]] [list [expr {$x + 6.0}] [expr {$y_max + $upper}]]]
        create_terminal -port [get_ports $net] -layer METAL3 -boundary $boundary
    }
}


proc collect_reports {folder} {
    file mkdir $folder
    redirect -file $folder/legality.rpt {check_legality -verbose}
    redirect -file $folder/routes.rpt {check_routes}
    check_pg_connectivity -check_std_cell_pins one -write_connectivity_file $folder/pg_connectivity.rpt
    redirect -file $folder/pg_drc_console.rpt {check_pg_drc -output $folder/pg_drc.rpt}
    redirect -file $folder/internal_lvs.rpt {check_lvs -checks all -max_errors 0}
    redirect -file $folder/design.rpt {report_design -physical}
    redirect -file $folder/utilization.rpt {report_utilization}
    redirect -file $folder/qor.rpt {report_qor}
    redirect -file $folder/clock_qor.rpt {report_clock_qor -type summary}
    redirect -file $folder/setup.rpt {report_timing -delay_type max -max_paths 10 -significant_digits 4}
    redirect -file $folder/hold.rpt {report_timing -delay_type min -max_paths 10 -significant_digits 4}
    redirect -file $folder/timing_coverage.rpt {check_timing}
    redirect -file $folder/rc.rpt {report_parasitic_parameters}
    redirect -file $folder/tie_ports.rpt {report_net -connections [get_nets {phase2_const_zero weight31_const_zero}]}
}

proc compact_original {} {
    prepare_working_copy
    set_host_options -max_cores $::env(AREA_CORES)
    file mkdir reports output
    open_lib ./compact.ndm
    copy_block -from_block cali_logic/final_routed_10ns -to_block cali_logic/compact_seed_work
    current_block cali_logic/compact_seed_work
    link_block
    set_app_options -name opt.dft.optimize_scan_chain -value false
    set_app_options -name opt.dft.do_repartition -value false
    set clk [get_clocks cal_clk]
    set fillers [get_flat_cells -all -quiet -filter {ref_name =~ FILL*}]
    remove_cells $fillers

    set old_core [get_attribute [get_core_area] bbox]
    set locations {}
    foreach_in_collection cell [get_flat_cells -all] {
        set loc [get_attribute -quiet $cell origin]
        set orient [get_attribute -quiet $cell orientation]
        if {[llength $loc] == 2 && $orient ne ""} {
            lappend locations [list [get_object_name $cell] $loc $orient]
        }
    }
    puts "SEED_LOCATIONS [llength $locations]"
    if {[llength $locations] < 3000} {error "Could not capture the original placement"}
    initialize_floorplan -core_utilization $::env(AREA_UTIL) -core_offset [list $::env(AREA_OFFSET)]
    set core [get_attribute [get_core_area] bbox]
    puts "CORE_BBOX $core"
    make_power $core
    lassign [lindex $old_core 0] old_x old_y
    lassign [lindex $old_core 1] old_x_max old_y_max
    lassign [lindex $core 0] new_x new_y
    lassign [lindex $core 1] new_x_max new_y_max
    set scale_x [expr {($new_x_max-$new_x)/($old_x_max-$old_x)}]
    set scale_y [expr {($new_y_max-$new_y)/($old_y_max-$old_y)}]
    foreach record $locations {
        lassign $record name loc orient
        lassign $loc old_cell_x old_cell_y
        set cx [expr {$new_x+($old_cell_x-$old_x)*$scale_x}]
        set cy [expr {$new_y+($old_cell_y-$old_y)*$scale_y}]
        set_cell_location [get_cells -exact $name] -coordinates [list $cx $cy] -orientation $orient
    }
    set_ignored_layers -min_routing_layer METAL2 -max_routing_layer METAL6
    place_pins -self
    legalize_placement
    connect_pg_net -automatic
    snapshot packed_placed

    read_parasitic_tech -tlup $::env(AREA_TLU) -layermap $::env(AREA_LAYER_MAP) -name pack_seed_par -sanity_check basic
    set_parasitic_parameters -corners typ_trial -early_spec pack_seed_par -late_spec pack_seed_par
    clock_opt -from route_clock -to route_clock
    snapshot packed_clocked
    route_auto -max_detail_route_iterations 20
    redirect -file reports/initial_routes.rpt {check_routes}
    redirect -file reports/initial_qor.rpt {report_qor}
    snapshot packed_routed

    set_app_options -name route_opt.flow.enable_ccd -value true
    set_clock_uncertainty -setup 0.15 $clk
    set_clock_uncertainty -hold 0.10 $clk
    route_opt
    snapshot packed_optimized
    set refs {}
    foreach size {64 32 16 8 4 2 1} {lappend refs smic18_fill/FILL$size}
    create_stdcell_fillers -lib_cells $refs -prefix U_FILL_
    connect_pg_net -automatic
    route_opt
    set_clock_uncertainty -setup 0.0 $clk
    set_clock_uncertainty -hold 0.0 $clk
    connect_pg_net -automatic
    collect_reports reports/final
    snapshot packed_final
    write_def output/cali_logic_routed.def
    puts "MILESTONE CANDIDATE_COMPLETE"
}

if {[catch {compact_original} message options]} {
    puts "FLOW_FAILED $message"
    puts [dict get $options -errorinfo]
    exit 1
}
exit 0
