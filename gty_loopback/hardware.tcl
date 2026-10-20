set root [file dirname [file normalize [info script]]]
set out [file join $root build]

# ---- Command arguments and connector mapping ----
set mode [lindex $argv 0]
if {$mode ni {program test external} ||
    ($mode ne "external" && [llength $argv] != 1) ||
    ($mode eq "external" && [llength $argv] < 2)} {
    error {Usage: hardware.tcl program|test|external PORT[:PEER] ...}
}

set ports [dict create \
    QSFP0 {233} \
    QSFP1 {232} \
    QSFP2 {229} \
    QSFP3 {228} \
    SLIMSAS1 {129 133} \
    SLIMSAS2 {120 121} \
]
set names [dict create]
set channel_ports [dict create]
dict for {port quads} $ports {
    set offset 0
    foreach quad $quads {
        for {set lane 0} {$lane < 4} {incr lane} {
            dict set names $quad,$lane "$port.[expr {$offset + $lane}](q$quad/lane$lane)"
            dict set channel_ports $quad,$lane $port
        }
        incr offset 4
    }
}

# A bare port means self-loop, a pair records both traffic directions
set peers [dict create]
if {$mode eq "external"} {
    foreach link [lrange $argv 1 end] {
        set ends [split [string toupper $link] :]
        if {[llength $ends] == 1} {
            lappend ends [lindex $ends 0]
        }
        if {[llength $ends] != 2} {
            error "Invalid connection: $link"
        }
        lassign $ends left right
        foreach port $ends {
            if {![dict exists $ports $port]} {
                error "Unknown port: $port"
            }
            if {[dict exists $peers $port]} {
                error "Port specified more than once: $port"
            }
        }
        if {[llength [dict get $ports $left]] != [llength [dict get $ports $right]]} {
            error "Connection needs equal lane counts: $link"
        }
        dict set peers $left $right
        dict set peers $right $left
    }
}

# Reject probe maps from the old image before connecting to hardware
source [file join $out probes.tcl]
dict for {quad pins} $probe_names {
    if {![dict exists $pins probe_out10]} {
        error "Old VIO interface on quad $quad, rebuild the image"
    }
}

# ---- Hardware connection and programming ----
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
set dev [lindex $devices 0]
if {[get_property PART $dev] ne "xcvu13p"} {
    error "Unexpected FPGA identity"
}
set_property PROBES.FILE [file join $out all_channels.ltx] $dev
if {$mode eq "program"} {
    set_property PROGRAM.FILE [file join $out all_channels.bit] $dev
    puts "PROGRAM_MODE=volatile_JTAG_SRAM"
    program_hw_devices $dev
    after 3000
}
refresh_hw_device $dev
set vios [get_hw_vios -quiet -of_objects $dev]
if {[llength $vios] != 8} {
    error "Expected eight VIO cores, got $vios"
}

# Resolve VIO net names from the generated probe map
set cores [dict create]
foreach quad [dict keys $probe_names] {
    set found {}
    foreach vio $vios {
        if {[get_property CELL_NAME $vio] eq "q${quad}_control/vio"} {
            lappend found $vio
        }
    }
    if {[llength $found] != 1} {
        error "Missing VIO for quad $quad"
    }
    dict set cores $quad [lindex $found 0]
    dict for {port net} [dict get $probe_names $quad] {
        set probes [get_hw_probes -quiet $net -of_objects [lindex $found 0]]
        if {[llength $probes] != 1} {
            error "Missing probe $quad $port $net"
        }
        dict set mapped $quad $port [lindex $probes 0]
        if {[string match probe_in* $port]} {
            set_property INPUT_VALUE_RADIX HEX [lindex $probes 0]
        } else {
            set_property OUTPUT_VALUE_RADIX HEX [lindex $probes 0]
        }
    }
}

# ---- VIO access ----
# Probe indices are defined by quad_control.v and build.tcl
# Inputs: 0 ready, 1 PRBS lock, 2 sticky errors, 3 interruptions
#         4 DRP data, 5 DRP done, 6 DRP timeout, 7 DRP busy
# Outputs: 0 full reset, 1 RX reset, 2 RX PMA reset, 3 loopback mode
#          4 counter reset, 5 clear faults, 6 measure, 7 lane error toggles
#          8 DRP address, 9 DRP request, 10 RX polarity
# Output changes commit per quad
proc output_one {quad index value} {
    set_property OUTPUT_VALUE [format %X $value] [dict get $::mapped $quad probe_out$index]
    commit_hw_vio [dict get $::cores $quad]
}

proc output_all {index value} {
    dict for {quad vio} $::cores {
        set_property OUTPUT_VALUE [format %X $value] [dict get $::mapped $quad probe_out$index]
    }
    dict for {quad vio} $::cores {
        commit_hw_vio $vio
    }
}

proc input_value {quad index} {
    set raw [string trim [get_property INPUT_VALUE [dict get $::mapped $quad probe_in$index]]]
    regsub -nocase {^0x} $raw {} raw
    if {![regexp -nocase {^[0-9a-f]+$} $raw]} {
        error "Invalid VIO value: $raw"
    }
    return [expr "0x$raw"]
}

proc pulse {index} {
    output_all $index 1
    after 100
    output_all $index 0
}

# ---- Qualification and native error counters ----
# Unselected quads never contribute to pass/fail checks
proc status {label clean} {
    set qualified 1
    dict for {quad vio} $::cores {
        refresh_hw_vio $vio
        set ready [input_value $quad 0]
        set locked [input_value $quad 1]
        set errors [input_value $quad 2]
        set interrupted [input_value $quad 3]
        if {$ready != 15 || $locked != 15} {
            set qualified 0
        }
        if {$clean && ($errors || $interrupted)} {
            error "Fault at $label on quad $quad: errors=$errors interrupted=$interrupted"
        }
    }
    return $qualified
}

proc qualify {} {
    for {set attempt 0} {$attempt < 50} {incr attempt} {
        after 100
        if {[status QUALIFY 0]} {
            return
        }
    }
    dict for {quad vio} $::cores {
        refresh_hw_vio $vio
        puts "NOT_QUALIFIED=quad:$quad,ready:[input_value $quad 0],locked:[input_value $quad 1]"
    }
    error "Selected channels did not all acquire ready/PRBS lock, check cabling and module enables"
}

# Each selected quad completes four independent DRP reads
proc read_words {address} {
    output_all 8 $address
    after 10
    output_all 9 1
    after 10
    output_all 9 0
    set result [dict create]
    for {set attempt 0} {$attempt < 100} {incr attempt} {
        dict for {quad vio} $::cores {
            refresh_hw_vio $vio
            if {[input_value $quad 6]} {
                error "DRP timeout on quad $quad"
            }
            if {[input_value $quad 5] == 15 && [input_value $quad 7] == 0} {
                dict set result $quad [input_value $quad 4]
            }
        }
        if {[dict size $result] == [dict size $::cores]} {
            return $result
        }
        after 10
    }
    error "DRP read did not complete on every selected channel"
}

# Native counter reads require low word before high word
proc counters {} {
    set low [read_words 0x25e]
    set high [read_words 0x25f]
    set result [dict create]
    foreach quad [dict keys $::cores] {
        for {set lane 0} {$lane < 4} {incr lane} {
            set lo [expr {([dict get $low $quad] >> (16*$lane)) & 0xffff}]
            set hi [expr {([dict get $high $quad] >> (16*$lane)) & 0xffff}]
            dict set result $quad,$lane [expr {($hi << 16) | $lo}]
        }
    }
    return $result
}

proc require_zero {counts} {
    dict for {channel count} $counts {
        if {$count != 0} {
            error "Nonzero PRBS count on [dict get $::names $channel]: $count"
        }
    }
}

# Clear prior faults before each lane marker or soak
proc start_measurement {} {
    output_all 6 0
    output_all 5 1
    pulse 4
    qualify
    require_zero [counters]
    output_all 5 0
    after 100
    output_all 6 1
    if {![status START 1]} {
        error "Selected channels not qualified at start"
    }
}

# ---- Lane discovery ----
# Identify routes by changing only one transmitter at a time
proc discover {} {
    set routes [dict create]
    foreach quad [dict keys $::cores] {
        for {set lane 0} {$lane < 4} {incr lane} {
            set tx $quad,$lane
            start_measurement
            after 100
            require_zero [counters]
            # Both toggle edges inject an error on the selected TX lane
            output_one $quad 7 [expr {1 << $lane}]
            after 100
            output_one $quad 7 0
            after 100
            if {![status DISCOVERY 0]} {
                error "Readiness/lock lost during discovery"
            }

            # Counters and sticky flags must agree on exactly one receiver
            set hits {}
            dict for {rx count} [counters] {
                lassign [split $rx ,] rq rl
                set sticky [expr {([input_value $rq 2] >> $rl) & 1}]
                set interrupted [expr {([input_value $rq 3] >> $rl) & 1}]
                if {$interrupted} {
                    error "Interrupted receiver: [dict get $::names $rx]"
                }
                if {($count != 0) != ($sticky != 0)} {
                    error "Counter/sticky disagreement on [dict get $::names $rx]"
                }
                if {$count != 0} {
                    lappend hits $rx
                }
            }
            if {[llength $hits] != 1} {
                error "TX [dict get $::names $tx] reached [llength $hits] selected receivers, expected one: $hits"
            }

            # Lane order may differ, each route must still reach its declared port
            set rx [lindex $hits 0]
            if {[dict exists $routes $rx]} {
                error "Multiple transmitters reached receiver $rx"
            }
            set expected [dict get $::peers [dict get $::channel_ports $tx]]
            if {[dict get $::channel_ports $rx] ne $expected} {
                error "TX [dict get $::names $tx] reached [dict get $::names $rx], expected port $expected"
            }

            dict set routes $rx $tx
            lassign [split $rx ,] rq rl
            set inverted [expr {([dict get $::polarity $rq] >> $rl) & 1}]
            puts "LANE_MAP=TX:[dict get $::names $tx],RX:[dict get $::names $rx],rx_inverted:$inverted"
        }
    }
    if {[dict size $routes] != 4 * [dict size $::cores]} {
        error "Incomplete lane mapping"
    }
    puts "DISCOVERY=PASS,lanes:[dict size $routes]"
}

# ---- Test selection and startup ----

if {$mode eq "program"} {
    puts "PROGRAM_COMPLETE=8_VIO_CORES"
    close_hw_target
    close_hw_manager
    exit
}

# Keep only requested quads for every subsequent helper call
if {$mode eq "external"} {
    set selected [dict create]
    foreach port [dict keys $peers] {
        foreach quad [dict get $ports $port] {
            dict set selected $quad [dict get $cores $quad]
        }
    }
    set cores $selected
}
set channels [expr {4 * [dict size $cores]}]

# Test startup, hold fault capture clear through loopback and reset changes
puts "TEST_MODE=$mode,concurrent_channels:$channels,PRBS31,nominal_25.78125_Gbps"
output_all 6 0
output_all 5 1
output_all 9 0
output_all 4 0
output_all 7 0
output_all 10 0
output_all 2 0
output_all 3 0
output_all 1 1

# Hold RX reset while changing loopback, then restart the PMA and reset helper
pulse 0
after 3000
if {$mode eq "test"} {
    output_all 3 2
}
after 100
output_all 1 0
pulse 2
after 3000
pulse 0
after 3000

# ---- External polarity acquisition and injection checks ----
# Try RX inversion on lanes that have not acquired PRBS lock
set polarity [dict create]
dict for {quad vio} $cores {
    set invert 0
    if {$mode eq "external"} {
        refresh_hw_vio $vio
        set invert [expr {15 ^ [input_value $quad 1]}]
        output_one $quad 10 $invert
    }
    dict set polarity $quad $invert
}
if {$mode eq "external"} {
    after 100
    pulse 2
    after 3000
}
qualify
if {$mode eq "external"} {
    discover
} else {
    start_measurement
    after 100
    output_all 7 15
    after 1000
    dict for {channel count} [counters] {
        if {$count == 0} {
            error "Error injection missed on [dict get $names $channel]"
        }
    }
    if {![status INJECTION 0]} {
        error "Channels lost qualification during injection"
    }
    dict for {quad vio} $cores {
        if {[input_value $quad 2] != 15 || [input_value $quad 3] != 0} {
            error "Sticky injection check failed on quad $quad"
        }
    }
}

# ---- Concurrent 120-second soak and results ----
# Clear discovery or injection faults before enabling the shared measurement
puts "INJECTION_RESULT=PASS,channels:$channels"
output_all 6 0
output_all 5 1
output_all 7 0
after 100
start_measurement
for {set sample 1} {$sample <= 12} {incr sample} {
    after 10000
    if {![status SOAK_$sample 1]} {
        error "Channel readiness/lock dropped during soak"
    }
}
set end [counters]
if {![status END 1]} {
    error "Channel readiness/lock dropped at end"
}
dict for {channel count} $end {
    puts "CHANNEL_RESULT=[dict get $names $channel],errors:$count"
}
require_zero $end
puts "RESULT=PASS,mode:$mode,channels:$channels,INJECTION=PASS"
close_hw_target
close_hw_manager
