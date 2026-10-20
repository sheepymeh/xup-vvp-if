namespace eval ::board {
    variable part xcvu13p-figd2104-2-e
    variable hw_part xcvu13p
}

proc ::board::setting {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default
}
