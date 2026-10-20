set root [file normalize [file join [file dirname [info script]] ..]]
set bitfile [file join $root build xdma.bit]
source [file join $root .. common hardware.tcl]

set fpga [hardware::connect]
try {
    hardware::program $fpga $bitfile
    refresh_hw_device $fpga
} finally {
    hardware::close
}
puts "PASS: volatile JTAG configuration from $bitfile"
