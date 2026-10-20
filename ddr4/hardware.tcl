set root [file dirname [file normalize [info script]]]
set out [file join $root build]

set mode [lindex $argv 0]
set selection [string toupper [lindex $argv 1]]
if {($mode in {program diagnose} && [llength $argv] != 1) ||
    ($mode eq "test" && ([llength $argv] != 2 || $selection ni {DIMM0 DIMM1 BOTH})) ||
    $mode ni {program diagnose test}} {
    error "Usage: hardware.tcl program | diagnose | test DIMM0|DIMM1|both"
}

source [file join $root .. common hardware.tcl]
source [file join $root .. common vio.tcl]
source [file join $out probes.tcl]

proc ready {} {
    refresh_hw_vio $::vio
    set status [vio::read $::probe]
    foreach dimm $::selected {
        if {!(($status >> $dimm) & 1) || (($status >> ($dimm + 2)) & 1)} {
            return 0
        }
    }
    return 1
}

set device [hardware::connect [file join $out ddr4_test.ltx]]
try {
    if {$mode eq "program"} {
        hardware::program $device [file join $out ddr4_test.bit]
        puts "PROGRAM_COMPLETE"
        return
    }
    refresh_hw_device $device
    set resolved [vio::resolve $device $vio_map]
    set vio [dict get $resolved ddr4_bd_i/status/inst/vio core]
    set pins [dict get $resolved ddr4_bd_i/status/inst/vio pins]
    set probe [dict get $pins probe_in0]

    if {$mode eq "diagnose"} {
        foreach mig [get_hw_migs -of_objects $device] {
            refresh_hw_mig $mig
            report_hw_mig $mig
        }
        refresh_hw_vio $vio
        set startup [vio::read [dict get $pins probe_in1]]
        puts "STARTUP,EOS:[expr {$startup & 1}],DCI_LOCKED:[expr {($startup >> 1) & 1}],DCI_RESET:[expr {($startup >> 2) & 1}],SYS_RESET:[expr {($startup >> 3) & 1}]"
        puts "CALIBRATION_STATUS=[get_property INPUT_VALUE $probe]"

        set samples {}
        for {set sample 0} {$sample < 2} {incr sample} {
            set start [clock microseconds]
            refresh_hw_vio $vio
            set values {}
            foreach port {probe_in2 probe_in3 probe_in4} {
                lappend values [vio::read [dict get $pins $port]]
            }
            lappend samples [list [expr {($start + [clock microseconds]) / 2}] $values]
            if {$sample == 0} {after 2000}
        }
        lassign [lindex $samples 0] time0 counters0
        lassign [lindex $samples 1] time1 counters1
        foreach name {DIMM0_UI DIMM1_UI MONITOR} scale {1048576 1048576 1} before $counters0 after $counters1 {
            set delta [expr {($after - $before) & 0xffffffff}]
            set mhz [expr {double($delta) * $scale / ($time1 - $time0)}]
            puts [format "CLOCK=%s,estimated_MHz:%.3f" $name $mhz]
            if {$delta == 0} {error "No clock activity for $name"}
        }
        if {$startup != 3} {error "Startup sequence incomplete: $startup"}
        puts "DIAGNOSTICS_COMPLETE"
        return
    }

    set masters [dict create]
    foreach master [get_hw_axis -of_objects $device] {
        set cell [get_property CELL_NAME $master]
        if {[regexp {(^|/)jtag_axi_([01])(/|$)} $cell -> prefix dimm]} {
            dict set masters $dimm $master
        }
    }
    if {$selection eq "BOTH"} {
        set selected {0 1}
    } else {
        set selected [list [string index $selection end]]
    }
    foreach dimm $selected {
        if {![dict exists $masters $dimm]} {
            error "Missing AXI master for DIMM$dimm, program matching image"
        }
    }

    # Avoid AXI requests to an uncalibrated DIMM, UI clocks may be unavailable
    set deadline [expr {[clock milliseconds] + 60000}]
    while {![ready]} {
        if {[clock milliseconds] >= $deadline} {
            error "Calibration timed out for $selection, status=[get_property INPUT_VALUE $probe]"
        }
        after 250
    }
    puts "CALIBRATION=PASS,selection:$selection"

    # Write every word before reading, distinct DIMM patterns expose memory aliasing
    set expected [dict create]
    foreach dimm $selected {
        set offset 0
        foreach pattern {A5A55A5A 01234567 89ABCDEF 5AA5A55A} {
            set address [format %08X [expr {0x1000 + $offset}]]
            scan $pattern %x value
            set value [format %08X [expr {$value ^ ($dimm ? 0xffffffff : 0)}]]
            dict set expected $dimm,$address $value
            incr offset 4
        }
    }

    foreach operation {WRITE READ} {
        dict for {location value} $expected {
            if {![ready]} {
                error "Selected DIMM lost calibration or entered UI reset"
            }
            lassign [split $location ,] dimm address
            set args [list -type $operation -address $address -len 1]
            if {$operation eq "WRITE"} {
                lappend args -data $value
            }
            create_hw_axi_txn memory_word [dict get $masters $dimm] {*}$args
            set txn [get_hw_axi_txns memory_word]
            run_hw_axi $txn
            if {$operation eq "READ"} {
                set actual [string trim [get_property DATA $txn]]
                if {![string equal -nocase $actual $value]} {
                    error "DIMM$dimm at $address: expected $value, read $actual"
                }
                puts "WORD=PASS,DIMM$dimm,address:$address,data:$actual"
            }
            delete_hw_axi_txn $txn
        }
    }
    if {![ready]} {
        error "Selected DIMM lost calibration or entered UI reset"
    }
    puts "RESULT=PASS,selection:$selection,bytes_per_DIMM:16"
} finally {
    hardware::close
}
