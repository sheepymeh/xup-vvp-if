# ---- Local project and fixed memory geometry ----
set root [file dirname [file normalize [info script]]]
set out [file join $root build]
exec sh [file join $root prepare.sh]
create_project ddr4_test [file join $out project] -part xcvu13p-figd2104-2-e
set_property target_language Verilog [current_project]
add_files [list [file join $root powerup_reset.v] [file join $root memory_status.v]]
import_files -norecurse [file join $root BLS4G4D240FSB.csv]
foreach dimm {0 1} {
    add_files -fileset constrs_1 [file join build constraints dimm${dimm}.xdc]
}
add_files -fileset constrs_1 [file join $root startup.xdc]
set_property USED_IN_SYNTHESIS false [get_files startup.xdc]
set csv [get_files -all *BLS4G4D240FSB.csv]
if {[llength $csv] != 1} {
    error "Expected one custom memory-part CSV"
}

# ---- Calibration monitor, clocked independently of DDR4 ----
create_ip -name vio -vendor xilinx.com -library ip -module_name ddr_status_vio
set_property -dict [list CONFIG.C_NUM_PROBE_IN 1 CONFIG.C_NUM_PROBE_OUT 0 \
    CONFIG.C_PROBE_IN0_WIDTH 4] [get_ips ddr_status_vio]
generate_target all [get_ips ddr_status_vio]
update_compile_order -fileset sources_1

# ---- Independent controller and JTAG AXI path per DIMM ----
# Vivado chooses external port suffixes, identify the newly added port by name
proc expose_interface {pin name} {
    set before [get_bd_intf_ports -quiet]
    make_bd_intf_pins_external [get_bd_intf_pins $pin]
    set added {}
    foreach port [get_bd_intf_ports] {
        if {$port ni $before} {
            lappend added $port
        }
    }
    if {[llength $added] != 1} {
        error "Expected one new external interface for $pin"
    }
    set port [lindex $added 0]
    if {[get_property NAME $port] ne $name} {
        set_property NAME $name $port
    }
}

create_bd_design ddr4_bd
create_bd_cell -type module -reference powerup_reset por
create_bd_cell -type module -reference memory_status status
connect_bd_net [get_bd_pins por/monitor_clk] [get_bd_pins status/clk]

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
        [get_bd_pins interconnect_$dimm/aclk]
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

# ---- Synthesis and routing ----
create_ip_run $bd
create_ip_run [get_ips ddr_status_vio]
foreach run [get_runs] {
    foreach report [get_report_configs -of_objects $run] {
        set_property IS_ENABLED false $report
    }
}
foreach run [get_runs -filter {IS_SYNTHESIS == 1 && NAME != synth_1}] {
    if {[get_property PROGRESS $run] eq "100%"} {
        continue
    }
    launch_runs $run -jobs 1
    wait_on_run $run
    if {[get_property PROGRESS $run] ne "100%"} {
        error "IP synthesis failed: $run, [get_property STATUS $run]"
    }
}
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "Top synthesis failed"
}

# Keep debug discovery available even with no calibrated DIMM UI clocks
open_run synth_1
set debug_xdc [file join $out debug_clock.xdc]
close [open $debug_xdc w]
add_files -fileset constrs_1 $debug_xdc
set_property USED_IN_SYNTHESIS false [get_files $debug_xdc]
set_property TARGET_CONSTRS_FILE $debug_xdc [get_filesets constrs_1]
set monitor [get_nets -hier -filter {NAME == ddr4_bd_i/por_monitor_clk}]
if {[llength $monitor] != 1} {
    error "Missing independent debug monitor clock"
}
disconnect_debug_port dbg_hub/clk
connect_debug_port dbg_hub/clk $monitor
set_property C_CLK_INPUT_FREQ_HZ 50000000 [get_debug_cores dbg_hub]
save_constraints -force
close_design

launch_runs impl_1 -to_step route_design -jobs 1
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Implementation failed"
}
open_run impl_1

# ---- Required implementation checks and programming artifacts ----
foreach dimm {0 1} {
    set ports [get_ports -quiet C${dimm}_DDR4_0_*]
    if {[llength $ports] == 0} {
        error "Missing DIMM$dimm interface, incorrect synthesis top"
    }
}
foreach primitive {STARTUPE3 DCIRESET} {
    if {[llength [get_cells -hier -filter "REF_NAME == $primitive"]] != 1} {
        error "Expected one device-wide $primitive"
    }
}
if {![report_route_status -boolean_check ROUTED_FULLY]} {
    error "Unrouted nets"
}
foreach delay {max min} {
    set path [get_timing_paths -delay_type $delay -max_paths 1]
    if {[llength $path] != 1 || [get_property SLACK $path] < 0} {
        error "Missing or failing $delay timing path"
    }
}
write_bitstream -force [file join $out ddr4_test.bit]
write_debug_probes -force [file join $out ddr4_test.ltx]
puts "BUILD_COMPLETE, FPGA_NOT_PROGRAMMED"
close_project
