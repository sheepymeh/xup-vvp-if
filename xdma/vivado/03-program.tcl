set root [file join [file dirname [info script]] ..]
set bitfile [file join $root build xdma.bit]

open_hw_manager
connect_hw_server -url localhost:3121

current_hw_target [lindex [get_hw_targets -quiet *Digilent*] 0]
open_hw_target

set fpga [lindex [get_hw_devices -quiet *xcvu13p*] 0]
set_property PROGRAM.FILE $bitfile $fpga
program_hw_devices $fpga
refresh_hw_device $fpga

close_hw_target
disconnect_hw_server
close_hw_manager

puts "PASS: volatile JTAG configuration from $bitfile"
