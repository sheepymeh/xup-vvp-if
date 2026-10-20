source [file join [file dirname [info script]] board.tcl]

namespace eval ::hardware {}

proc ::hardware::connect {{probes ""}} {
    open_hw_manager
    connect_hw_server -url [::board::setting HW_SERVER_URL localhost:3121]
    set pattern [::board::setting JTAG_TARGET *Digilent*]
    set targets [get_hw_targets -quiet $pattern]
    if {[llength $targets] != 1} {
        error "Expected one JTAG target matching $pattern: $targets"
    }
    open_hw_target [lindex $targets 0]
    set devices [get_hw_devices]
    if {[llength $devices] != 1} {
        error "Expected one FPGA: $devices"
    }
    set device [lindex $devices 0]
    if {[get_property PART $device] ne $::board::hw_part} {
        error "Unexpected FPGA identity: [get_property PART $device]"
    }
    if {$probes ne ""} {
        set_property PROBES.FILE $probes $device
    }
    return $device
}

proc ::hardware::program {device bitfile} {
    set_property PROGRAM.FILE $bitfile $device
    puts "PROGRAM_MODE=volatile_JTAG_SRAM"
    program_hw_devices $device
}

proc ::hardware::close {} {
    close_hw_target
    disconnect_hw_server
    close_hw_manager
}
