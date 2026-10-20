set root [file dirname [file normalize [info script]]]
set out [file join $root build]

# ---- Command selection ----
set mode [lindex $argv 0]
set selection [string toupper [lindex $argv 1]]
if {($mode eq "program" && [llength $argv] != 1) ||
    ($mode eq "test" && ([llength $argv] != 2 || $selection ni {DIMM0 DIMM1 BOTH})) ||
    $mode ni {program test}} {
    error "Usage: hardware.tcl program | test DIMM0|DIMM1|both"
}

# ---- Board identity and volatile programming ----
open_hw_manager
connect_hw_server
set targets [get_hw_targets]
if {[llength $targets] != 1} {
    error "Unexpected JTAG targets: $targets"
}
open_hw_target [lindex $targets 0]
set devices [get_hw_devices]
if {[llength $devices] != 1} {
    error "Expected one FPGA: $devices"
}
set device [lindex $devices 0]
if {[get_property PART $device] ne "xcvu13p"} {
    error "Unexpected FPGA identity"
}
set_property PROBES.FILE [file join $out ddr4_test.ltx] $device
if {$mode eq "program"} {
    set_property PROGRAM.FILE [file join $out ddr4_test.bit] $device
    puts "PROGRAM_MODE=volatile_JTAG_SRAM"
    program_hw_devices $device
    close_hw_target
    close_hw_manager
    puts "PROGRAM_COMPLETE"
    exit
}
refresh_hw_device $device

# ---- Independent AXI masters and always-clocked calibration monitor ----
set masters [dict create]
foreach master [get_hw_axis -of_objects $device] {
    set cell [get_property CELL_NAME $master]
    if {[regexp {(^|/)jtag_axi_([01])(/|$)} $cell -> prefix dimm]} {
        if {[dict exists $masters $dimm]} {
            error "Duplicate AXI master for DIMM$dimm"
        }
        dict set masters $dimm $master
    }
}
set vios [get_hw_vios -of_objects $device]
if {[llength $vios] != 1} {
    error "Expected one DDR4 status VIO, program matching image"
}
set vio [lindex $vios 0]
set probes [get_hw_probes -of_objects $vio]
if {[llength $probes] != 1} {
    error "Expected one four-bit DDR4 status probe"
}
set probe [lindex $probes 0]
set_property INPUT_VALUE_RADIX HEX $probe

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

proc ready {} {
    refresh_hw_vio $::vio
    set raw [string trim [get_property INPUT_VALUE $::probe]]
    if {![regexp -nocase {^[0-9a-f]$} $raw]} {
        error "Invalid calibration status: $raw"
    }
    scan $raw %x status
    foreach dimm $::selected {
        if {!(($status >> $dimm) & 1) || (($status >> ($dimm + 2)) & 1)} {
            return 0
        }
    }
    return 1
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

# ---- Existing four-word smoke test ----
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
close_hw_target
disconnect_hw_server
close_hw_manager
