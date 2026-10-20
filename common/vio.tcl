namespace eval ::vio {}

proc ::vio::read {probe} {
    return [expr "0x[get_property INPUT_VALUE $probe]"]
}

proc ::vio::resolve {device map} {
    set result [dict create]
    dict for {cell pins} $map {
        set core [get_hw_vios -quiet -of_objects $device -filter [list CELL_NAME == $cell]]
        if {[llength $core] != 1} {
            error "Expected one VIO at $cell: $core"
        }
        dict set result $cell core $core
        dict for {port net} $pins {
            set probes [get_hw_probes -quiet $net -of_objects $core]
            if {[llength $probes] != 1} {
                error "Expected one probe for $cell/$port: $net"
            }
            set probe [lindex $probes 0]
            dict set result $cell pins $port $probe
            if {[string match probe_in* $port]} {
                set_property INPUT_VALUE_RADIX HEX $probe
            } else {
                set_property OUTPUT_VALUE_RADIX HEX $probe
            }
        }
    }
    return $result
}
