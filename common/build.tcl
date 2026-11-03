source [file join [file dirname [info script]] board.tcl]

namespace eval ::build {}

proc ::build::create_vio {name inputs outputs} {
    create_ip -name vio -vendor xilinx.com -library ip -module_name $name
    set ip [get_ips $name]
    set params [list CONFIG.C_NUM_PROBE_IN [llength $inputs] \
        CONFIG.C_NUM_PROBE_OUT [llength $outputs]]
    foreach direction {IN OUT} widths [list $inputs $outputs] {
        set index 0
        foreach width $widths {
            lappend params CONFIG.C_PROBE_${direction}${index}_WIDTH $width
            incr index
        }
    }
    set_property -dict $params $ip
    generate_target all $ip
}

proc ::build::disable_optional_reports {} {
    foreach run [get_runs] {
        foreach report [get_report_configs -of_objects $run] {
            set_property IS_ENABLED false $report
        }
    }
}

proc ::build::run {name args} {
    set run [get_runs $name]
    if {[get_property PROGRESS $run] eq "100%"} {
        return
    }
    launch_runs $run {*}$args -jobs 1
    wait_on_run $run
    if {[get_property PROGRESS $run] ne "100%"} {
        error "$name failed: [get_property STATUS $run]"
    }
}

proc ::build::check_synchronizers {} {
    set pins [get_pins -hier -filter {NAME =~ */sync_first_reg*/D}]
    if {[llength $pins] == 0} {
        error "Missing shared synchronizer first-stage pins"
    }
    puts "CDC_FIRST_STAGE_PINS=[llength $pins]"
}

proc ::build::check_implementation {reports} {
    file mkdir $reports
    report_route_status -file [file join $reports route.rpt]
    report_drc -file [file join $reports drc.rpt]
    report_timing_summary -file [file join $reports timing.rpt]
    if {![report_route_status -boolean_check ROUTED_FULLY]} {
        error "Unrouted nets"
    }
    foreach delay {max min} {
        set paths [get_timing_paths -delay_type $delay -max_paths 1]
        if {[llength $paths] != 1} {
            error "Missing $delay timing path"
        }
        set slack [get_property SLACK [lindex $paths 0]]
        if {$slack < 0} {
            error "$delay timing failed: slack=$slack"
        }
        puts "TIMING $delay worst slack: $slack ns"
    }
}
