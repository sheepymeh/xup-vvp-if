set root [file dirname [file normalize [info script]]]
set out [file join $root build]
set common [file join $root .. common]
source [file join $common build.tcl]
exec sh [file join $root prepare.sh]
create_project ddr4_test [file join $out project] -part $::board::part
set_property target_language Verilog [current_project]
add_files [list [file join $root powerup_reset.v] [file join $root memory_status.v] \
    [file join $common rtl sync_bus.v]]
add_files -fileset constrs_1 [file join $common rtl sync_bus.xdc]
import_files -norecurse [file join $root BLS4G4D240FSB.csv]
foreach dimm {0 1} {
    add_files -fileset constrs_1 [file join $out constraints dimm${dimm}.xdc]
}
add_files -fileset constrs_1 [file join $root startup.xdc]
set_property USED_IN_SYNTHESIS false [get_files {startup.xdc sync_bus.xdc}]
set csv [get_files -all *BLS4G4D240FSB.csv]

build::create_vio ddr_status_vio {4 4 32 32 32} {}
update_compile_order -fileset sources_1

proc expose_interface {pin name} {
    set pin [get_bd_intf_pins $pin]
    make_bd_intf_pins_external $pin
    set port [get_bd_intf_ports -of_objects [get_bd_intf_nets -of_objects $pin]]
    set_property NAME $name $port
}

create_bd_design ddr4_bd
create_bd_cell -type module -reference powerup_reset por
create_bd_cell -type module -reference memory_status status
connect_bd_net [get_bd_pins por/monitor_clk] [get_bd_pins status/clk]
connect_bd_net [get_bd_pins por/startup_status] [get_bd_pins status/startup_status]

foreach dimm {0 1} {
    set controller ddr4_$dimm
    set master jtag_axi_$dimm
    set reset proc_rst_$dimm
    create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4:2.2 $controller
    set_property -dict [list \
        CONFIG.C0.DDR4_TimePeriod 833 \
        CONFIG.C0.DDR4_InputClockPeriod 9996 \
        CONFIG.C0.DDR4_CLKOUT0_DIVIDE 5 \
        CONFIG.C0.DDR4_CustomParts [lindex $csv 0] \
        CONFIG.C0.DDR4_isCustom true \
        CONFIG.C0.DDR4_MemoryType UDIMMs \
        CONFIG.C0.DDR4_MemoryPart BLS4G4D240FSB-2400 \
        CONFIG.C0.DDR4_DataWidth 64] [get_bd_cells $controller]

    # Explicit names must match prepared pin constraints
    expose_interface $controller/C0_DDR4 C${dimm}_DDR4_0
    expose_interface $controller/C0_SYS_CLK dimm${dimm}_refclk
    set_property CONFIG.FREQ_HZ 100000000 [get_bd_intf_ports dimm${dimm}_refclk]

    create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi:1.2 $master
    set_property CONFIG.M_AXI_ADDR_WIDTH 32 [get_bd_cells $master]
    # Adapt 32-bit JTAG transactions to the controller's 512-bit AXI port
    create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 interconnect_$dimm
    set_property -dict [list CONFIG.NUM_SI 1 CONFIG.NUM_MI 1] [get_bd_cells interconnect_$dimm]
    create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 $reset
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 locked_$dimm
    set_property -dict [list CONFIG.CONST_VAL 1 CONFIG.CONST_WIDTH 1] [get_bd_cells locked_$dimm]

    connect_bd_net [get_bd_pins por/sys_rst] [get_bd_pins $controller/sys_rst]
    connect_bd_net [get_bd_pins $controller/c0_ddr4_ui_clk] \
        [get_bd_pins $master/aclk] [get_bd_pins $reset/slowest_sync_clk] \
        [get_bd_pins interconnect_$dimm/aclk] [get_bd_pins status/ui_clk$dimm]
    connect_bd_net [get_bd_pins $controller/c0_ddr4_ui_clk_sync_rst] \
        [get_bd_pins $reset/ext_reset_in] [get_bd_pins status/reset$dimm]
    connect_bd_net [get_bd_pins locked_$dimm/dout] [get_bd_pins $reset/dcm_locked]
    connect_bd_net [get_bd_pins $reset/peripheral_aresetn] \
        [get_bd_pins $controller/c0_ddr4_aresetn] [get_bd_pins $master/aresetn] \
        [get_bd_pins interconnect_$dimm/aresetn]
    connect_bd_net [get_bd_pins $controller/c0_init_calib_complete] \
        [get_bd_pins status/calibrated$dimm]
    connect_bd_intf_net [get_bd_intf_pins $master/M_AXI] \
        [get_bd_intf_pins interconnect_$dimm/S00_AXI]
    connect_bd_intf_net [get_bd_intf_pins interconnect_$dimm/M00_AXI] \
        [get_bd_intf_pins $controller/C0_DDR4_S_AXI]

    # Separate masters each expose their own 4 GiB aperture at address zero
    set segment [get_bd_addr_segs -of_objects [get_bd_intf_pins $controller/C0_DDR4_S_AXI]]
    assign_bd_address -offset 0x00000000 -range 4G $segment
}
validate_bd_design
save_bd_design
set bd [get_files -all */ddr4_bd.bd]
generate_target all $bd
add_files -norecurse [make_wrapper -files $bd -top]
set_property TOP_AUTO_SET 0 [get_filesets sources_1]
set_property top ddr4_bd_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

create_ip_run $bd
create_ip_run [get_ips ddr_status_vio]
build::disable_optional_reports
foreach run [get_runs -filter {IS_SYNTHESIS == 1 && NAME != synth_1}] {
    build::run $run
}
build::run synth_1

# Keep debug discovery available even with no calibrated DIMM UI clocks
open_run synth_1
set debug_xdc [file join $out debug_clock.xdc]
close [open $debug_xdc w]
add_files -fileset constrs_1 $debug_xdc
set_property USED_IN_SYNTHESIS false [get_files $debug_xdc]
set_property TARGET_CONSTRS_FILE $debug_xdc [get_filesets constrs_1]
disconnect_debug_port dbg_hub/clk
connect_debug_port dbg_hub/clk [get_nets -hier -filter {NAME == ddr4_bd_i/por_monitor_clk}]
set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
save_constraints -force
close_design

build::run impl_1 -to_step route_design
open_run impl_1

build::check_synchronizers
build::check_implementation [file join $out reports]
write_bitstream -force [file join $out ddr4_test.bit]
write_debug_probes -force [file join $out ddr4_test.ltx]
exec python3 [file join $common probes.py] \
    [file join $out ddr4_test.ltx] [file join $out probes.tcl]
puts "BUILD_COMPLETE, FPGA_NOT_PROGRAMMED"
close_project
